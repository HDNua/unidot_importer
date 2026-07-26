import io
import json
import os
import tarfile
import tempfile
import unittest

from tools.checks import package_overlap


MODEL_GUID = "11111111111111111111111111111111"
PREFAB_GUID = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
COMMON_FILE_ID = 42
NEGATIVE_FILE_ID = -9007199254740993
LARGE_FILE_ID = 9223372036854775807


def _add_tar_file(archive, name, data):
	if isinstance(data, str):
		data = data.encode("utf-8")
	member = tarfile.TarInfo(name)
	member.size = len(data)
	member.mtime = 0
	archive.addfile(member, io.BytesIO(data))


def _write_package(path, model_bytes, prefab_body, include_model=True):
	assets = []
	if include_model:
		assets.append((MODEL_GUID, "Assets/Shared/Model.fbx", model_bytes))
	assets.append((PREFAB_GUID, "Assets/Consumers/Consumer.prefab", prefab_body))
	# This extension is intentionally outside the documented scan scope.
	assets.append(("bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb", "Assets/Ignored.anim",
		"m_Clip: {fileID: 777, guid: %s, type: 3}\n" % MODEL_GUID))
	with tarfile.open(path, "w:gz") as archive:
		for guid, pathname, body in assets:
			# Match real Asset Store archives: asset precedes pathname.
			_add_tar_file(archive, guid + "/asset", body)
			_add_tar_file(archive, guid + "/asset.meta", "meta\n")
			_add_tar_file(archive, guid + "/pathname", pathname + "\n")


class PackageOverlapTest(unittest.TestCase):
	def setUp(self):
		self.temporary_directory = tempfile.TemporaryDirectory()
		common = "m_Common: {fileID: %d, guid: %s, type: 3}\n" % (COMMON_FILE_ID, MODEL_GUID)
		a_only = (
			"m_Negative: {fileID: %d, guid: %s, type: 3}\n"
			"m_Duplicate: {fileID: %d, guid: %s, type: 3}\n"
			"m_Reordered: {guid: %s, type: 3, fileID: %d}\n"
		) % (
			NEGATIVE_FILE_ID, MODEL_GUID,
			NEGATIVE_FILE_ID, MODEL_GUID,
			MODEL_GUID.upper(), LARGE_FILE_ID,
		)
		paths = {}
		for name, model_bytes, prefab_body, include_model in (
			("A", b"model version a", common + a_only, True),
			("A Copy", b"model version a", common + a_only, True),
			("B", b"model version b", common, True),
			("External", b"", common + (
				"m_External: {fileID: 314, guid: %s, type: 3}\n" % MODEL_GUID), False),
		):
			path = os.path.join(self.temporary_directory.name, name + ".unitypackage")
			_write_package(path, model_bytes, prefab_body, include_model)
			paths[name] = path
		self.paths = paths

	def tearDown(self):
		self.temporary_directory.cleanup()

	def _build_report(self, reverse=False):
		names = list(self.paths)
		if reverse:
			names.reverse()
		packages = {name: package_overlap.scan(self.paths[name]) for name in names}
		references = {
			name: package_overlap.scan_consumer_references(
				self.paths[name], packages[name], (MODEL_GUID,))
			for name in names
		}
		return package_overlap.analyze(packages, references)

	def test_two_pass_profiles_and_directional_candidates(self):
		report = self._build_report()
		self.assertEqual(1, len(report["model_consumer_analysis"]))
		model = report["model_consumer_analysis"][0]
		self.assertEqual(MODEL_GUID, model["guid"])
		self.assertEqual(2, len(model["consumer_profiles"]))

		profile_a = next(profile for profile in model["consumer_profiles"]
			if profile["packages"] == ["A", "A Copy"])
		self.assertEqual(
			[str(NEGATIVE_FILE_ID), str(COMMON_FILE_ID), str(LARGE_FILE_ID)],
			profile_a["file_ids"],
		)
		self.assertTrue(all(isinstance(file_id, str) for file_id in profile_a["file_ids"]))
		self.assertNotIn("777", profile_a["file_ids"])

		a_displaced = next(direction for direction in model["directions"]
			if direction["displaced_packages"] == ["A", "A Copy"])
		self.assertEqual(
			[str(NEGATIVE_FILE_ID), str(LARGE_FILE_ID)],
			a_displaced["consumer_only_file_ids"],
		)
		self.assertEqual("consumer_text_references_only", a_displaced["evidence_scope"])
		self.assertFalse(a_displaced["replacement_membership_checked"])
		self.assertEqual("heuristic_review_candidates", a_displaced["assessment"])
		self.assertEqual(1, len(a_displaced["candidate_assets"]))
		candidate = a_displaced["candidate_assets"][0]
		self.assertEqual(["A", "A Copy"], candidate["packages"])
		self.assertEqual(
			[str(NEGATIVE_FILE_ID), str(LARGE_FILE_ID)], candidate["file_ids"])

		b_displaced = next(direction for direction in model["directions"]
			if direction["displaced_packages"] == ["B"])
		self.assertEqual([], b_displaced["consumer_only_file_ids"])
		self.assertEqual([], b_displaced["candidate_assets"])
		self.assertEqual("no_observed_consumer_reference_asymmetry", b_displaced["assessment"])

		self.assertEqual(1, len(model["unversioned_consumers"]))
		self.assertEqual(["External"], model["unversioned_consumers"][0]["packages"])
		self.assertIn("model's sub-object inventory", report["model_consumer_analysis_limitation"])
		json.dumps(report)

	def test_report_is_independent_of_input_mapping_order(self):
		self.assertEqual(self._build_report(), self._build_report(reverse=True))

	def test_duplicate_package_labels_are_rejected(self):
		with self.assertRaisesRegex(ValueError, "duplicate: Same"):
			package_overlap.package_labels((
				"/one/Same.unitypackage",
				"/two/Same.unitypackage",
			))


if __name__ == "__main__":
	unittest.main()

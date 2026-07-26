import io
import json
import os
import tarfile
import tempfile
import unittest

from tools.checks import unity_source_pose_gate as gate


PREFAB_GUID = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
MODEL_GUID = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
TEXTURE_GUID = "cccccccccccccccccccccccccccccccc"


def _add(archive, name, body):
	if isinstance(body, str):
		body = body.encode("utf-8")
	member = tarfile.TarInfo(name)
	member.size = len(body)
	member.mtime = 0
	archive.addfile(member, io.BytesIO(body))


class UnitySourcePoseGateTest(unittest.TestCase):
	def test_manifest_is_two_pass_minimal_and_path_safe(self):
		with tempfile.TemporaryDirectory() as temporary:
			package = os.path.join(temporary, "synthetic.unitypackage")
			with tarfile.open(package, "w:gz") as archive:
				# Real Asset Store archives commonly put the body before pathname.
				_add(archive, PREFAB_GUID + "/asset", "prefab yaml")
				_add(archive, PREFAB_GUID + "/pathname", "../../escape.prefab\n00")
				_add(archive, MODEL_GUID + "/asset", b"fbx")
				_add(archive, MODEL_GUID + "/pathname", "Assets/Model.fbx")
				_add(archive, TEXTURE_GUID + "/asset", b"png")
				_add(archive, TEXTURE_GUID + "/pathname", "Assets/Texture.png")
			manifest_dir = os.path.join(temporary, "manifest")
			os.mkdir(manifest_dir)
			manifest = gate.build_manifest(package, manifest_dir)

			self.assertEqual(gate.MANIFEST_VERSION, manifest["version"])
			self.assertEqual("Assets/Model.fbx", manifest["guid_to_path"][MODEL_GUID])
			self.assertEqual(1, len(manifest["prefabs"]))
			record = manifest["prefabs"][0]
			self.assertEqual(PREFAB_GUID, record["guid"])
			self.assertEqual("../../escape.prefab", record["source_path"])
			self.assertEqual(
				os.path.join(manifest_dir, PREFAB_GUID + ".prefab"), record["yaml_path"])
			with open(record["yaml_path"], "rb") as extracted:
				self.assertEqual(b"prefab yaml", extracted.read())
			self.assertEqual([PREFAB_GUID + ".prefab"], os.listdir(manifest_dir))

	def test_worker_contract_is_plain_headless(self):
		command = gate.worker_command("godot", "/project", "/tmp/manifest.json")
		self.assertEqual("godot", command[0])
		self.assertIn("--headless", command)
		self.assertNotIn("--editor", command)
		self.assertNotIn("--recovery-mode", command)
		self.assertEqual(
			["--path", "/project", "--script", gate.WORKER_RESOURCE_PATH,
			 "--", "/tmp/manifest.json"], command[2:])

	def test_last_result_record_wins(self):
		first = {"result": "FAIL"}
		last = {"result": "PASS", "checked_prefabs": 1}
		output = "%s%s\nnoise\n%s%s\n" % (
			gate.RESULT_PREFIX, json.dumps(first), gate.RESULT_PREFIX, json.dumps(last))
		self.assertEqual(last, gate.parse_worker_result(output))
		with self.assertRaisesRegex(ValueError, "did not emit"):
			gate.parse_worker_result("noise only")

	def test_script_error_markers_include_parse_failures(self):
		self.assertEqual(0, gate.count_script_errors("ordinary Godot output"))
		self.assertEqual(1, gate.count_script_errors("Parse Error: bad annotation"))
		self.assertEqual(
			3,
			gate.count_script_errors(
				"SCRIPT ERROR: Parse Error: bad token\nFailed to load script"))


if __name__ == "__main__":
	unittest.main()

#!/usr/bin/env python3
"""Compare converted skeleton poses with source data from a ``.unitypackage``.

This is a vendor-neutral source-consistency gate.  It does not assume that a
prefab was authored at bind pose.  Unity YAML assets are parsed by Unidot's own
parser in the Godot worker, and authored transforms are converted by Unidot's
existing transform converter before being compared with final bone poses.

FBX-backed prefab variants have no authored bone transforms in their YAML.  A
separate, explicitly weaker oracle compares them with a separately instantiated
persisted source-model scene through the exact fileID/nodepath/bone mapping in
its AssetMeta.  Saved pre-retarget transforms and deltas provide a rotation
cross-check for every mapped bone with a saved original, not a numeric position
oracle.  Exact final names in the persisted active humanoid map (auto-detected
first, authored fallback) are the required subset; only non-required bones with
no saved original are reported as composition-only.  Model-level defects are
shared by the baseline and final
prefab, so this branch checks only composition and application consistency; it
does not independently validate FBX decoding.

The shared YAML parser and coordinate converter are also part of the system
under test.  Symmetric bugs in either can escape this gate.  Direct-prefab
synthetic-root proof additionally checks authored YAML ``m_Bones`` IDs.  The
FBX branch has no equivalent raw bone inventory and must trust its persisted
fileID/parent map, so corruption that removes an authored root from that same
map may remain invisible.

Usage:

    python3 tools/checks/unity_source_pose_gate.py \
        Some.unitypackage /path/to/validation_project

The validation project must contain the converted package, its
``unidot_asset_database.res``, and this checkout synced as
``addons/unidot_importer``.  The worker runs in plain headless mode: it never
enables editor plugins and writes no project files.
"""

import argparse
import json
import os
import subprocess
import sys
import tarfile
import tempfile


DEFAULT_GODOT = "/Applications/Godot_mono.app/Contents/MacOS/Godot"
WORKER_RESOURCE_PATH = (
	"res://addons/unidot_importer/tools/checks/unity_source_pose_gate.gd"
)
RESULT_PREFIX = "UNITY_SOURCE_POSE_GATE_JSON="
MANIFEST_VERSION = 1
SCRIPT_ERROR_MARKERS = ("SCRIPT ERROR:", "Failed to load script", "Parse Error:")


def _archive_records(package_path: str) -> dict:
	"""Return GUID records without trusting archive member paths for extraction."""
	records = {}
	with tarfile.open(package_path, "r:gz") as archive:
		for member in archive:
			if not member.isfile() or "/" not in member.name:
				continue
			guid, kind = member.name.split("/", 1)
			if len(guid) != 32 or kind not in ("asset", "pathname"):
				continue
			record = records.setdefault(guid.lower(), {})
			if kind == "pathname":
				stream = archive.extractfile(member)
				if stream is None:
					continue
				text = stream.read().decode("utf-8", "replace")
				record["source_path"] = text.splitlines()[0].strip() if text else ""
			else:
				record["asset_member"] = member.name
	return records


def build_manifest(package_path: str, temporary_directory: str) -> dict:
	"""Extract only prefab YAML bodies and describe all package GUID paths.

	The archive is never extracted by pathname.  Temporary filenames are GUIDs,
	which avoids traversal and keeps commercial source data out of the checkout.
	"""
	records = _archive_records(package_path)
	guid_to_path = {
		guid: record["source_path"]
		for guid, record in records.items()
		if record.get("source_path")
	}
	prefabs = []
	selected = {
		guid: record for guid, record in records.items()
		if record.get("source_path", "").lower().endswith(".prefab")
		and record.get("asset_member")
	}
	with tarfile.open(package_path, "r:gz") as archive:
		members = {member.name: member for member in archive if member.isfile()}
		for guid, record in sorted(
			selected.items(), key=lambda item: (item[1]["source_path"], item[0])):
			member = members.get(record["asset_member"])
			if member is None:
				continue
			stream = archive.extractfile(member)
			if stream is None:
				continue
			temporary_path = os.path.join(temporary_directory, guid + ".prefab")
			with open(temporary_path, "wb") as output:
				for chunk in iter(lambda: stream.read(1 << 20), b""):
					output.write(chunk)
			prefabs.append({
				"guid": guid,
				"source_path": record["source_path"],
				"yaml_path": temporary_path,
			})
	return {
		"version": MANIFEST_VERSION,
		"guid_to_path": guid_to_path,
		"prefabs": prefabs,
	}


def parse_worker_result(output: str) -> dict:
	for line in reversed(output.splitlines()):
		if line.startswith(RESULT_PREFIX):
			return json.loads(line[len(RESULT_PREFIX):])
	raise ValueError("Godot worker did not emit a result record")


def count_script_errors(output: str) -> int:
	return sum(output.count(marker) for marker in SCRIPT_ERROR_MARKERS)


def worker_command(godot: str, project_dir: str, manifest_path: str) -> list:
	return [
		godot,
		"--headless",
		"--path",
		project_dir,
		"--script",
		WORKER_RESOURCE_PATH,
		"--",
		manifest_path,
	]

def run_gate(package_path: str, project_dir: str, godot: str) -> tuple:
	with tempfile.TemporaryDirectory(prefix="unidot-source-pose-") as temporary:
		manifest = build_manifest(package_path, temporary)
		manifest_path = os.path.join(temporary, "manifest.json")
		with open(manifest_path, "w", encoding="utf-8") as output:
			json.dump(manifest, output, sort_keys=True)
		result = subprocess.run(
			worker_command(godot, project_dir, manifest_path),
			cwd=project_dir,
			text=True,
			stdout=subprocess.PIPE,
			stderr=subprocess.STDOUT,
		)
		try:
			report = parse_worker_result(result.stdout)
		except (ValueError, json.JSONDecodeError) as error:
			raise RuntimeError(str(error) + "\n" + result.stdout[-8000:]) from error
		script_error_markers = count_script_errors(result.stdout)
		if script_error_markers:
			report["result"] = "FAIL"
			report.setdefault("failures", []).append(
				"Godot reported %d script/load errors" % script_error_markers)
			report["engine_script_errors"] = script_error_markers
			return 1, report, result.stdout
		return result.returncode, report, result.stdout


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__)
	parser.add_argument("package", help="original .unitypackage")
	parser.add_argument("project_dir", help="converted validation project")
	parser.add_argument(
		"--godot", default=os.environ.get("GODOT", DEFAULT_GODOT),
		help="Godot executable (default: $GODOT or the macOS mono app path)")
	parser.add_argument("--json", action="store_true", help="print only JSON")
	args = parser.parse_args()

	package_path = os.path.abspath(os.path.expanduser(args.package))
	project_dir = os.path.abspath(os.path.expanduser(args.project_dir))
	if not os.path.isfile(package_path):
		parser.error("package does not exist: " + package_path)
	if not os.path.isfile(os.path.join(project_dir, "project.godot")):
		parser.error("not a Godot project: " + project_dir)
	if not os.path.isfile(os.path.join(project_dir, "unidot_asset_database.res")):
		parser.error("missing unidot_asset_database.res in: " + project_dir)
	if not os.path.isfile(args.godot):
		parser.error("Godot executable does not exist: " + args.godot)

	try:
		returncode, report, worker_output = run_gate(package_path, project_dir, args.godot)
	except (OSError, tarfile.TarError, RuntimeError) as error:
		print("unity source pose gate: " + str(error), file=sys.stderr)
		return 1

	if args.json:
		print(json.dumps(report, indent=2, sort_keys=True))
	else:
		for line in worker_output.splitlines():
			if line.startswith("=== Unity source pose") or line.startswith("  ") \
					or line.startswith("RESULT:"):
				print(line)
	return 0 if returncode == 0 and report.get("result") == "PASS" else 1


if __name__ == "__main__":
	sys.exit(main())

#!/usr/bin/env python3
"""Summarize one package import: what was produced, and what the log complained
about.

Vendor-neutral. Everything it reports is derived from the import log and the
output tree, so it applies to any .unitypackage, not just a particular
publisher's. Checks that depend on knowing which prefabs matter, or on a
publisher's own conventions, belong under tools/publishers/ instead.

    tools/checks/import_report.py <project_dir>

<project_dir> is a project created by tools/validate_package.py: it holds
import.log, validation_context.json and the Unidot/ output tree.
"""
import argparse
import collections
import glob
import json
import os
import re
import sys

# Ordered: the first pattern that matches a message decides its class, so put
# the specific ones first.
WARNING_CLASSES = [
	("particle", re.compile(r"particle|billboard|InitialModule", re.I)),
	("shader-source-only", re.compile(r"Shader Sub Graph|shadergraph|shadersubgraph|source-only", re.I)),
	("prefab-stripped", re.compile(r"stripped intermediate", re.I)),
	("lighting", re.compile(r"lightmap|LightingSettings", re.I)),
	("humanoid-validator", re.compile(r"humanoid|humanDescription|bone map", re.I)),
	("missing-meta", re.compile(r"no meta", re.I)),
	("main-object-id", re.compile(r"main_object_id", re.I)),
]


def classify(message: str) -> str:
	for name, pattern in WARNING_CLASSES:
		if pattern.search(message):
			return name
	return "other"


def stage_logs(project_dir: str) -> list:
	"""Import logs for the project, oldest stage first.

	A single-package project has one import.log; a multi-package one has
	import.<n>.log per stage, and the stage matters — a diagnostic raised while
	the second package was landing is not a fact about the first.
	"""
	single = os.path.join(project_dir, "import.log")
	if os.path.isfile(single):
		return [single]
	staged = glob.glob(os.path.join(project_dir, "import.*.log"))
	return sorted(staged, key=lambda p: int(re.search(r"import\.(\d+)\.log$", p).group(1)))


def read_log(path: str) -> str:
	with open(path, errors="ignore") as f:
		return f.read()


def engine_diagnostics(log: str) -> dict:
	dead_images = re.findall(r"couldn't be loaded from path: (\S+)", log)
	extensions = collections.Counter(os.path.splitext(p)[1].lower() for p in dead_images)
	return {
		"error_lines": log.count("\nERROR:"),
		"dead_texture_references": len(dead_images),
		"dead_texture_extensions": dict(extensions.most_common()),
		"distinct_dead_textures": len({os.path.basename(p) for p in dead_images}),
		"case_mismatch_warnings": log.count("Case mismatch"),
		"missing_guid_dependencies": len(set(re.findall(r"depends on missing GUID (\w+)", log))),
	}


def unidot_diagnostics(log: str) -> dict:
	# Only present when the addon was built with per-asset log echoing; absent in
	# a stock run, in which case the dialog counters are the source of truth.
	warns = re.findall(r"warn: (.*)", log)
	fails = re.findall(r"FAIL: (.*)", log)
	by_class = collections.Counter(classify(w) for w in warns)
	return {
		"warnings": len(warns),
		"warnings_by_class": dict(by_class.most_common()),
		"failures": len(fails),
		"failure_messages": dict(collections.Counter(f.split(" ref ")[0].strip() for f in fails).most_common(5)),
	}


def output_inventory(project_dir: str) -> dict:
	root = os.path.join(project_dir, "Unidot")
	counts = collections.Counter()
	top_level = collections.Counter()
	total = 0
	for dirpath, _dirnames, filenames in os.walk(root):
		rel = os.path.relpath(dirpath, root)
		parts = rel.split(os.sep)
		bucket = "/".join(parts[:3]) if len(parts) >= 3 else rel
		for name in filenames:
			ext = os.path.splitext(name)[1].lower()
			counts[ext] += 1
			top_level[bucket] += 1
			total += 1
	return {
		"files": total,
		"by_extension": dict(counts.most_common(12)),
		"by_source_folder": dict(top_level.most_common(12)),
	}


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	parser.add_argument("project_dir", help="a project produced by tools/validate_package.py")
	parser.add_argument("--json", action="store_true", help="emit JSON instead of a text summary")
	parser.add_argument("--stage", type=int, help="report only stage N of a multi-package project (1-based)")
	args = parser.parse_args()

	project_dir = os.path.abspath(os.path.expanduser(args.project_dir))
	logs = stage_logs(project_dir)
	if not logs:
		print("No import log in " + project_dir, file=sys.stderr)
		return 1
	if args.stage is not None:
		if not 1 <= args.stage <= len(logs):
			print("No stage %d; the project has %d" % (args.stage, len(logs)), file=sys.stderr)
			return 1
		logs = [logs[args.stage - 1]]
	log = "\n".join(read_log(p) for p in logs)

	context = {}
	context_path = os.path.join(project_dir, "validation_context.json")
	if os.path.isfile(context_path):
		with open(context_path) as f:
			context = json.load(f)

	report = {
		"context": context,
		"stages": [os.path.basename(p) for p in logs],
		"import_completed": "AUTO_IMPORT_BOOTSTRAP: import finished" in log,
		"engine": engine_diagnostics(log),
		"unidot": unidot_diagnostics(log),
		"output": output_inventory(project_dir),
	}

	if args.json:
		json.dump(report, sys.stdout, indent=2)
		sys.stdout.write("\n")
		return 0

	packages = context.get("packages") or [context.get("package", "?")]
	for i, p in enumerate(packages, 1):
		print("package %d: %s" % (i, p))
	print("unidot:   " + str(context.get("unidot_revision", "?")))
	print("stages:   " + ", ".join(report["stages"]))
	print("finished: " + ("yes" if report["import_completed"] else "NO"))
	if len(packages) > 1 and args.stage is None:
		print("\nNote: figures below cover every stage together. They describe the")
		print("combined project, not any one package. Use --stage N for one stage.")
	e = report["engine"]
	print("\nEngine-level diagnostics")
	print("  ERROR lines                 %d" % e["error_lines"])
	print("  dead texture references     %d (%d distinct files) %s"
		% (e["dead_texture_references"], e["distinct_dead_textures"], e["dead_texture_extensions"] or ""))
	print("  case-mismatch warnings      %d" % e["case_mismatch_warnings"])
	print("  missing GUID dependencies   %d" % e["missing_guid_dependencies"])
	u = report["unidot"]
	if u["warnings"] or u["failures"]:
		print("\nUnidot diagnostics")
		print("  warnings                    %d" % u["warnings"])
		for name, count in u["warnings_by_class"].items():
			print("      %-24s%d" % (name, count))
		print("  failures                    %d" % u["failures"])
		for msg, count in u["failure_messages"].items():
			print("      %dx %s" % (count, msg[:88]))
	else:
		print("\nUnidot per-asset diagnostics were not echoed to the log;")
		print("read the counters in the import dialog instead.")
	o = report["output"]
	print("\nOutput: %d files" % o["files"])
	for folder, count in o["by_source_folder"].items():
		print("  %-52s%d" % (folder, count))
	return 0


if __name__ == "__main__":
	sys.exit(main())

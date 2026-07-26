#!/usr/bin/env python3
"""Compare .unitypackage files for content they both claim to own.

Vendor-neutral: any publisher can ship the same shared library inside several
packages, and Unity's identity model makes that ambiguous as soon as two of them
land in one project. An asset is identified by its GUID, and Unidot's asset
database keeps one output path per GUID, so when two packages carry the same
GUID one of them decides what that GUID means. Unidot writes the file whenever
the incoming bytes differ from what is on disk, so in practice the package
imported last wins.

    tools/checks/package_overlap.py A.unitypackage B.unitypackage [C ...]

Three things are worth knowing before importing several packages together, and
all three are answerable from the archives alone, without running an import:

  shared, identical    the same GUID and the same bytes everywhere. Benign: it
                       does not matter which package supplies it.
  shared, conflicting  the same GUID, different bytes. The last package to be
                       imported replaces the file. If the versions are not
                       interchangeable — a model that lost a mesh, a prefab that
                       lost a child — content from the other packages that
                       referenced the missing part is left pointing at nothing.
  path collision       different GUIDs, one pathname. Two distinct assets want
                       to occupy one file.

Conflicting models are called out individually because they are the ones that
carry sub-objects: other assets reference a mesh or a bone *inside* the model by
file ID, so replacing the model can invalidate references held by assets that
were imported perfectly.

For each conflicting model build, a second archive pass also records the file
IDs used by text-asset consumers shipped alongside that build. Directional set
differences identify assets worth checking when the other build wins. This is a
consumer-reference-profile heuristic, not a model inventory: a file ID used
only by one side's consumers is not proof that the other model lacks that ID,
and an empty difference is not proof that the builds are compatible or that one
is a superset of the other.

Use --json for machine-readable output.
"""
import argparse
import collections
import concurrent.futures
import hashlib
import itertools
import json
import os
import re
import sys
import tarfile

# A .unitypackage is a gzipped tar of <guid>/{pathname,asset,asset.meta,...}.
# Streaming mode ("r|gz") rejects the headers some of these archives carry, so
# they are read in random-access mode but still traversed in order.
MODEL_EXTENSIONS = (".fbx", ".obj", ".dae", ".gltf", ".glb", ".blend")
TEXT_ASSET_EXTENSIONS = (".asset", ".controller", ".mat", ".playable", ".prefab", ".unity")

# Unity external references are normally one-line YAML flow mappings. Parse the
# fields independently so field order does not matter. File IDs are signed
# 64-bit values in real packages; keep them as Python integers while comparing
# and render them as decimal strings in JSON so consumers cannot lose precision.
INLINE_MAPPING_RE = re.compile(rb"\{[^{}\r\n]*\}")
FILE_ID_RE = re.compile(rb"\bfileID:\s*(-?\d+)\b")
GUID_RE = re.compile(rb"\bguid:\s*([0-9a-fA-F]{32})\b")

CONSUMER_PROFILE_LIMITATION = (
	"Consumer-only file IDs compare references made by text assets accompanying each model build. "
	"They do not inspect the model's sub-object inventory, so they are not evidence that the winning "
	"model lacks an ID, nor proof of compatibility or a superset relationship."
)


def scan(path: str) -> dict:
	"""guid -> {pathname, sha, size, meta_sha} for one package."""
	entries = {}
	with tarfile.open(path, "r:gz") as tar:
		for member in tar:
			if "/" not in member.name or not member.isfile():
				continue
			guid, kind = member.name.split("/", 1)
			record = entries.setdefault(guid, {})
			if kind == "pathname":
				text = tar.extractfile(member).read().decode("utf-8", "replace")
				record["pathname"] = text.split("\n")[0].strip()
			elif kind == "asset":
				digest = hashlib.sha256()
				stream = tar.extractfile(member)
				for chunk in iter(lambda: stream.read(1 << 20), b""):
					digest.update(chunk)
				record["sha"] = digest.hexdigest()
				record["size"] = member.size
			elif kind == "asset.meta":
				record["meta_sha"] = hashlib.sha256(tar.extractfile(member).read()).hexdigest()
	# Folder entries carry a pathname but no asset; they own no content.
	return {g: r for g, r in entries.items() if "sha" in r}


def scan_consumer_references(path: str, entries: dict, target_guids) -> dict:
	"""Collect inline fileID references to target GUIDs from supported text assets.

	The first pass's entries supply pathnames because real unitypackage archives
	commonly store ``asset`` before ``pathname``. Bodies are read a line at a time
	and discarded; the result is target_guid -> source_guid -> set(fileID).
	"""
	targets = {guid.lower() for guid in target_guids}
	if not targets:
		return {}
	text_sources = {
		guid for guid, record in entries.items()
		if os.path.splitext(record.get("pathname", ""))[1].lower() in TEXT_ASSET_EXTENSIONS
	}
	references = collections.defaultdict(lambda: collections.defaultdict(set))
	with tarfile.open(path, "r:gz") as tar:
		for member in tar:
			if "/" not in member.name or not member.isfile():
				continue
			source_guid, kind = member.name.split("/", 1)
			if kind != "asset" or source_guid not in text_sources:
				continue
			stream = tar.extractfile(member)
			for line in stream:
				if b"fileID" not in line or b"guid" not in line:
					continue
				for mapping in INLINE_MAPPING_RE.finditer(line):
					file_id_match = FILE_ID_RE.search(mapping.group(0))
					guid_match = GUID_RE.search(mapping.group(0))
					if not file_id_match or not guid_match:
						continue
					target_guid = guid_match.group(1).decode("ascii").lower()
					if target_guid in targets:
						references[target_guid][source_guid].add(int(file_id_match.group(1)))
	return {
		target_guid: {source_guid: set(file_ids) for source_guid, file_ids in by_source.items()}
		for target_guid, by_source in references.items()
	}


def label(path: str) -> str:
	return os.path.basename(path).rsplit(".unitypackage", 1)[0]


def package_labels(paths) -> list:
	"""Return archive labels, rejecting basenames that would overwrite each other."""
	labels = [label(path) for path in paths]
	counts = collections.Counter(labels)
	duplicates = sorted(name for name, count in counts.items() if count > 1)
	if duplicates:
		raise ValueError("package filenames must have unique labels; duplicate: " + ", ".join(duplicates))
	return labels


def _json_file_ids(file_ids) -> list:
	"""Sort numerically, then preserve signed 64-bit values as exact JSON strings."""
	return [str(file_id) for file_id in sorted(file_ids)]


def _group_consumer_assets(packages: dict, references: dict, model_guid: str,
		package_names, allowed_file_ids=None) -> list:
	"""Group equal package copies while preserving their package provenance."""
	grouped = collections.defaultdict(list)
	for package_name in sorted(package_names):
		by_source = references.get(package_name, {}).get(model_guid, {})
		for source_guid, file_ids in by_source.items():
			matched = set(file_ids)
			if allowed_file_ids is not None:
				matched &= allowed_file_ids
			if not matched:
				continue
			pathname = packages[package_name][source_guid].get("pathname", "?")
			key = (source_guid, pathname, tuple(sorted(matched)))
			grouped[key].append(package_name)
	return [
		{
			"guid": source_guid,
			"pathname": pathname,
			"packages": sorted(package_names),
			"file_ids": _json_file_ids(file_ids),
		}
		for (source_guid, pathname, file_ids), package_names in sorted(
			grouped.items(), key=lambda item: (item[0][1], item[0][0], item[0][2]))
	]


def _model_consumer_analysis(packages: dict, conflict_details: list, references: dict) -> list:
	"""Build deterministic consumer profiles and every ordered version direction."""
	analyses = []
	for detail in conflict_details:
		if os.path.splitext(detail["pathname"])[1].lower() not in MODEL_EXTENSIONS:
			continue
		model_guid = detail["guid"]
		holders = sorted(name for name, entries in packages.items() if model_guid in entries)
		version_packages = collections.defaultdict(list)
		for package_name in holders:
			version_packages[packages[package_name][model_guid].get("sha")].append(package_name)

		profiles = []
		profile_file_ids = {}
		for model_sha, package_names in sorted(version_packages.items()):
			file_ids = set()
			for package_name in package_names:
				for source_ids in references.get(package_name, {}).get(model_guid, {}).values():
					file_ids.update(source_ids)
			profile_file_ids[model_sha] = file_ids
			first_record = packages[package_names[0]][model_guid]
			profiles.append({
				"model_sha": model_sha,
				"model_size": first_record.get("size"),
				"packages": sorted(package_names),
				"file_ids": _json_file_ids(file_ids),
			})

		directions = []
		for displaced_sha, winning_sha in itertools.permutations(sorted(version_packages), 2):
			displaced_packages = sorted(version_packages[displaced_sha])
			winning_packages = sorted(version_packages[winning_sha])
			consumer_only = profile_file_ids[displaced_sha] - profile_file_ids[winning_sha]
			directions.append({
				"evidence_scope": "consumer_text_references_only",
				"replacement_membership_checked": False,
				"assessment": (
					"heuristic_review_candidates" if consumer_only
					else "no_observed_consumer_reference_asymmetry"),
				"displaced_model_sha": displaced_sha,
				"winning_model_sha": winning_sha,
				"displaced_packages": displaced_packages,
				"winning_packages": winning_packages,
				"consumer_only_file_ids": _json_file_ids(consumer_only),
				"candidate_assets": _group_consumer_assets(
					packages, references, model_guid, displaced_packages, consumer_only),
			})

		unversioned_packages = sorted(set(packages) - set(holders))
		analyses.append({
			"guid": model_guid,
			"pathname": detail["pathname"],
			"consumer_profiles": profiles,
			"directions": directions,
			"unversioned_consumers": _group_consumer_assets(
				packages, references, model_guid, unversioned_packages),
		})
	return sorted(analyses, key=lambda item: (item["pathname"], item["guid"]))


def analyze(packages: dict, references=None) -> dict:
	owners = collections.defaultdict(dict)
	for name, entries in packages.items():
		for guid, record in entries.items():
			owners[guid][name] = record

	shared = {g: o for g, o in owners.items() if len(o) > 1}
	conflicts, meta_conflicts = {}, {}
	for guid, holders in shared.items():
		if len({r.get("sha") for r in holders.values()}) > 1:
			conflicts[guid] = holders
		if len({r.get("meta_sha") for r in holders.values()}) > 1:
			meta_conflicts[guid] = holders

	# Different GUIDs competing for one pathname. Distinct from the above: there
	# the packages agree on what the asset is and disagree on its content.
	by_path = collections.defaultdict(set)
	for name, entries in packages.items():
		for guid, record in entries.items():
			pathname = record.get("pathname")
			if pathname is not None:
				by_path[pathname].add(guid)
	collisions = {p: sorted(by_path[p]) for p in sorted(by_path) if len(by_path[p]) > 1}

	def path_of(holders):
		return sorted(record.get("pathname", "?") for record in holders.values())[0]

	def versions(holders):
		groups = collections.defaultdict(list)
		for name, record in holders.items():
			groups[record.get("sha")].append(name)
		return [
			{"sha": sha, "size": holders[sorted(names)[0]].get("size"), "packages": sorted(names)}
			for sha, names in sorted(groups.items(), key=lambda kv: (-len(kv[1]), kv[0] or ""))
		]

	conflict_details = sorted(
		({"guid": g, "pathname": path_of(h), "versions": versions(h)} for g, h in conflicts.items()),
		key=lambda d: (d["pathname"], d["guid"]),
	)
	extensions = collections.Counter(
		os.path.splitext(detail["pathname"])[1].lower() for detail in conflict_details)
	report = {
		"packages": {name: len(packages[name]) for name in sorted(packages)},
		"distinct_guids": len(owners),
		"shared_guids": len(shared),
		"shared_identical": len(shared) - len(conflicts),
		"shared_conflicting": len(conflicts),
		"shared_meta_conflicting": len(meta_conflicts),
		"conflicts_by_extension": {
			extension: count for extension, count in sorted(
				extensions.items(), key=lambda item: (-item[1], item[0]))
		},
		"conflicts": conflict_details,
		"path_collisions": collisions,
		"model_consumer_analysis_limitation": CONSUMER_PROFILE_LIMITATION,
		"model_consumer_text_extensions": list(TEXT_ASSET_EXTENSIONS),
		"model_consumer_analysis": [],
	}
	if references is not None:
		report["model_consumer_analysis"] = _model_consumer_analysis(
			packages, conflict_details, references)
	return report


def print_model_consumer_analysis(report: dict, limit: int) -> None:
	analyses = report["model_consumer_analysis"]
	if not analyses:
		return
	print("\n=== directional consumer-reference candidates (heuristic)")
	print("  Compares file IDs used by text assets accompanying each model build.")
	print("  It does not inspect which file IDs the replacement model actually contains.")
	for analysis in analyses[:limit]:
		print("\n  %s" % analysis["pathname"])
		print("    GUID %s" % analysis["guid"])
		for profile in analysis["consumer_profiles"]:
			print("    build %s  %4d consumer file IDs  <- %s" % (
				profile["model_sha"][:12], len(profile["file_ids"]), ", ".join(profile["packages"])))
		for direction in analysis["directions"]:
			print("\n    if build %s (%s) is imported after build %s (%s):" % (
				direction["winning_model_sha"][:12], ", ".join(direction["winning_packages"]),
				direction["displaced_model_sha"][:12], ", ".join(direction["displaced_packages"])))
			consumer_only = direction["consumer_only_file_ids"]
			candidates = direction["candidate_assets"]
			if not consumer_only:
				print("      no observed consumer-reference asymmetry in this direction")
				print("      (this does not establish compatibility)")
				continue
			print("      %d file IDs occur only in consumers accompanying the displaced build" % len(consumer_only))
			print("      heuristic review candidates: %d assets" % len(candidates))
			for candidate in candidates[:limit]:
				print("        %s  [%d matching IDs] <- %s" % (
					candidate["pathname"], len(candidate["file_ids"]), ", ".join(candidate["packages"])))
			if len(candidates) > limit:
				print("        ... %d more (use --json for the full list)" % (len(candidates) - limit))
		if analysis["unversioned_consumers"]:
			unversioned = analysis["unversioned_consumers"]
			print("\n    consumers in packages that do not carry this model: %d assets" % len(unversioned))
			for consumer in unversioned[:limit]:
				print("      %s <- %s" % (consumer["pathname"], ", ".join(consumer["packages"])))
			if len(unversioned) > limit:
				print("      ... %d more (use --json for the full list)" % (len(unversioned) - limit))
	if len(analyses) > limit:
		print("\n  ... %d more models (use --json for the full list)" % (len(analyses) - limit))
	print("\n  Limitation: %s" % report["model_consumer_analysis_limitation"])


def main() -> int:
	parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	parser.add_argument("packages", nargs="+", help="two or more .unitypackage files")
	parser.add_argument("--json", action="store_true", help="emit JSON instead of a text summary")
	parser.add_argument("--limit", type=int, default=20, help="conflicting assets to list per section (default 20)")
	args = parser.parse_args()

	paths = [os.path.abspath(os.path.expanduser(p)) for p in args.packages]
	for p in paths:
		if not os.path.isfile(p):
			print("No such package: " + p, file=sys.stderr)
			return 1
	if len(paths) < 2:
		print("Need at least two packages to compare", file=sys.stderr)
		return 1
	try:
		labels = package_labels(paths)
	except ValueError as error:
		print(str(error), file=sys.stderr)
		return 1

	if not args.json:
		print("scanning %d packages..." % len(paths), file=sys.stderr)
	with concurrent.futures.ProcessPoolExecutor() as pool:
		scanned_list = list(pool.map(scan, paths))
		scanned = dict(zip(labels, scanned_list))
		preliminary = analyze(scanned)
		model_guids = tuple(
			detail["guid"] for detail in preliminary["conflicts"]
			if os.path.splitext(detail["pathname"])[1].lower() in MODEL_EXTENSIONS)
		if model_guids:
			reference_list = list(pool.map(
				scan_consumer_references,
				paths,
				scanned_list,
				itertools.repeat(model_guids),
			))
		else:
			reference_list = [{} for _path in paths]
	references = dict(zip(labels, reference_list))
	report = analyze(scanned, references)

	if args.json:
		json.dump(report, sys.stdout, indent=2)
		sys.stdout.write("\n")
		return 0

	print("\n=== packages")
	for name, count in report["packages"].items():
		print("  %-40s %6d assets" % (name, count))

	print("\n=== GUID overlap")
	print("  distinct GUIDs across all packages   %6d" % report["distinct_guids"])
	print("  carried by more than one package     %6d" % report["shared_guids"])
	print("    identical everywhere               %6d  (benign)" % report["shared_identical"])
	print("    different content per package      %6d  (last import wins)" % report["shared_conflicting"])
	print("    different .meta per package        %6d  (import settings differ)" % report["shared_meta_conflicting"])

	if report["conflicts_by_extension"]:
		print("\n=== conflicting assets by type")
		for ext, count in report["conflicts_by_extension"].items():
			print("  %-14s %d" % (ext or "(none)", count))

	models = [d for d in report["conflicts"] if os.path.splitext(d["pathname"])[1].lower() in MODEL_EXTENSIONS]
	if models:
		print("\n=== conflicting models (other assets reference sub-objects inside these)")
		for detail in models[: args.limit]:
			print("\n  %s" % detail["pathname"])
			for version in detail["versions"]:
				print("    %s  %10d bytes  <- %s"
					% (version["sha"][:12], version["size"] or -1, ", ".join(version["packages"])))

	print_model_consumer_analysis(report, args.limit)

	others = [d for d in report["conflicts"] if d not in models]
	if others:
		print("\n=== other conflicting assets (%d)" % len(others))
		for detail in others[: args.limit]:
			print("  %-64s %d versions" % (detail["pathname"][:64], len(detail["versions"])))
		if len(others) > args.limit:
			print("  ... %d more (use --json for the full list)" % (len(others) - args.limit))

	print("\n=== pathname collisions between different GUIDs")
	if not report["path_collisions"]:
		print("  none")
	else:
		for pathname, guids in list(report["path_collisions"].items())[: args.limit]:
			print("  %s  <- %s" % (pathname, ", ".join(guids)))

	if report["shared_conflicting"] or report["path_collisions"]:
		print("\nImporting these together is order-dependent. Verify the packages that")
		print("were imported first still hold up afterwards, not only the last one.")
	return 0


if __name__ == "__main__":
	sys.exit(main())

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

Use --json for machine-readable output.
"""
import argparse
import collections
import concurrent.futures
import hashlib
import json
import os
import sys
import tarfile

# A .unitypackage is a gzipped tar of <guid>/{pathname,asset,asset.meta,...}.
# Streaming mode ("r|gz") rejects the headers some of these archives carry, so
# they are read in random-access mode but still traversed in order.
MODEL_EXTENSIONS = (".fbx", ".obj", ".dae", ".gltf", ".glb", ".blend")


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


def label(path: str) -> str:
	return os.path.basename(path).rsplit(".unitypackage", 1)[0]


def analyze(packages: dict) -> dict:
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
			by_path[record.get("pathname")].add(guid)
	collisions = {p: sorted(g) for p, g in by_path.items() if len(g) > 1}

	def path_of(holders):
		return next(iter(holders.values())).get("pathname", "?")

	def versions(holders):
		groups = collections.defaultdict(list)
		for name, record in holders.items():
			groups[record.get("sha")].append(name)
		return [
			{"sha": sha, "size": holders[names[0]].get("size"), "packages": sorted(names)}
			for sha, names in sorted(groups.items(), key=lambda kv: -len(kv[1]))
		]

	conflict_details = sorted(
		({"guid": g, "pathname": path_of(h), "versions": versions(h)} for g, h in conflicts.items()),
		key=lambda d: d["pathname"],
	)
	return {
		"packages": {n: len(e) for n, e in packages.items()},
		"distinct_guids": len(owners),
		"shared_guids": len(shared),
		"shared_identical": len(shared) - len(conflicts),
		"shared_conflicting": len(conflicts),
		"shared_meta_conflicting": len(meta_conflicts),
		"conflicts_by_extension": dict(collections.Counter(
			os.path.splitext(d["pathname"])[1].lower() for d in conflict_details).most_common()),
		"conflicts": conflict_details,
		"path_collisions": collisions,
	}


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

	if not args.json:
		print("scanning %d packages..." % len(paths), file=sys.stderr)
	with concurrent.futures.ProcessPoolExecutor() as pool:
		scanned = dict(zip((label(p) for p in paths), pool.map(scan, paths)))
	report = analyze(scanned)

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

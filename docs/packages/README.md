# Package validation reports

One file per `.unitypackage` that has been validated against this fork. The main
[README](../../README.md) documents what Unidot converts in general; these
reports carry the figures for a specific package.

- [Synty POLYGON - Prototype Pack](./polygon-prototype.md)
- [Synty POLYGON - Starter Pack](./polygon-starter.md)

Reports are written in English only. Their figures change with every import run,
and keeping two translations of them in step is not worth the drift.

## Producing a report

Validate each package in its own throwaway Godot project. A package must not
share a project with another one while you are measuring it: the asset database
keeps one active output path per Unity GUID, Godot caches imports under
`.godot/`, and Synty packages overlap heavily — the POLYGON Prototype pack is
`1,247` PolygonGeneric assets against `1,043` of its own. Numbers collected from
a shared project cannot be attributed to one package.

`tools/validate_package.py` scaffolds that project and can run the import:

```bash
tools/validate_package.py "~/art/POLYGON - Prototype Pack.unitypackage" --run
```

It creates `<package-name>_validate/` next to the package, syncs this checkout
into it as `addons/unidot_importer`, generates a bootstrap plugin that drives the
import dialog headlessly, and records the Unidot revision in
`validation_context.json` so the report can state what produced its figures. Use
`--root` to put the project elsewhere, `--name` to override the directory name,
and `--clean` to reset a previous import before re-running.

`--clean` removes the output tree, the asset database **and** `.godot/`. Deleting
only the output tree leaves stale artifacts in Godot's import cache that will
skew the next run.

## What a report should separate

Synty ships a shared PolygonGeneric library inside its packages. Diagnostics
raised against that shared content will repeat in every package that carries it —
all `13` errors in the POLYGON Prototype report come from PolygonGeneric, not
from POLYGON Prototype itself. Split pack-specific from shared content so
packages stay comparable, and say which side a figure belongs to.

Importing several packages into one project is a separate scenario worth testing
deliberately, since that is what a real project does and it is the only case
where GUID overlap between packages is exercised. Keep it out of the per-package
measurements.

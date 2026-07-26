# Validation tooling

Scripts for checking that a `.unitypackage` converted correctly. They are split
by how far they generalize, because conflating the two produces checks that
quietly assume one publisher's conventions.

```
tools/
  validate_package.py     scaffold an isolated project and run the import
  checks/                 vendor-neutral: applies to any .unitypackage
  publishers/<vendor>/<pack>/   specific to one publisher, or one pack
```

## `validate_package.py`

Creates a throwaway Godot project for one package, syncs this checkout into it
as `addons/unidot_importer`, and optionally runs the import headlessly.

```bash
tools/validate_package.py "~/art/Some Pack.unitypackage" --run
```

See [docs/packages/](../docs/packages/README.md) for why each package needs its
own project and what a report should record.

## `checks/`

Vendor-neutral. A check belongs here only if it is meaningful without knowing
who made the package.

- `import_report.py <project_dir>` — summarizes an import: engine diagnostics
  (dead texture references embedded in the source FBX files, case mismatches,
  missing GUID dependencies), Unidot's own warnings grouped by class, and an
  inventory of what was produced. `--json` for machine-readable output.

## `publishers/`

Everything else. A check lands here when it depends on knowing which prefabs
matter, what a pack is supposed to contain, or how a publisher names things.
Resist the urge to promote these into `checks/` by adding parameters: a gate
that needs to be told which eight prefabs to look at is not a general gate, it
is a specific one wearing a costume, and the pack-specific knowledge is the part
worth keeping.

- `synty/polygon-prototype/gate_fps_arms.py` — checks that every bone of every
  `Skin` in the eight FPS arm prefabs deforms rigidly (`D = G_bone x bind` is
  the identity). Written for the defect described in
  [the POLYGON Prototype report](../docs/packages/polygon-prototype.md#humanoid-skinning-correctness);
  the prefab list and the reason for caring about these particular prefabs are
  both specific to that pack.

  Requires the converted scenes as text (`.tscn`). It parses them rather than
  loading them, so it runs without Godot.

New publishers get a sibling directory. Nothing in `checks/` may import from
`publishers/`.

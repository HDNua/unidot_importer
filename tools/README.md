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

Creates a throwaway Godot project, syncs this checkout into it as
`addons/unidot_importer`, and optionally runs the import headlessly.

```bash
tools/validate_package.py "~/art/Some Pack.unitypackage" --run
```

See [docs/packages/](../docs/packages/README.md) for why each package needs its
own project and what a report should record.

Given several packages it imports them into one project in the order given, one
stage per package, with its own `import.<n>.log`. That is the integration case,
not a way to measure a package — figures from a shared project cannot be
attributed to one of them.

```bash
tools/validate_package.py A.unitypackage B.unitypackage --run --verify
```

`--verify` runs `checks/verify_output.gd` after *every* stage rather than at the
end. That is the whole point: the integration question is not whether the last
package imported, it is whether the earlier ones survived it.

## `checks/`

Vendor-neutral. A check belongs here only if it is meaningful without knowing
who made the package.

- `import_report.py <project_dir>` — summarizes an import: engine diagnostics
  (dead texture references embedded in the source FBX files, case mismatches,
  missing GUID dependencies), Unidot's own warnings grouped by class, and an
  inventory of what was produced. `--stage N` restricts it to one stage of a
  multi-package project; `--json` for machine-readable output.

- `verify_output.gd <project>` — correctness pass over the output tree: every
  scene loads and instantiates, every node a scene declares still exists after
  instantiation, and every `MeshInstance3D` has a mesh. Also reports how many
  converted materials bind a texture, without a verdict. GDScript rather than
  Python so it reads the resources directly instead of parsing `.tscn` text,
  which means it also works on binary output.

  ```bash
  Godot --headless --path <project> -s addons/unidot_importer/tools/checks/verify_output.gd
  ```

  It deliberately does **not** check skin deformation. See below.

- `package_overlap.py A.unitypackage B.unitypackage [...]` — static comparison,
  no Godot and no import. Reports GUIDs carried by more than one package, split
  into identical (benign) and conflicting (the last import wins), plus pathname
  collisions between different GUIDs. Run it before an integration import: it
  predicts what will contend, and conflicting *models* are called out separately
  because other assets reference sub-objects inside them by file ID.

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

- `synty/polygon-prototype/gate_fps_arms.gd` — the same subject in GDScript, so
  it also works on the binary `.scn` output that `validate_package.py` produces.

### Why the skinning gate is here and not in `checks/`

It looks vendor-neutral and is not. The test — `D = global_bone_pose * bind_pose`
must be the identity — only holds when the skeleton sits at the pose its meshes
were bound in, and there is no way to establish that independently, because the
identity *is* the test. A prefab authored in any other pose fails it while
rendering perfectly.

Measured on POLYGON Prototype: the eight FPS arm prefabs satisfy the identity on
every bind, while the `39` PolygonGeneric character prefabs in the same project
miss it on `22,737` binds and render correctly anyway — they are simply not
stored at their bind pose. Rendering them confirmed it. Knowing which prefabs
are at bind pose is knowledge about how a publisher authors a pack, which is
exactly the kind of thing this directory is for.

New publishers get a sibling directory. Nothing in `checks/` may import from
`publishers/`.

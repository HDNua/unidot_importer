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

It also accepts Unity `Assets` directories. Use the preservation switches when
the output is intended for editor-side migration work rather than a compact
binary validation artifact:

```bash
tools/validate_package.py "/path/to/UnityProject/Assets" --run --verify \
  --text-scenes --preserve-yaml --add-unsupported
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
  because other assets reference sub-objects inside them by file ID. For each
  conflicting model build, a second pass groups the file IDs referenced by its
  accompanying text assets and reports both replacement directions, including
  the candidate consumer assets and their package provenance. `--json` retains
  file IDs as decimal strings so signed 64-bit values stay exact.

  The directional result is deliberately a **consumer-reference heuristic**.
  It does not inspect the replacement model's sub-object inventory: a file ID
  observed only in one side's consumers is a review candidate, not proof that
  the other model lacks it. An empty difference likewise does not establish
  compatibility, a lossless import order, or a superset relationship.

- `unity_source_pose_gate.py PACKAGE PROJECT [--godot PATH] [--json]` — compares
  every bone pose in every converted skin-bearing prefab with its source-side
  baseline from the original Unity package and persisted conversion artifacts.
  The Python front end extracts only the source records needed for the
  comparison, then runs the
  GDScript worker in the converted Godot project. It prints the discovered and
  checked prefab counts, compared-bone counts, tolerances, largest observed
  errors, and any prefab/bone mismatches. A run also perturbs one compared bone
  in memory and requires the worker to detect it before reporting `PASS`, so an
  implementation that silently compares nothing cannot pass.

  ```bash
  python3 tools/checks/unity_source_pose_gate.py \
    "Some Pack.unitypackage" /path/to/converted-project
  ```

  This is a **source-consistency** gate, not an independent Unity rendering
  oracle. The direct branch compares authored prefab transforms after reusing
  Unidot's YAML parser and coordinate conversion, so defects shared by those
  components may be invisible. For FBX-backed prefab instances with no bone
  TRS overrides, the weaker branch separately instantiates both the persisted
  source-model scene and the final prefab. Saved AssetMeta supplies the exact
  fileID-to-nodepath-to-bone mapping; its original/delta data is used only for
  a rotation-consistency check, not as a numeric position oracle. The exact,
  uniquely resolved final bone names in the persisted active humanoid map
  (auto-detected first, authored fallback) define the required subset. Every
  other mapped bone with a saved original is cross-checked too; only
  non-required bones without one are reported as composition-only. Required
  and completed counts must agree, and total checks plus composition-only bones
  must equal all FBX bones. Model-level defects in FBX decoding,
  humanoid mapping, or delta generation can therefore be shared by both sides
  and remain invisible. Other inherited forms fail closed instead of being
  guessed at. Both the persisted source-model scene and final prefab must have
  a fully explained bone inventory.

  Synthetic identity roots in the direct branch are accepted only when their
  matched topology agrees with both persisted parent data and the independent
  authored `SkinnedMeshRenderer.m_Bones`/nonzero `m_RootBone` inventory. Every
  authored weighted `m_Bones` Transform must also be compared exactly once.
  FBX source YAML has no such bone inventory, so its corresponding proof must
  trust the persisted fileID/parent map; corruption that removes an authored
  root from that same map can remain invisible.

  The original `.unitypackage` and converted project are both required, and
  the checkout under `addons/unidot_importer` in that project must be current.
  The worker uses plain headless mode: it does not enable editor plugins or
  write project files.

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

The vendor-neutral source-pose gate above does not replace these two FPS-arm
gates. It accepts any authored pose and checks conversion consistency, while
the FPS gates deliberately assert the stronger bind-pose rigidity property for
eight known prefabs. That narrower regression caught the historical humanoid
Root-hijacking defect, so it remains in place.

### Why the skinning gate is here and not in `checks/`

It looks vendor-neutral and is not. The test — `D = global_bone_pose * bind_pose`
must be the identity — only holds when the skeleton sits at the pose its meshes
were bound in, and there is no way to establish that independently, because the
identity *is* the test. A prefab authored in any other pose fails it while
rendering perfectly.

Measured on POLYGON Prototype: the eight FPS arm prefabs satisfy the identity on
every bind. A broader scan examined `39` skin-bearing prefabs total, already
including those eight, and reported `22,737` failures across `20` posed
PolygonGeneric full-character prefabs plus one `Fov_01` check. The affected
characters render correctly anyway; they are not stored at their bind pose.
Knowing which prefabs satisfy the identity is knowledge about how a publisher
authors a pack, which is exactly the kind of thing this directory is for.

New publishers get a sibling directory. Nothing in `checks/` may import from
`publishers/`.

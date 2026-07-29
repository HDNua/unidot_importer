# Synty POLYGON - Starter Pack

*Read this report in [Korean](./polygon-starter.ko.md).*

Validation report for the Synty **POLYGON - Starter Pack** `.unitypackage`.
See [README.md](../../README.md) for what Unidot converts in general and for the
behaviour every Synty package shares; this file records only what is specific to
this package.

Tested on Godot `4.7.1-stable.mono` for macOS at importer revision `5576bf8`,
imported into `res://Unidot` by `tools/validate_package.py` in a project of its
own, then checked with `tools/checks/verify_output.gd` and
`tools/checks/import_report.py`.

**Result: the pack converts correctly.** Every generated scene loads and the
converted materials bind the textures they are supposed to. No defect specific
to this pack was found.

## Content split

The pack is mostly Synty's shared library rather than its own content, so most
figures below say more about PolygonGeneric than about the Starter Pack.

| Source folder | Output files |
| --- | ---: |
| `Assets/Synty/PolygonGeneric` | `2,495` |
| `Assets/Synty/PolygonStarter` | `481` |
| Total | `2,976` |

## Per-area result

| Area | Status | Evidence |
| --- | :---: | --- |
| Scenes and prefabs | OK | `499/499` load and instantiate (`496` prefabs, `3` authored scenes) |
| Materials converted from Unity `.mat` | OK | `45` of `55` bind a texture; the other `10` are cloud, glass, skybox, water and blank materials that carry no texture GUID in the Unity source either |
| Humanoid rigs and skinning | Not asserted | `4` prefabs contain skins; they satisfied the rigidity identity on `200` binds when this was measured at revision `5576bf8`, but see below |

The skin-deformation figure is recorded as an observation, not as a pass. The
identity it tests (`D = global_bone_pose * bind_pose` is `I`) only holds when a
prefab is stored at the pose its meshes were bound in, which is a property of
how the publisher authored the pack rather than of the conversion — see
[Several packages in one project](./multi-package.md#what-this-run-also-settled-the-skinning-check-was-not-vendor-neutral)
for the measurement that established this. `tools/checks/verify_output.gd` no
longer asserts it; the pack-specific gates under `tools/publishers/` do.

`507` materials extracted from model files bind no texture. That is expected
rather than a defect: those are the FBX files' own materials, which point at
paths that were never shipped (see the diagnostics below), and Unidot overrides
them from the Unity `.mat` assets after import.

## Import diagnostics

| Diagnostic | Count |
| --- | ---: |
| Engine-level `ERROR` lines | `5,426` |
| Dead texture references embedded in the source FBX files | `2,062` across `33` distinct files (`1,755` `.psd`, `303` `.png`, `4` `.tif`) |
| Missing GUID dependencies | `27` |
| Case-mismatch warnings | `5` |

All of these belong to classes 1 and 2 in
[Understanding the import diagnostics](../../README.md#understanding-the-import-diagnostics):
references the vendor shipped already broken. None of them corresponds to
something Unidot converted incorrectly.

Unidot's own per-asset warning and failure counters are not captured by a
headless run; they are shown in the import dialog. The engine-level figures
above come from the import log.

## Shared defects, not Starter defects

Two findings here are identical to the ones in the
[POLYGON Prototype report](./polygon-prototype.md), because both packs ship the
same PolygonGeneric library:

- The `5` case-mismatch warnings are for one file,
  `PolygonGeneric/Textures/Generic_Road_01.png`, requested through a lowercase
  `textures/` path — the engine defect described under
  [Known limitations](../../README.md#known-limitations).
- The same `23` extracted meshes carry that mis-cased reference.

Expect both to reappear in every Synty pack that carries PolygonGeneric. Count
them once against the shared library rather than once per pack.

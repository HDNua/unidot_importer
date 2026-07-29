# Unidot Importer

*Read this in [한국어](./README.ko.md).*

Unidot is a Unity-to-Godot source-asset translator for Godot 4. It converts
`.unitypackage` archives and extracted Unity asset folders into Godot scenes
and resources: for example, `.unity` and `.prefab` files become `.tscn`
scenes, while meshes, animations, materials, and other supported assets become
Godot-native resources.

This repository is the public
[HDNua fork](https://github.com/HDNua/unidot_importer) of
[V-Sekai/unidot_importer](https://github.com/V-Sekai/unidot_importer). It keeps
the upstream translator and adds Godot 4.7 compatibility work, an isolated
output root, reproducible package-validation tools, and fixes backed by public
regression tests. See [License and attribution](#license-and-attribution).

> [!IMPORTANT]
> The measured Godot 4.7.1 results below are compatibility evidence for the
> named packages and configuration, not a promise of lossless Unity project
> conversion. Scripts, custom shaders, and several engine features still need
> manual porting.

## Current fork status

- Upstream's documented compatibility range is Godot 4.0 through 4.2.
- This fork has compatibility fixes and measured package validation on
  Godot `4.7.1-stable.mono` for macOS.
- All six measured package imports completed. Cumulative structural output
  verification passed after stages 1 through 5 and failed after stage 6 because
  Fantasy Kingdom contains 52 reproducible meshless nodes. See
  [Measured package status](#measured-package-status).
- All six package-scoped source-pose gates passed in the final project, within
  that gate's documented source-consistency scope. This does not cancel the
  separate mesh-reference failure and is not an independent Unity rendering
  oracle.
- Thread-safe log collection has a synthetic multithreaded regression test.
  A production end-to-end gate using 10 workers with verbose logging is still
  pending, so production verbose-mode thread safety is not claimed complete.

The latest detailed evidence lives in the
[package report index](./docs/packages/README.md), its
[Korean edition](./docs/packages/README.ko.md), and the
[validation-tool documentation](./tools/README.md).

## Quick links

- [HDNua fork](https://github.com/HDNua/unidot_importer)
- [Upstream project](https://github.com/V-Sekai/unidot_importer)
- [Upstream website](https://unidotengine.org/)
- [Upstream documentation](https://docs.unidotengine.org/)
- [Discord community](https://discord.gg/JzXkxMRd9x)
- [Godot 4.7.1 compatibility tracking issue](https://github.com/HDNua/unidot_importer/issues/1)

## Requirements

Unidot has been used on Windows, macOS, and Linux. The current Godot 4.7.1
package measurements in this fork are macOS measurements; they do not establish
the same coverage for every OS and renderer combination.

The upstream FBX path uses
[FBX2glTF](https://github.com/godotengine/FBX2glTF/releases). Install it and set
the FBX2glTF executable in Godot's **Editor Settings → Import** when using that
path. The published Godot 4.7.1 package measurements used Godot's native FBX
importer, so do not assume identical results between the two FBX paths.

At least 16 GB of RAM is recommended for large packages. Unidot pre-parses many
assets and can use 10–12 GB during large imports; virtual-memory swapping is
expected to be slower but is not by itself a failure.

## Installation and use

1. Place this repository at `addons/unidot_importer` in a Godot project, for
   example as a Git submodule or an extracted archive.
2. Enable **Unidot Importer** under **Project Settings → Plugins**.
3. Configure FBX2glTF in **Editor Settings → Import** when using the upstream
   FBX2glTF path.
4. For TIFF/`.tif` and PSD/`.psd` support, install
   [ImageMagick](https://imagemagick.org/) or
   [GraphicsMagick](http://www.graphicsmagick.org/) in the system path, or place
   `convert.exe` in this add-on directory on Windows.
5. Open **Project → Tools → Import .unitypackage...** and select a package or an
   asset folder.

Converted scenes can reference `runtime/anim_tree.gd`. Keep that file if you
remove the rest of the importer after conversion.

![FBX2glTF in Editor Settings and the plug-in enabled in Project Settings](./unidot_instructions.png)

### Import destination

The import dialog can place translated assets below a project-relative output
root without changing their Unity source paths. The backward-compatible default
is `res://`. Selecting `res://Unidot`, for example, maps:

```text
Assets/Example/Model.fbx -> res://Unidot/Assets/Example/Model.fbx
```

A project can provide a default with the `unidot/import_output_root` setting.
The destination must stay inside `res://`; absolute paths, `user://`,
backslashes, and relative `.` or `..` segments are rejected.

When a non-root destination is used, fallback texture and material searches are
confined to that destination. This prevents unrelated assets already present in
the project from being linked by fallback lookup. The importer assumes a
trusted project tree and does not sandbox writes against pre-existing symlinks
or junctions. The asset database retains one active output path per Unity GUID,
so importing the same package into several destinations in one project is not
supported.

## What Unidot converts

- Unity `.unitypackage` archives and extracted asset folders
- Unity scenes and prefabs, including inherited prefabs
- Meshes, MeshFilter, MeshRenderer, and SkinnedMeshRenderer
- Standard materials and supported texture properties
- Avatar and AnimationClip resources
- AnimatorController, state machines, transitions, and blend trees
- GameObject, Transform, colliders, Rigidbody, Light, Camera, and AudioSource
- Texture2D, CubeMap, Texture2DArray, and AudioClip
- Terrain, with limited detail-mesh support through MultiMeshInstance
- LightingSettings and PostProcessLayer at their documented conversion scope
- A deterministic common subset of ParticleSystem and ParticleSystemRenderer

The fork also preserves GameObject active-in-hierarchy state and renderer
visibility, validates structurally inconsistent humanoid maps before using
them, handles duplicated bone names across hands, and recognizes common
underscored Unity texture properties such as `_Albedo_Map`, `_Base_Map`,
`_Normal_Map`, and `_Emission_Map`.

## Unsupported or partial

- Unity C# scripts and MonoBehaviour behavior are not ported.
- ShaderGraph and SubGraph semantics are not translated. Source files are
  preserved for manual porting.
- Custom shaders need manual Godot equivalents.
- Canvas/UI, AvatarMask, and PlayableDirector are not implemented.
- ParticleSystem conversion covers a deterministic common subset. Unsupported
  modules and approximations emit explicit warnings.
- Unity realtime GI has no direct Godot LightmapGI equivalent; supported
  lightmap authoring values are preserved, while realtime intent is metadata.
- Anything not listed as supported should be treated as unsupported until
  measured.

## Reproducible validation

The repository includes a headless validation harness. It is intended for
repeatable testing and report production; it is not yet a stable general-purpose
headless import API.

### One package in isolation

`tools/validate_package.py` creates a throwaway Godot project, copies the
current checkout into `addons/unidot_importer`, imports into
`res://Unidot`, and can verify the result:

```bash
python3 tools/validate_package.py "/path/to/Pack.unitypackage" --run --verify
```

The sync copies the working tree except `.git`, so run it from a clean checkout
to keep untracked or local files out of the validation project.

Use a separate clean project for every per-package report. This keeps its GUID
database, Godot import cache, output, and diagnostic counts attributable to that
package.

### Several packages in one project

Package integration is a different test. Compare archives first, then import in
an explicit order and verify after every stage:

```bash
python3 tools/checks/package_overlap.py A.unitypackage B.unitypackage
python3 tools/validate_package.py A.unitypackage B.unitypackage --run --verify
```

The tools have deliberately separate responsibilities:

- `import_report.py` classifies stage-scoped diagnostics and inventories
  output; `--json` provides machine-readable output.
- `verify_output.gd` loads and instantiates every generated scene, checks that
  every declared node path survives instantiation, and rejects meshless
  `MeshInstance3D` nodes.
- `package_overlap.py` reports shared GUIDs, conflicting bytes, metadata
  differences, path collisions, and directional model-consumer review
  candidates without running Godot.
- `unity_source_pose_gate.py` checks converted skin-bearing prefabs against
  source-side and persisted-conversion evidence and includes negative controls.
  Its documented weaker FBX branch is a source-consistency check, not an
  independent Unity renderer.
- Publisher-specific gates remain under `tools/publishers/`; they are not
  promoted to vendor-neutral checks.

These checks establish specific structural and source-consistency invariants.
They do not prove visual, behavioral, shader, or gameplay parity. Generated
validation context can contain local source paths; review it before publishing.
See [tools/README.md](./tools/README.md) for the full contracts.

## Measured package status

The two packages marked **isolated** have a full dedicated-project report.
Town, War, and Sci-Fi City currently have only cumulative staged-integration
evidence, so their PASS rows must not be presented as isolated package
measurements. Fantasy Kingdom has the staged result plus a focused clean
single-package control that reproduced the same failure.

| Publisher | Package | Evidence available | Measured result | English | 한국어 |
| --- | --- | --- | --- | --- | --- |
| Synty Studios | POLYGON - Starter Pack | Isolated report; six-pack stage 1 | Isolated conversion OK; stage PASS | [Report](./docs/packages/polygon-starter.md) | [리포트](./docs/packages/polygon-starter.ko.md) |
| Synty Studios | POLYGON - Town Pack | Six-pack cumulative stage 2 only | Stage PASS | [Integration report](./docs/packages/multi-package.md) | [통합 리포트](./docs/packages/multi-package.ko.md) |
| Synty Studios | POLYGON - War Pack | Six-pack cumulative stage 3 only | Stage PASS | [Integration report](./docs/packages/multi-package.md) | [통합 리포트](./docs/packages/multi-package.ko.md) |
| Synty Studios | POLYGON - Prototype Pack | Isolated report; six-pack stage 4 | Isolated conversion OK at documented scope; stage PASS | [Report](./docs/packages/polygon-prototype.md) | [리포트](./docs/packages/polygon-prototype.ko.md) |
| Synty Studios | POLYGON - Sci-Fi City Pack | Six-pack cumulative stage 5 only | Stage PASS | [Integration report](./docs/packages/multi-package.md) | [통합 리포트](./docs/packages/multi-package.ko.md) |
| Synty Studios | POLYGON - Fantasy Kingdom Pack | Six-pack stage 6; focused clean control | **FAIL / known model-reference limitation** | [Integration report](./docs/packages/multi-package.md) | [통합 리포트](./docs/packages/multi-package.ko.md) |

All rows above were measured with Godot `4.7.1-stable.mono` on macOS, but at
the importer revisions recorded in the linked reports. Do not silently
inherit those results after converter changes.

### Six-package staged run

At importer revision `c0892c5`, a clean project imported Starter → Town → War
→ Prototype → Sci-Fi City → Fantasy Kingdom. Every import completed. Each row
below is cumulative and verifies the whole project after adding that package:

| Stage | Package added | Scenes loaded / instantiated | Declared paths / missing | Mesh nodes / meshless | Verify |
| ---: | --- | ---: | ---: | ---: | --- |
| 1 | Starter | `499/499` | `2,855 / 0` | `1,422 / 0` | PASS |
| 2 | Town | `1,253/1,253` | `12,214 / 0` | `8,037 / 0` | PASS |
| 3 | War | `1,840/1,840` | `21,133 / 0` | `15,336 / 0` | PASS |
| 4 | Prototype | `2,340/2,340` | `25,091 / 0` | `17,663 / 0` | PASS |
| 5 | Sci-Fi City | `2,979/2,979` | `32,146 / 0` | `22,974 / 0` | PASS |
| 6 | Fantasy Kingdom | `5,175/5,175` | `77,811 / 0` | `58,646 / 52` | **FAIL** |

The 52 findings are 17 direct meshless nodes in 16 Fantasy prefabs and 35 uses
of those prefabs in three Fantasy scenes. A clean Fantasy-only control loaded
and instantiated `2,687/2,687` scenes with zero missing declared paths and
reproduced the exact same 52 meshless nodes. The current evidence points to a
Fantasy-local model sub-object/file-ID resolution limitation, not a shared-GUID
overwrite by one of the preceding five packages.

The measured order avoided one previously reproduced content-loss case in which
Town replaced a shared character model after Prototype. It is a risk-minimizing
validation order, not a proof of a lossless or universally safe order. The only
directional constraint supported by current evidence is to put Town and War
before Fantasy Kingdom, Prototype, or Sci-Fi City. Read the bilingual
integration report before combining these packs:
[English](./docs/packages/multi-package.md) ·
[한국어](./docs/packages/multi-package.ko.md).

## Understanding the import diagnostics

A large engine `ERROR` count or a non-zero Unidot warning counter is not, by
itself, a conversion verdict. Observed package diagnostics include:

1. dead texture paths embedded in vendor FBX files;
2. GUID references already missing from the source package;
3. explicit notices for unsupported or approximated features;
4. importer validators reporting that they rejected inconsistent source data.

Use `import_report.py`, the output verifier, and the package report together.
Do not assume every error is harmless: script errors, missing declared nodes, or
meshless output can still be real importer defects.

![A completed POLYGON Prototype import with non-zero warning and error counters](./hdnua_import_dialog.png)

## Known limitations

- Fantasy Kingdom currently reproduces 52 meshless nodes because some Unity
  model sub-object/file-ID references do not resolve to Godot's extracted
  meshes. This is the current public conversion blocker documented above.
- Godot's FBX texture probing can preserve a lowercase `textures/` spelling
  after opening `Textures/` on a case-insensitive filesystem. The resulting
  extracted-mesh reference can fail on a case-sensitive filesystem; converted
  Unity `.mat` resources are unaffected.
- Reimporting animations can lose corrected track paths because scenes modify
  animations during import.
- Missing GUID references are not always obvious in source content.
- Humanoid rigs missing UpperChest, Shoulder, or Neck, rotated hips, scaled
  armatures, and unpacked humanoid prefabs can still require review.
- Non-weight-painted vertices currently fall back to skeleton bone index 0.
- FBX conversion paths can have their own limitations, including n-gons and
  RotationPivot handling.
- Dependency selection does not discover every texture referenced by a model.
- Import can consume substantial memory and appear unresponsive during large
  animation phases.

## Troubleshooting

- Open **Project → Tools → Show last import logs** after an interactive import.
  Yellow and red columns show grouped diagnostics; a file's **Logs** button
  shows its complete log.
- Confirm that all referenced dependencies were included.
- If a large import crashes, reproduce it with a smaller package or subset.
- For subset imports, import textures before materials, and models/materials
  before scenes. Shift-selection helps but does not discover every dependency.
- If a scene model looks corrupted and uses an unpacked prefab, compare it with
  the converted original model scene.
- For repeatable bug reports, use an isolated project and record the Godot
  version, importer commit, FBX path, command, and verification result. Do not
  publish licensed asset bytes or local source paths.

## Project scope

Unidot translates usable source assets made for editor workflows. It does not
decompile asset bundles or rip game content, and there are no plans to add
those capabilities. Use only assets you have the right to convert.

## License and attribution

This fork remains licensed under the repository's [MIT license](./LICENSE.txt).
The original copyright and permission notices remain in that file. Unidot was
created by Lyuma and contributors, with work from the V-Sekai community and the
other contributors credited by the upstream project.

Special thanks retained from upstream:

- Cthulhoo, for humanoid-rig and root-motion test cases and insight.
- Stan, for game-jam projects with varied prefab-reference patterns.
- Everyone who contributed test assets and reports.
- The [V-Sekai community](https://github.com/V-Sekai) and
  [V-Sekai team](https://v-sekai.org).

![Synty POLYGON Prototype demo imported with Unidot in Godot 4.7.1](./hdnua_synty_polygon_prototype_godot_4_7_1.png)

![An Unidot import dialog over a converted scene](./unidot_example.jpg)

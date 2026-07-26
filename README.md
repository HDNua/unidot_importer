# Unidot Importer

*Read this in [한국어](./README.ko.md).*

Unify your Godot asset interop with **Unidot**, a **Uni**versal Go**dot** Engine source asset translator and interoperability pipeline for Godot 4.

At its heart, Unidot Importer can convert `.unitypackage` assets and asset folders into Godot 4.x compatible formats.

It takes original **source assets** and *translates* them into Godot native equivalents.
For example, `.unity` and `.prefab` become `.tscn` and `.prefab.tscn`.

FBX Files are currently ported to glTF but this may be made more flexible in the future.

Raw mesh, anim, material assets and more are converted directly to godot `.tres/.res` equivalents.

Due to being a translator, Unidot may safely be removed from the project when completed. (other than `runtime/anim_tree.gd`)

## Quick links

- [Follow updates at https://unidotengine.org/](https://unidotengine.org).
- [Read documentation at https://docs.unidotengine.org/](https://docs.unidotengine.org).
- [Join our community on Discord](https://discord.gg/JzXkxMRd9x) for help, to share success or feedback.

## Made for Godot Engine 4

We rely on automatic FBX to glTF translation during `.unitypackage` import using FBX2glTF. [please download the FBX2glTF exe](https://github.com/godotengine/FBX2glTF/releases) and configure FBX Import in Godot Editor Settings before using Unidot.

Please use a version of Godot 4.0 or later with FBX2glTF configured in Editor Settings to run this addon.

## System requirements:

Unidot has been tested on Windows, macOS and Linux versions. It supports Godot Editor versions 4.0 through 4.2, with compatibility smoke-tested on Godot 4.7.1.

Unidot recommends a system with at least 16GB of RAM for many assets. It is uncommon for large imports to take more than 10-12GB.

Due to pre-caching of assets in memory, it is okay if some data is swapped to disk with virtual memory, especially in large imports of thousands of files..

## Installation:

1. This repository should be imported at `addons/unidot_importer` in the project, such as using git submodule or unzipping.
   * Note that `runtime/anim_tree.gd` will be referenced by scenes and should be kept even if the rest of unidot is removed.
2. Enable the Unidot Importer plugin in `Project Settings -> Plugins tab -> Unidot`
3. Unidot requires an installation of FBX2glTF from https://github.com/godotengine/FBX2glTF/releases and set in the FBX2glTF.exe path in the Import category of **Editor Settings** (not Project Settings)
4. To add TIFF / .tif and PSD / .psd support, install [ImageMagick](https://imagemagick.org/) or [GraphicsMagick](http://www.graphicsmagick.org/) into your system path or copy convert.exe into this addon directory.
5. Access the importer through `Project -> Tools -> Import .unitypackage...` and select a package or an asset folder

### Import destination

The import dialog can place translated assets below a project-relative destination
without changing their Unity source paths. The default remains `res://` for
backward compatibility. For example, selecting `res://Unidot` maps:

```text
Assets/Example/Model.fbx -> res://Unidot/Assets/Example/Model.fbx
```

Projects may provide a default with the `unidot/import_output_root` project
setting. The destination must remain inside `res://`; absolute paths, `user://`,
backslashes, and relative `.` or `..` segments are rejected.
When a non-root destination is selected, fallback texture and material searches
are confined to that destination so existing project assets are not linked by
accident.
The importer assumes a trusted project tree and does not sandbox writes against
pre-existing symlinks or junctions inside the project.
The asset database keeps one active output path per Unity GUID, so importing the
same package into multiple destinations in one project is not supported.

![Screenshot showing FBX2glTF in Editor Settings, and enabling the plugin in Project Settings](./unidot_instructions.png)

Read more at our [documentation site](https://docs.unidotengine.org).

## Features

- `.unitypackage` importer and translation shim.
- Translates native filetypes (such as .unity or .mat) to Godot native scene or resource types.
- Animation and animation tree porting, including humanoid .anim format.
- Support for humanoid armatures, including from prefabs, unpacked prefabs and model import.
- Translates prefabs and inherited prefabs to native Godot scenes and inherited scenes.
- Supports both binary and text YAML encoding
- Implementation of an asset database by GUID

Note that scripts and shaders will need to be ported by hand. However, it will be possible to map scripts/shaders to Godot equivalents after porting.

## Supported asset types:

* Mesh/MeshFilter/MeshRenderer/SkinnedMeshRenderer
* Material (standard shader only)
* Avatar
* AnimationClip
* AnimatorController (relies on small runtime helper script `unidot_importer/runtime/anim_tree.gd`)
* AnimatorState/AnimatorStateMachine/AnimatorTransitionBase/BlendTree
* PrefabInstance (prefabs)
* GameObject/Transform/Collider/SkinnedMeshRenderer/MeshFilter/Animator/Light/Camera etc. (scenes)
* Texture2D/CubeMap/Texture2DArray etc.
* AssetImporter
* AudioClip/AudioSource
* Collider/Rigidbody
* Terrain (limited support for detail meshes as MultiMeshInstance)
* LightingSettings/PostProcessLayer

## Unsupported

* Shader: a system may someday be added to create mappings of equivalent Godot Engine shaders, but porting must be done by hand.
* MonoBehaviour (C# Script porting)
* AvatarMask (waiting for better Godot engine support)
* Canvas / UI is not implemented.
* PlayableDirector
* Anything not listed above

## Troubleshooting

* If an import fails, it is possible to view the logs of the most recently completed import.
	* Use `Project -> Tools -> Show last import logs`.
	* Click the yellow or red columns to see all errors in the project.
	* Or, click a Logs button on a file to see the entire log.
	* Clicking the Logs for Assets may take time to collect all logs in the project, but can be helpful for submitting a bug report.
	* The Godot console output may also be helpful if submitting a bug report.

* It would be good to double check that all dependencies imported, and then try again.

* If Godot crashes during an import, it may be good to try a smaller import.

* If importing a subset of files, import assets in the correct order: make sure to do materials after textures, and scenes after models / materials they may need.
  Using the shift key while selecting assets can ensure you include the needed depdencies.

* If models in a scene are looking corrupted, it may be due to the scene using unpacked prefabs. In this case, replacing them with the original converted ".gltf" should work.

## Known issues

- There may be large memory consumption in the earlier phases of the import process. Unidot will pre-parse most assets upfront in the "Preprocessing" stage.
  Additionally, Godot may read textures from disk while assigning materials.
- Due to memory constraints, large animation files currently import in the main thread.
	- This could cause Godot to hang or freeze for a long time in animation packs with a message such as "Importing 50 textures, animations and audio...".
- Reimporting animations after import can lose the correct track paths, since the animations are modified during scene import.
- Unidot does not indicate clearly when assets are missing GUID references. Models missing referenced data may not import correctly.
- Models missing UpperChest, Shoulder or Neck bones may animate incorrectly due to lack of missing bone compensation in Godot's Humanoid retargeter.
- Unpacked prefabs of humanoid models may malfunction due to the retargeting.
  Unidot does its best to correct these cases, but some models, especially those with rotated hips and scaled armature, may malfunction.
- non-weight-painted vertices currently go to skeleton origin instead of hips (bone index 0)
- FBX2glTF which is used to convert .fbx to .gltf has some rare bugs. These would currently affect all FBX imports into Godot Engine.
	- Some rare fbx models with ngons may be missing triangles.
	- Models using RotationPivots may not have the meshes centered at the pivot points,
	  which could impact content or animations that expect the correct pivots.
- Shift to select dependencies does not find all texture assets referenced by models.

## Future work

- Repacking unpacked avatar prefabs where possible
- Better support for attaching outfits to imported models.
  For example, if any skinned meshes are humanoid but missing animator or no avatar set,
  treat skeleton hierarchy as having humanoid avatar enabled from that model.
- Reduce the dependency on FBX conversion tools

## A final note:

This tool is designed to assist with importing or translating source assets made for use in the editor. It makes an assumption that (other than animator controllers) most yaml files contain only one object).

Unidot solely translates existing usable source assets into equivalent Godot source assets. There are no plans to add functionality for decompiling asset bundles or ripping game content. That is not the goal of this project.

# Join our community

- [Follow updates at https://unidotengine.org/](https://unidotengine.org).
- [Read documentation at https://docs.unidotengine.org/](https://docs.unidotengine.org).
- [Join our community on Discord](https://discord.gg/JzXkxMRd9x) for help, to share success or feedback.

# Thanks

it is only thanks to all of you in the community using and supporting the project,
and for the many contributors that Unidot released in the form it has today <3

Special Thanks to

* Cthulhoo for some incredibly useful testcases for various humanoid rigs and animations,
  and for their explanation and insight into how Root Motion works that allowed me to implement RM support.
* Stan for sending over some really cool gamejam projects filled with all sorts of different ways to reference prefabs.
* And quite a number of others who provided test assets or testing.
* The [V-Sekai community](https://github.com/V-Sekai) for all your support.
* The [V-Sekai team](https://v-sekai.org) for contributions and inspiration.

![Screenshot showing an import dialog open with a scene underneath](./unidot_example.jpg)

## HDNua update

### Tested packages

| Publisher | Package | Tested with | Support | Report |
| --- | --- | --- | :---: | --- |
| Synty Studios | POLYGON - Prototype Pack | Godot `4.7.1-stable.mono`, macOS | △ Partial | [Details](./docs/packages/polygon-prototype.md) |
| Synty Studios | POLYGON - Starter Pack | Godot `4.7.1-stable.mono`, macOS | △ Partial | [Details](./docs/packages/polygon-starter.md) |

Each package is validated in its own throwaway project, scaffolded by
`tools/validate_package.py`. See
[docs/packages/](./docs/packages/README.md) for how a report is produced and
what it should separate.

Importing several packages into one project is a separate, order-dependent case:
where two packages ship the same Unity GUID with different content, the one
imported last replaces the file, and content converted from the earlier package
that referenced a part the replacement lacks is left incomplete. This is a
property of the packages, not of Unidot, and there is nothing in the archives
that says which version is intended. `tools/checks/package_overlap.py` reports
what will contend before you import, and
[Several packages in one project](./docs/packages/multi-package.md) records a
measured case.

`△ Partial` means the package has a validated usable subset, but the import is
not lossless and still requires review or manual porting for the gaps below. The
status stays `△` because ShaderGraph content is not translated at all — not
because the converted geometry is in doubt.

### What converts

| Area | Status | Notes |
| --- | :---: | --- |
| Meshes, transforms, prefab and scene hierarchy | ○ Converted | |
| Materials and albedo textures | ○ Converted | Underscored Unity texture properties such as `_Albedo_Map`, `_Base_Map`, `_Normal_Map`, and `_Emission_Map` are recognized, and mask, normal, metallic, roughness, and emission textures are prevented from being picked as generic albedo fallbacks |
| Collision shapes | ○ Converted | |
| GameObject active state and renderer visibility | ○ Converted | Combines the renderer's `m_Enabled` state with its source GameObject's active-in-hierarchy state, even when the mesh is deferred under a shared `Skeleton3D` |
| Humanoid rigs and skinning | ○ Converted | Including rigs whose Unity avatar is structurally invalid, and rigs with bone names duplicated across both hands |
| Scene root order | ○ Converted | |
| Lightmap authoring values | ○ Converted | Realtime GI intent is metadata only |
| ParticleSystem | △ Partial | The deterministic common subset converts; enabled modules outside it produce explicit warnings |
| Realtime GI | ✗ Not converted | Godot `LightmapGI` has no realtime equivalent |
| ShaderGraph and SubGraph | ✗ Not converted | Preserved as source for manual porting; semantics are not translated |

Per-package figures backing each row are in that package's report.

### Understanding the import diagnostics

Importing a Synty package prints a large number of engine-level `ERROR` lines
and leaves non-zero warning and error counters in the Unidot dialog. **This is
expected, and on its own it does not indicate a failed or incorrect
conversion.** Every diagnostic observed so far falls into one of four classes,
three of which are defects in the source package rather than in the conversion.

![The Unidot import dialog after a full POLYGON Prototype import, reporting 124 warnings and 13 errors alongside "Import complete."](./hdnua_import_dialog.png)

*What a successful import looks like: `Import complete.` with warnings and
errors still on the counters. The POLYGON Prototype report accounts for every
one of them.*

**1. Dead texture paths baked into the vendor's FBX files.** This is the source
of the thousands of red `ERROR` lines in the Godot console. Synty artists export
their FBX files with their own working textures still assigned — `.psd`, `.tif`,
and source `.png` files under their personal working folders, and in some cases
a plain `C:/Users/<artist>/Downloads/...` path. Those paths are stored verbatim
inside the shipped FBX, but the files themselves are not part of the
`.unitypackage`; only the flattened runtime `.png` atlases are. Unity never
surfaces this because it ignores FBX-embedded material references and binds
textures through the `.mat` asset's GUID instead. Godot's FBX parser is more
literal: it resolves each embedded path, fails, and reports it. This is cosmetic
because Unidot does not trust FBX-embedded materials either — it converts the
Unity `.mat` assets and assigns them after import.

**2. References the package ships already broken.** Prefabs can point at a mesh,
texture, or script GUID that no `.meta` file in the package owns, so the
reference is dead in Unity too. Unidot reports each one once as a structured
source-data failure, skips only the affected component, and converts the rest of
the object normally. These are what fill the red error counter in the dialog.

**3. Feature-gap notices.** Where Godot has no equivalent for a Unity feature —
most ParticleSystem modules, ShaderGraph semantics, realtime GI, lightmap values
outside Godot's supported range — Unidot converts what it can and warns
explicitly about what it approximated or skipped. These are the bulk of the
warning counter.

**4. Unidot's own validators reporting that they caught something.** The
humanoid bone-map validator logs a warning when it rejects a structurally
invalid Unity avatar and falls back to automatic bone mapping, and the `Root`
guard logs when it refuses to overwrite an existing profile mapping. A warning
from these means the defense worked.

Only one class of diagnostic points at a defect neither the package nor Unidot
can be blamed for; see [Known limitations](#known-limitations).

### Source-data defects Unidot defends against

Unity's humanoid avatar is used only for animation retargeting, and Unity draws
scenes straight from the original rig transforms. A badly authored avatar is
therefore invisible in Unity, but an importer that trusts it to rebuild the
skeleton will produce a collapsed mesh. Unidot validates a `humanDescription`
bone map against the rig hierarchy — every mapped bone's nearest mapped ancestor
must also be its ancestor in `SkeletonProfileHumanoid` — and falls back to
automatic humanoid bone mapping when the map is structurally inconsistent,
logging a warning that says so. A map with no `Hips` at all is rejected the same
way.

The POLYGON Prototype pack ships exactly such an avatar, and the
[package report](./docs/packages/polygon-prototype.md#source-data-defect-the-synty-humanoid-avatar)
walks through it as a worked example, including the before and after renders.

### Known limitations

The `△ Partial` status is intentional. ShaderGraph/SubGraph files are preserved
for manual porting, not converted to Godot shaders. ParticleSystem conversion
covers the common deterministic subset; modules such as Rotation, Noise,
Velocity, ClampVelocity, UV animation, Collision, bursts, and some shape or
billboard modes are omitted or approximated with explicit warnings. Unity
realtime GI is also not converted to a Godot realtime-GI system.
Active-state validation covers serialized base GameObject and renderer states;
arbitrary prefab overrides that toggle active state are not yet covered by any
package fixture.

One defect belongs to neither the package nor Unidot, and Unidot cannot correct
it. Godot's FBX importer resolves an embedded texture reference by probing
candidate directories, and one of those probes is a lowercase `textures/`. On a
case-insensitive filesystem that probe opens a file stored as `Textures/`, Godot
warns about the case mismatch, and the requested spelling is what gets written
into the extracted mesh. That reference then fails to load if the project is
exported to a case-sensitive filesystem. The converted `.mat` resources are
unaffected, so prefabs and scenes render correctly. Unidot cannot repair the
stored reference from its post-import script: it writes those `.mesh` files, but
Godot's own `save_to_file` subresource extraction rewrites the same paths
afterwards, so any correction made during post-import is overwritten. Fixing it
properly requires a change in the engine's texture probe or in how the model
`.import` configuration extracts meshes.

The red error counter in the Unidot log is a count of diagnostic messages, not
a count of unique failed files or failed scenes. A scene can load successfully
while an unsupported component or override inside it was skipped.

These are compatibility results for the packages and configuration listed above,
not a claim that every Synty package or every Unity feature is fully supported.
Custom ShaderGraph/SubGraph content, MonoBehaviours, advanced ParticleSystems,
realtime GI, and source assets with missing external references may still
require manual work.

![Synty POLYGON Prototype demo imported with Unidot in Godot 4.7.1](./hdnua_synty_polygon_prototype_godot_4_7_1.png)

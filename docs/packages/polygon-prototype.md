# Synty POLYGON - Prototype Pack

Validation report for the Synty **POLYGON - Prototype Pack** `.unitypackage`.
See [README.md](../../README.md) for what Unidot converts in general and for the
behaviour every Synty package shares; this file records only what is specific to
this package.

Tested on Godot `4.7.1-stable.mono` for macOS, importing with the native Godot
FBX importer into `res://Unidot`, saving translated resources and scenes as text.
Figures below are from importer revision `b60759d` unless noted.

## Per-area result

| Area | Status | Evidence |
| --- | :---: | --- |
| Meshes, transforms, prefab and scene hierarchy | OK | `498/498` prefabs and scenes instantiate; `989/989` generated scene resources load |
| Materials and albedo textures | OK | `121` of `139` converted materials bind a texture; the other `18` carry none in the Unity source either. All `13` representative albedo mappings matched |
| Collision shapes | OK | `0` missing bindings, except `13` colliders whose source mesh is absent from the package itself |
| GameObject active state and renderer visibility | OK | `32` variants produced exactly `8` visible and `24` hidden meshes, `0` mismatches |
| Humanoid rigs and skinning | OK at the documented source-consistency scope for all `39` skin-bearing prefabs; stronger bind-pose rigidity OK for the `8` FPS arm prefabs | Source consistency: `39/39` prefabs and `1,980` bone poses, `0` mismatches. FPS rigidity: `3,600` checks, `0` failures — see [below](#skinning-scope) |
| Scene root order | OK | Authored root order restored in the demo scene |
| Lightmap authoring values | OK | `2` bounces, directional mode, `0.025` texel scale, `2048` maximum texture size |
| ParticleSystem | Partial | All `30` ParticleSystem/ParticleSystemRenderer pairs produced `GPUParticles3D`; `108` warnings mark omitted or approximated modules |
| ShaderGraph and SubGraph | Not converted | All `25` files preserved as source, `0` `.failed_import` files |

## Source-data defect: the Synty humanoid avatar

The FPS arm prefabs in this package collapsed on import, and the cause was
neither Unidot nor Godot — it is an error in the Synty asset's own avatar data.

![The four Standard FPS arm prefabs before the fix: torn and twisted geometry](../../hdnua_arms_before.png)

*Before: the Standard FPS arm prefabs, torn apart by the bad avatar data.*

- `Character_FPSHands_01.fbx`, the model used by the Standard prefabs, ships a
  Unity avatar that maps `Hips → Root`, the rig root bone. That shifts the whole
  spine chain up by one level: `Spine ← Hips`, `Chest ← Spine_01`,
  `UpperChest ← Spine_02`, and `Spine_03` is left unmapped.
- `Character_FPSHands_02.fbx`, used by the FiveFinger prefabs, maps
  `Hips → Hips` and is correct. This is why the FiveFinger family always
  imported cleanly while the Standard family did not.

Why it looks fine in Unity: Unity uses the avatar mapping only for humanoid
animation retargeting, and draws the scene straight from the original rig
transforms. So a badly authored avatar is harmless in Unity, while Unidot
trusts that mapping and uses it to rebuild the skeleton — which is why the
breakage appears only in Godot. This is the point that was previously
misdiagnosed as an "engine problem". It is really a source-data defect, and one
the importer can defend against.

That defense now exists. Unidot validates a `humanDescription` bone map against
the rig hierarchy — every mapped bone's nearest mapped ancestor must also be its
ancestor in `SkeletonProfileHumanoid` — and falls back to automatic humanoid
bone mapping when the map is structurally inconsistent, logging a warning that
says so. A map with no `Hips` at all is rejected the same way.

## Humanoid skinning correctness

Revision `b60759d` closes the last known geometry defect for this package. The
converted FPS arm prefabs now reproduce the Unity source rig exactly: for every
one of the 8 arm prefabs, every bone, and every `Skin`, the skin deformation
`D = G_bone × bind` is the identity transform (translation < 1 cm, scale error
< 0.01, rotation < 1°, and adjacent-bone probe gaps < 1 cm) across `3,600`
checks, with `0` failures. Before the fix the same gate reported `256` failures,
all confined to the right arm chain.

### Skinning scope

That gate covers the `8` FPS arm prefabs and nothing else. A prior generic scan
found `39` skin-bearing prefabs in total, **not** `39` PolygonGeneric characters;
the `39` already included those `8` FPS prefabs. The other `31` were `22`
PolygonGeneric character prefabs, `2` PolygonGeneric FX prefabs, `6` Prototype
FixedScale character prefabs, and `Fov_01`. The identity failed `22,737` checks
across the `20` posed full-character prefabs plus one `Fov_01` check, while the
remaining `10` passed. That mixed result does not make the identity a general
gate: the affected characters are stored at a pose other than the one their
meshes were bound in and render correctly regardless. The measurement behind
that, including the renders, is in
[Several packages in one project](./multi-package.md#what-this-run-also-settled-the-skinning-check-was-not-vendor-neutral).

The vendor-neutral source-pose gate now covers that full inventory without a
bind-pose assumption. It found and checked all `39/39` source and output
skin-bearing prefabs in both directions and compared `1,980` mapped bone poses:
`37` direct-YAML prefabs (`1,826` bones) and `2` FBX-backed prefab instances
(`154` bones), with `0` missing or unexplained prefabs and `0` pose mismatches.
Two independent in-memory negative controls—one for each comparison branch—were
both detected and restored.

For the weaker FBX branch, saved originals supplied `152` rotation
cross-checks. The persisted active humanoid maps required `80/80` of those
checks explicitly; the remaining `2` mapped duplicate-name bones had no saved
original and were reported as composition-only. Both the persisted source-model
and final-prefab bone inventories were fully explained.

This result has a deliberately narrower meaning than an independent Unity
render oracle. The direct branch reuses Unidot's YAML parser and coordinate
converter, so a symmetric defect in either may escape it. The two FBX-backed
prefabs use a weaker composition check: a separately instantiated persisted
source-model scene supplies the pose baseline, while saved mapping and retarget
metadata cross-check the mapped humanoid rotations. That catches prefab
composition and application defects, but source-model FBX decoding, humanoid
mapping, or delta-generation defects can be shared by both sides. The existing
FPS-arm gates therefore remain: they assert the stronger, package-specific
bind-pose rigidity property that caught the historical `Root` hijack.

Falling back to automatic bone mapping exposed two further defects, both
triggered by rigs that combine an incomplete auto-detected bone map with bone
names duplicated across both hands:

1. **Root hijack.** Humanoid `Root` discovery walked up from an arbitrary mapped
   bone and claimed the last unmapped ancestor it saw. When the auto-mapper left
   the clavicles unmapped, a walk starting from a right-hand finger claimed
   `Clavicle_R` as the profile `Root`. Its original orientation was then never
   recorded, which corrupted the pre-retarget rest chain — and therefore the
   rotation delta — of every bone below it by a constant 138.7°. The walk now
   rejects any candidate that still has a mapped bone above it, so only bones
   above the entire mapped rig (such as an `Armature` node) can become `Root`.
2. **Bone name space mismatch.** Prefab conversion looked bones up in the
   auto-detected map using Godot-sanitized skeleton names (`Finger_01_2`), while
   prefab GameObjects carry Unity's de-duplicated names (`Finger_01 1`). Every
   affected right-hand finger therefore lost both its humanoid mapping and its
   rotation delta. Lookups are now translated through
   `godot_sanitized_to_orig_remap`, and rotation deltas are aliased under the
   Unity names.

All three fixes ship with asset-independent synthetic regression tests, and the
full public GDScript test suite passes (`17/17`).

![The same four Standard FPS arm prefabs after the fix: clean, symmetric arms](../../hdnua_arms_after.png)

*After: the same four prefabs, same camera, with the fixes applied.*

![Close-up of Character_FPS_Arms_Standard_01 showing a matched left and right arm](../../hdnua_arms_closeup.png)

*`Character_FPS_Arms_Standard_01` in close-up. The right arm — the one that used
to be twisted around the wrist axis — now mirrors the left.*

![The FPS arm prefabs in the package Overview scene, all intact](../../hdnua_arms_overview.png)

*The same result in context: the FPS arm rows of the package `Overview` scene,
rendered at runtime rather than in the editor, so no gizmos or RESET pose
overrides are in frame.*


## Import diagnostics, counted

Every diagnostic this package emits was classified message-by-message from an
instrumented full import. [README.md](../../README.md#understanding-the-import-diagnostics)
explains what each class of diagnostic means; this section is the tally for this
package.

![The Unidot import dialog after a full POLYGON Prototype import, reporting 124 warnings and 13 errors alongside "Import complete."](../../hdnua_import_dialog.png)

*What a successful import of this package looks like: `Import complete.` with
`124` warnings and `13` errors still on the counters. The rest of this section
accounts for every one of them.*

**The thousands of red `ERROR` lines in the Godot console are dead texture
paths baked into the vendor's FBX files.** The Synty artists exported the FBX
files with their own working textures still assigned — `.psd`, `.tif`, and
source `.png` files living under their personal Dropbox working folders. Those
paths are stored verbatim inside the shipped FBX, but the files themselves are
not part of the `.unitypackage`; only the flattened runtime `.png` atlases are.
Unity never surfaces this because it ignores FBX-embedded material references
and binds textures through the `.mat` asset's GUID instead. Godot's FBX parser
is more literal: it resolves each embedded path, fails, and reports it. In one
full import this produced `10,736` engine `ERROR` lines and `3,916`
`FBX: Image index ... couldn't be loaded` warnings, referencing `2,576` `.psd`,
`1,324` `.png`, `12` `.tga`, and `4` `.tif` targets — `1,483` of which point at
artist working directories that were never shipped. Five further warnings are
case-mismatched folder names inside the package (`textures/` vs `Textures/`).

This is cosmetic because Unidot does not trust FBX-embedded materials in the
first place: it converts the Unity `.mat` assets and assigns them after import.
Verified on the converted output, `121` of `139` converted materials have a
real albedo texture bound; the remaining `18` are glass, water, glow, skybox,
blank, and FX materials that carry no texture GUID in the Unity source either.

**The `13` red errors in the Unidot dialog are a defect in the vendor package,
not in the conversion.** All `13` are the same message —
`Unable to create MeshCollider shape because the source mesh could not be resolved`
— raised by 13 POLYGON **Generic** prop prefabs (`SM_Gen_Prop_Sack_01` through
`_05`, `Sack_Stack_01`/`_02`, `Pot_04`/`_05`, `Potion_01`, `Rope_Knot_01`,
`Screen_01`, `Skull_01`). Each has a `MeshCollider` pointing at a collision-mesh
GUID that no `.meta` file anywhere in the Unity project owns, meaning the
reference is already broken in Unity. Unidot reports each one once as a
structured source-data failure, skips only the collision shape, and converts the
rest of the prefab normally. **POLYGON Prototype itself produces `0` errors.**

**The `124` dialog warnings are feature-gap notices, not damage.** The
distribution over the `152` raw warning records emitted during the run (the
dialog counts only the subset on assets selected for import, so `.cs` and
`.shader` assets are excluded) is:

| Count | Category |
| ---: | --- |
| `108` | ParticleSystem modules Godot has no equivalent for, or that are approximated (Rotation, Noise, ClampVelocity, Velocity, UV animation, Collision, emission bursts, stretched billboards, hemisphere and sphere-shell shapes, 3D start size/rotation) |
| `23` | ShaderGraph/SubGraph files preserved as source-only instead of translated |
| `9` | Stripped intermediate prefab transforms |
| `4` | Unity lightmap authoring values clamped into Godot's supported range |
| `3` | Heuristic main-object-id resolution |
| `3` | Humanoid bone-map validators reporting that they rejected a bad source avatar |
| `2` | Material references without a meta entry, loaded directly |

The three humanoid warnings are the importer's own defenses reporting success,
not problems: one is the `humanDescription` validator rejecting
`Character_FPSHands_01`'s structurally inconsistent Unity avatar described
above, and two are the guard that refuses to overwrite an existing profile
mapping with `Root`.

**Conclusion: for the Synty POLYGON Prototype package, this revision is a
correct Unity → Godot asset conversion.** Every diagnostic above is either a
defect in the source package that Unity also carries, or an explicit notice
about a Godot feature gap. None of them corresponds to a mesh, material,
transform, or skinning value that was converted incorrectly.

## Full validation run

The import results were originally collected with importer revision
`40f917184968c6193c81ebe3fa719a386ea86c1c` and re-confirmed at `b60759d`.
The public suite and source-pose gate were re-run for this report update:

- The public synthetic regression suite passed (`17/17`), including dedicated
  GameObject active-hierarchy, deferred SkinnedMeshRenderer visibility,
  warning-severity, repeated missing-MeshCollider lookup, humanoid avatar bone
  map validation, humanoid `Root` discovery, and duplicate-bone-name prefab
  remap coverage.
- The source-pose gate found and checked all `39/39` skin-bearing prefabs and
  compared `1,980` bone poses with `0` mismatches; both negative controls were
  detected.
- All `8` FPS arm prefabs passed the skin-deformation identity gate
  (`3,600` checks, `0` failures). See
  [Humanoid skinning correctness](#humanoid-skinning-correctness).
- `2,291` package assets selected and `5,944` output files generated.
- All `496` POLYGON Prototype prefabs and `2` regular scenes loaded and
  instantiated (`498/498`).
- All `13` expected representative albedo texture mappings matched (`13/13`).
- The POLYGON Prototype validation found `0` missing mesh, material, or
  collision-shape bindings.
- All `989` generated Synty `.tscn` resources from the package loaded and
  instantiated, including POLYGON Generic and POLYGON Prototype content. This
  is a structural load gate, not a semantic-parity or lossless-conversion claim.
- All `8` FPS/VR hand prefabs preserved the intended active SkinnedMesh variant:
  `32` variants produced exactly `8` visible and `24` hidden meshes with `0`
  mismatches. Instantiating the package `Overview.tscn` produced the same
  `8/24` result. The importer now combines the renderer's `m_Enabled` state
  with its source GameObject's active-in-hierarchy state even when the mesh is
  deferred under a shared Godot `Skeleton3D`.
- All `30` Unity ParticleSystem/ParticleSystemRenderer pairs generated
  `GPUParticles3D` nodes. The common Initial, Emission, Shape, Color, Size,
  billboard, stretched-billboard, and mesh-renderer subset is converted;
  enabled unsupported modules produce explicit warnings.
- Unity `SceneRoots` restored the authored root order in the demo scene.
- The package LightingSettings asset generated a Godot resource, and the demo
  `LightmapGI` preserved the mapped authoring values (`2` bounces, directional
  mode, `0.025` texel scale, and `2048` maximum texture size). Unity realtime-GI
  intent is metadata-only because Godot `LightmapGI` has no equivalent realtime
  conversion.
- All `25` ShaderGraph/SubGraph files were preserved as source-only files and
  no `.failed_import` files were generated. Their shader semantics were not
  translated.
- This full-import run observed warning diagnostics decrease from the `667`
  baseline to `141`, while failure diagnostics remained at `13`. A preceding
  equivalent run collected `140`; the one-message variation was in concurrent
  source-only shader warning collection, while the `25/25` source-preservation
  gate was unchanged. The `b60759d` re-run counted `124` dialog warnings and the
  same `13` failures, from `152` raw warning records and `26` raw failure
  records; the difference between the raw and dialog counts is the `.cs` and
  `.shader` assets that are deselected from import by default.
- Targeted non-actionable warning noise was `0`: disabled-animation
  `AnimationClip` fallback IDs and identity Humanoid rotations are retained only
  in verbose diagnostics, while repeated missing-MeshCollider lookups no longer
  emit duplicate generic no-meta warnings.
- The remaining warnings are actionable or explicitly lossy diagnostics, and are
  broken down per category in
  [Import diagnostics, counted](#import-diagnostics-counted).
- The `13` red diagnostics are all for POLYGON Generic MeshColliders whose
  referenced source mesh GUID/fileID is absent from the package. Each missing
  reference is reported once as a structured source-data failure instead of a
  null-mesh script error. The referenced GUIDs are owned by no `.meta` file
  anywhere in the Unity project, so the references are already broken in Unity.

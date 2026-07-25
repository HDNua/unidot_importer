# Unidot Importer

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

## HDNua update (English)

The Korean edition of this section is below:
[HDNua update (한국어)](#hdnua-update-한국어).

### Asset support matrix

| Publisher | Package | Tested with | Support | Details |
| --- | --- | --- | :---: | --- |
| Synty Studios | POLYGON - Prototype Pack | Godot `4.7.1-stable.mono`, macOS | △ Partial | Prefabs and scenes instantiate with validated mesh, material, collision, albedo, active-state, humanoid skinning, scene-root, lighting-authoring, and basic particle conversion. ShaderGraph semantics, advanced particle modules, realtime GI, and source-missing collider references still require review. |

`△ Partial` means the package has a validated usable subset, but the import is
not lossless and still requires review or manual porting for the listed gaps.

### Source-data defect: the Synty humanoid avatar

The FPS arm prefabs in this package collapsed on import, and the cause was
neither Unidot nor Godot — it is an error in the Synty asset's own avatar data.

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

### Humanoid skinning correctness

Revision `b60759d` closes the last known geometry defect for this package. The
converted FPS arm prefabs now reproduce the Unity source rig exactly: for every
one of the 8 arm prefabs, every bone, and every `Skin`, the skin deformation
`D = G_bone × bind` is the identity transform (translation < 1 cm, scale error
< 0.01, rotation < 1°, and adjacent-bone probe gaps < 1 cm) across `3,600`
checks, with `0` failures. Before the fix the same gate reported `256` failures,
all confined to the right arm chain.

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
full public test suite passes (`15/15`).

### Understanding the import diagnostics

Importing this package prints a large number of engine-level `ERROR` lines and
shows non-zero warning and error counters in the Unidot dialog. **None of them
indicate a failed or incorrect conversion of POLYGON Prototype.** They were
classified message-by-message from an instrumented full import at revision
`b60759d`. The summary below is that classification.

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

### Synty POLYGON Prototype validation details

The HDNua fork has been tested with the Synty **POLYGON - Prototype Pack**
`.unitypackage` on Godot `4.7.1-stable.mono` for macOS. The validated
configuration used the native Godot FBX importer, imported into
`res://Unidot`, and saved translated resources and scenes as text.

Validated results, originally collected with importer revision
`40f917184968c6193c81ebe3fa719a386ea86c1c` and re-confirmed at `b60759d`:

- The public synthetic regression suite passed (`15/15`), including dedicated
  GameObject active-hierarchy, deferred SkinnedMeshRenderer visibility,
  warning-severity, repeated missing-MeshCollider lookup, humanoid avatar bone
  map validation, humanoid `Root` discovery, and duplicate-bone-name prefab
  remap coverage.
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
  [Understanding the import diagnostics](#understanding-the-import-diagnostics).
- The `13` red diagnostics are all for POLYGON Generic MeshColliders whose
  referenced source mesh GUID/fileID is absent from the package. Each missing
  reference is reported once as a structured source-data failure instead of a
  null-mesh script error. The referenced GUIDs are owned by no `.meta` file
  anywhere in the Unity project, so the references are already broken in Unity.

The material mapping update recognizes underscored Unity texture properties
such as `_Albedo_Map`, `_Base_Map`, `_Normal_Map`, and `_Emission_Map`, while
preventing mask, normal, metallic, roughness, and emission textures from being
selected as generic albedo fallbacks.

### Known limitations

The `△ Partial` status is intentional. ShaderGraph/SubGraph files are preserved
for manual porting, not converted to Godot shaders. ParticleSystem conversion
covers the common deterministic subset; modules such as Rotation, Noise,
Velocity, ClampVelocity, UV animation, Collision, bursts, and some shape or
billboard modes are omitted or approximated with explicit warnings. Unity
realtime GI is also not converted to a Godot realtime-GI system.
The active-state validation above covers the package's serialized base
GameObject and renderer states; arbitrary prefab overrides that toggle active
state are not yet covered by this package fixture.

The red error counter in the Unidot log is a count of diagnostic messages, not
a count of unique failed files or failed scenes. A scene can load successfully
while an unsupported component or override inside it was skipped. In
particular, the deeper albedo and missing-binding checks above are scoped to the
`498` POLYGON Prototype prefabs and scenes; the `989/989` check only establishes
that every generated scene resource can be loaded and instantiated. In this
validation run, the remaining `13` red diagnostics are the source-missing
POLYGON Generic collider references described above.

This is a compatibility result for this package and configuration, not a claim
that every Synty package or every Unity feature is fully supported. Custom
ShaderGraph/SubGraph content, MonoBehaviours, advanced ParticleSystems,
realtime GI, and source assets with missing external references may still
require manual work.

---

## HDNua update (한국어)

이 절의 영어판은 위에 있습니다:
[HDNua update (English)](#hdnua-update-english).

### 에셋 지원 현황

| 퍼블리셔 | 패키지 | 검증 환경 | 지원 | 상세 |
| --- | --- | --- | :---: | --- |
| Synty Studios | POLYGON - Prototype Pack | Godot `4.7.1-stable.mono`, macOS | △ 부분 지원 | 프리팹과 씬이 메시·머티리얼·콜리전·albedo·active 상태·휴머노이드 스키닝·씬 루트·라이팅 저작값·기본 파티클 변환이 검증된 상태로 인스턴스화됩니다. ShaderGraph 시맨틱, 고급 파티클 모듈, 리얼타임 GI, 소스가 누락된 콜라이더 참조는 여전히 검토가 필요합니다. |

`△ 부분 지원`은 검증된 사용 가능 부분집합이 존재하지만 임포트가 무손실은 아니며,
위에 나열된 격차에 대해서는 검토나 수동 이식이 필요하다는 뜻입니다.

### 소스 데이터 결함: Synty 휴머노이드 아바타

이 패키지의 FPS 팔 프리팹은 임포트 시 붕괴했는데, 원인은 Unidot도 Godot도 아니고
Synty 에셋 자체의 아바타 데이터 오류였습니다.

- Standard 계열 프리팹이 쓰는 모델인 `Character_FPSHands_01.fbx`의 Unity 아바타가
  `Hips → Root`(리그 루트 본)로 잘못 매핑되어 있습니다. 그래서 전체 척추 체인이 한 칸씩
  밀립니다 — `Spine ← Hips`, `Chest ← Spine_01`, `UpperChest ← Spine_02`이며
  `Spine_03`은 미매핑으로 남습니다.
- FiveFinger 계열이 쓰는 `Character_FPSHands_02.fbx`는 `Hips → Hips`로 정상입니다.
  FiveFinger 계열은 처음부터 문제없이 임포트되고 Standard 계열만 깨졌던 이유가 이것입니다.

Unity에서 멀쩡해 보이는 이유는 이렇습니다. Unity는 아바타 매핑을 휴머노이드 애니메이션
리타게팅에만 쓰고, 씬 표시는 원본 리그 트랜스폼을 직접 사용합니다. 그래서 잘못 만들어진
아바타가 Unity에서는 무해한데, Unidot은 이 매핑을 신뢰해서 스켈레톤 재구성에 사용하므로
Godot에서만 깨집니다. 이전에 "엔진 자체 문제"로 오판했던 지점이 바로 여기입니다. 실제로는
소스 데이터 결함이고, 임포터가 방어할 수 있는 문제입니다.

지금은 그 방어막이 존재합니다. Unidot은 `humanDescription` 본맵을 리그 계층과 대조해
검증하며(매핑된 각 본의 가장 가까운 매핑된 조상은 `SkeletonProfileHumanoid`상에서도 그
본의 조상이어야 함), 구조적으로 모순된 맵이면 자동 휴머노이드 본 매핑으로 폴백하고 그
사실을 경고로 남깁니다. `Hips`가 아예 없는 맵도 같은 방식으로 거부합니다.

### 휴머노이드 스키닝 정확도

리비전 `b60759d`에서 이 패키지의 마지막 알려진 지오메트리 결함이 해결되었습니다.
변환된 FPS 팔 프리팹은 이제 Unity 원본 리그를 정확히 재현합니다. 팔 프리팹 8종
전부에 대해 모든 본과 모든 `Skin`에서 스킨 변형 `D = G_bone × bind`가 항등변환이며
(이동 < 1cm, 스케일 오차 < 0.01, 회전 < 1°, 인접 본 probe gap < 1cm), 총 `3,600`건
검사에서 실패 `0`건입니다. 수정 전 동일 게이트는 `256`건 실패였고 전부 오른팔
체인에 몰려 있었습니다.

자동 본 매핑으로 폴백하자 결함 두 개가 추가로 드러났습니다. 둘 다 "자동 감지 본맵에
구멍이 있고 + 양손에 본 이름이 중복되는" 리그에서만 발현합니다.

1. **Root 하이재킹.** 휴머노이드 `Root` 탐색이 임의의 매핑된 본에서 위로 올라가며
   마지막으로 만난 미매핑 조상을 Root로 지정했습니다. 자동 매퍼가 쇄골을 비워두면,
   오른손가락에서 출발한 탐색이 `Clavicle_R`을 프로파일 `Root`로 가로챕니다. 그러면
   그 본의 원본 방향이 기록되지 않아, 아래의 모든 본의 리타게팅 전 rest 체인 —
   따라서 회전 델타 — 이 상수 138.7°만큼 오염됩니다. 이제 탐색은 위쪽에 매핑된 본이
   남아 있는 후보를 거부하므로, 매핑된 리그 전체보다 위에 있는 본(예: `Armature`
   노드)만 `Root`가 될 수 있습니다.
2. **본 이름공간 불일치.** 프리팹 변환은 Godot 새니타이즈 이름(`Finger_01_2`)으로
   자동 본맵을 조회했지만, 프리팹 GameObject는 Unity가 중복 제거한 이름
   (`Finger_01 1`)을 가집니다. 그래서 해당 오른손가락들이 휴머노이드 매핑과 회전
   델타를 모두 잃었습니다. 이제 조회는 `godot_sanitized_to_orig_remap`을 거쳐
   변환되며, 회전 델타는 Unity 이름으로도 별칭 등록됩니다.

세 수정 모두 에셋에 의존하지 않는 합성 회귀 테스트를 포함하며, 공개 테스트 스위트
전체가 통과합니다 (`15/15`).

### 임포트 진단 메시지 해설

이 패키지를 임포트하면 엔진 레벨 `ERROR` 줄이 대량으로 출력되고, Unidot 다이얼로그의
경고·오류 카운터도 0이 아닙니다. **그러나 그중 어느 것도 POLYGON Prototype 변환이
실패했거나 잘못되었다는 뜻이 아닙니다.** 리비전 `b60759d`에서 계측을 넣고 전체
임포트를 돌려 메시지를 하나씩 분류한 결과가 아래입니다.

**Godot 콘솔의 수천 줄짜리 빨간 `ERROR`는 벤더의 FBX 파일 안에 박제된 죽은 텍스처
경로입니다.** Synty 아티스트가 자기 작업용 텍스처(`.psd`, `.tif`, 원본 `.png`)를
머티리얼에 꽂은 채로 FBX를 익스포트했고, 그 경로들이 — 개인 Dropbox 작업 폴더 경로까지
포함해서 — FBX 내부에 그대로 저장되어 배포되었습니다. 정작 그 파일들은
`.unitypackage`에 들어 있지 않습니다. 배포본에는 병합된 런타임 `.png` 아틀라스만
포함됩니다. Unity에서는 이게 드러나지 않는데, Unity는 FBX에 내장된 머티리얼 참조를
무시하고 `.mat` 에셋의 GUID로 텍스처를 연결하기 때문입니다. Godot의 FBX 파서는 더
곧이곧대로라서, 내장된 경로를 하나씩 해석해보고 실패하면 그대로 보고합니다. 전체
임포트 1회 기준으로 엔진 `ERROR` `10,736`줄과
`FBX: Image index ... couldn't be loaded` 경고 `3,916`건이 나왔고, 대상은 `.psd`
`2,576`건, `.png` `1,324`건, `.tga` `12`건, `.tif` `4`건이며, 그중 `1,483`건이 애초에
배포되지 않은 아티스트 작업 디렉터리를 가리킵니다. 여기에 패키지 내부 폴더명 대소문자
불일치(`textures/` vs `Textures/`) 경고가 `5`건 더 있습니다.

이것이 무해한 이유는 Unidot이 애초에 FBX 내장 머티리얼을 신뢰하지 않기 때문입니다.
Unidot은 Unity `.mat` 에셋을 변환해서 임포트 이후에 직접 할당합니다. 변환 결과물에서
확인한 결과, 변환된 머티리얼 `139`개 중 `121`개에 실제 albedo 텍스처가 연결되어
있습니다. 나머지 `18`개는 유리·물·발광·스카이박스·blank·FX 머티리얼로, Unity 원본에도
텍스처 GUID가 아예 없는 것들입니다.

**Unidot 다이얼로그의 오류 `13`건은 변환이 아니라 벤더 패키지 자체의 결함입니다.**
`13`건 전부 동일 메시지
(`Unable to create MeshCollider shape because the source mesh could not be resolved`)이며,
POLYGON **Generic**의 프롭 프리팹 13종(`SM_Gen_Prop_Sack_01`~`_05`,
`Sack_Stack_01`/`_02`, `Pot_04`/`_05`, `Potion_01`, `Rope_Knot_01`, `Screen_01`,
`Skull_01`)에서 발생합니다. 각각 `MeshCollider`가 충돌 메시 GUID를 참조하는데, 그
GUID를 소유한 `.meta` 파일이 Unity 프로젝트 어디에도 없습니다. 즉 Unity에서도 이미
깨져 있는 참조입니다. Unidot은 이를 구조화된 소스 데이터 실패로 한 번씩만 보고하고,
콜리전 셰이프만 건너뛴 뒤 프리팹의 나머지는 정상 변환합니다. **POLYGON Prototype
자체의 오류는 `0`건입니다.**

**다이얼로그 경고 `124`건은 손상이 아니라 기능 격차 통지입니다.** 임포트 중 발생한
원시 경고 레코드 `152`건의 분포는 아래와 같습니다. (다이얼로그는 임포트 대상으로
선택된 에셋의 경고만 세므로 `.cs`·`.shader` 에셋 분은 제외됩니다.)

| 건수 | 분류 |
| ---: | --- |
| `108` | Godot에 대응 기능이 없거나 근사 처리되는 ParticleSystem 모듈 (Rotation, Noise, ClampVelocity, Velocity, UV 애니메이션, Collision, emission burst, stretched billboard, hemisphere/sphere-shell 형상, 3D start size·rotation) |
| `23` | 번역하지 않고 소스 그대로 보존한 ShaderGraph/SubGraph 파일 |
| `9` | 제거된 중간 프리팹 트랜스폼 |
| `4` | Godot 지원 범위로 클램프된 Unity 라이트맵 저작 값 |
| `3` | 휴리스틱 main-object-id 해석 |
| `3` | 잘못된 소스 아바타를 거부했다고 보고하는 휴머노이드 본맵 검증기 |
| `2` | meta 항목이 없어 직접 로드한 머티리얼 참조 |

이 중 휴머노이드 경고 `3`건은 문제가 아니라 임포터의 방어 장치가 정상 작동했다는
신호입니다. 하나는 `humanDescription` 검증기가 위에서 설명한
`Character_FPSHands_01`의 구조적으로 모순된 Unity 아바타를 거부한 것이고, 나머지 둘은
기존 프로파일 매핑을 `Root`로 덮어쓰지 않도록 막는 가드입니다.

**결론: Synty POLYGON Prototype 패키지에 대해 이 리비전은 올바른 Unity → Godot 에셋
변환입니다.** 위의 모든 진단 메시지는 Unity에서도 동일하게 존재하는 소스 패키지 결함
이거나, Godot 기능 격차에 대한 명시적 통지입니다. 메시·머티리얼·트랜스폼·스키닝 값이
잘못 변환된 사례에 해당하는 것은 하나도 없습니다.

### Synty POLYGON Prototype 검증 상세

HDNua fork는 Synty **POLYGON - Prototype Pack** `.unitypackage`를 macOS의 Godot
`4.7.1-stable.mono`에서 검증했습니다. 검증 구성은 Godot 네이티브 FBX 임포터를 사용하고,
`res://Unidot`으로 임포트하며, 변환된 리소스와 씬을 텍스트로 저장한 상태입니다.

임포터 리비전 `40f917184968c6193c81ebe3fa719a386ea86c1c`에서 최초 수집하고 `b60759d`에서
재확인한 검증 결과입니다.

- 공개 합성 회귀 스위트 통과 (`15/15`). GameObject active 계층, 지연된
  SkinnedMeshRenderer 가시성, 경고 심각도, 반복되는 MeshCollider 누락 조회, 휴머노이드
  아바타 본맵 검증, 휴머노이드 `Root` 탐색, 중복 본 이름 프리팹 remap 커버리지를 포함합니다.
- FPS 팔 프리팹 `8`종 전부가 스킨 변형 항등 게이트를 통과 (`3,600`건 검사, 실패 `0`건).
  [휴머노이드 스키닝 정확도](#휴머노이드-스키닝-정확도) 참조.
- 패키지 에셋 `2,291`개 선택, 출력 파일 `5,944`개 생성.
- POLYGON Prototype 프리팹 `496`개와 일반 씬 `2`개 전부 로드·인스턴스화 (`498/498`).
- 대표 albedo 텍스처 매핑 `13`개 전부 일치 (`13/13`).
- POLYGON Prototype 검증에서 메시·머티리얼·콜리전 셰이프 바인딩 누락 `0`건.
- 패키지에서 생성된 Synty `.tscn` 리소스 `989`개 전부 로드·인스턴스화 (POLYGON Generic과
  POLYGON Prototype 콘텐츠 포함). 이는 구조적 로드 게이트이며, 시맨틱 동등성이나 무손실
  변환을 주장하는 것이 아닙니다.
- FPS/VR 손 프리팹 `8`종 전부가 의도된 active SkinnedMesh 변형을 보존: 변형 `32`개에서
  정확히 가시 `8`개, 숨김 `24`개가 생성되었고 불일치 `0`건. 패키지 `Overview.tscn`을
  인스턴스화해도 동일한 `8/24` 결과가 나왔습니다. 임포터는 메시가 공유 Godot
  `Skeleton3D` 아래로 지연되는 경우에도 렌더러의 `m_Enabled` 상태와 소스 GameObject의
  active-in-hierarchy 상태를 결합합니다.
- Unity ParticleSystem/ParticleSystemRenderer 쌍 `30`개 전부가 `GPUParticles3D` 노드를
  생성했습니다. 공통적인 Initial, Emission, Shape, Color, Size, billboard,
  stretched-billboard, mesh-renderer 부분집합이 변환되며, 활성화된 미지원 모듈은 명시적
  경고를 남깁니다.
- Unity `SceneRoots`가 데모 씬의 저작 루트 순서를 복원했습니다.
- 패키지 LightingSettings 에셋이 Godot 리소스를 생성했고, 데모 `LightmapGI`가 매핑된
  저작 값(바운스 `2`, directional 모드, texel 스케일 `0.025`, 최대 텍스처 크기 `2048`)을
  보존했습니다. Godot `LightmapGI`에는 대응되는 리얼타임 변환이 없으므로 Unity 리얼타임
  GI 의도는 메타데이터로만 남습니다.
- ShaderGraph/SubGraph 파일 `25`개 전부가 소스 전용 파일로 보존되었고 `.failed_import`
  파일은 생성되지 않았습니다. 셰이더 시맨틱은 번역되지 않았습니다.
- 이 전체 임포트 실행에서 경고 진단이 기준선 `667`에서 `141`로 감소했고, 실패 진단은
  `13`으로 유지되었습니다. 직전 동등 실행은 `140`을 수집했는데, 1건 차이는 동시성 환경의
  소스 전용 셰이더 경고 수집에서 발생한 것이며 `25/25` 소스 보존 게이트는 동일했습니다.
  `b60759d` 재실행에서는 다이얼로그 경고 `124`건과 동일한 실패 `13`건이 집계되었고, 원시
  기록으로는 경고 `152`건, 실패 `26`건이었습니다. 원시 카운트와 다이얼로그 카운트의 차이는
  기본적으로 임포트 대상에서 제외되는 `.cs`·`.shader` 에셋 분입니다.
- 표적화된 비실행성 경고 노이즈는 `0`입니다. 비활성 애니메이션 `AnimationClip` 폴백 ID와
  항등 휴머노이드 회전은 상세 진단에서만 유지되며, 반복되는 MeshCollider 누락 조회는 더
  이상 중복된 일반 no-meta 경고를 내지 않습니다.
- 남은 경고는 실행 가능하거나 명시적으로 손실이 있는 진단이며, 분류별 내역은
  [임포트 진단 메시지 해설](#임포트-진단-메시지-해설)에 있습니다.
- 빨간 진단 `13`건은 전부 POLYGON Generic MeshCollider가 참조하는 소스 메시
  GUID/fileID가 패키지에 없는 경우입니다. 각 누락 참조는 null 메시 스크립트 오류가 아니라
  구조화된 소스 데이터 실패로 한 번씩만 보고됩니다. 참조된 GUID는 Unity 프로젝트 어디에도
  소유 `.meta` 파일이 없으므로, Unity에서도 이미 깨져 있는 참조입니다.

머티리얼 매핑 업데이트는 `_Albedo_Map`, `_Base_Map`, `_Normal_Map`, `_Emission_Map`처럼
언더스코어가 붙은 Unity 텍스처 속성을 인식하며, mask·normal·metallic·roughness·emission
텍스처가 일반 albedo 폴백으로 선택되는 것을 방지합니다.

### 알려진 한계

`△ 부분 지원` 상태는 의도된 것입니다. ShaderGraph/SubGraph 파일은 Godot 셰이더로
변환되지 않고 수동 이식용 소스로 보존됩니다. ParticleSystem 변환은 결정적으로
대응 가능한 공통 부분집합만 다루며, Rotation·Noise·Velocity·ClampVelocity·UV
애니메이션·Collision·burst 및 일부 형상·빌보드 모드는 생략되거나 근사되고 그때마다
명시적 경고를 남깁니다. Unity 리얼타임 GI도 Godot 리얼타임 GI로 변환되지 않습니다.
위의 active-state 검증은 패키지에 직렬화된 기본 GameObject·렌더러 상태를 다루며,
active 상태를 토글하는 임의의 프리팹 오버라이드는 이 패키지 픽스처로는 아직
검증되지 않았습니다.

Unidot 로그의 빨간 오류 카운터는 진단 메시지 개수이지, 실패한 파일이나 씬의 개수가
아닙니다. 씬은 정상적으로 로드되면서 그 안의 미지원 컴포넌트나 오버라이드만 건너뛸 수
있습니다. 특히 위의 albedo·바인딩 누락 검사는 POLYGON Prototype 프리팹·씬 `498`개를
범위로 하며, `989/989` 검사는 생성된 모든 씬 리소스가 로드·인스턴스화된다는 구조적
확인일 뿐입니다.

이는 이 패키지와 이 설정에 대한 호환성 결과이며, 모든 Synty 패키지나 모든 Unity 기능이
완전히 지원된다는 주장이 아닙니다. 커스텀 ShaderGraph/SubGraph, MonoBehaviour, 고급
ParticleSystem, 리얼타임 GI, 외부 참조가 누락된 소스 에셋은 여전히 수작업이 필요할 수
있습니다.

![Synty POLYGON Prototype demo imported with Unidot in Godot 4.7.1](./hdnua_synty_polygon_prototype_godot_4_7_1.png)

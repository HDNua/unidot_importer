# Synty POLYGON - Prototype Pack

*이 보고서를 [English](./polygon-prototype.md)로 읽기.*

Synty **POLYGON - Prototype Pack** `.unitypackage`의 검증 보고서입니다.
Unidot이 일반적으로 무엇을 변환하는지와 모든 Synty 패키지에 공통인 동작은
[README](../../README.ko.md)를 참고하세요. 이 파일은 이 패키지에만 해당하는
내용을 기록합니다.

macOS용 Godot `4.7.1-stable.mono`에서 Godot native FBX importer를 사용해
`res://Unidot`으로 import하고, 변환된 resource와 scene을 text 형식으로 저장해
검증했습니다. 별도 표기가 없으면 아래 수치는 importer revision `b60759d`에서
얻었습니다.

## 영역별 결과

| 영역 | 상태 | 근거 |
| --- | :---: | --- |
| Mesh, transform, prefab 및 scene 계층 | 정상 | prefab과 scene `498/498`개가 instantiate됨. 생성된 scene resource `989/989`개가 load됨 |
| Material과 albedo texture | 정상 | 변환된 material `139`개 중 `121`개가 texture를 연결함. 나머지 `18`개는 Unity source에도 texture가 없음. 대표 albedo mapping `13`개가 모두 일치 |
| Collision shape | 정상 | source mesh 자체가 package에 없는 collider `13`개를 제외하면 누락 binding `0` |
| GameObject active 상태와 renderer visibility | 정상 | variant `32`개에서 정확히 mesh `8`개가 visible, `24`개가 hidden이었고 mismatch `0` |
| Humanoid rig와 skinning | skin이 있는 prefab `39`개 모두 문서화한 source-consistency 범위에서 정상. FPS arm prefab `8`개는 더 강한 bind-pose rigidity도 정상 | Source consistency: prefab `39/39`, bone pose `1,980`, mismatch `0`. FPS rigidity: 검사 `3,600`, failure `0` — [아래](#skinning-범위) 참고 |
| Scene root 순서 | 정상 | demo scene에서 저작된 root 순서를 복원 |
| Lightmap 저작 값 | 정상 | bounce `2`, directional mode, texel scale `0.025`, 최대 texture size `2048` |
| ParticleSystem | 부분 지원 | ParticleSystem/ParticleSystemRenderer pair `30`개가 모두 `GPUParticles3D`를 생성. 생략하거나 근사한 module을 warning `108`개로 표시 |
| ShaderGraph와 SubGraph | 변환하지 않음 | file `25`개를 모두 source로 보존하고 `.failed_import` file은 `0` |

## Source data 결함: Synty humanoid avatar

이 패키지의 FPS arm prefab은 import할 때 무너졌습니다. 원인은 Unidot이나 Godot이
아니라 Synty asset 자체의 avatar data 오류였습니다.

![수정 전 Standard FPS arm prefab 네 개의 찢어지고 뒤틀린 geometry](../../hdnua_arms_before.png)

*수정 전: 잘못된 avatar data 때문에 Standard FPS arm prefab이 찢어진 모습입니다.*

- Standard prefab이 사용하는 model인 `Character_FPSHands_01.fbx`에는 rig root
  bone을 `Hips → Root`로 mapping한 Unity avatar가 들어 있습니다. 그 결과 전체
  spine chain이 한 단계 올라가 `Spine ← Hips`, `Chest ← Spine_01`,
  `UpperChest ← Spine_02`가 되고 `Spine_03`은 mapping되지 않습니다.
- FiveFinger prefab이 사용하는 `Character_FPSHands_02.fbx`는 `Hips → Hips`로
  올바르게 mapping합니다. FiveFinger 계열은 항상 깨끗하게 import되고 Standard
  계열만 그렇지 않았던 이유입니다.

Unity에서 정상으로 보이는 이유는 Unity가 avatar mapping을 humanoid animation
retargeting에만 사용하고, 원래 rig transform으로 scene을 직접 그리기 때문입니다.
따라서 잘못 저작한 avatar가 Unity에서는 문제가 없지만, 그 mapping을 신뢰해 skeleton을
다시 만드는 Unidot에서는 결함이 Godot 쪽에서만 드러납니다. 이전에는 이를 “engine
문제”로 잘못 진단했습니다. 실제로는 importer가 방어할 수 있는 source data 결함입니다.

현재는 그 방어 기능이 있습니다. Unidot은 `humanDescription` bone map을 rig 계층과
대조합니다. mapping된 각 bone의 가장 가까운 mapping된 조상이
`SkeletonProfileHumanoid`에서도 해당 bone의 조상이어야 합니다. 구조적으로 모순된
map이면 자동 humanoid bone mapping으로 fallback하고 warning을 남깁니다. `Hips`가
전혀 없는 map도 같은 방식으로 거부합니다.

## Humanoid skinning 정확성

Revision `b60759d`는 이 패키지에서 마지막으로 알려졌던 geometry 결함을 해결합니다.
변환된 FPS arm prefab은 이제 Unity source rig를 정확히 재현합니다. arm prefab
8개 각각의 모든 bone과 모든 `Skin`에서 skin deformation
`D = G_bone × bind`가 identity transform입니다(translation < 1 cm, scale error
< 0.01, rotation < 1°, 인접 bone probe gap < 1 cm). 검사 `3,600`개에서 failure는
`0`이었습니다. 수정 전 같은 gate는 오른쪽 arm chain에만 국한된 failure `256`개를
보고했습니다.

### Skinning 범위

이 gate는 FPS arm prefab `8`개만 다루고 그 밖의 대상은 다루지 않습니다. 앞선 generic
scan에서 skin이 있는 prefab은 총 `39`개였으며, PolygonGeneric character가 `39`개라는
뜻이 **아닙니다**. 이 `39`개에는 이미 FPS prefab `8`개가 들어 있습니다. 나머지
`31`개는 PolygonGeneric character prefab `22`개, PolygonGeneric FX prefab `2`개,
Prototype FixedScale character prefab `6`개, 그리고 `Fov_01`입니다. Pose가 적용된
full-character prefab `20`개에 대한 검사와 `Fov_01` 검사 하나에서 identity 검사
`22,737`개가 실패했고, 나머지 `10`개는 통과했습니다. 이 혼합 결과가 identity를
일반 목적 gate로 만들어주지는 않습니다. 해당 character들은 mesh가 bind된 pose와 다른
pose로 저장되어 있으므로 identity는 실패하지만 정상적으로 render됩니다. Render를 포함한
근거 측정은 [한 프로젝트에서 여러 패키지 사용](./multi-package.ko.md#이-실행으로-함께-확인한-사항-skinning-검사는-vendor-neutral하지-않았음)에
있습니다.

현재 vendor-neutral source-pose gate는 bind-pose 가정 없이 이 전체 inventory를
다룹니다. Source와 output 양쪽에서 skin이 있는 prefab `39/39`개를 모두 찾아 검사했고,
mapping된 bone pose `1,980`개를 비교했습니다. direct-YAML prefab은 `37`개
(`1,826`개 bone), FBX 기반 prefab instance는 `2`개(`154`개 bone)였으며, 누락되거나
설명되지 않은 prefab `0`, pose mismatch `0`이었습니다. 비교 branch마다 하나씩 둔
독립적인 in-memory negative control 두 개도 모두 검출한 뒤 복원했습니다.

더 약한 FBX branch에서는 저장해 둔 원본으로 rotation cross-check `152`개를
수행했습니다. 지속 저장된 active humanoid map이 그중 `80/80`개 검사를 명시적으로
요구했습니다. 나머지 mapping된 duplicate-name bone `2`개에는 저장된 원본이 없어
composition-only로 보고했습니다. 지속 저장된 source-model과 최종 prefab의 bone
inventory도 모두 설명할 수 있었습니다.

이 결과는 독립적인 Unity render oracle보다 의도적으로 의미가 좁습니다. Direct branch는
Unidot의 YAML parser와 좌표 converter를 재사용하므로 어느 한쪽의 대칭적인 결함을 놓칠 수
있습니다. FBX 기반 prefab 두 개는 더 약한 composition 검사를 사용합니다. 별도로
instantiate한 지속 저장 source-model scene이 pose baseline을 제공하고, 저장된 mapping과
retarget metadata가 mapping된 humanoid rotation을 교차 확인합니다. 이 방식은 prefab
composition 및 적용 결함을 잡지만, source-model FBX decoding, humanoid mapping 또는
delta 생성 결함은 양쪽에 공유될 수 있습니다. 따라서 기존 FPS-arm gate도 유지합니다.
이 gate는 과거 `Root` 탈취를 잡아낸 더 강한 package-specific bind-pose rigidity 속성을
단정합니다.

자동 bone mapping으로 fallback하면서 두 가지 결함이 더 드러났습니다. 둘 다 불완전하게
자동 감지된 bone map과 양손에 중복된 bone 이름을 함께 사용하는 rig에서 발생했습니다.

1. **Root 탈취.** Humanoid `Root` 탐색은 임의로 mapping된 bone에서 위로 올라가며 마지막으로
   본 mapping되지 않은 조상을 선택했습니다. Auto-mapper가 clavicle을 mapping하지 않은
   경우, 오른손 finger에서 시작한 탐색이 `Clavicle_R`을 profile `Root`로 차지했습니다.
   그러면 원래 orientation이 기록되지 않아 아래 모든 bone의 pre-retarget rest chain과
   rotation delta가 일정한 138.7°만큼 손상됐습니다. 이제 탐색은 그 위에 mapping된 bone이
   남아 있는 후보를 거부하므로, 전체 mapping rig보다 위에 있는 bone(예: `Armature` node)만
   `Root`가 될 수 있습니다.
2. **Bone 이름 공간 불일치.** Prefab 변환은 자동 감지 map에서 bone을 찾을 때 Godot이
   sanitize한 skeleton 이름(`Finger_01_2`)을 사용했지만, prefab GameObject에는 Unity가
   중복을 해소한 이름(`Finger_01 1`)이 들어 있습니다. 따라서 영향을 받은 오른손 finger는
   humanoid mapping과 rotation delta를 모두 잃었습니다. 이제
   `godot_sanitized_to_orig_remap`을 통해 lookup 이름을 변환하고, rotation delta에는
   Unity 이름 alias도 둡니다.

세 수정 모두 asset-independent synthetic regression test가 있으며, 전체 공개 GDScript
test suite가 통과합니다(`17/17`).

![수정 후 깨끗하고 대칭인 같은 Standard FPS arm prefab 네 개](../../hdnua_arms_after.png)

*수정 후: 같은 camera에서 같은 prefab 네 개에 수정 사항을 적용한 모습입니다.*

![왼팔과 오른팔이 일치하는 Character_FPS_Arms_Standard_01 확대 화면](../../hdnua_arms_closeup.png)

*`Character_FPS_Arms_Standard_01` 확대 화면입니다. 이전에는 wrist axis 주위로 뒤틀렸던
오른팔이 이제 왼팔과 대칭입니다.*

![패키지 Overview scene에서 모두 온전한 FPS arm prefab](../../hdnua_arms_overview.png)

*패키지 `Overview` scene의 FPS arm row를 문맥 안에서 확인한 같은 결과입니다. Editor가
아니라 runtime에서 render해 gizmo나 RESET pose override가 화면에 없습니다.*

## Import 진단 수치

이 패키지가 내는 모든 진단을 계측한 full import 결과에서 message별로 분류했습니다.
[README](../../README.ko.md#임포트-진단-메시지-해설)는 각 진단 분류의 의미를
설명하며, 이 절은 해당 패키지의 집계입니다.

![POLYGON Prototype 전체 import 뒤 경고 124건과 오류 13건을 Import complete.와 함께 표시한 Unidot import dialog](../../hdnua_import_dialog.png)

*이 패키지의 성공적인 import 모습입니다. `Import complete.`와 함께 counter에 warning
`124`건과 error `13`건이 남습니다. 이 절의 나머지 내용이 모두 설명합니다.*

**Godot console의 수천 개 빨간 `ERROR` line은 vendor FBX file에 박제된 유효하지 않은
texture 경로입니다.** Synty artist가 자기 작업용 texture를 연결한 상태로 FBX를
export했습니다. 개인 Dropbox 작업 folder의 `.psd`, `.tif`, source `.png` file입니다.
경로는 배포된 FBX 안에 그대로 저장되어 있지만 file 자체는 `.unitypackage`에 없고, 평탄화된
runtime `.png` atlas만 들어 있습니다. Unity는 FBX 내장 material 참조를 무시하고 `.mat`
asset의 GUID로 texture를 연결하므로 이를 드러내지 않습니다. Godot FBX parser는 더
직접적으로 각 내장 경로를 resolve하려다 실패하고 보고합니다. 한 번의 full import에서
engine `ERROR` line `10,736`개와 `FBX: Image index ... couldn't be loaded` warning
`3,916`개가 발생했습니다. 대상은 `.psd` `2,576`개, `.png` `1,324`개, `.tga`
`12`개, `.tif` `4`개였고, 그중 `1,483`개는 배포된 적 없는 artist 작업
directory를 가리킵니다. 추가 warning 다섯 개는 package 안 folder 이름의 대소문자 불일치
(`textures/`와 `Textures/`)입니다.

Unidot은 애초에 FBX 내장 material을 신뢰하지 않으므로 이는 외관상 진단일 뿐입니다.
Unity `.mat` asset을 변환하고 import 뒤 할당합니다. 변환된 output으로 확인했을 때
material `139`개 중 `121`개에 실제 albedo texture가 연결되어 있습니다. 나머지 `18`개는
glass, water, glow, skybox, blank, FX material이며 Unity source에도 texture GUID가
없습니다.

**Unidot dialog의 빨간 error `13`건은 변환이 아니라 vendor package의 결함입니다.**
이 `13`건은 모두 같은 message인
`Unable to create MeshCollider shape because the source mesh could not be resolved`이며,
POLYGON **Generic** prop prefab 13개(`SM_Gen_Prop_Sack_01`부터 `_05`,
`Sack_Stack_01`/`_02`, `Pot_04`/`_05`, `Potion_01`, `Rope_Knot_01`,
`Screen_01`, `Skull_01`)가 발생시킵니다. 각 prefab의 `MeshCollider`가 Unity project
어디에도 해당 `.meta` 소유자가 없는 collision-mesh GUID를 가리키므로 Unity에서도 이미
깨진 참조입니다. Unidot은 각각 한 번씩 구조화된 source-data failure로 보고하고 collision
shape만 건너뛴 뒤 prefab 나머지를 정상 변환합니다. **POLYGON Prototype 자체에서 발생한
error는 `0`입니다.**

**Dialog warning `124`건은 손상이 아니라 기능 격차 알림입니다.** 실행 중 생성된 raw
warning record `152`건의 분포는 다음과 같습니다. Dialog는 import 대상으로 선택한 asset의
부분집합만 세므로 `.cs`와 `.shader` asset은 제외됩니다.

| 수치 | 분류 |
| ---: | --- |
| `108` | Godot에 등가물이 없거나 근사한 ParticleSystem module(Rotation, Noise, ClampVelocity, Velocity, UV animation, Collision, emission burst, stretched billboard, hemisphere 및 sphere-shell shape, 3D start size/rotation) |
| `23` | 변환하지 않고 source-only로 보존한 ShaderGraph/SubGraph file |
| `9` | 제거된 중간 prefab transform |
| `4` | Godot 지원 범위로 clamp한 Unity lightmap 저작 값 |
| `3` | Heuristic main-object-id resolution |
| `3` | 잘못된 source avatar를 거부했다고 알리는 humanoid bone-map validator |
| `2` | Meta entry가 없어 직접 load한 material 참조 |

Humanoid warning 세 개는 문제라기보다 importer 자체 방어가 성공했다는 보고입니다. 하나는
위에서 설명한 `Character_FPSHands_01`의 구조적으로 모순된 Unity avatar를
`humanDescription` validator가 거부한 것이고, 두 개는 기존 profile mapping을 `Root`로
덮어쓰지 않는 guard의 warning입니다.

**결론: 이 revision에서 Synty POLYGON Prototype package는 올바르게 Unity → Godot
asset으로 변환됩니다.** 위 진단은 모두 Unity에도 존재하는 source package 결함이거나
Godot 기능 격차에 대한 명시적인 알림입니다. Mesh, material, transform 또는 skinning 값을
잘못 변환한 경우는 없습니다.

## 전체 검증 실행

Import 결과는 처음 importer revision
`40f917184968c6193c81ebe3fa719a386ea86c1c`에서 수집했고 `b60759d`에서 다시
확인했습니다. 이 보고서 갱신을 위해 공개 suite와 source-pose gate도 다시 실행했습니다.

- 공개 synthetic regression suite가 통과했습니다(`17/17`). 여기에는 전용
  GameObject active-hierarchy, 지연된 SkinnedMeshRenderer visibility, warning severity,
  반복 missing-MeshCollider lookup, humanoid avatar bone map validation, humanoid `Root`
  discovery, duplicate-bone-name prefab remap coverage가 포함됩니다.
- Source-pose gate가 skin이 있는 prefab `39/39`개를 모두 찾아 검사하고 bone pose
  `1,980`개를 비교해 mismatch `0`을 확인했습니다. Negative control 두 개도 모두
  검출했습니다.
- FPS arm prefab `8`개가 모두 skin-deformation identity gate를 통과했습니다
  (검사 `3,600`, failure `0`). [Humanoid skinning 정확성](#humanoid-skinning-정확성)을
  참고하세요.
- Package asset `2,291`개를 선택했고 output file `5,944`개를 생성했습니다.
- POLYGON Prototype prefab `496`개와 일반 scene `2`개가 모두 load·instantiate됐습니다
  (`498/498`).
- 대표 albedo texture mapping `13`개가 모두 일치했습니다(`13/13`).
- POLYGON Prototype 검증에서 누락된 mesh, material, collision-shape binding은 `0`입니다.
- Package에서 생성된 Synty `.tscn` resource `989`개가 모두 load·instantiate됐으며,
  POLYGON Generic과 POLYGON Prototype 콘텐츠를 포함합니다. 이는 구조적 load gate이지
  semantic parity나 lossless conversion 주장과는 다릅니다.
- FPS/VR hand prefab `8`개가 모두 의도된 active SkinnedMesh variant를 보존했습니다.
  Variant `32`개에서 정확히 `8`개 mesh가 visible, `24`개가 hidden이었고 mismatch는
  `0`이었습니다. Package `Overview.tscn`을 instantiate해도 같은 `8/24` 결과였습니다.
  Importer는 이제 mesh가 공유 Godot `Skeleton3D` 아래로 지연되는 경우에도 renderer의
  `m_Enabled` 상태와 source GameObject의 active-in-hierarchy 상태를 결합합니다.
- Unity ParticleSystem/ParticleSystemRenderer pair `30`개가 모두 `GPUParticles3D`
  node를 생성했습니다. 공통 Initial, Emission, Shape, Color, Size, billboard,
  stretched-billboard, mesh-renderer 부분집합을 변환하며, 활성화된 미지원 module은 명시적
  warning을 생성합니다.
- Unity `SceneRoots`가 demo scene의 저작된 root 순서를 복원했습니다.
- Package LightingSettings asset이 Godot resource를 생성했고, demo `LightmapGI`는
  mapping된 저작 값(bounce `2`, directional mode, texel scale `0.025`, 최대 texture
  size `2048`)을 보존했습니다. Godot `LightmapGI`에는 대응되는 realtime 변환이 없으므로
  Unity realtime-GI 의도는 metadata로만 남습니다.
- ShaderGraph/SubGraph file `25`개를 모두 source-only file로 보존했고
  `.failed_import` file은 생성하지 않았습니다. Shader 의미는 변환하지 않았습니다.
- 이 full-import 실행에서 warning 진단은 baseline `667`에서 `141`로 감소했고 failure
  진단은 `13`으로 유지됐습니다. 직전의 동등한 실행은 `140`을 수집했습니다. 한 message
  차이는 병렬 source-only shader warning 수집에서 생겼으며, `25/25` source-preservation
  gate에는 변화가 없었습니다. `b60759d` 재실행은 raw warning record `152`건과 raw
  failure record `26`건에서 dialog warning `124`건과 같은 failure `13`건을 셌습니다.
  Raw 수치와 dialog 수치의 차이는 기본적으로 import 선택에서 해제되는 `.cs` 및 `.shader`
  asset입니다.
- 의도적으로 줄인 비실행성 warning noise는 `0`입니다. Disabled-animation
  `AnimationClip` fallback ID와 identity Humanoid rotation은 verbose 진단에만 남고,
  반복 missing-MeshCollider lookup은 더 이상 중복 generic no-meta warning을 내지
  않습니다.
- 나머지 warning은 실행 가능한 진단이거나 명시적으로 손실이 있는 진단이며,
  [Import 진단 수치](#import-진단-수치)에서 분류별로 설명합니다.
- 빨간 진단 `13`건은 모두 package에 없는 source mesh GUID/fileID를 참조하는 POLYGON
  Generic MeshCollider입니다. 누락 참조는 null-mesh script error 대신 각각 한 번씩
  구조화된 source-data failure로 보고됩니다. 참조된 GUID는 Unity project 어디에서도
  `.meta` file이 소유하지 않으므로 Unity에서도 이미 깨진 참조입니다.

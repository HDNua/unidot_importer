# Unidot Importer (한국어)

*Read this in [English](./README.md).*

**Unidot**은 Unity 소스 에셋을 Godot 4 네이티브 형식으로 번역하는 에셋 상호운용
파이프라인입니다. `.unitypackage` 파일과 에셋 폴더를 Godot 4.x 호환 형식으로 변환합니다.

원본 **소스 에셋**을 Godot 네이티브 등가물로 *번역*합니다. 예를 들어 `.unity`와
`.prefab`은 `.tscn`과 `.prefab.tscn`이 됩니다. 메시·애니메이션·머티리얼 등의 원시
에셋은 Godot `.tres`/`.res` 등가물로 직접 변환됩니다.

번역기이므로 작업이 끝나면 프로젝트에서 안전하게 제거할 수 있습니다
(`runtime/anim_tree.gd` 제외).

이 문서는 **HDNua fork 전용 한국어판**입니다. Unidot 본체의 전체 기능 목록, 지원
에셋 타입, 문제 해결, 알려진 이슈, 향후 계획은 영어 원문
[README.md](./README.md)를 참고하세요.

## 빠른 링크

- [업데이트 확인: https://unidotengine.org/](https://unidotengine.org)
- [문서: https://docs.unidotengine.org/](https://docs.unidotengine.org)
- [Discord 커뮤니티](https://discord.gg/JzXkxMRd9x) — 도움 요청, 성과 공유, 피드백

## 시스템 요구사항

Unidot은 Windows, macOS, Linux에서 테스트되었습니다. Godot 에디터 4.0~4.2를
지원하며, Godot 4.7.1에서 호환성 스모크 테스트를 거쳤습니다.

`.unitypackage` 임포트 시 FBX를 glTF로 자동 변환하는 데 FBX2glTF를 사용합니다.
이 fork의 검증은 Godot 네이티브 FBX 임포터로 수행했습니다.
[FBX2glTF 실행 파일을 내려받아](https://github.com/godotengine/FBX2glTF/releases)
Godot 에디터 설정에서 FBX Import를 구성한 뒤 사용하세요.

## 설치

1. 이 저장소를 프로젝트의 `addons/unidot_importer`에 배치합니다.
2. 프로젝트 설정 → 플러그인에서 **Unidot Importer**를 활성화합니다.
3. 메뉴의 Unidot 항목에서 `.unitypackage` 또는 에셋 폴더를 선택해 임포트합니다.

### 임포트 대상 경로

임포트 대화상자에서 출력 루트를 지정할 수 있습니다. 지정하지 않으면 패키지의
원본 경로 구조가 프로젝트 루트에 그대로 재현됩니다. 이 fork의 검증은
`res://Unidot`을 출력 루트로 사용했습니다.

## HDNua 업데이트

### 에셋 지원 현황

| 퍼블리셔 | 패키지 | 검증 환경 | 지원 | 상세 |
| --- | --- | --- | :---: | --- |
| Synty Studios | POLYGON - Prototype Pack | Godot `4.7.1-stable.mono`, macOS | △ 부분 지원 | 프리팹과 씬이 메시·머티리얼·콜리전·albedo·active 상태·휴머노이드 스키닝·씬 루트·라이팅 저작값·기본 파티클 변환이 검증된 상태로 인스턴스화됩니다. ShaderGraph 시맨틱, 고급 파티클 모듈, 리얼타임 GI, 소스가 누락된 콜라이더 참조는 여전히 검토가 필요합니다. |

`△ 부분 지원`은 검증된 사용 가능 부분집합이 존재하지만 임포트가 무손실은 아니며,
위에 나열된 격차에 대해서는 검토나 수동 이식이 필요하다는 뜻입니다.

### 소스 데이터 결함: Synty 휴머노이드 아바타

이 패키지의 FPS 팔 프리팹은 임포트 시 붕괴했는데, 원인은 Unidot도 Godot도 아니고
Synty 에셋 자체의 아바타 데이터 오류였습니다.

![수정 전 Standard FPS 팔 프리팹 4종: 지오메트리가 찢어지고 뒤틀린 상태](./hdnua_arms_before.png)

*수정 전: 잘못된 아바타 데이터 때문에 찢어진 Standard FPS 팔 프리팹.*

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

![수정 후 동일한 Standard FPS 팔 프리팹 4종: 좌우 대칭의 정상 팔](./hdnua_arms_after.png)

*수정 후: 동일한 프리팹 4종을 동일한 카메라로 렌더한 결과.*

![Character_FPS_Arms_Standard_01 클로즈업: 좌우 팔이 대칭](./hdnua_arms_closeup.png)

*`Character_FPS_Arms_Standard_01` 클로즈업. 손목 축으로 뒤틀려 있던 오른팔이 이제
왼팔과 대칭입니다.*

![패키지 Overview 씬 안의 FPS 팔 프리팹들이 모두 정상인 모습](./hdnua_arms_overview.png)

*맥락 속에서 본 동일한 결과: 패키지 `Overview` 씬의 FPS 팔 행. 에디터가 아니라
런타임 렌더라서 기즈모나 RESET 포즈 오버라이드가 화면에 없습니다.*

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

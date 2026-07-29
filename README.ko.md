# Unidot Importer

*[English](./README.md)로 읽기.*

Unidot은 Godot 4용 Unity → Godot 소스 에셋 번역기입니다.
`.unitypackage` 아카이브와 압축을 푼 Unity 에셋 폴더를 Godot 씬과 리소스로
변환합니다. 예를 들어 `.unity`와 `.prefab` 파일은 `.tscn` 씬이 되고,
메시·애니메이션·머티리얼을 비롯한 지원 에셋은 Godot 네이티브 리소스가 됩니다.

이 저장소는
[V-Sekai/unidot_importer](https://github.com/V-Sekai/unidot_importer)의 공개
[HDNua fork](https://github.com/HDNua/unidot_importer)입니다. upstream 번역기를
유지하면서 Godot 4.7 호환 작업, 격리 출력 루트, 재현 가능한 패키지 검증 도구, 공개 회귀
테스트로 뒷받침되는 수정 사항을 추가했습니다.
[라이선스와 저작자 표시](#라이선스와-저작자-표시)도 참고하세요.

> [!IMPORTANT]
> 아래 Godot 4.7.1 실측 결과는 명시된 패키지와 설정에 대한 호환성 근거이지,
> Unity 프로젝트를 무손실로 변환한다는 약속이 아닙니다. 스크립트, 커스텀 셰이더,
> 일부 엔진 기능은 여전히 수동 이식해야 합니다.

## 현재 fork 상태

- upstream이 문서화한 호환 범위는 Godot 4.0~4.2입니다.
- 이 fork에는 호환성 수정이 적용됐고 macOS용
  Godot `4.7.1-stable.mono`에서 패키지 검증을 실측했습니다.
- 측정한 6개 패키지의 임포트는 모두 완료됐습니다. 누적 구조 검증은 1~5단계에서
  통과했지만, 6단계 Fantasy Kingdom에서 재현 가능한 meshless node 52개가
  발견되어 실패했습니다. [패키지 실측 상태](#패키지-실측-상태)를 참고하세요.
- 최종 프로젝트에서 실행한 패키지 범위 source-pose gate 6회는 모두 각 gate가
  문서화한 source-consistency 범위 안에서 통과했습니다. 이는 별도의 mesh-reference
  실패를 무효화하지 않으며 독립적인 Unity 렌더링 오라클도 아닙니다.
- thread-safe 로그 수집에는 합성 멀티스레드 회귀 테스트가 있습니다. 그러나
  10 workers와 verbose logging을 함께 쓰는 production end-to-end gate는 아직
  남아 있으므로, production verbose mode의 thread safety가 완전히 검증됐다고
  주장하지 않습니다.

최신 상세 근거는 [한국어 패키지 리포트 인덱스](./docs/packages/README.ko.md),
[영문 인덱스](./docs/packages/README.md), 그리고
[검증 도구 문서](./tools/README.md)에 있습니다.

## 빠른 링크

- [HDNua fork](https://github.com/HDNua/unidot_importer)
- [upstream 프로젝트](https://github.com/V-Sekai/unidot_importer)
- [upstream 웹사이트](https://unidotengine.org/)
- [upstream 문서](https://docs.unidotengine.org/)
- [Discord 커뮤니티](https://discord.gg/JzXkxMRd9x)
- [Godot 4.7.1 호환성 추적 이슈](https://github.com/HDNua/unidot_importer/issues/1)

## 요구사항

Unidot은 Windows, macOS, Linux에서 사용돼 왔습니다. 이 fork의 현재
Godot 4.7.1 패키지 측정은 macOS에서 수행했으며, 모든 OS와 렌더러 조합에서
동일한 범위를 검증했다는 뜻은 아닙니다.

upstream FBX 경로는
[FBX2glTF](https://github.com/godotengine/FBX2glTF/releases)를 사용합니다.
이 경로를 사용할 때는 FBX2glTF를 설치하고 Godot의
**에디터 설정 → 가져오기**에서 실행 파일을 지정하세요. 공개된 Godot 4.7.1 패키지
측정은 Godot 네이티브 FBX 임포터를 사용했으므로 두 FBX 경로의 결과가 같다고
가정하면 안 됩니다.

큰 패키지에는 RAM 16GB 이상을 권장합니다. Unidot은 여러 에셋을 미리 파싱하므로
대규모 임포트에서 10~12GB를 사용할 수 있습니다. 가상 메모리 swap은 느리지만
그 자체가 실패를 뜻하지는 않습니다.

## 설치와 사용

1. 이 저장소를 Godot 프로젝트의 `addons/unidot_importer`에 배치합니다.
   Git submodule이나 압축 해제한 아카이브를 사용할 수 있습니다.
2. **프로젝트 설정 → 플러그인**에서 **Unidot Importer**를 활성화합니다.
3. upstream FBX2glTF 경로를 쓸 때는 **에디터 설정 → 가져오기**에서
   FBX2glTF를 구성합니다.
4. TIFF/`.tif`와 PSD/`.psd`를 지원하려면
   [ImageMagick](https://imagemagick.org/) 또는
   [GraphicsMagick](http://www.graphicsmagick.org/)을 시스템 경로에
   설치하세요. Windows에서는 `convert.exe`를 이 add-on 디렉터리에
   둘 수도 있습니다.
5. **프로젝트 → 도구 → Import .unitypackage...**를 열고 패키지 또는 에셋
   폴더를 선택합니다.

변환된 씬이 `runtime/anim_tree.gd`를 참조할 수 있습니다. 변환을 마친 뒤
임포터의 나머지 부분을 제거하더라도 이 파일은 필요한 경우 유지하세요.

![에디터 설정의 FBX2glTF와 프로젝트 설정에서 활성화한 플러그인](./unidot_instructions.png)

### 임포트 대상 경로

임포트 대화상자에서 Unity 소스 경로 구조를 바꾸지 않은 채, 변환 에셋을
프로젝트 상대 출력 루트 아래에 둘 수 있습니다. 하위 호환 기본값은
`res://`입니다. 예를 들어 `res://Unidot`을 선택하면 다음과 같이 매핑됩니다.

```text
Assets/Example/Model.fbx -> res://Unidot/Assets/Example/Model.fbx
```

프로젝트의 `unidot/import_output_root` 설정으로 기본값을 지정할 수 있습니다.
대상은 반드시 `res://` 내부여야 하며, 절대경로, `user://`, 역슬래시,
상대 `.` 또는 `..` 세그먼트는 거부됩니다.

루트가 아닌 대상을 사용하면 fallback texture와 material 검색도 그 대상 내부로
제한됩니다. 따라서 프로젝트에 이미 있던 무관한 에셋이 fallback 검색으로 연결되는
것을 막습니다. 임포터는 신뢰할 수 있는 프로젝트 트리를 전제로 하며 기존 symlink나
junction을 통한 쓰기를 sandbox하지 않습니다. 에셋 데이터베이스는 Unity GUID마다
활성 출력 경로 하나만 유지하므로 한 프로젝트에서 같은 패키지를 여러 대상으로
임포트하는 것은 지원하지 않습니다.

## Unidot이 변환하는 것

- Unity `.unitypackage` 아카이브와 압축을 푼 에셋 폴더
- Unity 씬과 프리팹(상속 프리팹 포함)
- Mesh, MeshFilter, MeshRenderer, SkinnedMeshRenderer
- Standard material과 지원되는 texture 속성
- Avatar와 AnimationClip 리소스
- AnimatorController, state machine, transition, blend tree
- GameObject, Transform, collider, Rigidbody, Light, Camera, AudioSource
- Texture2D, CubeMap, Texture2DArray, AudioClip
- MultiMeshInstance를 통한 제한적인 detail mesh 지원을 포함한 Terrain
- 문서화된 변환 범위 안의 LightingSettings와 PostProcessLayer
- ParticleSystem과 ParticleSystemRenderer의 결정적 공통 부분집합

이 fork는 GameObject의 active-in-hierarchy 상태와 renderer visibility를
보존하고, 구조적으로 모순된 humanoid map을 사용 전에 검증하며, 양손에 중복된
bone name을 처리합니다. `_Albedo_Map`, `_Base_Map`, `_Normal_Map`,
`_Emission_Map`처럼 자주 쓰이는 밑줄 포함 Unity texture 속성도 인식합니다.

## 미지원 또는 부분 지원

- Unity C# script와 MonoBehaviour 동작은 이식하지 않습니다.
- ShaderGraph와 SubGraph의 의미는 번역하지 않습니다. 소스 파일은 수동 이식용으로
  보존합니다.
- custom shader는 대응되는 Godot 구현을 수동으로 만들어야 합니다.
- Canvas/UI, AvatarMask, PlayableDirector는 구현되지 않았습니다.
- ParticleSystem은 결정적으로 대응 가능한 공통 부분집합만 변환합니다. 미지원
  모듈과 근사 처리에는 명시적인 경고를 남깁니다.
- Unity realtime GI에 직접 대응하는 Godot LightmapGI 기능은 없습니다.
  지원되는 lightmap 저작 값은 보존하고 realtime 의도는 metadata로 남깁니다.
- 지원 목록에 없는 것은 측정되기 전까지 미지원으로 간주해야 합니다.

## 재현 가능한 검증

이 저장소에는 headless 검증 하네스가 있습니다. 반복 가능한 테스트와 리포트
생성용이며, 아직 범용으로 지원되는 안정적인 headless import API는 아닙니다.

### 패키지 하나를 격리 검증

`tools/validate_package.py`는 일회용 Godot 프로젝트를 만들고 현재 checkout을
`addons/unidot_importer`에 복사한 뒤 `res://Unidot`으로 임포트하고,
선택적으로 결과까지 검증합니다.

```bash
python3 tools/validate_package.py "/path/to/Pack.unitypackage" --run --verify
```

동기화는 `.git`을 제외한 working tree를 복사하므로, untracked 또는 로컬 파일이
검증 프로젝트에 섞이지 않게 clean checkout에서 실행하세요.

패키지별 리포트는 반드시 패키지마다 별도의 깨끗한 프로젝트에서 만드세요.
그래야 GUID 데이터베이스, Godot import cache, 출력, 진단 수치를 해당 패키지에
귀속할 수 있습니다.

### 한 프로젝트에 여러 패키지

패키지 통합은 별도의 테스트입니다. 먼저 아카이브를 비교한 뒤 명시적인 순서로
임포트하고 매 단계 전체를 검증합니다.

```bash
python3 tools/checks/package_overlap.py A.unitypackage B.unitypackage
python3 tools/validate_package.py A.unitypackage B.unitypackage --run --verify
```

도구의 책임은 의도적으로 나뉩니다.

- `import_report.py`는 단계별 진단을 분류하고 출력을 집계합니다.
  `--json`으로 기계 판독 결과를 만들 수 있습니다.
- `verify_output.gd`는 생성된 모든 씬을 load·instantiate하고, 선언한 모든
  node path가 instantiate 뒤에도 존재하는지 검사하며, mesh가 없는
  `MeshInstance3D`를 실패로 판정합니다.
- `package_overlap.py`는 Godot을 실행하지 않고 공유 GUID, 서로 다른 bytes,
  metadata 차이, 경로 충돌, 방향별 model-consumer 검토 후보를 보고합니다.
- `unity_source_pose_gate.py`는 skin이 있는 변환 프리팹을 source-side 및
  persisted-conversion 근거와 비교하고 negative control도 실행합니다. 문서에
  표시된 더 약한 FBX branch는 source-consistency 검사이지 독립적인 Unity
  renderer가 아닙니다.
- publisher 전용 gate는 `tools/publishers/`에 남기며 vendor-neutral 검사로
  승격하지 않습니다.

이 검사는 특정 구조와 source-consistency 불변조건을 입증합니다. 시각적·행동적·
shader·gameplay 동등성을 증명하지는 않습니다. 생성된 validation context에는
로컬 소스 경로가 들어갈 수 있으므로 공개하기 전에 검토하세요. 전체 계약은
[tools/README.md](./tools/README.md)에 있습니다.

## 패키지 실측 상태

**격리**로 표시된 두 패키지는 전용 프로젝트에서 수행한 전체 리포트가 있습니다.
Town, War, Sci-Fi City에는 현재 누적 단계 통합 근거만 있으므로 그 PASS를 패키지
단독 측정처럼 표현하면 안 됩니다. Fantasy Kingdom에는 누적 단계 결과와 함께
같은 실패를 재현한 목적 한정 clean single-package 대조군이 있습니다.

| 퍼블리셔 | 패키지 | 현재 근거 | 실측 결과 | 한국어 | English |
| --- | --- | --- | --- | --- | --- |
| Synty Studios | POLYGON - Starter Pack | 격리 리포트, 6팩 1단계 | 격리 변환 OK, 단계 PASS | [리포트](./docs/packages/polygon-starter.ko.md) | [Report](./docs/packages/polygon-starter.md) |
| Synty Studios | POLYGON - Town Pack | 6팩 누적 2단계만 있음 | 단계 PASS | [통합 리포트](./docs/packages/multi-package.ko.md) | [Integration report](./docs/packages/multi-package.md) |
| Synty Studios | POLYGON - War Pack | 6팩 누적 3단계만 있음 | 단계 PASS | [통합 리포트](./docs/packages/multi-package.ko.md) | [Integration report](./docs/packages/multi-package.md) |
| Synty Studios | POLYGON - Prototype Pack | 격리 리포트, 6팩 4단계 | 문서화된 범위에서 격리 변환 OK, 단계 PASS | [리포트](./docs/packages/polygon-prototype.ko.md) | [Report](./docs/packages/polygon-prototype.md) |
| Synty Studios | POLYGON - Sci-Fi City Pack | 6팩 누적 5단계만 있음 | 단계 PASS | [통합 리포트](./docs/packages/multi-package.ko.md) | [Integration report](./docs/packages/multi-package.md) |
| Synty Studios | POLYGON - Fantasy Kingdom Pack | 6팩 6단계, 목적 한정 clean 대조군 | **FAIL / 알려진 model-reference 한계** | [통합 리포트](./docs/packages/multi-package.ko.md) | [Integration report](./docs/packages/multi-package.md) |

위 결과는 모두 macOS용 Godot `4.7.1-stable.mono`에서 측정했지만 importer
revision은 연결된 리포트에 기록된 값입니다. converter code가 바뀐 뒤 이 결과를
재검증 없이 그대로 승계하면 안 됩니다.

### 6패키지 단계별 실행

importer revision `c0892c5`의 깨끗한 프로젝트에서 Starter → Town → War →
Prototype → Sci-Fi City → Fantasy Kingdom 순서로 임포트했습니다. 모든 임포트가
완료됐습니다. 아래 각 행은 그 패키지를 추가한 뒤 프로젝트 전체를 누적 검증한
결과입니다.

| 단계 | 추가 패키지 | 씬 load / instantiate | 선언 경로 / 누락 | mesh node / meshless | 검증 |
| ---: | --- | ---: | ---: | ---: | --- |
| 1 | Starter | `499/499` | `2,855 / 0` | `1,422 / 0` | PASS |
| 2 | Town | `1,253/1,253` | `12,214 / 0` | `8,037 / 0` | PASS |
| 3 | War | `1,840/1,840` | `21,133 / 0` | `15,336 / 0` | PASS |
| 4 | Prototype | `2,340/2,340` | `25,091 / 0` | `17,663 / 0` | PASS |
| 5 | Sci-Fi City | `2,979/2,979` | `32,146 / 0` | `22,974 / 0` | PASS |
| 6 | Fantasy Kingdom | `5,175/5,175` | `77,811 / 0` | `58,646 / 52` | **FAIL** |

52건은 Fantasy 프리팹 16개의 직접 meshless node 17개와, Fantasy 씬 3개에서
그 프리팹을 사용한 35건입니다. 깨끗한 Fantasy 단독 대조군은 씬
`2,687/2,687`개를 load·instantiate하고 선언 경로 누락 0개를 확인했지만,
정확히 같은 meshless node 52개를 재현했습니다. 현재 근거는 앞선 다섯 패키지의
공유 GUID 덮어쓰기가 아니라 Fantasy 내부 model sub-object/file-ID 해석 한계를
가리킵니다.

실측 순서는 Town이 Prototype 뒤에서 공유 character model을 교체해 content loss를
일으켰던 기존 재현 사례를 피했습니다. 그러나 이는 위험을 줄이기 위한 검증
순서이지 무손실 또는 범용 안전 순서의 증명은 아닙니다. 현재 근거가 뒷받침하는
유일한 방향 제약은 Town과 War를 Fantasy Kingdom, Prototype, Sci-Fi City보다
먼저 임포트하는 것입니다. 이 팩들을 결합하기 전에 통합 리포트를 읽으세요.
[한국어](./docs/packages/multi-package.ko.md) ·
[English](./docs/packages/multi-package.md).

## 임포트 진단 메시지 해설

엔진 `ERROR`가 많거나 Unidot warning counter가 0이 아니라는 사실만으로 변환
성공·실패를 판정할 수 없습니다. 지금까지 관측한 패키지 진단에는 다음이 있습니다.

1. vendor FBX에 내장된 죽은 texture 경로
2. source package에서 이미 빠져 있는 GUID 참조
3. 미지원 또는 근사 기능에 대한 명시적 통지
4. 일관되지 않은 source data를 거부한 importer validator의 보고

`import_report.py`, output verifier, 패키지 리포트를 함께 보세요. 모든 오류가
무해하다고 가정해서도 안 됩니다. script error, 선언 node 누락, meshless output은
실제 importer 결함일 수 있습니다.

![warning·error counter가 0이 아니지만 완료된 POLYGON Prototype 임포트](./hdnua_import_dialog.png)

## 알려진 한계

- Fantasy Kingdom에서는 일부 Unity model sub-object/file-ID 참조가 Godot이
  추출한 mesh로 해석되지 않아 meshless node 52개가 재현됩니다. 현재 공개적으로
  문서화된 변환 blocker입니다.
- 대소문자를 구분하지 않는 파일시스템에서 Godot FBX texture 탐색이
  `Textures/` 파일을 열고도 소문자 `textures/` 표기를 보존할 수 있습니다.
  그 결과 추출 mesh의 참조가 대소문자를 구분하는 파일시스템에서 실패할 수
  있습니다. 변환된 Unity `.mat` 리소스에는 영향이 없습니다.
- animation을 다시 import하면 scene import 중 수정한 track path가 사라질 수
  있습니다.
- source의 누락 GUID 참조가 항상 명확하게 드러나지는 않습니다.
- UpperChest·Shoulder·Neck이 빠진 humanoid rig, 회전된 hips, scale이 적용된
  armature, unpacked humanoid prefab은 추가 검토가 필요할 수 있습니다.
- weight가 칠해지지 않은 vertex는 현재 skeleton bone index 0으로 갑니다.
- FBX 변환 경로 자체에도 n-gon과 RotationPivot 처리 등의 한계가 있을 수 있습니다.
- dependency 선택은 model이 참조하는 모든 texture를 찾아주지 못합니다.
- 대규모 import는 메모리를 많이 사용하고 큰 animation 단계에서 멈춘 것처럼
  보일 수 있습니다.

## 문제 해결

- 대화형 임포트 뒤 **프로젝트 → 도구 → Show last import logs**를 여세요.
  노란색·빨간색 열에서 진단을 묶어 보고, 파일의 **Logs** 버튼으로 전체 로그를
  볼 수 있습니다.
- 참조한 dependency를 모두 포함했는지 확인하세요.
- 큰 import가 crash하면 더 작은 패키지나 부분집합으로 재현하세요.
- 부분집합은 texture → material → model/material → scene 순서로 임포트하세요.
  Shift 선택이 도움이 되지만 모든 dependency를 찾아주지는 않습니다.
- unpacked prefab을 쓰는 scene model이 깨져 보이면 변환된 원본 model scene과
  비교하세요.
- 재현 가능한 bug report에는 격리 프로젝트를 사용하고 Godot 버전, importer
  commit, FBX 경로, 명령, 검증 결과를 기록하세요. 라이선스가 있는 asset bytes나
  로컬 source path는 공개하지 마세요.

## 프로젝트 범위

Unidot은 에디터 작업에 사용하는 적법한 source asset을 번역합니다. asset bundle을
decompile하거나 게임 콘텐츠를 추출하는 도구가 아니며, 그런 기능을 추가할 계획도
없습니다. 변환 권리가 있는 에셋만 사용하세요.

## 라이선스와 저작자 표시

이 fork는 저장소의 [MIT 라이선스](./LICENSE.txt)를 그대로 따릅니다. 원 저작권과
허가 고지는 해당 파일에 유지돼 있습니다. Unidot은 Lyuma와 기여자들이 만들었고,
V-Sekai 커뮤니티 및 upstream 프로젝트가 표시한 다른 기여자의 작업을 포함합니다.

upstream의 특별 감사 대상을 그대로 기록합니다.

- humanoid rig·root motion testcase와 통찰을 제공한 Cthulhoo
- 다양한 prefab 참조 패턴이 담긴 game-jam 프로젝트를 제공한 Stan
- test asset과 report에 기여한 모든 분
- [V-Sekai 커뮤니티](https://github.com/V-Sekai)와
  [V-Sekai 팀](https://v-sekai.org)

![Godot 4.7.1에 Unidot으로 임포트한 Synty POLYGON Prototype demo](./hdnua_synty_polygon_prototype_godot_4_7_1.png)

![변환된 scene 위에 열린 Unidot import dialog](./unidot_example.jpg)

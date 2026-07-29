# Synty POLYGON - Starter Pack

*이 보고서를 [English](./polygon-starter.md)로 읽기.*

Synty **POLYGON - Starter Pack** `.unitypackage`의 검증 보고서입니다. Unidot이
일반적으로 무엇을 변환하는지와 모든 Synty 패키지에 공통인 동작은
[README](../../README.ko.md)를 참고하세요. 이 파일은 이 패키지에만 해당하는 내용을
기록합니다.

macOS용 Godot `4.7.1-stable.mono`, importer revision `5576bf8`에서 검증했습니다.
`tools/validate_package.py`로 별도 프로젝트의 `res://Unidot`에 import한 뒤
`tools/checks/verify_output.gd`와 `tools/checks/import_report.py`로 검사했습니다.

**결과: 이 pack은 올바르게 변환됩니다.** 생성된 scene이 모두 load되고, 변환된
material은 의도된 texture를 연결합니다. 이 pack에 고유한 결함은 발견되지 않았습니다.

## 콘텐츠 구성

이 pack은 자체 콘텐츠보다 Synty의 공유 library가 대부분이므로 아래 수치의 상당 부분은
Starter Pack보다 PolygonGeneric을 더 많이 설명합니다.

| Source folder | Output file |
| --- | ---: |
| `Assets/Synty/PolygonGeneric` | `2,495` |
| `Assets/Synty/PolygonStarter` | `481` |
| 합계 | `2,976` |

## 영역별 결과

| 영역 | 상태 | 근거 |
| --- | :---: | --- |
| Scene과 prefab | 정상 | `499/499`개가 load·instantiate됨(`496`개 prefab, 저작된 scene `3`개) |
| Unity `.mat`에서 변환한 material | 정상 | `55`개 중 `45`개가 texture를 연결함. 나머지 `10`개는 cloud, glass, skybox, water, blank material이며 Unity source에도 texture GUID가 없음 |
| Humanoid rig와 skinning | 판정하지 않음 | skin이 있는 prefab은 `4`개임. revision `5576bf8`에서 측정했을 때 bind `200`개가 rigidity identity를 만족했지만 아래 설명을 참고할 것 |

skin deformation 수치는 통과 판정이 아니라 관측값으로 기록합니다. 이 검사가 사용하는
identity(`D = global_bone_pose * bind_pose`가 `I`)는 prefab이 mesh를 bind한 pose로 저장된
경우에만 성립합니다. 이는 변환 자체가 아니라 publisher가 pack을 저작한 방식의 속성입니다.
이를 확인한 측정은 [한 프로젝트에서 여러 패키지 사용](./multi-package.ko.md#이-실행으로-함께-확인한-사항-skinning-검사는-vendor-neutral하지-않았음)을
참고하세요. `tools/checks/verify_output.gd`는 더 이상 이 identity를 단정하지 않으며,
`tools/publishers/` 아래 pack 전용 gate에서만 검사합니다.

model file에서 추출된 material `507`개에는 연결된 texture가 없습니다. 이는 결함이 아니라
예상된 결과입니다. 해당 material은 배포되지 않은 경로를 가리키는 FBX 자체 material이며
(아래 진단 참고), Unidot은 import 뒤 Unity `.mat` asset을 사용해 이를 덮어씁니다.

## Import 진단

| 진단 | 수치 |
| --- | ---: |
| Engine 수준 `ERROR` line | `5,426` |
| source FBX file에 내장된 유효하지 않은 texture 참조 | 서로 다른 file `33`개에서 `2,062`건(`.psd` `1,755`, `.png` `303`, `.tif` `4`) |
| 누락된 GUID dependency | `27` |
| 대소문자 불일치 warning | `5` |

모두 [Import 진단 메시지 해설](../../README.ko.md#임포트-진단-메시지-해설)의 분류
1과 2, 즉 vendor가 이미 깨진 상태로 배포한 참조에 속합니다. 어느 것도 Unidot이 잘못
변환한 항목을 의미하지 않습니다.

Headless 실행은 Unidot 자체의 asset별 warning·failure counter를 capture하지 않습니다.
해당 수치는 import dialog에 표시됩니다. 위 engine 수준 수치는 import log에서 얻었습니다.

## Starter 결함이 아닌 공유 결함

아래 두 finding은 두 pack 모두 같은 PolygonGeneric library를 포함하므로
[POLYGON Prototype 보고서](./polygon-prototype.ko.md)와 동일합니다.

- 대소문자 불일치 warning `5`건은 하나의 file
  `PolygonGeneric/Textures/Generic_Road_01.png`를 소문자 `textures/` 경로로 요청해서
  발생합니다. [알려진 한계](../../README.ko.md#알려진-한계)에 설명한 engine 결함입니다.
- 추출된 mesh `23`개에도 같은 대소문자 오류 참조가 들어 있습니다.

PolygonGeneric을 포함하는 모든 Synty pack에서 둘 다 다시 나타날 것으로 예상해야 합니다.
pack마다 따로 세지 말고 공유 library에 대해 한 번만 집계합니다.

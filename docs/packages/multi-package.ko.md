# 한 프로젝트에서 여러 패키지 사용

*이 보고서를 [English](./multi-package.md)로 읽기.*

이 directory의 다른 file은 `.unitypackage` 하나씩을 격리해 측정합니다. 이 보고서는
여러 패키지를 한 프로젝트에 넣었을 때를 다룹니다. 실제 프로젝트가 사용하는 방식이며,
같은 GUID를 공유하는 패키지들이 같은 output path를 두고 경쟁하는 유일한 경우입니다.

Static 비교는 importer revision `e5e93b3`에서 다시 실행했습니다. Prototype 다음 Town을
import한 실측은 macOS용 Godot `4.7.1-stable.mono`, revision `69bd28a`에서
`tools/checks/package_overlap.py`로 static 비교하고
`tools/validate_package.py A B --run --verify`로 import했습니다.

단계별 6패키지 검증은 Godot `4.7.1-stable.mono`, revision `c0892c5`에서 수행했습니다.
Starter, Town, War, Prototype, Sci-Fi City, Fantasy Kingdom 순서로 import하고 각 단계
뒤 vendor-neutral output verifier를 실행한 다음, 최종 project를 대상으로 source
package별 package-scoped source-pose gate를 한 번씩 실행했습니다.

**결과: 여러 패키지를 함께 import하면 순서에 따라 결과가 달라지며, 실제로 콘텐츠를
잃은 사례가 하나 있습니다.** 두 패키지가 같은 GUID에 서로 다른 byte를 담으면 나중에
import한 패키지의 file이 앞선 file을 대체합니다. Import 중 warning은 없으며, 먼저
변환된 콘텐츠가 대체본에는 없는 부분을 참조하고 있었다면 해당 부분은 불완전해집니다.

측정한 6패키지 순서는 알려진 underwear 손실을 피하지만 최종 output 검증은 **통과하지
않습니다**. Fantasy Kingdom을 추가하면 Fantasy 내부 model 참조에 뿌리를 둔 meshless
node `52`개가 나타납니다. Source-pose gate 여섯 번은 모두 통과하므로 새로운 finding은
skinning과 다른 invariant에 있습니다.

## 패키지 사이의 차이

Synty POLYGON pack 여섯 개 전체의 수치는 다음과 같습니다.

| 항목 | 수치 |
| --- | ---: |
| 여섯 pack 전체에서 서로 다른 GUID | `14,733` |
| 둘 이상의 pack이 포함 | `1,257` |
| — 모든 pack에서 byte가 같음 | `1,122` |
| — **pack마다 byte가 다름** | `135` |
| — pack마다 `.meta`가 다름 | `58` |
| 서로 다른 GUID 사이 pathname 충돌 | `0` |

동일한 `1,122`개는 문제가 없습니다. Pack들이 일치하므로 어느 pack이 file을 제공해도
상관없습니다. 문제가 되는 것은 `135`개이며, 균등하게 분포하지도 않습니다. 대부분은
material과 collision mesh지만 네 개는 model입니다.

| 충돌하는 model | Version |
| --- | --- |
| `PolygonGeneric/Models/Base/SM_Bld_Base_Floor_Round_01.fbx` | Starter 대 나머지 다섯 pack |
| `PolygonGeneric/Models/Base/SM_Bld_Base_Wall_Half_Angle_02.fbx` | Starter 대 나머지 다섯 pack |
| `PolygonGeneric/Models/Base/SM_Bld_Base_Wall_Round_01.fbx` | Starter 대 나머지 다섯 pack |
| `PolygonGeneric/Models/Generic_Characters.fbx` | Fantasy Kingdom, Prototype, Sci-Fi City(`7,326,192` B) 대 Town, War(`6,712,624` B) |

Model은 개수에 비해 더 중요합니다. 다른 asset이 model *안의* mesh나 bone을 file ID로
참조하므로, model 하나를 대체하면 완벽하게 변환된 asset의 참조도 무효가 될 수 있습니다.

Pathname 충돌이 `0`이라는 점도 중요합니다. Pack들은 GUID가 *어떤* asset을 가리키는지를
두고 다투는 것이 아니라 그 asset의 내용에만 동의하지 않습니다.

## 15개 조합 전체의 방향별 static screen

확장 비교는 지원되는 text asset을 대상으로 archive를 두 번째로 읽고, 충돌하는 model
build별로 참조되는 file ID를 묶습니다. 각 대체 방향에 대해 밀려나는 build와 함께 있는
consumer에서만 관측된 ID를 보고한 뒤, 그 consumer asset을 heuristic review 후보로
제시합니다.

이는 **consumer-reference heuristic**이지 import 결과나 model inventory가 아닙니다.
이기는 model에 해당 ID가 실제로 있는지 검사하지 않습니다. 0이 아닌 결과는 검토할 대상을
알려주며, 0은 방향별 consumer-reference 비대칭을 관측하지 못했다는 뜻일 뿐입니다.
어느 결과도 호환성, 무손실 순서 또는 superset 관계를 확립하지 않습니다.

표는 `6 choose 2 = 15`인 모든 pair를 다룹니다. `S/C/M`은 shared GUID, conflicting
GUID, meta-conflicting GUID입니다. 방향 cell은
`consumer-only file IDs / candidate assets`, 즉 한쪽 consumer에만 있는 file ID와 후보
asset입니다. `A / B` pair에서 “A 나중”은 A의
model build가 이기고 B와 함께 있던 consumer가 밀려난다는 뜻입니다. Dash는 분석할
상이한 model build가 없음을 뜻합니다. 이 표를 위해 import를 실행하지 않았고, 모든
pair의 pathname 충돌은 0이었습니다.

| Pair (A / B) | S / C / M | 서로 다른 model | A 나중 | B 나중 |
| --- | ---: | ---: | ---: | ---: |
| Fantasy Kingdom / Prototype | `1257 / 0 / 0` | `0` | — | — |
| Fantasy Kingdom / Sci-Fi City | `1257 / 1 / 0` | `0` | — | — |
| Fantasy Kingdom / Starter | `1054 / 75 / 58` | `3` | `0 / 0` | `0 / 0` |
| Fantasy Kingdom / Town | `1255 / 1 / 0` | `1` | `0 / 0` | `57 / 2` |
| Fantasy Kingdom / War | `1255 / 61 / 0` | `1` | `0 / 0` | `57 / 2` |
| Prototype / Sci-Fi City | `1257 / 1 / 0` | `0` | — | — |
| Prototype / Starter | `1054 / 75 / 58` | `3` | `0 / 0` | `0 / 0` |
| Prototype / Town | `1255 / 1 / 0` | `1` | `0 / 0` | `57 / 2` |
| Prototype / War | `1255 / 61 / 0` | `1` | `0 / 0` | `57 / 2` |
| Sci-Fi City / Starter | `1054 / 76 / 58` | `3` | `0 / 0` | `0 / 0` |
| Sci-Fi City / Town | `1255 / 2 / 0` | `1` | `0 / 0` | `57 / 2` |
| Sci-Fi City / War | `1255 / 62 / 0` | `1` | `0 / 0` | `57 / 2` |
| Starter / Town | `1054 / 75 / 58` | `3` | `0 / 0` | `0 / 0` |
| Starter / War | `1054 / 74 / 58` | `3` | `0 / 0` | `0 / 0` |
| Town / War | `1255 / 60 / 0` | `0` | — | — |

0이 아닌 여섯 방향은 모두 같은 `Generic_Characters.fbx` 분할입니다. Fantasy Kingdom,
Prototype 또는 Sci-Fi City 뒤에 Town이나 War의 build가 이기면 screen은 한쪽
consumer에만 있는 ID `57`개와 후보 asset 두 개를 찾습니다. 아래 Prototype 다음 Town
실측에서 확인한 것과 같은 underwear prefab 두 개입니다. 반대 순서는 `0 / 0`이지만,
여전히 “관측된 비대칭 없음”일 뿐 호환성 증명은 아닙니다.

Starter의 서로 다른 base model 세 개는 다섯 pair 모두에서 양방향 `0 / 0`입니다. 따라서
이 방법은 “Starter를 먼저 import”한다는 원칙을 검증하지 않습니다. 더 큰 model build가
superset이라는 넓은 가정도 입증하지 않습니다. 이를 신뢰성 있게 판정하려면 별도의 model
sub-object/file-ID inventory가 필요합니다.

## 실측 사례: Prototype 다음 Town

두 pack의 `Generic_Characters.fbx`는 같은 GUID와 byte-identical `.meta`를 사용하지만,
Prototype build에는 Town build에 없는 skinned mesh 두 개
`SM_Gen_Chr_Underwear_Female_01`, `SM_Gen_Chr_Underwear_Male_01`과 대응하는
bind pose 두 개가 들어 있습니다. 해당 prefab은 Prototype에만 있습니다.

Prototype을 import한 다음 Town을 같은 프로젝트에 import한 결과입니다.

| 항목 | Prototype 뒤 | Town 뒤 |
| --- | ---: | ---: |
| Load·instantiate되는 scene | `989/989` | `1693/1693` |
| Instantiate 뒤 누락된 선언 node path | `0` | **`4`** |
| Mesh가 없는 `MeshInstance3D` | `0` | `0` |

2단계가 `Generic_Characters.fbx`를 Town build로 다시 썼습니다. Town에는 underwear
prefab이 없으므로 Prototype의 두 prefab은 그대로 남았지만, 이제 mesh가 없는 model을
가리킵니다. 그 결과 Godot의 inherited-scene 복구 과정이 node를 버렸습니다.

```
WARNING: SM_Gen_Chr_Underwear_Female_01.prefab.scn: A node in the scene this one
         inherits from has been removed or moved, so a recovery process needs to
         take place.
WARNING: Node 'GeneralSkeleton/SM_Gen_Chr_Underwear_Male_01' was modified from
         inside an instance, but it has vanished.
```

손상은 아래에서 콘텐츠가 사라진 prefab 두 개에만 국한됩니다. 두 번째 import 전후의 skin
deformation은 동일하게 측정되었으므로 그 부분에는 변화가 없습니다.

## 새로운 검사가 필요했던 이유

Scene은 여전히 load되고 instantiate됩니다. Scene 안에 남은 모든 `MeshInstance3D`에는
여전히 mesh가 있습니다. Node는 비어 있는 것이 아니라 **사라졌으므로**, 존재하는 것만
세는 검사는 이를 볼 수 없습니다. 당시 checker를 이 project에 실행하면 integration
결함을 전혀 보고하지 않았습니다.

이제 `verify_output.gd`는 scene이 선언한 모든 node path가 instantiate 뒤에도
resolve되는지 단정합니다. 기대값이 아니라 scene 자체의 `SceneState`와 비교합니다.
결합 project에서는 선언된 node path `15,262`개 중 finding `4`개이며, static 비교가
미리 찾은 두 prefab에만 해당합니다. Scene `1,693`개 전체에서 false positive는
없었습니다.

반복되는 형태는 존재하는 항목을 열거하고 각각에 대해 무언가를 단정하는 검사입니다.
부재는 이런 검사에 보이지 않습니다.

## Source-pose gate도 같은 판정에 도달

Revision `0ac70a7`에서 추가한 source-pose gate는 이 사례에 대한 두 번째 구조 검사를
제공합니다. Direct-YAML prefab의 저작된 bone transform을 변환 scene과 비교하고, 더 약한
inherited-FBX branch에서는 모든 Unity prefab modification target이 지속 저장된 model
file-ID map을 통해 resolve되어야 합니다. 같은 Prototype package를 source로 사용해
깨끗한 Prototype-only project와 실측 Prototype-then-Town project 모두에서 실행했습니다.

| 항목 | Prototype만 | Prototype 다음 Town |
| --- | ---: | ---: |
| Skin prefab inventory(source/output) | `39/39` | `39/39` |
| 검사한 prefab | `39` | `37` |
| Direct YAML | `37` / bone `1,826` | `37` / bone `1,826` |
| 지속 저장 FBX composition | `2` / bone `154` | `0` |
| 지원하지 못한 prefab | `0` | **`2`** |
| 검출한 negative control | `2/2` | `1/1` |
| 수치 pose mismatch | `0` | `0` |
| 결과 | **PASS** | **FAIL** |

지원하지 못한 두 항목은 female 및 male underwear prefab입니다. 결합 project에서는 이들의
Unity modification target file ID `-8799741579280556076`이 지속 저장된 Town build의
`Generic_Characters.fbx`에서 더 이상 resolve되지 않습니다. 따라서 gate는 조용히
건너뛰는 대신 닫힌 상태로 실패합니다. 깨끗한 project에서는 두 prefab이 모두 resolve되고,
상속된 bone `154`개를 error 없이 비교합니다.

이는 독립적인 Unity data oracle이 아닙니다. 두 검사 모두 결국 같은 package에서 파생된
artifact를 검사합니다. 그렇지만 invariant와 failure mechanism은 다릅니다.
`verify_output.gd`는 instantiate 뒤 사라지는, 선언된 Godot `SceneState` path 네 개를
찾습니다. Source-pose gate는 지속 저장된 FBX mapping에서 resolve되지 않는 Unity prefab
target 두 개를 찾습니다. 두 검사가 같은 prefab 두 개를 지목하는 반면, 깨끗한 baseline에는
선언 path finding이 없고 source-pose 비교 branch도 모두 통과합니다.

## 이 실행으로 함께 확인한 사항: skinning 검사는 vendor-neutral하지 않았음

이 비교를 수행하며 이전 gate가 다루지 않았던 콘텐츠를
`tools/checks/verify_output.gd`로 검사했습니다. Skin이 있는 prefab 총 `39`개를 scan하는
동안 bone/skin failure `22,737`개가 보고됐습니다. 이 `39`개에는 통과한 FPS arm prefab
`8`개가 이미 포함됩니다. Failure는 pose가 적용된 PolygonGeneric full-character prefab
`20`개와 `Fov_01`의 검사 하나에서 나왔습니다. 나머지 non-FPS prefab `10`개도
통과했습니다. 영향받은 character chain의 일정한 angle은 FPS arm에서 수정한 Root 탈취
결함의 특징처럼 보였습니다.

Character failure는 false alarm이었습니다. **Character는 정상적으로 render됩니다.**
이 project에서 `SM_Gen_Chr_Business_Female_01`과
`SM_Gen_Chr_Peasent_Male_01`을 render하면 비율과 material이 올바르고 왜곡되지 않은
깨끗한 T-pose가 보입니다.

후보 mechanism 네 가지를 측정해 배제했습니다. 첫 frame 전 stale skeleton pose는 그
뒤에도 결과가 같았고, vertex weight가 없는 bind 문제는 weighted bind도 실패했으며,
중복 이름 때문에 bind-to-bone resolution이 잘못된 bone을 골랐다는 가정은 `1,150`개
모두에서 index와 이름이 일치했고, 보정되지 않은 mesh transform은 identity였습니다.
남은 원인은 검사 자체의 precondition입니다.
`D = global_bone_pose * bind_pose = I` identity는 skeleton이 mesh를 bind한 pose에 있을
때만 성립합니다. 해당 character prefab은 의도적으로 다른 pose로 저장되어 identity를
만족하지 않지만 정상적으로 render됩니다. 이것이 skinning의 동작입니다. FPS arm prefab은
우연히 bind pose에 있으므로 같은 검사가 그 대상에는 의미가 있습니다.

이 precondition은 독립적으로 검사할 수 없습니다. Identity 자체가 바로 검사이기
때문입니다. 따라서 이 검사는 publisher가 prefab을 어떻게 저작하는지에 대한 외부 지식이
필요하며, vendor-neutral로 가장한 publisher gate가 됩니다.
[tools/README.md](../../tools/README.md)가 경고하는 바로 그 형태입니다. 이 검사는
`tools/publishers/synty/polygon-prototype/gate_fps_arms.gd`로 옮겼고,
`verify_output.gd`는 더 이상 skinning에 대해 아무것도 단정하지 않습니다.

이것까지 포함하면 이 저장소의 검사 세 개가 현실과 다른 결과를 보고했습니다. Skin을
하나도 찾지 못하고 통과한 skeleton lookup, pose가 적용되어 저작된 scene을 실패로 판정한
검사, 그리고 이 검사입니다. 세 검사 모두 측정하지 않은 precondition을 확신하는 공통된
형태를 가집니다.

## 실측 6패키지 검증 순서

Revision `c0892c5`에서 깨끗한 project에 여섯 패키지를 권장 검증 순서로 import했습니다.
모든 import가 완료되었습니다. 표는 누적 결과이며, 각 row는 해당 package를 추가한 뒤
project를 검증합니다.

| 단계 | 추가한 package | Load / instantiate된 scene | 선언 node path | 누락 path | `MeshInstance3D` node | Meshless | Engine `ERROR` line | 대소문자 warning | Verify |
| ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| 1 | Starter | `499/499` | `2,855` | `0` | `1,422` | `0` | `5,432` | `5` | PASS |
| 2 | Town | `1,253/1,253` | `12,214` | `0` | `8,037` | `0` | `11,291` | `5` | PASS |
| 3 | War | `1,840/1,840` | `21,133` | `0` | `15,336` | `0` | `10,622` | `5` | PASS |
| 4 | Prototype | `2,340/2,340` | `25,091` | `0` | `17,663` | `0` | `9,691` | `5` | PASS |
| 5 | Sci-Fi City | `2,979/2,979` | `32,146` | `0` | `22,974` | `0` | `11,042` | `5` | PASS |
| 6 | Fantasy Kingdom | `5,175/5,175` | `77,811` | `0` | `58,646` | **`52`** | `29,783` | `5` | **FAIL** |

Engine 진단 수치는 단계별 import summary에서 가져온 문맥 정보이며 verifier 판정이
아닙니다. 모든 단계에서 `import_completed`가 true였고 Unidot warning 및 failure 수치는
모두 0이었습니다.

세 가지 예측을 구분할 수 있습니다. 첫째, 2단계에서 Town이 Starter의 base model 세 개를
덮어썼지만 열거한 scene, 선언 path, mesh 검사에서 finding이 없었습니다. 이는 이번 실행의
실측 근거이지 Starter-first가 일반적으로 안전하다는 증명이 아닙니다. 둘째, 4단계의
Prototype이 더 큰 `Generic_Characters.fbx` build를 복원했습니다. 선언 path finding은
계속 0이었고, Prototype source-pose gate는 더 약한 inherited-FBX 사례 두 개를 포함해
skin prefab `39`개를 모두 검사했습니다. 따라서 알려진 underwear 손실을 피했습니다.
셋째, meshless node가 0이라는 예측은 틀렸으며 6단계가 실패했습니다.

Finding `52`개는 Fantasy prefab `16`개에 있는 직접 meshless node `17`개와 Fantasy
scene 세 개에서 해당 prefab을 사용한 instance `35`개(`Demo`에 `9`,
`Demo_ExteriorOnly_Optimized`에 `9`, `Overview`에 `17`)입니다. 직접 finding마다 Unity
source의 `MeshFilter.m_Mesh` 참조가 0이 아닙니다. 영향받은 model GUID는 Fantasy
Kingdom에만 있고, 다른 package output tree 아래에는 finding이 없습니다. 따라서 shared-GUID
package 대체의 근거가 아닙니다. 대표 failure는 대신 model sub-object/file-ID resolution
격차를 보여줍니다. Mannequin 참조는 Godot이 추출한 `Mesh_###` resource에 resolve되지
않고, optimized tower part 두 개는 추출된 하나의 combined mesh로 표현됩니다.

같은 revision의 깨끗한 Fantasy-Kingdom-only control에서도 정확히 같은 scene/node
finding `52`개가 재현됐습니다. Scene `2,687/2,687`개가 load되고, 선언 node path
`48,801`개가 모두 살아 있었으며, mesh node는 `52/37,069`개가 meshless였습니다.
전체 finding inventory를 line별로 비교한 결과도 동일했습니다. 이 결과는 앞선 다섯
package의 import 순서와 finding을 분리합니다. 이는 6패키지 실행에서 드러난 Fantasy
model-reference 변환 한계이며 multi-package 충돌이 아닙니다.

최종 project는 이후 package-scoped source-pose gate 여섯 개를 모두 통과했습니다.

| Source package | Source / output skin prefab | 검사 | Direct YAML | 지속 저장 FBX composition(더 약함) | 비교한 bone | 미지원 / mismatch | Negative control | 결과 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| Starter | `4/4` | `4` | `4 / 106` | `0 / 0` | `106` | `0 / 0` | `1/1` | PASS |
| Town | `31/31` | `31` | `31 / 1,455` | `0 / 0` | `1,455` | `0 / 0` | `1/1` | PASS |
| War | `42/42` | `42` | `42 / 1,994` | `0 / 0` | `1,994` | `0 / 0` | `1/1` | PASS |
| Prototype | `39/39` | `39` | `37 / 1,826` | `2 / 154` | `1,980` | `0 / 0` | `2/2` | PASS |
| Sci-Fi City | `45/45` | `45` | `43 / 1,997` | `2 / 154` | `2,151` | `0 / 0` | `2/2` | PASS |
| Fantasy Kingdom | `52/52` | `52` | `50 / 2,176` | `2 / 154` | `2,330` | `0 / 0` | `2/2` | PASS |

각 실행에서 source-missing 및 output-unexplained prefab도 0이었고, process exit는 `0`,
관측된 position, rotation, scale error 최댓값도 `0`이었습니다. 검증 context와
materialize된 add-on은 revision `c0892c5`와 일치했습니다. 이 row는 package manifest
범위이므로 서로 겹칠 수 있습니다. 수치를 더해 고유한 6패키지 inventory라고 부르면 안
됩니다. 지속 저장 FBX branch는 위에서 설명한 더 약한 source-consistency oracle이며,
독립적인 Unity oracle이 아닙니다.

## 권장 사항

패키지를 함께 import하기 전에 static 비교를 실행하세요. 빠르고 Godot이 필요하지 않으며,
어떤 asset이 경합하는지 알려줍니다.

```bash
tools/checks/package_overlap.py "A.unitypackage" "B.unitypackage"
```

방향별 screen이 뒷받침하는 유일한 순서 제약은 Town과 War를 Fantasy Kingdom,
Prototype 또는 Sci-Fi City보다 먼저 import하는 것입니다. 관측된 consumer-reference
signal 하나를 최소화합니다. 실측 실행은 아래의 결정적 순서가 알려진 underwear 손실을
피함을 확인하지만, 최종 output에는 위에서 설명한 별도의 Fantasy mesh-reference finding이
여전히 있습니다. 이 finding은 Fantasy Kingdom만 import해도 재현되므로 아래 순서로
우회할 수 없습니다.

1. Starter
2. Town
3. War
4. Prototype
5. Sci-Fi City
6. Fantasy Kingdom

Starter의 위치와 두 model-build group 안의 순서는 tie-breaker이지 입증된 안전 속성이
아닙니다. 이는 관측한 heuristic signal을 최소화하도록 선택한 검증 순서이며, 무손실을
보장하는 순서가 아닙니다. 마지막 package만 검사하지 말고 매 단계마다 먼저 import한
package도 검증하세요.

```bash
tools/validate_package.py "A.unitypackage" "B.unitypackage" --run --verify
```

Unidot만으로 이 문제를 해결할 방법은 없습니다. 두 패키지가 같은 identity에 서로 다른
content를 주장하고, archive에는 어느 쪽이 의도된 것인지 적혀 있지 않습니다. 실측
사례에서는 `.meta` file도 byte-identical입니다. 사용자를 대신해 하나를 선택하면 추측이
되지만, 이를 보고하는 것은 추측이 아닙니다.

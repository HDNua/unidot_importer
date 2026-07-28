# HDNua Unidot Importer 인수인계

형식버전: 1

범위: 이 공개 fork 전체 — Godot 호환성, importer core, 병렬 처리, 공개 회귀 테스트와 downstream 소비 계약

내용수정시각: 260729-073545

내용검토시각: 260729-073545

내용검토상태: 완료

코드기준: `eebd8c08aa9fa3a06c6f1c5fda544e5f1b60332a`

코드상태: `GODOT_4_7_COMPATIBILITY_APPLIED / PACKAGE_VALIDATION_MEASURED / FANTASY_MODEL_REFERENCE_LIMITATION_OPEN / PRODUCTION_VERBOSE_GATE_PENDING`

## 저장소 정체성과 목적

이 저장소는 [`V-Sekai/unidot_importer`](https://github.com/V-Sekai/unidot_importer)의 공개 fork인 [`HDNua/unidot_importer`](https://github.com/HDNua/unidot_importer)다. Unity source asset과 `.unitypackage`를 Godot native scene·resource로 번역하는 Unidot Importer의 범용 기능을 유지하면서 다음을 개선한다.

1. Godot `4.7.x` 호환성
2. 병렬 import와 logging의 thread safety
3. headless 실행과 결정적 결과
4. 공개 fixture 기반 회귀 테스트
5. 기계 판독 가능한 import 결과와 범용 extension hook

특정 상용 asset, 특정 게임 또는 특정 downstream pipeline만을 위한 규칙은 importer core에 직접 넣지 않는다. 범용성이 입증된 기능과 공개 가능한 테스트만 이 fork가 소유한다.

## 현재 Git 및 구현 상태

- branch: `main`
- 현재 구현·검증 문서 기준: `eebd8c08aa9fa3a06c6f1c5fda544e5f1b60332a`
- 이 인수인계 문서를 추가하는 commit은 위 기준의 docs-only 후속 commit이다.
- origin: `https://github.com/HDNua/unidot_importer`
- upstream base: `V-Sekai/unidot_importer@7480b19649d50eef93cc8efd7ec9aa83d63a1bcb`
- fork delta: 위 upstream base부터 `eebd8c0`까지 `41` commits
- plugin version: `1.1.0`
- license: `MIT`
- Godot `4.7.1` compatibility tracking: [`HDNua/unidot_importer#1`](https://github.com/HDNua/unidot_importer/issues/1)

현재 clone에는 `upstream` remote가 아직 없다. 다음 설정을 한 번 수행한다.

```sh
git remote add upstream https://github.com/V-Sekai/unidot_importer.git
git fetch upstream
git remote -v
```

README는 기존 Godot `4.0`~`4.2` 지원과 외부 `FBX2glTF` 사용을 유지하면서 Godot `4.7.1` compatibility smoke test를 별도로 명시한다. 초기 호환 patch `06e0050` 이후 import output root, material·scene·particle·humanoid 보정, thread-safe logging, 공개 회귀 test와 package 검증 도구가 추가됐다. 최신 측정 결과와 한계는 [`docs/packages/`](docs/packages/README.md)와 [`tools/README.md`](tools/README.md)를 기준으로 본다.

## Godot 4.7.1에서 확인한 finding

아래 type fix와 modern Godot API migration은 초기 호환 commit `06e005025d31c3b218dab1d8b3cf12e2b7b5eef6`으로 `main`에 적용됐다. 이후의 수정과 검증 상태는 각 항목과 현재 검증 절을 따른다.

### 1. `runtime/anim_tree.gd`의 bool `_set()` 반환

`_set()`의 `node == null` 분기에 bare `return`이 있다. Godot `4.7.1`은 virtual `_set()`의 bool 반환 계약에 따라 이를 거부한다.

```diff
 if node == null:
     blend_to_meta_parameter[prop] = &""
-    return
+    return false
```

나머지 `_set()` exit도 `false`를 반환하므로 같은 의미를 유지하는 최소 호환 patch이며 `06e0050`에 반영됐다.

### 2. `yaml_parser.gd::parse_line()` 반환형

`parse_line()`은 `object_adapter.UnidotObject`를 반환할 수 있고 이 형식은 `RefCounted`를 상속한다. Godot `4.7.1`에서는 기존 `Resource` 반환 annotation과 실제 객체가 맞지 않아 runtime type error가 발생한다.

```diff
-func parse_line(...) -> Resource:
+func parse_line(...) -> RefCounted:
```

반환형 patch는 `06e0050`에 반영됐다. 공개 가능한 최소 YAML sequence와 `RefCounted.new()` callback을 사용하는 asset-independent regression test는 아직 추가해야 한다.

### 3. 추가 modern Godot API migration

같은 commit에는 다음 호환 변경도 포함됐다.

- scene save 뒤 현재 열려 있는 scene만 `reload_scene_from_path()` 호출
- asset database load 전에 `ResourceLoader.exists()` 확인
- `NavigationRegion3D.navigation_mesh` 사용
- skeleton owner를 실제 `godot_skeleton`에 지정
- `emission_energy_multiplier`, `scene_file_path`와 최신 `SubViewport` property 사용
- `PhysicalBoneSimulator3D`가 존재하는 Godot에서 physical bone을 simulator 아래 생성
- `AudioStreamPlayer3D` 전용 property를 실제 3D player에만 적용

### 4. stock 10-worker verbose logging 경합 — source fix 적용, production Gate 대기

두 type patch를 적용하고 stock `THREAD_COUNT = 10`과 verbose logging을 함께 사용했을 때 `asset_meta.gd`의 공유 `PackedStringArray` append 경로에서 다음 fatal이 재현됐다.

```text
FATAL: Index p_index = 0 is out of bounds (size() = 0).
```

실패 경로는 `LogMessageHolder.all_logs`, `warnings_fails`, `fails`와 공유 `global_log_count`를 동기화 없이 갱신한다. 공개 가능한 별도 stress reproducer에서도 여러 `Thread`가 하나의 `PackedStringArray`를 동시에 수정할 때 crash가 재현됐다.

이 경합의 알려진 공유 mutation 경로는 `f64a368e`에서 `LogMessageHolder`의 counter·array mutation과 snapshot을 mutex로 보호하도록 수정됐다. `test/logging_thread_safety_test.gd`는 `8` threads × `500` iterations로 debug·warning·failure 수집과 snapshot 일관성을 공개 fixture 없이 검증한다.

다만 이 synthetic test는 실제 importer의 `10 workers + verbose=true` end-to-end Gate와 같지 않다. 6패키지 import 완료도 verbose mode를 증명하지 않으므로, production 설정의 별도 stress Gate가 통과하기 전에는 thread-safety 검증 완료라고 확대 해석하지 않는다.

## 검증 현황

초기 `06e0050` 이전에 두 type patch만 임시 적용한 private downstream 평가가 있었지만, 그 corpus의 identity·규모·경로·hash·결과는 공개 검증 근거로 사용하지 않는다. 현재 상태 판정은 아래의 공개 저장소 문서와 재현 가능한 도구만을 따른다.

현재 판단은 revision `c0892c5`에서 수행하고 `eebd8c0`에 기록한 6패키지 통합 검증을 기준으로 한다. Starter → Town → War → Prototype → Sci-Fi City → Fantasy Kingdom 순서로 모든 import가 완료됐고, 5단계까지 output verify가 통과했다. 마지막 Fantasy Kingdom 단계에서는 `5,175/5,175` scene이 load·instantiate되고 선언 node path 누락은 `0`이었지만, `52`개 meshless node 때문에 최종 verify는 실패했다. 같은 `52`개 finding은 Fantasy Kingdom 단독 control에서도 재현됐다.

한편 최종 project에서 6개 package-scoped source-pose Gate는 모두 통과했고, source-missing·output-unexplained prefab과 pose mismatch는 `0`이었다. 따라서 현재 공개된 핵심 blocker는 package 충돌이나 skinning 회귀가 아니라 Fantasy Kingdom의 model sub-object/file-ID를 Godot extracted mesh에 연결하는 범용 변환 한계다. 수치와 검증 범위는 [`docs/packages/multi-package.md`](docs/packages/multi-package.md)의 measured six-package validation을 따른다.

`b145695` 이후 `eebd8c0`까지는 `.gitignore`와 검증 문서만 바뀌었으므로 converter 구현은 동일하다. downstream은 의미 있는 importer code 변경과 재검증이 생길 때만 submodule·source lock을 새 exact SHA로 함께 갱신한다.

## 저장소 소유 경계

이 fork가 소유한다.

- Godot 버전 호환성
- Unity YAML parser와 importer의 범용 동작
- 병렬 처리와 thread safety
- 공개·재배포 가능한 fixture와 회귀 테스트
- 권리가 확인된 공개 package report와 `tools/publishers/`의 package-specific Gate
- headless import API
- 결정적 실행 옵션
- 범용 material/script mapping hook
- 기계 판독 가능한 결과 보고
- 사용자 문서

downstream asset-pipeline workspace가 소유한다.

- 비공개 vendor 또는 asset pack 전용 profile
- 상용 asset의 원본과 변환 결과
- package provenance, 내부 manifest와 bundle 계약
- private 대규모 회귀 corpus와 검증 log
- 검증된 fork commit의 submodule·lock pin
- 실제 consumer materialization과 release 승인

범용 hook은 이 fork에 둘 수 있지만, 특정 vendor의 property mapping과 package 정책은 downstream에 둔다.

## 공개 저장소 안전 규칙

다음 항목은 commit, branch, issue, PR, fixture와 CI artifact에 포함하지 않는다.

- 상용·재배포 불가 asset 원본과 실질적 파생 bytes
- private package 경로·hash·manifest
- 사용자 로컬 절대경로
- 비공개 저장소 URL, credential과 token
- private corpus에서 추출한 model, texture, scene, material
- 공개 권한이 확인되지 않은 전체 log와 screenshot

`test/`에는 upstream에서 상속한 `.unitypackage` fixture가 이미 있지만, 새 fixture도 자동으로 공개 가능하다는 뜻은 아니다. 새 test data는 직접 제작했거나 재배포 권한이 명확한 경우만 추가한다.

`tools/validate_package.py`가 만드는 `validation_context.json`에는 source package의 절대경로가 들어가고 `import_report.py --json`은 그 context를 그대로 출력한다. 생성 report·log·throwaway project를 공개하기 전에는 경로와 package identity를 별도로 검사한다. add-on sync는 `.git`을 제외한 working tree를 복사하므로, 공개 artifact를 만들 때는 untracked 파일이 없는 clean checkout을 사용한다.

이미 추적 중인 screenshot·fixture·vendor report가 있다는 사실만으로 새 source 또는 파생 asset의 공개 권한이 생기지는 않는다. 새 binary나 screenshot은 출처와 재배포 권한을 확인한 뒤 추가한다.

`LICENSE.txt`의 MIT copyright·permission notice와 `humanoid/`, `deresuteme/`, `skeleton_merge_tool/`의 별도 license를 유지한다. 현재 `.gitignore`는 유료 asset과 변환 결과를 포괄적으로 차단하지 않으므로 commit 전에 `git status`와 staged file을 반드시 직접 검토한다.

## Git과 PR 운영

- `origin`은 이 fork, `upstream`은 원 저장소로 사용한다.
- `main`은 downstream이 pin할 수 있는 안정적인 fork branch로 유지한다.
- 한 branch와 PR에는 한 책임만 둔다.
- 서로 독립적인 importer defect와 검증 도구 변경은 별도 PR로 나눈다.
- commit 제목은 기존 history에 맞춰 짧은 영문 명령형 또는 설명형을 사용한다.
- 기존 license header를 제거하지 않는다.
- 강제 push와 unrelated formatting rewrite를 피한다.
- 변경 파일을 명시적으로 stage하고 commit 직전 diff를 다시 확인한다.

현재 후속 작업의 권장 branch 예시:

```text
fix/model-subobject-resolution
feat/headless-import-report
```

권장 변경 순서:

1. 공개 최소 reproducer 또는 regression test 추가
2. source fix 적용
3. Godot target version에서 headless test
4. issue를 연결한 fork PR
5. merge된 exact commit 확인
6. downstream submodule과 lock 갱신
7. downstream private corpus Gate

Unidot 변경과 downstream pin은 서로 다른 저장소의 별도 commit으로 남긴다.

## Downstream submodule 소비 계약

downstream workspace는 이 fork를 converter source dependency로 사용한다.

- submodule은 merge·검증된 exact commit에 고정한다.
- submodule working tree는 clean·detached 상태를 기본으로 하고 그 안에서 임의 개발하지 않는다.
- 별도 Unidot clone에서 개발하고 fork PR merge 후 submodule pointer를 갱신한다.
- submodule gitlink와 별도 source lock의 revision이 다르면 Gate를 실패시킨다.
- 실제 Godot project에는 submodule source를 `addons/unidot_importer`로 copy materialize하고 `.git` metadata는 제외한다.
- 변환된 scene이 참조하는 `runtime/anim_tree.gd`는 importer 제거 후에도 필요한 경우 보존한다.
- branch 이름이나 tag만 provenance로 사용하지 않고 항상 40자리 commit SHA를 기록한다.

논리적 변경 흐름:

```text
Unidot feature branch → PR → merged commit U
                                  ↓ exact SHA
downstream submodule + source lock → private Gate → downstream commit H
```

## 다음 작업

우선순위는 다음과 같다.

1. Fantasy Kingdom의 `52` meshless finding을 재현하는 공개·asset-independent model sub-object/file-ID fixture 설계
2. 범용 resolution fix와 최소 regression test 구현
3. 공개 synthetic suite, Fantasy 단독 control, deterministic 6패키지 order를 다시 검증
4. 실제 `10 workers + verbose=true` end-to-end logging stress Gate 추가
5. importer code가 바뀐 exact SHA에서만 downstream submodule·source lock과 distribution bundle을 함께 갱신
6. native `ufbx`를 포함한 modern Godot import 경로 정리
7. headless import entry point
8. 결정적 output과 기계 판독 report
9. 범용 material mapping hook
10. `upstream` remote 설정과 fork sync 정책 확정

Godot `4.7.1` 호환과 source-pose 검증은 구현·검증됐고 logging mutex에는 synthetic regression이 있다. 다음 importer 작업의 초점은 Fantasy model-reference 변환 한계와 production verbose Gate이며, 특정 상용 pack 이름이나 경로를 core에 hard-code하지 않고 공개 가능한 최소 fixture로 일반화해야 한다.

## 완료 기준

Godot `4.7.x` 호환 작업은 최소한 다음을 만족해야 완료로 본다.

- fresh project에서 addon parse·enable 오류 `0`
- asset-independent YAML regression 통과
- `_set()` bool contract regression 통과
- synthetic 및 실제 `10 workers + verbose=true` logging stress crash와 수집 누락 `0`
- 기존 공개 fixture 회귀 없음
- private asset이나 local path가 Git/issue/CI artifact에 포함되지 않음
- fork PR과 merge commit이 issue에 연결됨
- downstream submodule과 source lock이 같은 exact commit을 가리킴

## 작업 시작 체크리스트

```sh
git status --short --branch
git remote -v
git log -1 --oneline
```

그다음 이 문서와 [`HDNua/unidot_importer#1`](https://github.com/HDNua/unidot_importer/issues/1)을 읽고, 현재 code가 문서의 구현 기준 SHA와 어떤 차이가 있는지 확인한 뒤 작업한다. docs-only 후속 commit은 허용하되 importer code가 달라졌다면 검증 결과를 자동 상속하지 않는다. 문서와 실제 Git 상태가 충돌하면 실제 commit·diff·test 결과를 우선하고 이 문서를 함께 갱신한다.

## 관련 링크

- fork: <https://github.com/HDNua/unidot_importer>
- upstream: <https://github.com/V-Sekai/unidot_importer>
- Godot `4.7.1` compatibility issue: <https://github.com/HDNua/unidot_importer/issues/1>
- upstream website: <https://unidot.org/>
- upstream documentation: <https://unidot.org/docs/>
- license: [`LICENSE.txt`](LICENSE.txt)

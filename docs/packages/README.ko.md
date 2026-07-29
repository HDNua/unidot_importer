# 패키지 검증 보고서

*이 페이지를 [English](./README.md)로 읽기.*

이 fork에서 검증한 `.unitypackage`마다 보고서 하나를 둡니다. 기본
[README](../../README.ko.md)는 Unidot이 일반적으로 무엇을 변환하는지 설명하고,
이 보고서들은 특정 패키지에서 측정한 수치를 기록합니다.

- Synty POLYGON - Prototype Pack: [한국어](./polygon-prototype.ko.md) · [English](./polygon-prototype.md)
- Synty POLYGON - Starter Pack: [한국어](./polygon-starter.ko.md) · [English](./polygon-starter.md)

패키지 하나가 아니라 여러 패키지를 함께 사용할 때를 다루는 보고서도 있습니다.

- 한 프로젝트에서 여러 패키지 사용: [한국어](./multi-package.ko.md) · [English](./multi-package.md)

보고서는 영어와 한국어로 함께 관리합니다. 측정 revision, 수치, 코드 블록, 주의사항을
하나의 이중 언어 기록으로 취급하고, 검증 결과가 바뀌면 같은 변경에서 두 언어 파일을
모두 갱신합니다.

## 보고서 만들기

각 패키지는 일회용 Godot 프로젝트에서 따로 검증합니다. 측정 중인 패키지는 다른
패키지와 프로젝트를 공유하면 안 됩니다. asset database는 Unity GUID마다 활성 output
path 하나만 유지하고, Godot은 `.godot/` 아래에 import 결과를 cache하며, Synty 패키지는
서로 크게 겹칩니다. POLYGON Prototype pack의 경우 PolygonGeneric asset `1,247`개와
자체 asset `1,043`개가 있습니다. 공유 프로젝트에서 얻은 수치는 어느 패키지의 결과인지
귀속시킬 수 없습니다.

`tools/validate_package.py`는 격리 프로젝트를 만들고 import도 실행할 수 있습니다.

```bash
tools/validate_package.py "~/art/POLYGON - Prototype Pack.unitypackage" --run
```

이 도구는 패키지 옆에 `<package-name>_validate/`를 만들고, 현재 checkout을
`addons/unidot_importer`로 동기화하고, import dialog를 headless로 구동하는 bootstrap
plugin을 생성합니다. 또한 보고서가 수치의 생성 근거를 밝힐 수 있도록 Unidot revision을
`validation_context.json`에 기록합니다. 프로젝트 위치를 바꾸려면 `--root`, 디렉터리
이름을 바꾸려면 `--name`, 이전 import를 초기화하고 다시 실행하려면 `--clean`을 사용합니다.

`--clean`은 output tree와 asset database뿐 아니라 `.godot/`도 제거합니다. output tree만
지우면 Godot import cache의 오래된 artifact가 남아 다음 실행의 측정값을 왜곡합니다.

## 보고서에서 구분할 항목

Synty 패키지에는 공유 PolygonGeneric library가 들어 있습니다. 이 공유 콘텐츠에서 발생한
진단은 이를 포함한 모든 패키지에서 반복됩니다. POLYGON Prototype 보고서의 오류 `13`건은
모두 POLYGON Prototype 자체가 아니라 PolygonGeneric에서 발생합니다. 패키지 간 비교가
가능하도록 pack 고유 콘텐츠와 공유 콘텐츠를 나누고, 각 수치가 어느 쪽에 속하는지 밝힙니다.

여러 패키지를 한 프로젝트에 import하는 경우는 별도로 의도해서 검증할 가치가 있습니다.
실제 프로젝트가 사용하는 방식이고, 패키지 사이 Unity GUID 중복이 실제로 작동하는 유일한
경우이기 때문입니다. 이 결과를 패키지별 측정에 섞지 않습니다. 별도
[다중 패키지 보고서](./multi-package.ko.md)에서 다룹니다.

검증 전에 `tools/checks/package_overlap.py`를 실행하면 archive만으로 패키지들이 서로
다르게 담고 있는 asset을 확인할 수 있습니다.

```bash
tools/checks/package_overlap.py "~/art/A.unitypackage" "~/art/B.unitypackage"
```

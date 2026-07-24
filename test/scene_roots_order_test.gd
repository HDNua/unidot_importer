extends SceneTree

const CONVERT_SCENE := preload("res://addons/unidot_importer/convert_scene.gd")
const OBJECT_ADAPTER := preload("res://addons/unidot_importer/object_adapter.gd")


class FakeMeta:
	extends Resource
	var guid := "scene-roots-test"
	var main_object_id := 0
	var objects: Dictionary = {}
	var warnings: Array[String] = []
	var failures: Array[String] = []

	func lookup(unidot_ref: Array, _silent: bool = false) -> RefCounted:
		if unidot_ref.size() < 2:
			return null
		return objects.get(int(unidot_ref[1]))

	func log_debug(_file_id: int, _message: String) -> void:
		pass

	func log_warn(
		_file_id: int,
		message: String,
		_field: String = "",
		_remote_ref: Variant = null
	) -> void:
		warnings.append(message)

	func log_fail(
		_file_id: int,
		message: String,
		_field: String = "",
		_remote_ref: Variant = null
	) -> void:
		failures.append(message)


class FakeParsedAsset:
	extends RefCounted
	var assets: Dictionary = {}


class FakePackageAsset:
	extends RefCounted
	var parsed_asset := FakeParsedAsset.new()


func _initialize() -> void:
	var adapter := OBJECT_ADAPTER.new()
	var meta := FakeMeta.new()

	var root_a = _make_game_object(adapter, meta, 100, 101, "RootA")
	var root_b = _make_game_object(adapter, meta, 200, 201, "RootB")
	var transform_b = meta.objects[201]
	var root_extra_a = _make_game_object(adapter, meta, 300, 301, "FallbackExtraA")
	var root_extra_b = _make_game_object(adapter, meta, 500, 501, "FallbackExtraB")

	var prefab = adapter.instantiate_unidot_object(
		meta,
		400,
		1001,
		"PrefabInstance"
	)
	prefab.keys = {
		"m_Modification": {"m_TransformParent": _ref(0)},
		"m_SourcePrefab": [null, 100100000, "prefab-source", 3],
	}
	meta.objects[prefab.fileID] = prefab

	var stripped_prefab_transform = adapter.instantiate_unidot_object(
		meta,
		401,
		4,
		"Transform"
	)
	stripped_prefab_transform.is_stripped = true
	stripped_prefab_transform.keys = {
		"m_CorrespondingSourceObject": [null, 4, "prefab-source", 3],
		"m_PrefabInstance": _ref(prefab.fileID),
	}
	meta.objects[stripped_prefab_transform.fileID] = stripped_prefab_transform

	var scene_roots = adapter.instantiate_unidot_object(
		meta,
		9223372036854775807,
		1660057539,
		"SceneRoots"
	)
	scene_roots.keys = {
		"m_Roots": [
			_ref(transform_b.fileID),
			_ref(root_a.fileID),
			_ref(stripped_prefab_transform.fileID),
			_ref(transform_b.fileID),
			_ref(999999),
		],
	}
	meta.objects[scene_roots.fileID] = scene_roots

	if scene_roots.type != "SceneRoots" or not meta.failures.is_empty():
		_fail("SceneRoots class ID was not registered without a failure.")
		return

	var pkgasset := FakePackageAsset.new()
	pkgasset.parsed_asset.assets = meta.objects
	var converter := CONVERT_SCENE.new()
	var ordered: Array = converter.apply_scene_roots_order(
		pkgasset,
		[root_extra_a, root_b, root_extra_b, root_a, prefab]
	)
	var expected: Array = [root_b, root_a, prefab, root_extra_a, root_extra_b]
	if ordered != expected:
		_fail("SceneRoots order was not authoritative. Got " + str(_ids(ordered)))
		return
	if not _warning_contains(meta.warnings, "duplicate root"):
		_fail("A duplicate SceneRoots entry did not emit a warning.")
		return
	if not _warning_contains(meta.warnings, "missing object"):
		_fail("A missing SceneRoots reference did not emit a warning.")
		return
	if not _warning_contains(meta.warnings, "missing from SceneRoots"):
		_fail("A fallback extra root did not emit a warning.")
		return

	print("UNIDOT_SCENE_ROOTS_ORDER_TEST_PASS")
	quit(0)


func _make_game_object(
	adapter: RefCounted,
	meta: FakeMeta,
	game_object_id: int,
	transform_id: int,
	object_name: String
) -> RefCounted:
	var game_object = adapter.instantiate_unidot_object(
		meta,
		game_object_id,
		1,
		"GameObject"
	)
	var transform = adapter.instantiate_unidot_object(
		meta,
		transform_id,
		4,
		"Transform"
	)
	game_object.keys = {
		"m_Name": object_name,
		"m_Component": [{"component": _ref(transform_id)}],
	}
	transform.keys = {
		"m_GameObject": _ref(game_object_id),
		"m_Father": _ref(0),
		"m_Children": [],
	}
	meta.objects[game_object_id] = game_object
	meta.objects[transform_id] = transform
	return game_object


func _ref(file_id: int) -> Array:
	return [null, file_id, null, 0]


func _ids(assets: Array) -> Array:
	var ids: Array = []
	for asset in assets:
		ids.append(asset.fileID)
	return ids


func _warning_contains(warnings: Array[String], needle: String) -> bool:
	for warning in warnings:
		if warning.contains(needle):
			return true
	return false


func _fail(message: String) -> void:
	push_error("UNIDOT_SCENE_ROOTS_ORDER_TEST_FAIL: " + message)
	quit(1)

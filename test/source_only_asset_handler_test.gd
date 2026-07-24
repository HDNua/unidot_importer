extends SceneTree

const ASSET_ADAPTER := preload("res://addons/unidot_importer/asset_adapter.gd")
const OBJECT_ADAPTER := preload("res://addons/unidot_importer/object_adapter.gd")


class FakeHeader:
	extends RefCounted
	var data: PackedByteArray

	func _init(source_data: PackedByteArray) -> void:
		data = source_data

	func get_data() -> PackedByteArray:
		return data


class FakeMeta:
	extends Resource
	var guid := "source-only-handler-test"
	var fail_messages: Array[String] = []
	var warning_messages: Array[String] = []

	func log_debug(_file_id: int, _message: String) -> void:
		pass

	func log_warn(
		_file_id: int,
		message: String,
		_field: String = "",
		_remote_ref: Array = [null, 0, "", null]
	) -> void:
		warning_messages.append(message)

	func log_fail(
		_file_id: int,
		message: String,
		_field: String = "",
		_remote_ref: Array = [null, 0, "", null]
	) -> void:
		fail_messages.append(message)


class FakePkgAsset:
	extends RefCounted
	var asset_tar_header: RefCounted
	var metadata_tar_header: RefCounted = null
	var data_md5 := PackedByteArray()
	var existing_data_md5 := PackedByteArray()
	var pathname: String
	var orig_pathname: String
	var guid := "source-only-handler-test"
	var parsed_meta: Resource

	func log_debug(message: String) -> void:
		parsed_meta.log_debug(0, message)

	func log_warn(
		message: String,
		field: String = "",
		remote_ref: Array = [null, 0, "", null]
	) -> void:
		parsed_meta.log_warn(0, message, field, remote_ref)

	func log_fail(
		message: String,
		field: String = "",
		remote_ref: Array = [null, 0, "", null]
	) -> void:
		parsed_meta.log_fail(0, message, field, remote_ref)


func _initialize() -> void:
	var adapter := ASSET_ADAPTER.new()
	var shader_handler = adapter.file_handlers.get("shadergraph")
	var subgraph_handler = adapter.file_handlers.get("shadersubgraph")
	var lighting_handler = adapter.file_handlers.get("lighting")
	if not shader_handler is ASSET_ADAPTER.UnsupportedSourceHandler:
		_fail(".shadergraph is not dispatched to the source-only handler.")
		return
	if not subgraph_handler is ASSET_ADAPTER.UnsupportedSourceHandler:
		_fail(".shadersubgraph is not dispatched to the source-only handler.")
		return
	if not lighting_handler is ASSET_ADAPTER.YamlHandler:
		_fail(".lighting is not dispatched to the Unity YAML handler.")
		return

	var meta := FakeMeta.new()
	var scripted_importer = OBJECT_ADAPTER.new().instantiate_unidot_object(
		meta,
		0,
		0,
		"ScriptedImporter"
	)
	if not meta.fail_messages.is_empty():
		_fail("Known ScriptedImporter metadata produced a red fallback failure.")
		return
	if scripted_importer.get_main_object_id() != 0:
		_fail("ScriptedImporter claimed a universal main object fileID.")
		return

	var source_bytes := (
		"{\"m_SGVersion\":3,\"note\":\"synthetic public test\"}\n"
	).to_utf8_buffer()
	var pkgasset := FakePkgAsset.new()
	pkgasset.orig_pathname = "Synthetic/Example.shadergraph"
	pkgasset.pathname = pkgasset.orig_pathname
	pkgasset.asset_tar_header = FakeHeader.new(source_bytes)
	pkgasset.parsed_meta = meta

	if adapter.uses_godot_importer(pkgasset):
		_fail("Source-only Shader Graph was sent to the Godot importer.")
		return
	var temp_root := ".godot/unidot_source_only_handler_test"
	var output_path := adapter.preprocess_asset(null, pkgasset, temp_root, "worker")
	if output_path != pkgasset.orig_pathname:
		_fail("Source-only handler changed the asset path: " + output_path)
		return
	if meta.warning_messages.size() != 1:
		_fail("Source-only preservation did not emit exactly one warning.")
		return
	var warning := meta.warning_messages[0]
	if not warning.contains("source-only") or not warning.contains(
		pkgasset.orig_pathname
	):
		_fail("Source-only warning did not explain the preserved asset.")
		return

	var temp_path := temp_root.path_join(pkgasset.pathname)
	adapter.write_godot_asset(pkgasset, temp_path)
	if not FileAccess.file_exists("res://" + pkgasset.pathname):
		_fail("Source-only asset was not written.")
		return
	if FileAccess.get_file_as_bytes("res://" + pkgasset.pathname) != source_bytes:
		_fail("Source-only asset bytes were not preserved.")
		return
	if FileAccess.file_exists("res://" + pkgasset.pathname + ".failed_import"):
		_fail("Source-only asset was renamed to .failed_import.")
		return

	var cleanup := DirAccess.open("res://")
	cleanup.remove(pkgasset.pathname)
	cleanup.remove(temp_root.path_join(".gdignore"))
	cleanup.remove(temp_root.path_join("worker"))
	print("UNIDOT_SOURCE_ONLY_ASSET_HANDLER_TEST_PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error("UNIDOT_SOURCE_ONLY_ASSET_HANDLER_TEST_FAIL: " + message)
	quit(1)

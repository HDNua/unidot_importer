extends SceneTree

const ASSET_ADAPTER := preload("res://addons/unidot_importer/asset_adapter.gd")


class FakeImporter:
	extends RefCounted
	var animation_import := false
	var keys := {"animationType": 2}
	var meshes_light_baking := 1

	func get_animation_clips() -> Array[Dictionary]:
		return []

	func animation_optimizer_settings() -> Dictionary:
		return {
			"enabled": false,
			"max_linear_error": 0.0,
			"max_angular_error": 0.0,
		}


class FakeMeta:
	extends Resource
	var importer := FakeImporter.new()
	var internal_data: Dictionary = {}

	func is_force_humanoid() -> bool:
		return false

	func is_using_builtin_ufbx() -> bool:
		return false


class FakePkgAsset:
	extends RefCounted
	var pathname: String
	var parsed_meta := FakeMeta.new()
	var fail_messages: Array[String] = []

	func log_debug(_message: String) -> void:
		pass

	func log_warn(
		_message: String,
		_field: String = "",
		_remote_ref: Array = [null, 0, "", null]
	) -> void:
		pass

	func log_fail(
		message: String,
		_field: String = "",
		_remote_ref: Array = [null, 0, "", null]
	) -> void:
		fail_messages.append(message)


func _initialize() -> void:
	var adapter := ASSET_ADAPTER.new()
	if not _assert_animation_settings(
		adapter,
		"unidot_static_model_config_test.fbx",
		false
	):
		return
	if not _assert_animation_settings(
		adapter,
		"unidot_animated_model_config_test.fbx",
		true
	):
		return
	print("UNIDOT_MODEL_IMPORT_CONFIG_TEST_PASS")
	quit(0)


func _assert_animation_settings(
	adapter: Resource,
	model_path: String,
	animation_import: bool
) -> bool:
	var pkgasset := FakePkgAsset.new()
	pkgasset.pathname = model_path
	pkgasset.parsed_meta.importer.animation_import = animation_import
	var handler = adapter.file_handlers["fbx"]
	handler.write_godot_import(pkgasset, false)
	if not pkgasset.fail_messages.is_empty():
		_fail("Writing model import config logged a failure: " + str(
			pkgasset.fail_messages
		))
		return false

	var import_path := "res://" + model_path + ".import"
	var config := ConfigFile.new()
	if config.load(import_path) != OK:
		_fail("Unable to load generated model import config: " + import_path)
		return false
	var actual_import = config.get_value("params", "animation/import", null)
	var actual_reset = config.get_value(
		"params",
		"animation/import_rest_as_RESET",
		null
	)
	if actual_import != animation_import:
		_fail("animation/import did not match the Unity importer setting.")
		return false
	if actual_reset != animation_import:
		_fail(
			"animation/import_rest_as_RESET was enabled independently of "
			+ "animation/import."
		)
		return false
	DirAccess.open("res://").remove(model_path + ".import")
	return true


func _fail(message: String) -> void:
	push_error("UNIDOT_MODEL_IMPORT_CONFIG_TEST_FAIL: " + message)
	quit(1)

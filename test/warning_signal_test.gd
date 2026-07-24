extends SceneTree

const OBJECT_ADAPTER := preload("res://addons/unidot_importer/object_adapter.gd")
const POST_IMPORT_MODEL := preload("res://addons/unidot_importer/post_import_model.gd")


class FakeImporter:
	extends RefCounted
	var animation_import := false


class FakeMeta:
	extends Resource
	var importer := FakeImporter.new()
	var warnings: Array[String] = []
	var debug_messages: Array[String] = []

	func log_debug(_file_id: int, message: String) -> void:
		debug_messages.append(message)

	func log_warn(
		_file_id: int,
		message: String,
		_field: String = "",
		_remote_ref: Array = [null, 0, "", null]
	) -> void:
		warnings.append(message)


func _initialize() -> void:
	var meta := FakeMeta.new()
	var state = POST_IMPORT_MODEL.ParseState.new()
	state.object_adapter = OBJECT_ADAPTER.new()
	state.metaobj = meta

	var animation_id: int = state.get_obj_id(
		"AnimationClip",
		PackedStringArray(),
		"Take 001"
	)
	if animation_id != 7400000:
		_fail("Unexpected AnimationClip fallback ID: " + str(animation_id))
		return
	if not meta.warnings.is_empty():
		_fail("Disabled AnimationClip fallback emitted a warning.")
		return
	if meta.debug_messages.size() != 1:
		_fail("Disabled AnimationClip fallback was not retained as debug.")
		return

	meta.importer.animation_import = true
	state.get_obj_id("AnimationClip", PackedStringArray(), "Take 002")
	if meta.warnings.size() != 1:
		_fail("Enabled AnimationClip fallback warning was suppressed.")
		return

	var warning_count := meta.warnings.size()
	var debug_count := meta.debug_messages.size()
	state.log_humanoid_rotation("Hips", Quaternion.IDENTITY)
	if meta.warnings.size() != warning_count:
		_fail("Identity humanoid rotation emitted a warning.")
		return
	if meta.debug_messages.size() != debug_count + 1:
		_fail("Identity humanoid rotation was not retained as debug.")
		return

	state.log_humanoid_rotation(
		"Hips",
		Quaternion(Vector3.UP, deg_to_rad(15.0))
	)
	if meta.warnings.size() != warning_count + 1:
		_fail("Non-identity humanoid rotation warning was suppressed.")
		return

	print("UNIDOT_WARNING_SIGNAL_TEST_PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error("UNIDOT_WARNING_SIGNAL_TEST_FAIL: " + message)
	quit(1)

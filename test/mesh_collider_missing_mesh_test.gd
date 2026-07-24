extends SceneTree

const OBJECT_ADAPTER := preload("res://addons/unidot_importer/object_adapter.gd")


class FakeMeta:
	extends Resource
	var guid := "mesh-collider-test"
	var failures: Array[String] = []

	func get_godot_resource(
		_unidot_ref: Array,
		_silent: bool = false
	) -> Resource:
		return null

	func log_debug(_file_id: int, _message: String) -> void:
		pass

	func log_warn(
		_file_id: int,
		_message: String,
		_field: String = "",
		_remote_ref: Variant = null
	) -> void:
		pass

	func log_fail(
		_file_id: int,
		message: String,
		_field: String = "",
		_remote_ref: Variant = null
	) -> void:
		failures.append(message)


func _initialize() -> void:
	var meta := FakeMeta.new()
	var collider = OBJECT_ADAPTER.new().instantiate_unidot_object(
		meta,
		640001,
		64,
		"MeshCollider"
	)
	collider.keys = {
		"m_Mesh": [null, 4300000, "missing-mesh-guid", 3],
		"m_Convex": 1,
	}
	if collider.get_shape() != null:
		_fail("A missing source mesh produced a collision shape.")
		return
	if meta.failures.size() != 1:
		_fail("A missing source mesh did not produce one structured failure.")
		return
	if not meta.failures[0].contains("source mesh could not be resolved"):
		_fail("The missing-mesh failure did not explain the cause.")
		return
	print("UNIDOT_MESH_COLLIDER_MISSING_MESH_TEST_PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error("UNIDOT_MESH_COLLIDER_MISSING_MESH_TEST_FAIL: " + message)
	quit(1)

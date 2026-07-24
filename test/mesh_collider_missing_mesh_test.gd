extends SceneTree

const OBJECT_ADAPTER := preload("res://addons/unidot_importer/object_adapter.gd")


class FakeMeta:
	extends Resource
	var guid := "mesh-collider-test"
	var failures: Array[String] = []
	var silent_lookups: Array[bool] = []

	func get_godot_resource(
		_unidot_ref: Array,
		silent: bool = false
	) -> Resource:
		silent_lookups.append(silent)
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
	collider.convert_properties(
		CollisionShape3D.new(),
		{
			"m_Mesh": [null, 4300000, "missing-mesh-guid", 3],
			"m_Convex": 1,
		}
	)
	if meta.failures.size() != 1:
		_fail("Repeated lookup duplicated the structured failure.")
		return
	if meta.silent_lookups != [true, true]:
		_fail(
			"MeshCollider did not suppress duplicate generic lookup warnings: "
			+ str(meta.silent_lookups)
		)
		return

	var override_first_meta := FakeMeta.new()
	var override_first = OBJECT_ADAPTER.new().instantiate_unidot_object(
		override_first_meta,
		640002,
		64,
		"MeshCollider"
	)
	override_first.keys = collider.keys.duplicate(true)
	override_first.convert_properties(
		CollisionShape3D.new(),
		override_first.keys
	)
	override_first.get_shape()
	if override_first_meta.failures.size() != 1:
		_fail("Override-first lookup did not retain exactly one failure.")
		return
	if override_first_meta.silent_lookups != [true, true]:
		_fail(
			"Override-first lookup emitted generic warning lookups: "
			+ str(override_first_meta.silent_lookups)
		)
		return

	var instance_meta := FakeMeta.new()
	var instance_collider = OBJECT_ADAPTER.new().instantiate_unidot_object(
		instance_meta,
		640003,
		64,
		"MeshCollider"
	)
	instance_collider.source_mesh_instance = MeshInstance3D.new()
	if instance_collider.get_shape() != null:
		_fail("A null instanced-prefab mesh unexpectedly created a shape.")
		return
	if instance_meta.failures.size() != 1:
		_fail("A null instanced-prefab mesh did not retain one failure.")
		return
	if not instance_meta.silent_lookups.is_empty():
		_fail("A null instanced-prefab mesh performed a metadata lookup.")
		return
	print("UNIDOT_MESH_COLLIDER_MISSING_MESH_TEST_PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error("UNIDOT_MESH_COLLIDER_MISSING_MESH_TEST_FAIL: " + message)
	quit(1)

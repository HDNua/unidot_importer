extends SceneTree

const OBJECT_ADAPTER := preload("res://addons/unidot_importer/object_adapter.gd")


class FakeDatabase:
	extends Resource
	var enable_unidot_keys := false
	var truncated_material_reference := StandardMaterial3D.new()
	var null_material_reference := StandardMaterial3D.new()

	func _init() -> void:
		truncated_material_reference.resource_name = "SyntheticTruncatedMaterial"
		null_material_reference.resource_name = "SyntheticNullMaterial"


class FakeMeta:
	extends Resource
	var guid := "skinned-mesh-visibility-test"
	var main_object_id := 0
	var objects: Dictionary = {}
	var resources: Dictionary = {}
	var failures: Array[String] = []
	var warnings: Array[String] = []
	var database := FakeDatabase.new()
	var fileid_to_nodepath: Dictionary = {}
	var prefab_fileid_to_nodepath: Dictionary = {}
	var fileid_to_skeleton_bone: Dictionary = {}
	var prefab_fileid_to_skeleton_bone: Dictionary = {}
	var fileid_to_material_order_rev: Dictionary = {}
	var prefab_fileid_to_material_order_rev: Dictionary = {}
	var transform_fileid_to_rotation_delta: Dictionary = {}
	var prefab_transform_fileid_to_rotation_delta: Dictionary = {}
	var transform_fileid_to_scale_signs: Dictionary = {}
	var prefab_transform_fileid_to_scale_signs: Dictionary = {}
	var transform_fileid_to_parent_fileid: Dictionary = {}
	var prefab_transform_fileid_to_parent_fileid: Dictionary = {}

	func lookup(reference: Variant, _silent: bool = false) -> RefCounted:
		if not (reference is Array) or reference.size() < 2:
			return null
		return objects.get(int(reference[1]))

	func lookup_meta(_reference: Variant) -> Resource:
		return null

	func get_godot_resource(
		reference: Variant,
		_silent: bool = false
	) -> Resource:
		if not (reference is Array) or reference.size() < 2:
			return null
		return resources.get(int(reference[1]))

	func get_database() -> Resource:
		return database

	func get_enabled_plugins() -> Array:
		return []

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


class FakeSkelley:
	extends RefCounted
	var godot_skeleton: Skeleton3D

	func _init(skeleton: Skeleton3D) -> void:
		godot_skeleton = skeleton


class FakePrefabState:
	extends RefCounted
	var gameobject_name_map: Dictionary = {}
	var prefab_gameobject_name_map: Dictionary = {}


class FakeState:
	extends RefCounted
	var meta: Resource
	var owner: Node
	var scene_contents: Node
	var fileID_to_skelley: Dictionary = {}
	var skelley_parents: Dictionary = {}
	var active_avatars: Array = []
	var prefab_state := FakePrefabState.new()

	func _init(test_meta: Resource, root: Node3D) -> void:
		meta = test_meta
		owner = root
		scene_contents = root

	func add_child(child: Node, parent: Node3D, object: RefCounted) -> void:
		parent.add_child(child, true)
		child.owner = owner
		add_fileID(child, object)

	func add_fileID(child: Node, object: RefCounted) -> void:
		meta.fileid_to_nodepath[object.fileID] = scene_contents.get_path_to(child)


func _initialize() -> void:
	if not _assert_game_object_visibility(
		"active ordinary game object",
		1,
		true
	):
		return
	if not _assert_game_object_visibility(
		"inactive ordinary game object",
		0,
		false
	):
		return

	var cases := [
		{
			"name": "active game object and enabled renderer",
			"game_object_active": 1,
			"renderer_enabled": 1,
			"ancestor_active": 1,
			"expected_visible": true,
		},
		{
			"name": "inactive game object",
			"game_object_active": 0,
			"renderer_enabled": 1,
			"ancestor_active": 1,
			"expected_visible": false,
		},
		{
			"name": "disabled renderer",
			"game_object_active": 1,
			"renderer_enabled": 0,
			"ancestor_active": 1,
			"expected_visible": false,
		},
		{
			"name": "inactive game object and disabled renderer",
			"game_object_active": 0,
			"renderer_enabled": 0,
			"ancestor_active": 1,
			"expected_visible": false,
		},
		{
			"name": "inactive ancestor",
			"game_object_active": 1,
			"renderer_enabled": 1,
			"ancestor_active": 0,
			"expected_visible": false,
		},
	]

	for test_case: Dictionary in cases:
		if not _assert_visibility_case(test_case):
			return

	print("UNIDOT_SKINNED_MESH_VISIBILITY_TEST_PASS")
	quit(0)


func _assert_game_object_visibility(
	case_name: String,
	game_object_active: int,
	expected_visible: bool
) -> bool:
	var adapter := OBJECT_ADAPTER.new()
	var meta := FakeMeta.new()
	var root := Node3D.new()
	root.name = "Root"
	var state := FakeState.new(meta, root)
	var game_object = adapter.instantiate_unidot_object(
		meta,
		1000,
		1,
		"GameObject"
	)
	var transform = adapter.instantiate_unidot_object(
		meta,
		1004,
		4,
		"Transform"
	)
	game_object.keys = {
		"m_Name": "OrdinaryGameObject",
		"m_Component": [{"component": _ref(transform.fileID)}],
		"m_IsActive": game_object_active,
	}
	transform.keys = {
		"m_GameObject": _ref(game_object.fileID),
		"m_Father": _ref(0),
		"m_Children": [],
	}
	meta.objects = {
		game_object.fileID: game_object,
		transform.fileID: transform,
	}

	var node := game_object.create_godot_node(state, root) as Node3D
	if node == null:
		root.free()
		_fail(case_name + ": conversion did not create a Node3D.")
		return false
	if node.get_parent() != root:
		root.free()
		_fail(case_name + ": converted node was not parented to the root.")
		return false
	if not meta.failures.is_empty():
		var failures := meta.failures.duplicate()
		root.free()
		_fail(case_name + ": conversion logged failures: " + str(failures))
		return false
	if node.visible != expected_visible:
		var actual_visible := node.visible
		root.free()
		_fail(
			case_name
			+ ": expected visible="
			+ str(expected_visible)
			+ " but got "
			+ str(actual_visible)
		)
		return false

	root.free()
	return true


func _assert_visibility_case(test_case: Dictionary) -> bool:
	var adapter := OBJECT_ADAPTER.new()
	var meta := FakeMeta.new()
	var root := Node3D.new()
	root.name = "Root"
	var skeleton := Skeleton3D.new()
	skeleton.name = "GeneralSkeleton"
	skeleton.add_bone("SyntheticBone")
	root.add_child(skeleton)
	skeleton.owner = root
	var state := FakeState.new(meta, root)

	var ancestor_game_object = adapter.instantiate_unidot_object(
		meta,
		100,
		1,
		"GameObject"
	)
	var ancestor_transform = adapter.instantiate_unidot_object(
		meta,
		104,
		4,
		"Transform"
	)
	var mesh_game_object = adapter.instantiate_unidot_object(
		meta,
		200,
		1,
		"GameObject"
	)
	var mesh_transform = adapter.instantiate_unidot_object(
		meta,
		204,
		4,
		"Transform"
	)
	var renderer = adapter.instantiate_unidot_object(
		meta,
		237,
		137,
		"SkinnedMeshRenderer"
	)
	var bone_transform = adapter.instantiate_unidot_object(
		meta,
		304,
		4,
		"Transform"
	)

	ancestor_game_object.keys = {
		"m_Name": "Ancestor",
		"m_Component": [{"component": _ref(ancestor_transform.fileID)}],
		"m_IsActive": test_case["ancestor_active"],
	}
	ancestor_transform.keys = {
		"m_GameObject": _ref(ancestor_game_object.fileID),
		"m_Father": _ref(0),
		"m_Children": [_ref(mesh_transform.fileID)],
	}
	mesh_game_object.keys = {
		"m_Name": "SyntheticSkinnedMesh",
		"m_Component": [
			{"component": _ref(mesh_transform.fileID)},
			{"component": _ref(renderer.fileID)},
		],
		"m_IsActive": test_case["game_object_active"],
	}
	mesh_transform.keys = {
		"m_GameObject": _ref(mesh_game_object.fileID),
		"m_Father": _ref(ancestor_transform.fileID),
		"m_Children": [],
	}
	bone_transform.keys = {
		"m_GameObject": _ref(0),
		"m_Father": _ref(0),
		"m_Children": [],
	}
	bone_transform.skeleton_bone_index = 0

	const MESH_FILE_ID := 4300000
	renderer.keys = {
		"m_GameObject": _ref(mesh_game_object.fileID),
		"m_Enabled": test_case["renderer_enabled"],
		"m_Mesh": [null, MESH_FILE_ID, "synthetic-mesh-guid", 3],
		"m_Bones": [_ref(bone_transform.fileID)],
		"m_Materials": [],
	}
	meta.objects = {
		ancestor_game_object.fileID: ancestor_game_object,
		ancestor_transform.fileID: ancestor_transform,
		mesh_game_object.fileID: mesh_game_object,
		mesh_transform.fileID: mesh_transform,
		renderer.fileID: renderer,
		bone_transform.fileID: bone_transform,
	}
	meta.resources[MESH_FILE_ID] = BoxMesh.new()
	var skin := Skin.new()
	skin.add_bind(0, Transform3D.IDENTITY)
	meta.resources[-MESH_FILE_ID] = skin
	state.fileID_to_skelley[bone_transform.fileID] = FakeSkelley.new(skeleton)

	var mesh := renderer.create_skinned_mesh(state) as MeshInstance3D
	if mesh == null:
		root.free()
		_fail(test_case["name"] + ": deferred renderer did not create a mesh.")
		return false
	if mesh.get_parent() != skeleton:
		root.free()
		_fail(test_case["name"] + ": deferred mesh was not parented to Skeleton3D.")
		return false
	if not meta.failures.is_empty():
		var failures := meta.failures.duplicate()
		root.free()
		_fail(test_case["name"] + ": conversion logged failures: " + str(failures))
		return false
	var expected_visible: bool = test_case["expected_visible"]
	if mesh.visible != expected_visible:
		var actual_visible := mesh.visible
		root.free()
		_fail(
			test_case["name"]
			+ ": expected visible="
			+ str(expected_visible)
			+ " but got "
			+ str(actual_visible)
		)
		return false

	root.free()
	return true


func _ref(file_id: int) -> Array:
	return [null, file_id, "", 0]


func _fail(message: String) -> void:
	push_error("UNIDOT_SKINNED_MESH_VISIBILITY_TEST_FAIL: " + message)
	quit(1)

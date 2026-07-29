extends SceneTree

const OBJECT_ADAPTER := preload("res://addons/unidot_importer/object_adapter.gd")
const ASSET_DATABASE := preload("res://addons/unidot_importer/asset_database.gd")


class FakeMeta:
	extends Resource
	var guid := "fixture-scene-guid"
	var prefab_fileid_to_skeleton_bone := {}
	var fileid_to_skeleton_bone := {}
	var prefab_fileid_to_nodepath := {}
	var fileid_to_nodepath := {}
	var database := ASSET_DATABASE.new()
	var script_meta: Resource = null

	func get_database() -> Resource:
		return database

	func get_enabled_plugins() -> Array[RefCounted]:
		return []

	func lookup_meta(_unidot_ref: Array) -> Resource:
		return script_meta

	func lookup(_unidot_ref: Array, _silent: bool = false) -> RefCounted:
		return null


class FakeState:
	extends RefCounted

	func add_child(child: Node, new_parent: Node3D, _object: RefCounted) -> void:
		new_parent.add_child(child, true)


func _initialize() -> void:
	var component = OBJECT_ADAPTER.UnidotMonoBehaviour.new()
	var fake_meta := FakeMeta.new()
	fake_meta.database.add_unsupported_components = true
	fake_meta.database.enable_unidot_keys = true
	# Reproduce a normal import: .cs files are not converted to Godot resources,
	# so lookup_meta() returns null, while source identity still must survive.
	fake_meta.database.register_source_asset_path(
		"1234567890abcdef1234567890abcdef",
		"./Assets\\sh\\Scripts\\SH0_CombatUnit.cs"
	)
	component.meta = fake_meta
	component.type = "MonoBehaviour"
	component.fileID = 4242
	component.keys = {
		"m_GameObject": [null, 1, null, null],
		"m_Script": [null, 11500000, "1234567890abcdef1234567890abcdef", 3],
		"m_Name": "",
	}
	var parent := Node3D.new()
	var converted: Node = component.create_godot_node(FakeState.new(), parent)
	if converted == null:
		_fail("MonoBehaviour placeholder was not created.")
		return
	if converted.name != "SH0_CombatUnit":
		_fail("MonoScript class prefix was not preserved: " + str(converted.name))
		return
	if converted.get_meta("unity_monoscript_class_hint", "") != "SH0_CombatUnit":
		_fail("MonoScript class metadata was not preserved.")
		return
	if converted.get_meta("unity_monoscript_path", "") != "Assets/sh/Scripts/SH0_CombatUnit.cs":
		_fail("MonoScript source path metadata was not preserved.")
		return
	if converted.get_meta("unity_monoscript_guid", "") != "1234567890abcdef1234567890abcdef":
		_fail("MonoScript GUID metadata was not preserved.")
		return
	if not converted.has_meta("unidot_keys"):
		_fail("Requested Unity YAML metadata was not preserved.")
		return
	parent.free()
	print("UNIDOT_MONOBEHAVIOUR_IDENTITY_TEST_PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error("UNIDOT_MONOBEHAVIOUR_IDENTITY_TEST_FAIL: " + message)
	quit(1)

extends SceneTree

# Vendor-neutral correctness pass over a converted package. Run from a project
# produced by tools/validate_package.py:
#
#   Godot --headless -s addons/unidot_importer/tools/checks/verify_output.gd
#
# Answers three questions that do not depend on who made the package:
#   1. Does every generated scene load and instantiate?
#   2. Does every node a scene declares still exist after instantiation?
#   3. Does every MeshInstance3D actually have a mesh?
#
# Plus one figure reported without a verdict: how many converted materials bind
# a texture. Whether a given material should have one depends on the source.
#
# (2) exists because a scene can load perfectly while missing a piece. A
# converted prefab is usually an inherited scene storing only overrides against
# a base scene generated from a model; if a later import replaces that model
# with a build that no longer has a node, Godot drops the override, warns, and
# hands back a scene that instantiates cleanly with the node gone. Nothing that
# enumerates what is present can see that, so this compares each scene against
# its own SceneState instead.
#
# There is deliberately no skinning check here. The rigidity identity
# D = global_bone_pose * bind_pose = I only holds when the skeleton sits at the
# pose its meshes were bound in, and there is no way to test that precondition
# independently — the identity *is* the test. Prefabs authored in some other
# pose fail it while rendering perfectly, so asserting it needs outside
# knowledge of how a particular publisher authors prefabs. That belongs in
# tools/publishers/, and lives there for Synty POLYGON Prototype.

const ROOT := "res://Unidot"

var scenes_ok := 0
var scenes_failed: Array[String] = []
var materials_total := 0
var materials_textured := 0
var materials_untextured: Array[String] = []
var extracted_total := 0
var extracted_textured := 0
var mesh_nodes_checked := 0
var meshless_nodes: Array[String] = []
var declared_nodes_checked := 0
var vanished_nodes: Array[String] = []


func _init() -> void:
	var scene_paths: Array[String] = []
	var material_paths: Array[String] = []
	_collect(ROOT, scene_paths, material_paths)

	for p in scene_paths:
		_check_scene(p)
	for p in material_paths:
		_check_material(p)

	print("=== scenes")
	print("  loaded and instantiated  %d/%d" % [scenes_ok, len(scene_paths)])
	for f in scenes_failed.slice(0, 10):
		print("    FAIL ", f)
	print("=== nodes each scene declares")
	print("  declared node paths      %d" % declared_nodes_checked)
	print("  missing after instancing %d" % len(vanished_nodes))
	for v in vanished_nodes.slice(0, 20):
		print("    ", v)
	print("=== mesh nodes")
	print("  MeshInstance3D nodes     %d" % mesh_nodes_checked)
	print("  with no mesh             %d" % len(meshless_nodes))
	for m in meshless_nodes.slice(0, 20):
		print("    ", m)
	print("=== materials converted from Unity .mat assets")
	print("  with a texture bound     %d/%d" % [materials_textured, materials_total])
	print("  without any texture      %d" % len(materials_untextured))
	for m in materials_untextured.slice(0, 10):
		print("    ", m)
	print("=== materials extracted from model files (FBX-embedded)")
	print("  with a texture bound     %d/%d" % [extracted_textured, extracted_total])

	var ok: bool = scenes_failed.is_empty() and meshless_nodes.is_empty() and vanished_nodes.is_empty()
	print("\nRESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _collect(dir_path: String, scenes: Array[String], materials: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for f in d.get_files():
		var p: String = dir_path + "/" + f
		if f.ends_with(".scn") or f.ends_with(".tscn"):
			scenes.append(p)
		elif f.ends_with(".material") or f.contains(".mat."):
			materials.append(p)
	for sub in d.get_directories():
		_collect(dir_path + "/" + sub, scenes, materials)


func _check_scene(path: String) -> void:
	var ps = load(path)
	if ps == null or not (ps is PackedScene):
		scenes_failed.append(path + " (load failed)")
		return
	var inst = ps.instantiate()
	if inst == null:
		scenes_failed.append(path + " (instantiate failed)")
		return
	scenes_ok += 1
	_check_declared_nodes(ps, inst, path)
	if inst is Node3D:
		_check_meshes(inst, path)
	inst.free()


func _check_declared_nodes(ps: PackedScene, inst: Node, scene_path: String) -> void:
	var state: SceneState = ps.get_state()
	for i in range(state.get_node_count()):
		var np: NodePath = state.get_node_path(i)
		declared_nodes_checked += 1
		if inst.get_node_or_null(np) == null:
			vanished_nodes.append("%s: declares '%s', absent after instantiation" % [scene_path.get_file(), str(np)])


func _check_meshes(scene_root: Node, scene_path: String) -> void:
	for node in scene_root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node
		mesh_nodes_checked += 1
		if mi.mesh == null:
			meshless_nodes.append("%s / %s" % [scene_path.get_file(), mi.name])


func _check_material(path: String) -> void:
	var res = load(path)
	if res == null or not (res is BaseMaterial3D):
		return
	# Materials extracted from a model file are the FBX's own; Unidot overrides
	# them from the Unity .mat where one exists, so counting both together makes
	# the ratio meaningless.
	var is_extracted: bool = path.contains("/extracted/")
	var has_texture := false
	for prop in res.get_property_list():
		if (prop["usage"] & PROPERTY_USAGE_STORAGE) == 0 or not prop["hint_string"].contains("Texture"):
			continue
		if res.get(prop["name"]) != null:
			has_texture = true
			break
	if is_extracted:
		extracted_total += 1
		if has_texture:
			extracted_textured += 1
		return
	materials_total += 1
	if has_texture:
		materials_textured += 1
	else:
		# Not necessarily wrong: glass, glow and blank materials carry no texture
		# in the Unity source either. Reported for eyeballing, not failed.
		materials_untextured.append(path.get_file())

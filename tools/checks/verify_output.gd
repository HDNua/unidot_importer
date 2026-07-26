extends SceneTree

# Vendor-neutral correctness pass over a converted package. Run from a project
# produced by tools/validate_package.py:
#
#   Godot --headless -s addons/unidot_importer/tools/checks/verify_output.gd
#
# Answers four questions that do not depend on who made the package:
#   1. Does every generated scene load and instantiate?
#   2. Does every node a scene declares still exist after instantiation?
#   3. Does every MeshInstance3D actually have a mesh?
#   4. Does every skinned mesh in a prefab deform rigidly?
#
# (2) exists because a scene can load perfectly while missing a piece. A
# converted prefab is usually an inherited scene storing only overrides against
# a base scene generated from a model; if a later import replaces that model
# with a build that no longer has a node, Godot drops the override, warns, and
# hands back a scene that instantiates cleanly with the node gone. Nothing that
# enumerates what is present can see that, so this compares each scene against
# its own SceneState instead.
#
# (4) is the general form of the check: in a prefab's default state the skinning
# transform D = global_bone_pose * bind_pose must be the identity, or the mesh
# is already distorted before any animation plays. It needs no knowledge of
# which prefabs matter, only of which ones have a Skin.

const ROOT := "res://Unidot"
const ORIGIN_TOLERANCE := 0.01  # metres
const SCALE_TOLERANCE := 0.01
const ROTATION_TOLERANCE_DEG := 1.0

var scenes_ok := 0
var scenes_failed: Array[String] = []
var materials_total := 0
var materials_textured := 0
var materials_untextured: Array[String] = []
var extracted_total := 0
var extracted_textured := 0
var skins_checked := 0
var skin_failures: Array[String] = []
var prefabs_with_skin := 0
var posed_scenes_skipped := 0
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
	print("=== skinned meshes in prefabs (rest-pose rigidity)")
	print("  authored scenes skipped  %d (characters are posed there)" % posed_scenes_skipped)
	print("  prefabs containing skins %d" % prefabs_with_skin)
	print("  bone/skin checks         %d" % skins_checked)
	print("  failures                 %d" % len(skin_failures))
	for f in skin_failures.slice(0, 20):
		print("    ", f)

	var ok: bool = (scenes_failed.is_empty() and skin_failures.is_empty()
		and meshless_nodes.is_empty() and vanished_nodes.is_empty())
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
	# These two hold for anything that loaded, unlike the rigidity check below.
	_check_declared_nodes(ps, inst, path)
	if inst is Node3D:
		_check_meshes(inst, path)
	# Rigidity assumes the rest pose. An authored scene converted from a .unity
	# file deliberately poses its characters, so D is not expected to be the
	# identity there; only a prefab's default state carries that guarantee.
	if inst is Node3D and _is_prefab(path):
		# Skeleton3D only computes global bone poses once it is inside a tree.
		root.add_child(inst)
		_check_skins(inst, path)
		root.remove_child(inst)
	elif inst is Node3D:
		posed_scenes_skipped += 1
	inst.free()


func _is_prefab(path: String) -> bool:
	return path.contains(".prefab.")


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


func _check_skins(root: Node, scene_path: String) -> void:
	var found_skin := false
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node
		if mi.skin == null or mi.mesh == null:
			continue
		var skel := _skeleton_for(mi)
		if skel == null:
			skin_failures.append("%s / %s: has a Skin but no reachable Skeleton3D" % [scene_path.get_file(), mi.name])
			continue
		found_skin = true
		for bind_i in range(mi.skin.get_bind_count()):
			var bone_idx: int = mi.skin.get_bind_bone(bind_i)
			if bone_idx < 0:
				var bind_name: StringName = mi.skin.get_bind_name(bind_i)
				bone_idx = skel.find_bone(String(bind_name))
			if bone_idx < 0:
				skin_failures.append("%s: bind %d resolves to no bone" % [scene_path.get_file(), bind_i])
				continue
			var d: Transform3D = skel.get_bone_global_pose(bone_idx) * mi.skin.get_bind_pose(bind_i)
			skins_checked += 1
			var problem := _identity_error(d)
			if not problem.is_empty():
				skin_failures.append("%s / %s: %s" % [scene_path.get_file(), skel.get_bone_name(bone_idx), problem])
	if found_skin:
		prefabs_with_skin += 1


# The skeleton NodePath is not always populated in a converted prefab, so fall
# back to the nearest Skeleton3D ancestor. Without this the check silently finds
# no skins at all and reports a vacuous pass.
func _skeleton_for(mi: MeshInstance3D) -> Skeleton3D:
	if not mi.skeleton.is_empty():
		var by_path := mi.get_node_or_null(mi.skeleton) as Skeleton3D
		if by_path != null:
			return by_path
	var parent: Node = mi.get_parent()
	while parent != null:
		if parent is Skeleton3D:
			return parent
		parent = parent.get_parent()
	return null


func _identity_error(d: Transform3D) -> String:
	var problems: PackedStringArray = PackedStringArray()
	if d.origin.length() >= ORIGIN_TOLERANCE:
		problems.append("origin %.3fm" % d.origin.length())
	var scale: Vector3 = d.basis.get_scale()
	var scale_error: float = maxf(maxf(absf(scale.x - 1.0), absf(scale.y - 1.0)), absf(scale.z - 1.0))
	if scale_error >= SCALE_TOLERANCE:
		problems.append("scale %.3f" % scale_error)
	var angle: float = rad_to_deg(d.basis.get_rotation_quaternion().angle_to(Quaternion.IDENTITY)) * 2.0
	if angle >= ROTATION_TOLERANCE_DEG:
		problems.append("rotation %.2fdeg" % angle)
	return ", ".join(problems)

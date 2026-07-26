extends SceneTree

# Skin-deformation gate for the Synty POLYGON Prototype FPS arm prefabs.
#
#   Godot --headless --path <project> \
#     -s addons/unidot_importer/tools/publishers/synty/polygon-prototype/gate_fps_arms.gd
#
# Same subject as gate_fps_arms.py, which parses the converted scenes as text.
# This one loads them, so it also works when the output was written as binary
# .scn — which is what tools/validate_package.py produces.
#
# WHY THIS IS NOT IN tools/checks/
#
# The test is: for each bind of each Skin, D = global_bone_pose * bind_pose must
# be the identity. That only holds when the skeleton sits at the pose its meshes
# were bound in, and there is no independent way to establish that — the
# identity is the test. A prefab authored in some other pose fails it while
# rendering perfectly.
#
# Measured on POLYGON Prototype at revision 69bd28a: the eight prefabs below
# satisfy the identity on all 456 of their binds. A broader scan examined 39
# skin-bearing prefabs total, already including these eight, and reported 22,737
# failures across 20 posed PolygonGeneric full-character prefabs plus one Fov_01
# check. The affected characters render correctly; they are not stored at their
# bind pose. Knowing which prefabs satisfy the identity is publisher knowledge,
# so this gate lives with the pack.
#
# The defect this exists for is described in
# docs/packages/polygon-prototype.md#humanoid-skinning-correctness: a Root
# hijack contaminated the rest chain below the clavicle by a constant angle,
# which shows up here as every bone of the right arm failing at once.

const ROOT := "res://Unidot"
const ORIGIN_TOLERANCE := 0.01  # metres
const SCALE_TOLERANCE := 0.01
const ROTATION_TOLERANCE_DEG := 1.0

# Authored at bind pose in this pack; that is the property that makes the
# identity meaningful, and it is the part worth keeping specific.
const PREFABS := [
	"Character_FPS_Arms_FiveFinger_01",
	"Character_FPS_Arms_FiveFinger_02",
	"Character_FPS_Arms_FiveFinger_03",
	"Character_FPS_Hands_FiveFinger_01",
	"Character_FPS_Arms_Standard_01",
	"Character_FPS_Arms_Standard_02",
	"Character_FPS_Arms_Standard_03",
	"Character_FPS_Hands_Standard_01",
]

var checks := 0
var failures: Array[String] = []
var found: Array[String] = []


func _init() -> void:
	var by_name := {}
	_collect(ROOT, by_name)

	for name in PREFABS:
		var path: String = by_name.get(name, "")
		if path.is_empty():
			failures.append("%s: not found under %s" % [name, ROOT])
			continue
		found.append(name)
		_check(path)

	print("=== POLYGON Prototype FPS arm prefabs")
	print("  prefabs found            %d/%d" % [len(found), len(PREFABS)])
	print("  bone/skin checks         %d" % checks)
	print("  failures                 %d" % len(failures))
	for f in failures.slice(0, 20):
		print("    ", f)

	var ok: bool = failures.is_empty() and len(found) == len(PREFABS)
	print("\nRESULT: ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)


func _collect(dir_path: String, by_name: Dictionary) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for f in d.get_files():
		if f.ends_with(".prefab.scn") or f.ends_with(".prefab.tscn"):
			by_name[f.split(".prefab.")[0]] = dir_path + "/" + f
	for sub in d.get_directories():
		_collect(dir_path + "/" + sub, by_name)


func _check(path: String) -> void:
	var ps = load(path)
	if ps == null or not (ps is PackedScene):
		failures.append("%s: load failed" % path.get_file())
		return
	var inst = ps.instantiate()
	if inst == null or not (inst is Node3D):
		failures.append("%s: instantiate failed" % path.get_file())
		return
	# Skeleton3D only computes global bone poses once it is inside a tree.
	root.add_child(inst)
	for node in inst.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node
		if mi.skin == null or mi.mesh == null:
			continue
		var skel := _skeleton_for(mi)
		if skel == null:
			failures.append("%s / %s: has a Skin but no reachable Skeleton3D" % [path.get_file(), mi.name])
			continue
		for bind_i in range(mi.skin.get_bind_count()):
			var bone_idx: int = mi.skin.get_bind_bone(bind_i)
			if bone_idx < 0:
				bone_idx = skel.find_bone(String(mi.skin.get_bind_name(bind_i)))
			if bone_idx < 0:
				failures.append("%s: bind %d resolves to no bone" % [path.get_file(), bind_i])
				continue
			var d: Transform3D = skel.get_bone_global_pose(bone_idx) * mi.skin.get_bind_pose(bind_i)
			checks += 1
			var problem := _identity_error(d)
			if not problem.is_empty():
				failures.append("%s / %s: %s" % [path.get_file(), skel.get_bone_name(bone_idx), problem])
	root.remove_child(inst)
	inst.free()


# The skeleton NodePath is not always populated in a converted prefab, so fall
# back to the nearest Skeleton3D ancestor. Without this the gate silently finds
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

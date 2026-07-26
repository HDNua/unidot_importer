extends SceneTree

const gate := preload("../tools/checks/unity_source_pose_gate.gd")
const PASS_MARKER := "UNIDOT_UNITY_SOURCE_POSE_GATE_TEST_PASS"


func _init() -> void:
	var rotation := Quaternion(Vector3(0.2, 1.0, -0.4).normalized(), 1.234)
	assert(gate.quaternion_error_degrees(rotation, rotation) < 0.000001)
	assert(gate.quaternion_error_degrees(rotation, -rotation) < 0.000001)

	var identity_errors: Dictionary = gate.pose_errors(
		Transform3D.IDENTITY, Transform3D.IDENTITY)
	assert(not gate.errors_exceed_tolerance(identity_errors))
	var perturbed := Transform3D.IDENTITY
	perturbed.origin.x = gate.NEGATIVE_PERTURBATION_METERS
	assert(gate.errors_exceed_tolerance(gate.pose_errors(Transform3D.IDENTITY, perturbed)))
	var non_finite := Transform3D.IDENTITY
	non_finite.origin.x = NAN
	assert(gate.errors_exceed_tolerance(gate.pose_errors(Transform3D.IDENTITY, non_finite)))

	var passing := {
		"discovered_skin_prefabs": 1,
		"output_skin_prefabs": 1,
		"source_without_output": 0,
		"output_without_source": 0,
		"checked_prefabs": 1,
		"direct_yaml_prefabs": 1,
		"persisted_fbx_prefabs": 0,
		"direct_yaml_bones": 1,
		"persisted_fbx_bones": 0,
		"persisted_fbx_composition_only_bones": 0,
		"saved_fbx_meta_rotation_required_bones": 0,
		"saved_fbx_meta_required_rotation_checks": 0,
		"saved_fbx_meta_rotation_checks": 0,
		"unsupported_prefabs": 0,
		"compared_bones": 1,
		"mismatches": 0,
		"mismatched_prefabs": 0,
		"mismatched_bones": 0,
		"negative_controls_run": 1,
		"negative_controls_detected": 1,
	}
	assert(gate.report_is_pass(passing))
	for failing_change in [
		{"discovered_skin_prefabs": 0, "output_skin_prefabs": 0, "checked_prefabs": 0},
		{"source_without_output": 1},
		{"output_without_source": 1},
		{"unsupported_prefabs": 1},
		{"mismatches": 1, "mismatched_prefabs": 1},
		{"negative_controls_run": 0, "negative_controls_detected": 0},
	]:
		var failing: Dictionary = passing.duplicate(true)
		failing.merge(failing_change, true)
		assert(not gate.report_is_pass(failing))

	var fbx_passing: Dictionary = passing.duplicate(true)
	fbx_passing["direct_yaml_prefabs"] = 0
	fbx_passing["persisted_fbx_prefabs"] = 1
	fbx_passing["direct_yaml_bones"] = 0
	fbx_passing["persisted_fbx_bones"] = 2
	fbx_passing["persisted_fbx_composition_only_bones"] = 1
	fbx_passing["saved_fbx_meta_rotation_required_bones"] = 1
	fbx_passing["saved_fbx_meta_required_rotation_checks"] = 1
	fbx_passing["saved_fbx_meta_rotation_checks"] = 1
	fbx_passing["compared_bones"] = 2
	assert(gate.report_is_pass(fbx_passing))
	fbx_passing["saved_fbx_meta_rotation_checks"] = 0
	assert(not gate.report_is_pass(fbx_passing))
	var partial_meta: Dictionary = fbx_passing.duplicate(true)
	partial_meta["saved_fbx_meta_rotation_checks"] = 1
	partial_meta["saved_fbx_meta_rotation_required_bones"] = 2
	partial_meta["saved_fbx_meta_required_rotation_checks"] = 1
	assert(not gate.report_is_pass(partial_meta))

	var mixed: Dictionary = passing.duplicate(true)
	mixed.merge({
		"discovered_skin_prefabs": 2,
		"output_skin_prefabs": 2,
		"checked_prefabs": 2,
		"direct_yaml_prefabs": 1,
		"persisted_fbx_prefabs": 1,
		"direct_yaml_bones": 1,
		"persisted_fbx_bones": 2,
		"persisted_fbx_composition_only_bones": 1,
		"saved_fbx_meta_rotation_required_bones": 1,
		"saved_fbx_meta_required_rotation_checks": 1,
		"saved_fbx_meta_rotation_checks": 1,
		"compared_bones": 3,
		"negative_controls_run": 1,
		"negative_controls_detected": 1,
	}, true)
	assert(not gate.report_is_pass(mixed))
	mixed["negative_controls_run"] = 2
	mixed["negative_controls_detected"] = 2
	assert(gate.report_is_pass(mixed))

	# Synthetic Root acceptance requires a matched source-root relationship. An
	# authored identity Root with missing mapping must never be hidden by its name.
	var meta: Resource = gate.asset_meta_class.new()
	meta.humanoid_bone_map_dict = {"authored": "Hips"}
	assert(gate.active_humanoid_map(meta) == {"authored": "Hips"})
	meta.autodetected_bone_map_dict = {"detected": "Spine"}
	assert(gate.active_humanoid_map(meta) == {"detected": "Spine"})
	meta.autodetected_bone_map_dict = {}
	meta.type_to_fileids = {"SkinnedMeshRenderer": [137]}
	meta.fileid_to_skeleton_bone = {}
	meta.fileid_to_utype = {}
	meta.internal_data = {}
	assert(not gate.meta_has_skin_inventory(meta))
	assert(gate.meta_has_corrupt_skin_inventory(meta))
	meta.fileid_to_skeleton_bone = {10: "Hips"}
	meta.fileid_to_utype = {10: 4}
	assert(gate.meta_has_corrupt_skin_inventory(meta))
	meta.internal_data = {"humanoid_original_transforms": {"Hips": Transform3D.IDENTITY}}
	assert(gate.meta_has_skin_inventory(meta))
	assert(not gate.meta_has_corrupt_skin_inventory(meta))
	meta.fileid_to_skeleton_bone = {10: "Hips"}
	meta.fileid_to_utype = {10: 4}
	var wrapper := _wrapper_skeleton()
	var wrapper_matched := {_bone_key(wrapper, 1): 10}
	assert(gate.synthetic_root_topology_is_proven(wrapper, 0, wrapper_matched, meta))
	assert(not gate.synthetic_root_topology_is_proven(wrapper, 0, {}, meta))
	meta.transform_fileid_to_parent_fileid = {10: 9}
	assert(not gate.synthetic_root_topology_is_proven(
		wrapper, 0, wrapper_matched, meta, {9: true, 10: true}))
	meta.fileid_to_skeleton_bone = {10: "Root", 20: "Hips"}
	meta.fileid_to_utype = {10: 4, 20: 4}
	meta.transform_fileid_to_parent_fileid = {20: 10}
	assert(not gate.synthetic_root_topology_is_proven(
		wrapper, 0, {_bone_key(wrapper, 1): 20}, meta))
	wrapper.free()

	var collision := _collision_skeleton()
	var collision_matched := {
		_bone_key(collision, 0): 10,
		_bone_key(collision, 2): 20,
	}
	assert(gate.synthetic_root_topology_is_proven(
		collision, 1, collision_matched, meta))
	meta.transform_fileid_to_parent_fileid = {20: 0}
	assert(not gate.synthetic_root_topology_is_proven(
		collision, 1, collision_matched, meta))
	collision.free()

	print(PASS_MARKER)
	quit(0)


func _bone_key(skeleton: Skeleton3D, bone_index: int) -> String:
	return "%s:%d" % [str(skeleton.get_instance_id()), bone_index]


func _wrapper_skeleton() -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	skeleton.add_bone("Root")
	skeleton.add_bone("Hips")
	skeleton.set_bone_parent(1, 0)
	return skeleton


func _collision_skeleton() -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	skeleton.add_bone("Root1")
	skeleton.add_bone("Root")
	skeleton.add_bone("Hips")
	skeleton.set_bone_parent(1, 0)
	skeleton.set_bone_parent(2, 1)
	return skeleton

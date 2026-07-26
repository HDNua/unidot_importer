extends SceneTree

# Source-consistency gate for skeleton poses converted from Unity packages.
#
# Stronger branch: a prefab YAML directly contains SkinnedMeshRenderer and
# authored bone Transform documents.  The source TRS is parsed with Unidot's
# YAML parser and converted with UnidotTransform.convert_skeleton_properties().
#
# Weaker branch: a prefab variant contains no bone Transform documents and
# inherits a skinned FBX.  A separately instantiated persisted source-model
# scene supplies the baseline pose; saved AssetMeta provides exact
# fileID/nodepath/bone mapping. Its active humanoid-map values (auto-detected
# map first, authored map fallback) define the exact subset required to have an
# original/delta rotation cross-check. Other saved originals are checked too;
# only mapped bones without an original are explicitly composition-only. This
# catches prefab composition/application
# defects, but model-level defects are shared by the baseline and final prefab
# and remain invisible.
#
# The direct branch also shares Unidot's YAML parser and coordinate converter,
# so symmetric defects in those components are outside this gate's reach. Its
# synthetic-root proof does independently consult authored YAML m_Bones. The
# FBX proof must instead trust persisted fileID/parent metadata, so corruption
# that removes an authored root from that same mapping may remain invisible.

const asset_database_class := preload("../../asset_database.gd")
const asset_meta_class := preload("../../asset_meta.gd")
const object_adapter_class := preload("../../object_adapter.gd")

const RESULT_PREFIX := "UNITY_SOURCE_POSE_GATE_JSON="
const MANIFEST_VERSION := 1

# Kept deliberately tight: this gate compares persisted values produced by the
# same conversion pipeline, not independently sampled render output.
const POSITION_TOLERANCE_METERS := 0.00001
const ROTATION_TOLERANCE_DEGREES := 0.001
const SCALE_TOLERANCE := 0.00001
const NEGATIVE_PERTURBATION_METERS := 0.01

const ORACLE_DIRECT := "direct_yaml"
const ORACLE_FBX_COMPOSITION := "persisted_fbx_composition"
const FAILURE_LIMIT := 200
const INVALID_ERROR_SENTINEL := 1.0e30
const TRANSFORM_VALUE_PROPERTIES := {
	"m_LocalPosition.x": true,
	"m_LocalPosition.y": true,
	"m_LocalPosition.z": true,
	"m_LocalRotation.x": true,
	"m_LocalRotation.y": true,
	"m_LocalRotation.z": true,
	"m_LocalRotation.w": true,
	"m_LocalScale.x": true,
	"m_LocalScale.y": true,
	"m_LocalScale.z": true,
	# Euler angles are an editor hint when an authored quaternion is present.
	"m_LocalEulerAnglesHint.x": true,
	"m_LocalEulerAnglesHint.y": true,
	"m_LocalEulerAnglesHint.z": true,
}

var database: Resource
var guid_to_source_path: Dictionary = {}
var report: Dictionary = {}
var negative_modes_seen: Dictionary = {}
var source_skin_prefabs: Dictionary = {}
var output_skin_prefabs: Dictionary = {}
var mismatch_prefab_paths: Dictionary = {}
var mismatch_bone_paths: Dictionary = {}


func _init() -> void:
	report = _empty_report()
	var args := OS.get_cmdline_user_args()
	if len(args) != 1:
		_fatal("expected one manifest path after --")
		return
	var manifest := _read_json(String(args[0]))
	if manifest.is_empty():
		_fatal("manifest could not be read")
		return
	if int(manifest.get("version", 0)) != MANIFEST_VERSION:
		_fatal("unsupported manifest version")
		return
	guid_to_source_path = manifest.get("guid_to_path", {})
	database = load("res://unidot_asset_database.res")
	if database == null:
		_fatal("res://unidot_asset_database.res could not be loaded")
		return

	var prefab_records: Array = manifest.get("prefabs", [])
	for record_variant in prefab_records:
		if record_variant is Dictionary:
			_check_source_prefab(record_variant)

	_record_inventory_differences()
	_finalize()


func _empty_report() -> Dictionary:
	return {
		"result": "FAIL",
		"source_prefabs_scanned": 0,
		"discovered_skin_prefabs": 0,
		"output_skin_prefabs": 0,
		"source_without_output": 0,
		"output_without_source": 0,
		"checked_prefabs": 0,
		"direct_yaml_prefabs": 0,
		"persisted_fbx_prefabs": 0,
		"unsupported_prefabs": 0,
		"compared_bones": 0,
		"direct_yaml_bones": 0,
		"persisted_fbx_bones": 0,
		"persisted_fbx_composition_only_bones": 0,
		"saved_fbx_meta_rotation_required_bones": 0,
		"saved_fbx_meta_required_rotation_checks": 0,
		"saved_fbx_meta_rotation_checks": 0,
		"synthetic_roots": 0,
		"mismatches": 0,
		"mismatched_prefabs": 0,
		"mismatched_bones": 0,
		"negative_controls_run": 0,
		"negative_controls_detected": 0,
		"max_position_error_meters": 0.0,
		"max_rotation_error_degrees": 0.0,
		"max_scale_error": 0.0,
		"position_tolerance_meters": POSITION_TOLERANCE_METERS,
		"rotation_tolerance_degrees": ROTATION_TOLERANCE_DEGREES,
		"scale_tolerance": SCALE_TOLERANCE,
		"oracle_strengths": {
			ORACLE_DIRECT: "source YAML through Unidot parser/converter",
			ORACLE_FBX_COMPOSITION:
				"weaker: persisted source-FBX scene plus exact saved metadata mapping",
		},
		"failures": [],
	}


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	return {}


func _fresh_parse_meta(saved_meta: Resource, guid: String, source_path: String) -> Resource:
	var meta: Resource
	if saved_meta != null:
		meta = saved_meta.duplicate(true)
	else:
		meta = asset_meta_class.new()
		meta.guid = guid
		meta.path = source_path
		meta.orig_path = source_path
		meta.importer_type = "PrefabImporter"
	meta.initialize(database)
	meta.parsed = null
	return meta


func _parse_prefab(meta: Resource, yaml_path: String) -> Variant:
	var file := FileAccess.open(yaml_path, FileAccess.READ)
	if file == null:
		return null
	return meta.parse_asset(file)


func _check_source_prefab(record: Dictionary) -> void:
	report["source_prefabs_scanned"] += 1
	var guid := String(record.get("guid", "")).to_lower()
	var source_path := String(record.get("source_path", ""))
	var yaml_path := String(record.get("yaml_path", ""))
	var saved_meta: Resource = database.get_meta_by_guid(guid)
	var output_instance := _instantiate_output_prefab(saved_meta)
	if output_instance != null and not _skinned_skeletons(output_instance).is_empty():
		output_skin_prefabs[source_path] = true

	# Discovery deliberately uses a lightweight meta.  Deep-copying every saved
	# prefab meta also deep-copies its resource table and makes a package-wide
	# source scan needlessly expensive.  Only the discovered candidates are
	# reparsed against a copy of their persisted conversion maps below.
	var discovery_meta := _fresh_parse_meta(null, guid, source_path)
	var parsed: Variant = _parse_prefab(discovery_meta, yaml_path)
	if parsed == null:
		_record_mismatch(source_path, "", "source YAML parse failed")
		if output_instance != null:
			output_instance.free()
		return
	var classification := _classify_prefab(parsed)
	var is_candidate: bool = classification["is_candidate"]
	if not is_candidate:
		if output_instance != null:
			output_instance.free()
		return
	source_skin_prefabs[source_path] = true

	if saved_meta == null:
		_record_unsupported(source_path, "candidate has no persisted AssetMeta")
		if output_instance != null:
			output_instance.free()
		return
	if output_instance == null or _skinned_skeletons(output_instance).is_empty():
		if output_instance != null:
			output_instance.free()
		return

	var parse_meta := _fresh_parse_meta(saved_meta, guid, source_path)
	parsed = _parse_prefab(parse_meta, yaml_path)
	if parsed == null:
		_record_mismatch(source_path, "", "candidate YAML reparse with persisted metadata failed")
		output_instance.free()
		return
	classification = _classify_prefab(parsed)
	var all_instances: Array = classification["prefab_instances"]
	var modern_instances: Array = classification["modern_instances"]
	var inherited_skin_instances: Array = classification["inherited_skin_instances"]
	var invalid_fbx_instances: Array = classification["invalid_fbx_instances"]
	var unresolved_instances: Array = classification["unresolved_instances"]
	if int(classification["direct_skin_renderers"]) > 0 \
			and inherited_skin_instances.is_empty() and invalid_fbx_instances.is_empty() \
			and unresolved_instances.is_empty():
		_check_direct_prefab(source_path, parse_meta, parsed, output_instance)
	elif int(classification["direct_skin_renderers"]) == 0 \
			and int(classification["direct_transform_documents"]) == 0 \
			and int(classification["stripped_objects"]) == 0 \
			and int(parsed.assets.size()) == 1 \
			and len(all_instances) == 1 and len(modern_instances) == 1 \
			and len(inherited_skin_instances) == 1 and invalid_fbx_instances.is_empty() \
			and _prefab_instance_is_root(modern_instances[0]):
		_check_fbx_prefab(source_path, modern_instances[0], output_instance)
	else:
		_record_unsupported(source_path,
			(("mixed, nested, or unresolved skin form " +
			"(direct_renderers=%d, transforms=%d, instances=%d, stripped=%d, " +
			"skinned_sources=%d, invalid_fbx_sources=%d, unresolved_sources=%d)") % [
				int(classification["direct_skin_renderers"]),
				int(classification["direct_transform_documents"]), len(all_instances),
				int(classification["stripped_objects"]), len(inherited_skin_instances),
				len(invalid_fbx_instances), len(unresolved_instances)]))
	output_instance.free()


func _instantiate_output_prefab(saved_meta: Resource) -> Node:
	if saved_meta == null or String(saved_meta.path).is_empty():
		return null
	var packed: Resource = load("res://" + String(saved_meta.path))
	if packed == null or not (packed is PackedScene):
		return null
	return packed.instantiate()


func _classify_prefab(parsed: Variant) -> Dictionary:
	var direct_skin_renderers := 0
	var direct_transform_documents := 0
	var stripped_objects := 0
	var prefab_instances: Array = []
	var modern_instances: Array = []
	for object_variant in parsed.assets.values():
		if object_variant.is_prefab_reference:
			stripped_objects += 1
		if object_variant.type == "SkinnedMeshRenderer" and not object_variant.is_stripped:
			direct_skin_renderers += 1
		elif object_variant.type == "Transform" and not object_variant.is_stripped:
			direct_transform_documents += 1
		elif object_variant.type == "PrefabInstance":
			prefab_instances.append(object_variant)
			if not object_variant.is_legacy_parent_prefab:
				modern_instances.append(object_variant)

	var inherited_skin_instances: Array = []
	var invalid_fbx_instances: Array = []
	var unresolved_instances: Array = []
	for prefab_instance in modern_instances:
		var source_ref: Array = prefab_instance.source_prefab
		var source_guid := "" if len(source_ref) < 3 else String(source_ref[2]).to_lower()
		var inherited_meta: Resource = database.get_meta_by_guid(source_guid)
		if inherited_meta != null and meta_has_skin_inventory(inherited_meta):
			inherited_skin_instances.append(prefab_instance)
		elif inherited_meta != null and meta_has_corrupt_skin_inventory(inherited_meta):
			# A package FBX with missing or empty skin inventory is still a candidate;
			# corrupt conversion metadata must not make it vanish from discovery.
			invalid_fbx_instances.append(prefab_instance)
		elif inherited_meta == null:
			unresolved_instances.append(prefab_instance)
	return {
		"direct_skin_renderers": direct_skin_renderers,
		"direct_transform_documents": direct_transform_documents,
		"stripped_objects": stripped_objects,
		"prefab_instances": prefab_instances,
		"modern_instances": modern_instances,
		"inherited_skin_instances": inherited_skin_instances,
		"invalid_fbx_instances": invalid_fbx_instances,
		"unresolved_instances": unresolved_instances,
		"is_candidate": direct_skin_renderers > 0 \
			or not inherited_skin_instances.is_empty() or not invalid_fbx_instances.is_empty(),
	}


func _prefab_instance_is_root(prefab_instance: RefCounted) -> bool:
	var parent_ref: Array = prefab_instance.parent_ref
	return len(parent_ref) >= 2 and int(parent_ref[1]) == 0


func _record_inventory_differences() -> void:
	report["discovered_skin_prefabs"] = len(source_skin_prefabs)
	report["output_skin_prefabs"] = len(output_skin_prefabs)
	for source_path_variant in source_skin_prefabs:
		var source_path := String(source_path_variant)
		if not output_skin_prefabs.has(source_path):
			report["source_without_output"] += 1
			_record_mismatch(source_path, "", "source skin prefab has no output-side Skin")
	for source_path_variant in output_skin_prefabs:
		var source_path := String(source_path_variant)
		if not source_skin_prefabs.has(source_path):
			report["output_without_source"] += 1
			_record_mismatch(source_path, "", "output-side Skin has no source skin explanation")


static func meta_has_skin_inventory(meta: Resource) -> bool:
	var ids: Variant = meta.type_to_fileids.get("SkinnedMeshRenderer", [])
	return len(ids) > 0 and _mapped_transform_bone_count(meta) > 0 \
		and _mapped_original_bone_count(meta) > 0


static func meta_has_corrupt_skin_inventory(meta: Resource) -> bool:
	# A declared SkinnedMeshRenderer is source-side skin evidence even when the
	# entire saved bone mapping is missing. Corrupt conversion metadata must not
	# make the inherited source and a simultaneously dropped output disappear.
	var ids: Variant = meta.type_to_fileids.get("SkinnedMeshRenderer", [])
	return len(ids) > 0 and not meta_has_skin_inventory(meta)


static func _mapped_transform_bone_count(meta: Resource) -> int:
	var count := 0
	for fileid_variant in meta.fileid_to_skeleton_bone:
		if int(meta.fileid_to_utype.get(int(fileid_variant), 0)) == 4:
			count += 1
	return count


static func _mapped_original_bone_count(meta: Resource) -> int:
	var originals: Variant = meta.internal_data.get("humanoid_original_transforms", {})
	if not (originals is Dictionary):
		return 0
	var count := 0
	for fileid_variant in meta.fileid_to_skeleton_bone:
		var fileid := int(fileid_variant)
		var bone_name := String(meta.fileid_to_skeleton_bone[fileid])
		if int(meta.fileid_to_utype.get(fileid, 0)) == 4 and originals.has(bone_name):
			count += 1
	return count


func _source_extension(guid: String) -> String:
	return String(guid_to_source_path.get(guid, "")).get_extension().to_lower()


func _check_direct_prefab(source_path: String, meta: Resource, parsed: Variant, instance: Node) -> void:
	var bone_inventory := _direct_authored_bone_fileids(parsed)
	if not bool(bone_inventory.get("valid", false)):
		_record_unsupported(source_path,
			"direct SkinnedMeshRenderer has malformed or empty authored m_Bones/m_RootBone")
		return
	var weighted_bone_fileids: Dictionary = bone_inventory["weighted_fileids"]
	var provenance_bone_fileids: Dictionary = bone_inventory["provenance_fileids"]
	report["direct_yaml_prefabs"] += 1
	report["checked_prefabs"] += 1
	var matched: Dictionary = {}
	var matched_source_fileids: Dictionary = {}
	var comparisons_before := int(report["direct_yaml_bones"])
	for transform in parsed.assets.values():
		if transform.type != "Transform" or transform.is_prefab_reference:
			continue
		var bone_name := String(meta.fileid_to_skeleton_bone.get(transform.fileID, ""))
		if bone_name.is_empty():
			continue
		if not _has_complete_source_trs(transform.keys):
			_record_mismatch(source_path, bone_name,
				"authored Transform is missing position, rotation, or scale")
			continue
		var target := _target_bone(instance, meta, transform.fileID, bone_name)
		if target.is_empty():
			_record_mismatch(source_path, bone_name,
				"fileID %s does not resolve to an output bone" % str(transform.fileID))
			continue
		var target_key := _bone_key(target["skeleton"], target["bone_index"])
		if matched.has(target_key):
			_record_mismatch(source_path, bone_name,
				"source fileIDs %s and %s resolve to the same output bone" % [
					str(matched[target_key]), str(transform.fileID)])
			continue
		var source_properties: Dictionary = transform.keys.duplicate(true)
		var expected_builder := Callable(self, "_expected_from_properties").bind(
			transform, source_properties)
		var expected_variant: Variant = expected_builder.call()
		if not (expected_variant is Transform3D):
			_record_mismatch(source_path, bone_name, "source Transform conversion was incomplete")
			continue
		var expected: Transform3D = expected_variant
		_compare_bone(ORACLE_DIRECT, source_path, bone_name, target, expected, expected_builder)
		matched[target_key] = transform.fileID
		matched_source_fileids[transform.fileID] = \
			int(matched_source_fileids.get(transform.fileID, 0)) + 1

	if int(report["direct_yaml_bones"]) == comparisons_before:
		_record_unsupported(source_path, "direct SkinnedMeshRenderer has no mapped authored bone Transforms")
		return
	for fileid_variant in weighted_bone_fileids:
		var fileid := int(fileid_variant)
		if int(matched_source_fileids.get(fileid, 0)) != 1:
			_record_mismatch(source_path, str(fileid),
				"authored m_Bones Transform fileID was not compared exactly once")
	_check_unexplained_bones(source_path, instance, matched, meta, provenance_bone_fileids)


func _direct_authored_bone_fileids(parsed: Variant) -> Dictionary:
	var weighted_fileids: Dictionary = {}
	var provenance_fileids: Dictionary = {}
	var found_renderer := false
	for object_variant in parsed.assets.values():
		if object_variant.type != "SkinnedMeshRenderer" \
				or object_variant.is_prefab_reference or object_variant.is_stripped:
			continue
		found_renderer = true
		var bones_variant: Variant = object_variant.keys.get("m_Bones", null)
		if not (bones_variant is Array) or bones_variant.is_empty():
			return {"valid": false, "weighted_fileids": {}, "provenance_fileids": {}}
		for reference_variant in bones_variant:
			if not (reference_variant is Array) or len(reference_variant) < 2:
				return {"valid": false, "weighted_fileids": {}, "provenance_fileids": {}}
			var fileid := int(reference_variant[1])
			if fileid == 0:
				return {"valid": false, "weighted_fileids": {}, "provenance_fileids": {}}
			weighted_fileids[fileid] = true
			provenance_fileids[fileid] = true
		if object_variant.keys.has("m_RootBone"):
			var root_reference: Variant = object_variant.keys["m_RootBone"]
			if not (root_reference is Array) or len(root_reference) < 2:
				return {"valid": false, "weighted_fileids": {}, "provenance_fileids": {}}
			var root_fileid := int(root_reference[1])
			# Unity permits m_RootBone {fileID: 0} as an unset/automatic root.
			if root_fileid != 0:
				provenance_fileids[root_fileid] = true
	return {
		"valid": found_renderer and not weighted_fileids.is_empty(),
		"weighted_fileids": weighted_fileids,
		"provenance_fileids": provenance_fileids,
	}


func _has_complete_source_trs(keys: Dictionary) -> bool:
	return keys.has("m_LocalPosition") and keys.has("m_LocalRotation") and keys.has("m_LocalScale") \
		and keys["m_LocalPosition"] is Vector3 and keys["m_LocalRotation"] is Quaternion \
		and keys["m_LocalScale"] is Vector3 and _properties_are_finite(keys)


func _convert_with_identity_scratch(transform: RefCounted, properties: Dictionary) -> Dictionary:
	if not _properties_are_finite(properties):
		return {}
	var scratch := Skeleton3D.new()
	scratch.add_bone("__source__")
	scratch.set_bone_pose_position(0, Vector3.ZERO)
	scratch.set_bone_pose_rotation(0, Quaternion.IDENTITY)
	scratch.set_bone_pose_scale(0, Vector3.ONE)
	var converted: Dictionary = transform.convert_skeleton_properties(
		scratch, "__source__", properties)
	scratch.free()
	if not converted.has("position") or not converted.has("quaternion") or not converted.has("scale"):
		return {}
	if not (converted["position"] is Vector3) or not (converted["quaternion"] is Quaternion) \
			or not (converted["scale"] is Vector3) or not _properties_are_finite({
				"m_LocalPosition": converted["position"],
				"m_LocalRotation": converted["quaternion"],
				"m_LocalScale": converted["scale"],
			}):
		return {}
	return converted


func _transform_from_converted(converted: Dictionary) -> Transform3D:
	var rotation: Quaternion = converted["quaternion"]
	var scale: Vector3 = converted["scale"]
	return Transform3D(Basis(rotation).scaled(scale), converted["position"])


func _expected_from_properties(transform: RefCounted, properties: Dictionary) -> Variant:
	var converted := _convert_with_identity_scratch(transform, properties)
	if converted.is_empty():
		return null
	var expected := _transform_from_converted(converted)
	if not _transform_is_finite(expected):
		return null
	return expected


func _check_fbx_prefab(source_path: String, prefab_instance: RefCounted, instance: Node) -> void:
	var source_ref: Array = prefab_instance.source_prefab
	var source_guid := "" if len(source_ref) < 3 else String(source_ref[2]).to_lower()
	var source_path_from_package := String(guid_to_source_path.get(source_guid, ""))
	var source_meta: Resource = database.get_meta_by_guid(source_guid)
	if source_meta == null or source_path_from_package.get_extension().to_lower() != "fbx":
		_record_unsupported(source_path, "inherited skinned source is not a resolved package FBX")
		return
	if not source_meta.prefab_dependency_guids.is_empty():
		_record_unsupported(source_path, "nested inherited FBX metadata is unsupported")
		return
	var modification: Dictionary = prefab_instance.keys.get("m_Modification", {})
	for structural_key in ["m_RemovedComponents", "m_RemovedGameObjects", "m_AddedGameObjects", "m_AddedComponents"]:
		if not modification.get(structural_key, []).is_empty():
			_record_unsupported(source_path, "inherited form changes structure via " + structural_key)
			return

	var source_transform_ids: Dictionary = {}
	var bone_target_ids: Dictionary = {}
	for fileid_variant in source_meta.fileid_to_skeleton_bone:
		var fileid := int(fileid_variant)
		if int(source_meta.fileid_to_utype.get(fileid, 0)) == 4:
			source_transform_ids[fileid] = true
			bone_target_ids[fileid] = true
			var gameobject_fileid := int(source_meta.fileid_to_gameobject_fileid.get(fileid, 0))
			if gameobject_fileid != 0:
				bone_target_ids[gameobject_fileid] = true
	for mod_variant in prefab_instance.modifications:
		if not (mod_variant is Dictionary):
			_record_unsupported(source_path, "prefab modification is not a dictionary")
			return
		var mod: Dictionary = mod_variant
		var target: Array = mod.get("target", [])
		if len(target) < 3 or String(target[2]).to_lower() != source_guid:
			_record_unsupported(source_path, "prefab modification target is unresolved or crosses sources")
			return
		var target_fileid := int(target[1])
		if not source_meta.fileid_to_utype.has(target_fileid):
			_record_unsupported(source_path,
				"prefab modification target fileID %s is unresolved" % str(target_fileid))
			return
		var property_path := String(mod.get("propertyPath", ""))
		if _is_structural_property(property_path):
			_record_unsupported(source_path, "prefab modification changes structure: " + property_path)
			return
		if _is_transform_property(property_path):
			if bone_target_ids.has(target_fileid):
				_record_unsupported(source_path,
					"prefab modification overrides mapped bone TRS: " + property_path)
				return
			if int(source_meta.fileid_to_utype.get(target_fileid, 0)) != 4:
				_record_unsupported(source_path, "TRS override targets a non-Transform")
				return
			if target_fileid != int(source_meta.prefab_main_transform_id):
				_record_unsupported(source_path, "TRS override targets a non-root Transform")
				return
			var object_reference: Array = mod.get("objectReference", [])
			if len(object_reference) >= 2 and int(object_reference[1]) != 0:
				_record_unsupported(source_path, "TRS override carries an object reference")
				return
			var value_text := String(mod.get("value", ""))
			if not value_text.is_valid_float() or not _float_is_finite(value_text.to_float()):
				_record_unsupported(source_path, "TRS override is non-numeric or non-finite")
				return
		elif not _is_known_safe_pose_neutral_property(source_meta, target_fileid, property_path):
			_record_unsupported(source_path, "unknown prefab override: " + property_path)
			return

	var originals: Dictionary = source_meta.internal_data.get("humanoid_original_transforms", {})
	if originals.is_empty():
		_record_unsupported(source_path, "FBX AssetMeta has no saved humanoid_original_transforms")
		return
	var eligibility := _fbx_rotation_eligibility(source_path, source_meta, originals)
	if not bool(eligibility.get("valid", false)):
		return
	var rotation_required_fileids: Dictionary = eligibility["fileids"]
	var source_model_instance := _instantiate_output_prefab(source_meta)
	if source_model_instance == null or _skinned_skeletons(source_model_instance).is_empty():
		_record_unsupported(source_path, "persisted source FBX scene has no resolvable Skin")
		if source_model_instance != null:
			source_model_instance.free()
		return

	report["persisted_fbx_prefabs"] += 1
	report["checked_prefabs"] += 1
	report["saved_fbx_meta_rotation_required_bones"] += len(rotation_required_fileids)
	var matched: Dictionary = {}
	var source_matched: Dictionary = {}
	var comparisons_before := int(report["persisted_fbx_bones"])
	for fileid_variant in source_transform_ids:
		var fileid := int(fileid_variant)
		var bone_name := String(source_meta.fileid_to_skeleton_bone.get(fileid, ""))
		if bone_name.is_empty():
			continue
		var source_target := _target_bone(source_model_instance, source_meta, fileid, bone_name)
		if source_target.is_empty():
			_record_mismatch(source_path, bone_name,
				"saved FBX fileID %s does not resolve in the source model" % str(fileid))
			continue
		var source_target_key := _bone_key(
			source_target["skeleton"], source_target["bone_index"])
		if source_matched.has(source_target_key):
			_record_mismatch(source_path, bone_name,
				"source fileIDs %s and %s resolve to the same persisted source-model bone" % [
					str(source_matched[source_target_key]), str(fileid)])
			continue
		source_matched[source_target_key] = fileid
		var expected_builder := Callable(self, "_expected_from_bone_target").bind(source_target)
		var expected_variant: Variant = expected_builder.call()
		if not (expected_variant is Transform3D):
			_record_mismatch(source_path, bone_name, "persisted source FBX pose is invalid")
			continue
		var expected: Transform3D = expected_variant
		var target := _target_bone(instance, source_meta, fileid, bone_name)
		if target.is_empty():
			_record_mismatch(source_path, bone_name,
				"saved FBX fileID %s does not resolve to an output bone" % str(fileid))
			continue
		var target_key := _bone_key(target["skeleton"], target["bone_index"])
		if matched.has(target_key):
			_record_mismatch(source_path, bone_name,
				"source fileIDs %s and %s resolve to the same output bone" % [
					str(matched[target_key]), str(fileid)])
			continue
		if originals.has(bone_name):
			_check_saved_fbx_rotation_consistency(
				source_path, bone_name, source_meta, fileid, originals[bone_name], expected)
			if rotation_required_fileids.has(fileid):
				report["saved_fbx_meta_required_rotation_checks"] += 1
		else:
			report["persisted_fbx_composition_only_bones"] += 1
		_compare_bone(
			ORACLE_FBX_COMPOSITION, source_path, bone_name, target, expected, expected_builder)
		matched[target_key] = fileid

	if int(report["persisted_fbx_bones"]) == comparisons_before:
		_record_unsupported(source_path, "FBX metadata yielded zero Transform/bone intersections")
		source_model_instance.free()
		return
	# Validate the independently instantiated persisted source-model inventory as
	# well as the final prefab. Otherwise a bone omitted from saved mapping and
	# dropped from the final scene could disappear from both compared sets.
	_check_unexplained_bones(
		source_path, source_model_instance, source_matched, source_meta, {}, false)
	_check_unexplained_bones(source_path, instance, matched, source_meta)
	source_model_instance.free()


func _expected_from_bone_target(target: Dictionary) -> Variant:
	if not target.has("skeleton") or not target.has("bone_index"):
		return null
	var skeleton: Skeleton3D = target["skeleton"]
	var bone_index := int(target["bone_index"])
	if not is_instance_valid(skeleton) or bone_index < 0 or bone_index >= skeleton.get_bone_count():
		return null
	var expected := _bone_pose(skeleton, bone_index)
	return expected if _transform_is_finite(expected) else null


func _check_saved_fbx_rotation_consistency(source_path: String, bone_name: String,
		meta: Resource, fileid: int, original: Transform3D,
		expected_source_pose: Transform3D) -> void:
	report["saved_fbx_meta_rotation_checks"] += 1
	if not _transform_is_finite(original):
		_record_mismatch(source_path, bone_name, "saved FBX original transform is non-finite")
		return
	var virtual_transform: RefCounted = object_adapter_class.new().instantiate_unidot_object(
		meta, fileid, 4, "Transform")
	if virtual_transform == null:
		_record_mismatch(source_path, bone_name, "saved FBX Transform adapter is unavailable")
		return
	var properties := _unity_properties_from_godot_source(original, meta, fileid)
	var reconstructed: Variant = _expected_from_properties(virtual_transform, properties)
	if not (reconstructed is Transform3D):
		_record_mismatch(source_path, bone_name, "saved FBX rotation reconstruction failed")
		return
	var rotation_error := quaternion_error_degrees(
		reconstructed.basis.get_rotation_quaternion(),
		expected_source_pose.basis.get_rotation_quaternion())
	if not _float_is_finite(rotation_error) or rotation_error > ROTATION_TOLERANCE_DEGREES:
		_record_mismatch(source_path, bone_name,
			"saved FBX original/delta rotation disagrees with source model: %.9fdeg" % rotation_error)


func _fbx_rotation_eligibility(source_path: String, meta: Resource,
		originals: Dictionary) -> Dictionary:
	# AssetMeta stores active-map keys in the Unity/source-name domain and values
	# in the final SkeletonProfileHumanoid bone-name domain. Match the importer's
	# precedence (auto-detected first, authored fallback); the persisted fileID map
	# uses the value domain, so only exact values form the required subset.
	var humanoid_map := active_humanoid_map(meta)
	if humanoid_map.is_empty():
		_record_unsupported(source_path, "FBX AssetMeta has no persisted active humanoid bone map")
		return {"valid": false, "fileids": {}}
	var mapped_fileids_by_name: Dictionary = {}
	for fileid_variant in meta.fileid_to_skeleton_bone:
		var fileid := int(fileid_variant)
		if int(meta.fileid_to_utype.get(fileid, 0)) != 4:
			continue
		var mapped_name := String(meta.fileid_to_skeleton_bone[fileid])
		if not mapped_fileids_by_name.has(mapped_name):
			mapped_fileids_by_name[mapped_name] = []
		(mapped_fileids_by_name[mapped_name] as Array).append(fileid)
	var eligible_names: Dictionary = {}
	var valid := true
	for final_name_variant in humanoid_map.values():
		var final_name := String(final_name_variant)
		if final_name.is_empty() or eligible_names.has(final_name):
			_record_mismatch(source_path, final_name,
				"persisted humanoid map has an empty or duplicate final bone name")
			valid = false
			continue
		eligible_names[final_name] = true
	var eligible_fileids: Dictionary = {}
	for final_name_variant in eligible_names:
		var final_name := String(final_name_variant)
		var candidates: Array = mapped_fileids_by_name.get(final_name, [])
		if len(candidates) != 1:
			_record_mismatch(source_path, final_name,
				"persisted humanoid bone must resolve to exactly one mapped Transform fileID")
			valid = false
			continue
		if not originals.has(final_name):
			_record_mismatch(source_path, final_name,
				"persisted humanoid bone lacks its saved original transform")
			valid = false
			continue
		eligible_fileids[int(candidates[0])] = true
	if eligible_fileids.is_empty():
		_record_unsupported(source_path, "FBX metadata yielded zero rotation-required humanoid bones")
		valid = false
	return {"valid": valid, "fileids": eligible_fileids}


static func active_humanoid_map(meta: Resource) -> Dictionary:
	if not meta.autodetected_bone_map_dict.is_empty():
		return meta.autodetected_bone_map_dict
	return meta.humanoid_bone_map_dict


func _is_transform_property(property_path: String) -> bool:
	return TRANSFORM_VALUE_PROPERTIES.has(property_path)


func _is_structural_property(property_path: String) -> bool:
	return property_path == "m_Father" or property_path == "m_RootOrder" \
		or property_path.begins_with("m_Children") \
		or property_path.begins_with("m_Added") \
		or property_path.begins_with("m_Removed")


func _is_known_safe_pose_neutral_property(meta: Resource, fileid: int,
		property_path: String) -> bool:
	if property_path == "m_IsActive" or property_path == "m_Name":
		return int(meta.fileid_to_utype.get(fileid, 0)) == 1
	if property_path.begins_with("m_Materials.Array.data[") and property_path.ends_with("]"):
		var index_text := property_path.trim_prefix("m_Materials.Array.data[").trim_suffix("]")
		return index_text.is_valid_int() and index_text.to_int() >= 0 \
			and (_fileid_has_type(meta, fileid, "SkinnedMeshRenderer") \
			or _fileid_has_type(meta, fileid, "MeshRenderer")
			)
	return false


func _fileid_has_type(meta: Resource, fileid: int, type_name: String) -> bool:
	var fileids: Variant = meta.type_to_fileids.get(type_name, [])
	return fileid in fileids


func _unity_properties_from_godot_source(source: Transform3D, meta: Resource,
		fileid: int) -> Dictionary:
	var godot_quaternion := source.basis.get_rotation_quaternion()
	var unity_quaternion := Quaternion(
		godot_quaternion.x, -godot_quaternion.y, -godot_quaternion.z, godot_quaternion.w)
	var source_scale := source.basis.get_scale()
	if meta.transform_fileid_to_scale_signs.has(fileid):
		var saved_signs: Vector3 = meta.transform_fileid_to_scale_signs[fileid]
		source_scale = source_scale.abs() * saved_signs
	return {
		"m_LocalPosition": source.origin * Vector3(-1.0, 1.0, 1.0),
		"m_LocalRotation": unity_quaternion,
		"m_LocalScale": source_scale,
	}


func _target_bone(instance: Node, meta: Resource, fileid: int, bone_name: String) -> Dictionary:
	if not meta.fileid_to_nodepath.has(fileid):
		return {}
	var nodepath: NodePath = meta.fileid_to_nodepath.get(fileid, NodePath())
	if nodepath == NodePath():
		return {}
	var by_path := instance.get_node_or_null(nodepath) as Skeleton3D
	if by_path != null:
		var by_path_index := by_path.find_bone(bone_name)
		if by_path_index >= 0:
			var collision_index := _source_root_collision_index(
				by_path, by_path_index, bone_name, meta, fileid)
			return {
				"skeleton": by_path,
				"bone_index": collision_index if collision_index >= 0 else by_path_index,
			}
	return {}


func _source_root_collision_index(skeleton: Skeleton3D, exact_index: int,
		bone_name: String, meta: Resource, fileid: int) -> int:
	# When Unidot inserts an identity synthetic root whose name collides with an
	# authored parentless bone, Godot keeps the synthetic exact name and gives the
	# authored bone a numeric suffix.  Resolve only the topology proven by the
	# persisted source parent map; this is not a global name fallback.
	var source_parent_fileid := int(meta.transform_fileid_to_parent_fileid.get(fileid, 0))
	if not String(meta.fileid_to_skeleton_bone.get(source_parent_fileid, "")).is_empty():
		return -1
	var output_parent_index := skeleton.get_bone_parent(exact_index)
	if output_parent_index < 0 or not _pose_within_tolerance(
			Transform3D.IDENTITY, _bone_pose(skeleton, exact_index)):
		return -1
	if skeleton.get_bone_parent(output_parent_index) >= 0:
		return -1
	var parent_name := String(skeleton.get_bone_name(output_parent_index))
	return output_parent_index if _is_numeric_collision_name(parent_name, bone_name) else -1


static func _is_numeric_collision_name(candidate: String, base_name: String) -> bool:
	if candidate.begins_with(base_name + " "):
		return candidate.trim_prefix(base_name + " ").is_valid_int()
	if candidate.begins_with(base_name):
		return candidate.trim_prefix(base_name).is_valid_int()
	return false


func _skinned_skeletons(instance: Node) -> Array:
	var found: Dictionary = {}
	for node_variant in instance.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node_variant as MeshInstance3D
		if mesh_instance.skin == null or mesh_instance.mesh == null:
			continue
		var skeleton := _skeleton_for(mesh_instance)
		if skeleton != null:
			found[skeleton] = true
	return found.keys()


func _skeleton_for(mesh_instance: MeshInstance3D) -> Skeleton3D:
	if not mesh_instance.skeleton.is_empty():
		var by_path := mesh_instance.get_node_or_null(mesh_instance.skeleton) as Skeleton3D
		if by_path != null:
			return by_path
	var parent := mesh_instance.get_parent()
	while parent != null:
		if parent is Skeleton3D:
			return parent
		parent = parent.get_parent()
	return null


func _check_unexplained_bones(source_path: String, instance: Node,
		matched: Dictionary, meta: Resource,
		authored_bone_fileids: Dictionary = {},
		count_synthetic_roots: bool = true) -> void:
	for skeleton_variant in _skinned_skeletons(instance):
		var skeleton := skeleton_variant as Skeleton3D
		var synthetic_candidates: Array[int] = []
		for bone_index in range(skeleton.get_bone_count()):
			if matched.has(_bone_key(skeleton, bone_index)):
				continue
			var bone_name := skeleton.get_bone_name(bone_index)
			var pose := _bone_pose(skeleton, bone_index)
			if bone_name == "Root" and _pose_within_tolerance(Transform3D.IDENTITY, pose):
				synthetic_candidates.append(bone_index)
			else:
				_record_mismatch(source_path, bone_name,
					"skeleton bone has no persisted source mapping/explanation")
		if len(synthetic_candidates) != 1:
			for bone_index in synthetic_candidates:
				_record_mismatch(source_path, skeleton.get_bone_name(bone_index),
					"identity Root is not a unique synthetic-root candidate")
		elif synthetic_root_topology_is_proven(
				skeleton, synthetic_candidates[0], matched, meta, authored_bone_fileids):
			if count_synthetic_roots:
				report["synthetic_roots"] += 1
		else:
			_record_mismatch(source_path, skeleton.get_bone_name(synthetic_candidates[0]),
				"identity Root lacks persisted source/matched-child synthetic provenance")


static func synthetic_root_topology_is_proven(skeleton: Skeleton3D, bone_index: int,
		matched: Dictionary, meta: Resource,
		authored_bone_fileids: Dictionary = {}) -> bool:
	if skeleton == null or bone_index < 0 or bone_index >= skeleton.get_bone_count():
		return false
	var children: PackedInt32Array = skeleton.get_bone_children(bone_index)
	if children.is_empty():
		return false
	var parent_index := skeleton.get_bone_parent(bone_index)
	if parent_index < 0:
		# Normal synthetic wrapper: every output child is matched to a source root.
		for child_index in children:
			var child_key := _bone_key(skeleton, child_index)
			if not matched.has(child_key):
				return false
			var child_fileid := int(matched[child_key])
			var source_parent_fileid := int(
				meta.transform_fileid_to_parent_fileid.get(child_fileid, 0))
			if authored_bone_fileids.has(source_parent_fileid) \
					or not _source_fileid_is_mapped_root(meta, child_fileid):
				return false
		return true
	# Name-collision form: the matched authored source Root was renamed RootN,
	# while the identity profile Root sits between it and the mapped children.
	var parent_key := _bone_key(skeleton, parent_index)
	if not matched.has(parent_key):
		return false
	var parent_fileid := int(matched[parent_key])
	if not _source_fileid_is_mapped_root(meta, parent_fileid) \
			or String(meta.fileid_to_skeleton_bone.get(parent_fileid, "")) != "Root" \
			or skeleton.get_bone_parent(parent_index) >= 0 \
			or not _is_numeric_collision_name(
				String(skeleton.get_bone_name(parent_index)), "Root"):
		return false
	for child_index in children:
		var child_key := _bone_key(skeleton, child_index)
		if not matched.has(child_key):
			return false
		var child_fileid := int(matched[child_key])
		if int(meta.transform_fileid_to_parent_fileid.get(child_fileid, 0)) != parent_fileid:
			return false
	return true


static func _source_fileid_is_mapped_root(meta: Resource, fileid: int) -> bool:
	if int(meta.fileid_to_utype.get(fileid, 0)) != 4 \
			or String(meta.fileid_to_skeleton_bone.get(fileid, "")).is_empty():
		return false
	var parent_fileid := int(meta.transform_fileid_to_parent_fileid.get(fileid, 0))
	return String(meta.fileid_to_skeleton_bone.get(parent_fileid, "")).is_empty()


static func _bone_key(skeleton: Skeleton3D, bone_index: int) -> String:
	return "%s:%d" % [str(skeleton.get_instance_id()), bone_index]


func _bone_pose(skeleton: Skeleton3D, bone_index: int) -> Transform3D:
	return Transform3D(
		Basis(skeleton.get_bone_pose_rotation(bone_index)).scaled(
			skeleton.get_bone_pose_scale(bone_index)),
		skeleton.get_bone_pose_position(bone_index))


func _compare_bone(oracle: String, source_path: String, bone_name: String,
		target: Dictionary, expected: Transform3D, expected_builder: Callable) -> void:
	var skeleton: Skeleton3D = target["skeleton"]
	var bone_index := int(target["bone_index"])
	var actual := _bone_pose(skeleton, bone_index)
	var errors := pose_errors(expected, actual)
	report["compared_bones"] += 1
	if oracle == ORACLE_DIRECT:
		report["direct_yaml_bones"] += 1
	else:
		report["persisted_fbx_bones"] += 1
	_update_max_errors(errors)
	if errors_exceed_tolerance(errors):
		_record_mismatch(source_path, bone_name,
			"%s mismatch: position=%.9fm rotation=%.9fdeg scale=%.9f" % [
				oracle, errors["position"], errors["rotation"], errors["scale"]])
	if not negative_modes_seen.has(oracle):
		negative_modes_seen[oracle] = true
		_run_negative_control(
			oracle, source_path, bone_name, skeleton, bone_index, expected, expected_builder)


func _run_negative_control(oracle: String, source_path: String, bone_name: String,
		skeleton: Skeleton3D, bone_index: int, expected: Transform3D,
		expected_builder: Callable) -> void:
	report["negative_controls_run"] += 1
	var original_position := skeleton.get_bone_pose_position(bone_index)
	var original_actual := _bone_pose(skeleton, bone_index)
	skeleton.set_bone_pose_position(
		bone_index, original_position + Vector3(NEGATIVE_PERTURBATION_METERS, 0.0, 0.0))
	var perturbed := _bone_pose(skeleton, bone_index)
	var detected := errors_exceed_tolerance(pose_errors(expected, perturbed))
	# Rebuild from the independent source builder (YAML or a separately
	# instantiated persisted source model) while the output pose is perturbed.
	# This proves the expected side does not alias or read the target.
	var rebuilt_variant: Variant = expected_builder.call()
	var source_stable := rebuilt_variant is Transform3D \
		and _pose_within_tolerance(expected, rebuilt_variant)
	skeleton.set_bone_pose_position(bone_index, original_position)
	var restored := _pose_within_tolerance(original_actual, _bone_pose(skeleton, bone_index))
	if detected and source_stable and restored:
		report["negative_controls_detected"] += 1
	else:
		_record_mismatch(source_path, bone_name,
			"%s negative control failed (detected=%s source_stable=%s restored=%s)" % [
				oracle, str(detected), str(source_stable), str(restored)])


static func _float_is_finite(value: float) -> bool:
	return not is_nan(value) and not is_inf(value)


static func _vector3_is_finite(value: Vector3) -> bool:
	return _float_is_finite(value.x) and _float_is_finite(value.y) \
		and _float_is_finite(value.z)


static func _quaternion_is_valid(value: Quaternion) -> bool:
	return _float_is_finite(value.x) and _float_is_finite(value.y) \
		and _float_is_finite(value.z) and _float_is_finite(value.w) \
		and value.length_squared() > 1.0e-20


static func _properties_are_finite(properties: Dictionary) -> bool:
	return properties.get("m_LocalPosition") is Vector3 \
		and properties.get("m_LocalRotation") is Quaternion \
		and properties.get("m_LocalScale") is Vector3 \
		and _vector3_is_finite(properties["m_LocalPosition"]) \
		and _quaternion_is_valid(properties["m_LocalRotation"]) \
		and _vector3_is_finite(properties["m_LocalScale"])


static func _transform_is_finite(value: Transform3D) -> bool:
	return _vector3_is_finite(value.origin) and _vector3_is_finite(value.basis.x) \
		and _vector3_is_finite(value.basis.y) and _vector3_is_finite(value.basis.z)


static func quaternion_error_degrees(expected: Quaternion, actual: Quaternion) -> float:
	if not _quaternion_is_valid(expected) or not _quaternion_is_valid(actual):
		return INVALID_ERROR_SENTINEL
	var a := expected.normalized()
	var b := actual.normalized()
	var dot_abs := clampf(absf(a.dot(b)), 0.0, 1.0)
	return rad_to_deg(2.0 * acos(dot_abs))


static func pose_errors(expected: Transform3D, actual: Transform3D) -> Dictionary:
	if not _transform_is_finite(expected) or not _transform_is_finite(actual):
		return {
			"position": INVALID_ERROR_SENTINEL,
			"rotation": INVALID_ERROR_SENTINEL,
			"scale": INVALID_ERROR_SENTINEL,
			"finite": false,
		}
	var expected_scale := expected.basis.get_scale()
	var actual_scale := actual.basis.get_scale()
	var scale_error := maxf(
		maxf(absf(expected_scale.x - actual_scale.x), absf(expected_scale.y - actual_scale.y)),
		absf(expected_scale.z - actual_scale.z))
	return {
		"position": expected.origin.distance_to(actual.origin),
		"rotation": quaternion_error_degrees(
			expected.basis.get_rotation_quaternion(), actual.basis.get_rotation_quaternion()),
		"scale": scale_error,
		"finite": true,
	}


static func errors_exceed_tolerance(errors: Dictionary) -> bool:
	var position := float(errors.get("position", INVALID_ERROR_SENTINEL))
	var rotation := float(errors.get("rotation", INVALID_ERROR_SENTINEL))
	var scale := float(errors.get("scale", INVALID_ERROR_SENTINEL))
	return not bool(errors.get("finite", false)) \
		or not _float_is_finite(position) or not _float_is_finite(rotation) \
		or not _float_is_finite(scale) or position > POSITION_TOLERANCE_METERS \
		or rotation > ROTATION_TOLERANCE_DEGREES or scale > SCALE_TOLERANCE


static func _pose_within_tolerance(expected: Transform3D, actual: Transform3D) -> bool:
	return not errors_exceed_tolerance(pose_errors(expected, actual))


static func report_is_pass(report_value: Dictionary) -> bool:
	var expected_negative_controls := 0
	if int(report_value.get("direct_yaml_prefabs", 0)) > 0:
		expected_negative_controls += 1
	if int(report_value.get("persisted_fbx_prefabs", 0)) > 0:
		expected_negative_controls += 1
	return int(report_value.get("discovered_skin_prefabs", 0)) > 0 \
		and int(report_value.get("output_skin_prefabs", 0)) == int(report_value.get("discovered_skin_prefabs", 0)) \
		and int(report_value.get("source_without_output", 0)) == 0 \
		and int(report_value.get("output_without_source", 0)) == 0 \
		and int(report_value.get("checked_prefabs", 0)) == int(report_value.get("discovered_skin_prefabs", 0)) \
		and int(report_value.get("direct_yaml_prefabs", 0)) + int(report_value.get("persisted_fbx_prefabs", 0)) == int(report_value.get("checked_prefabs", 0)) \
		and int(report_value.get("unsupported_prefabs", 0)) == 0 \
		and int(report_value.get("compared_bones", 0)) > 0 \
		and int(report_value.get("direct_yaml_bones", 0)) \
			+ int(report_value.get("persisted_fbx_bones", 0)) \
			== int(report_value.get("compared_bones", 0)) \
		and (int(report_value.get("persisted_fbx_prefabs", 0)) == 0 \
			or int(report_value.get("saved_fbx_meta_rotation_checks", 0)) > 0) \
		and int(report_value.get("saved_fbx_meta_required_rotation_checks", 0)) \
			== int(report_value.get("saved_fbx_meta_rotation_required_bones", 0)) \
		and int(report_value.get("saved_fbx_meta_rotation_checks", 0)) \
			+ int(report_value.get("persisted_fbx_composition_only_bones", 0)) \
			== int(report_value.get("persisted_fbx_bones", 0)) \
		and int(report_value.get("mismatches", 0)) == 0 \
		and int(report_value.get("mismatched_prefabs", 0)) == 0 \
		and int(report_value.get("mismatched_bones", 0)) == 0 \
		and int(report_value.get("negative_controls_run", 0)) == expected_negative_controls \
		and int(report_value.get("negative_controls_detected", 0)) == expected_negative_controls


func _update_max_errors(errors: Dictionary) -> void:
	report["max_position_error_meters"] = maxf(
		float(report["max_position_error_meters"]), float(errors["position"]))
	report["max_rotation_error_degrees"] = maxf(
		float(report["max_rotation_error_degrees"]), float(errors["rotation"]))
	report["max_scale_error"] = maxf(
		float(report["max_scale_error"]), float(errors["scale"]))


func _record_mismatch(source_path: String, bone_name: String, message: String) -> void:
	report["mismatches"] += 1
	mismatch_prefab_paths[source_path] = true
	report["mismatched_prefabs"] = len(mismatch_prefab_paths)
	var where := source_path
	if not bone_name.is_empty():
		mismatch_bone_paths[source_path + "\n" + bone_name] = true
		report["mismatched_bones"] = len(mismatch_bone_paths)
		where += " / " + bone_name
	_append_failure(where + ": " + message)


func _record_unsupported(source_path: String, message: String) -> void:
	report["unsupported_prefabs"] += 1
	mismatch_prefab_paths[source_path] = true
	report["mismatched_prefabs"] = len(mismatch_prefab_paths)
	_append_failure(source_path + ": unsupported: " + message)


func _append_failure(message: String) -> void:
	var failures: Array = report["failures"]
	if len(failures) < FAILURE_LIMIT:
		failures.append(message)


func _fatal(message: String) -> void:
	_append_failure(message)
	report["result"] = "FAIL"
	_print_report()
	quit(1)


func _finalize() -> void:
	report["result"] = "PASS" if report_is_pass(report) else "FAIL"
	_print_report()
	quit(0 if report["result"] == "PASS" else 1)


func _print_report() -> void:
	print("=== Unity source pose consistency")
	print("  source prefabs scanned    %d" % int(report["source_prefabs_scanned"]))
	print("  source skin prefabs      %d" % int(report["discovered_skin_prefabs"]))
	print("  output skin prefabs      %d" % int(report["output_skin_prefabs"]))
	print("  source/output differences %d missing / %d unexplained" % [
		int(report["source_without_output"]), int(report["output_without_source"])])
	print("  prefabs checked          %d" % int(report["checked_prefabs"]))
	print("  direct YAML oracle       %d prefabs / %d bones" % [
		int(report["direct_yaml_prefabs"]), int(report["direct_yaml_bones"])])
	print("  persisted FBX composition %d prefabs / %d bones (weaker)" % [
		int(report["persisted_fbx_prefabs"]), int(report["persisted_fbx_bones"])])
	print("  saved FBX rotation checks %d total; %d/%d required; %d composition-only" % [
		int(report["saved_fbx_meta_rotation_checks"]),
		int(report["saved_fbx_meta_required_rotation_checks"]),
		int(report["saved_fbx_meta_rotation_required_bones"]),
		int(report["persisted_fbx_composition_only_bones"])])
	print("  synthetic identity roots %d" % int(report["synthetic_roots"]))
	print("  total compared bones     %d" % int(report["compared_bones"]))
	print("  unsupported prefabs      %d" % int(report["unsupported_prefabs"]))
	print("  mismatches               %d events / %d prefabs / %d bones" % [
		int(report["mismatches"]), int(report["mismatched_prefabs"]),
		int(report["mismatched_bones"])])
	print("  negative controls        %d/%d detected" % [
		int(report["negative_controls_detected"]), int(report["negative_controls_run"])])
	print("  tolerances               position=%.9fm rotation=%.9fdeg scale=%.9f" % [
		POSITION_TOLERANCE_METERS, ROTATION_TOLERANCE_DEGREES, SCALE_TOLERANCE])
	print("  maximum observed errors  position=%.9fm rotation=%.9fdeg scale=%.9f" % [
		float(report["max_position_error_meters"]),
		float(report["max_rotation_error_degrees"]), float(report["max_scale_error"])])
	for failure in (report["failures"] as Array).slice(0, 20):
		print("    ", failure)
	print("RESULT: ", report["result"])
	print(RESULT_PREFIX + JSON.stringify(report))

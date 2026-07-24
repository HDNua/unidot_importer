extends SceneTree

const CONVERT_SCENE := preload("res://addons/unidot_importer/convert_scene.gd")
const OBJECT_ADAPTER := preload("res://addons/unidot_importer/object_adapter.gd")
const SETTINGS_META := &"unidot_lighting_settings"


class FakeDatabase:
	extends Resource
	var enable_unidot_keys := false


class FakeMeta:
	extends Resource
	var guid := "lighting-settings-test"
	var main_object_id := 4242
	var failures: Array[String] = []
	var warnings: Array[String] = []
	var external_resource: Resource
	var database := FakeDatabase.new()

	func get_main_object_name() -> String:
		return "SyntheticLightingSettings"

	func get_database() -> Resource:
		return database

	func get_godot_resource(
		unidot_ref: Array,
		_silent: bool = false
	) -> Resource:
		if unidot_ref.size() >= 2 and int(unidot_ref[1]) != 0:
			return external_resource
		return null

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


func _initialize() -> void:
	var adapter := OBJECT_ADAPTER.new()
	var meta := FakeMeta.new()
	var external = adapter.instantiate_unidot_object(
		meta,
		meta.main_object_id,
		850595691,
		"LightingSettings"
	)
	external.keys = {
		"m_Name": "SyntheticLightingSettings",
		"serializedVersion": 3,
		"m_EnableBakedLightmaps": 1,
		"m_EnableRealtimeLightmaps": 0,
		"m_BounceScale": 1.0,
		"m_IndirectOutputScale": 1.0,
		"m_LightmapMaxSize": 1024,
		"m_BakeResolution": 40.0,
		"m_LightmapsBakeMode": 1,
		"m_PVRBounces": 2,
	}
	if external.type != "LightingSettings" or not meta.failures.is_empty():
		_fail("LightingSettings class ID was not registered without a failure.")
		return
	if external.get_godot_extension() != ".lighting.tres":
		_fail("LightingSettings did not choose a stable Godot resource suffix.")
		return

	meta.external_resource = external.create_godot_resource()
	if (
		meta.external_resource == null
		or not meta.external_resource.has_meta(SETTINGS_META)
	):
		_fail("LightingSettings did not preserve normalized authoring metadata.")
		return
	var roundtrip_path := "res://unidot_lighting_settings_test.tres"
	if ResourceSaver.save(meta.external_resource, roundtrip_path) != OK:
		_fail("LightingSettings resource could not be saved.")
		return
	meta.external_resource = ResourceLoader.load(
		roundtrip_path,
		"",
		ResourceLoader.CACHE_MODE_IGNORE
	)
	DirAccess.open("res://").remove(roundtrip_path)
	if (
		meta.external_resource == null
		or not meta.external_resource.has_meta(SETTINGS_META)
	):
		_fail("LightingSettings metadata did not survive a resource round trip.")
		return

	var lightmap_settings = adapter.instantiate_unidot_object(
		meta,
		3,
		157,
		"LightmapSettings"
	)
	lightmap_settings.keys = {
		"m_GISettings": {
			"m_EnableBakedLightmaps": 0,
			"m_BounceScale": 0.5,
			"m_IndirectOutputScale": 0.5,
		},
		"m_LightmapEditorSettings": {
			"m_AtlasSize": 4096,
			"m_BakeResolution": 10.0,
			"m_LightmapsBakeMode": 0,
			"m_PVRBounces": 1,
		},
		"m_LightingSettings": [null, meta.main_object_id, meta.guid, 2],
	}

	var converter := CONVERT_SCENE.new()
	var normalized: Dictionary = converter.get_lighting_settings(
		lightmap_settings
	)
	if not bool(normalized.get("enable_baked_lightmaps", false)):
		_fail("External LightingSettings did not override inline scene settings.")
		return

	var lightmap := LightmapGI.new()
	converter.configure_lightmap_gi(lightmap, normalized, lightmap_settings)
	if lightmap.bounces != 2:
		_fail("Unity PVR bounce count was not mapped.")
		return
	if not is_equal_approx(lightmap.bounce_indirect_energy, 1.0):
		_fail("Unity indirect energy was not mapped.")
		return
	if not lightmap.directional:
		_fail("Unity directional lightmap mode was not mapped.")
		return
	if not is_equal_approx(lightmap.texel_scale, 0.025):
		_fail("Unity bake resolution was not converted to texel scale.")
		return
	if lightmap.max_texture_size != 2048:
		_fail("Unity lightmap size was not clamped to Godot's supported range.")
		return
	if not _warning_contains(meta.warnings, "lightmap size 1024"):
		_fail("A lossy lightmap-size clamp did not emit a warning.")
		return

	meta.warnings.clear()
	var realtime_only_settings := normalized.duplicate(true)
	realtime_only_settings["enable_baked_lightmaps"] = false
	realtime_only_settings["enable_realtime_lightmaps"] = true
	var realtime_lightmap := LightmapGI.new()
	converter.configure_lightmap_gi(
		realtime_lightmap,
		realtime_only_settings,
		lightmap_settings
	)
	if not _warning_contains(meta.warnings, "realtime lightmaps"):
		_fail("Unsupported Unity realtime GI did not emit a warning.")
		return
	if not realtime_lightmap.has_meta(SETTINGS_META):
		_fail("Realtime-only Unity lighting intent was not preserved as metadata.")
		return
	var preserved_realtime_settings: Variant = realtime_lightmap.get_meta(
		SETTINGS_META
	)
	if (
		typeof(preserved_realtime_settings) != TYPE_DICTIONARY
		or not bool(
			preserved_realtime_settings.get(
				"enable_realtime_lightmaps",
				false
			)
		)
	):
		_fail("Preserved realtime-only lighting metadata was invalid.")
		return
	if not realtime_lightmap.editor_description.contains("realtime-GI"):
		_fail("Realtime-only authoring intent was not visible on the Godot node.")
		return
	if not converter.keeps_lighting_authoring_settings(
		realtime_only_settings
	):
		_fail("A realtime-only scene would discard its authoring placeholder.")
		return

	lightmap.free()
	realtime_lightmap.free()
	print("UNIDOT_LIGHTING_SETTINGS_TEST_PASS")
	quit(0)


func _warning_contains(warnings: Array[String], needle: String) -> bool:
	for warning in warnings:
		if warning.contains(needle):
			return true
	return false


func _fail(message: String) -> void:
	push_error("UNIDOT_LIGHTING_SETTINGS_TEST_FAIL: " + message)
	quit(1)

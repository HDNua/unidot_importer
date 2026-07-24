extends SceneTree

const OBJECT_ADAPTER := preload("res://addons/unidot_importer/object_adapter.gd")


class FakeDatabase:
	extends Resource
	var enable_unidot_keys := false


class FakeMeta:
	extends Resource
	var guid := "material-test"
	var main_object_id := 2100000
	var textures: Dictionary = {}
	var database := FakeDatabase.new()

	func get_main_object_name() -> String:
		return "MaterialTextureMappingTest"

	func get_database() -> Resource:
		return database

	func get_godot_resource(unidot_ref: Array, _silent: bool = false) -> Resource:
		if unidot_ref.size() < 3 or int(unidot_ref[1]) == 0:
			return null
		return textures.get(str(unidot_ref[2]))

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
		_message: String,
		_field: String = "",
		_remote_ref: Variant = null
	) -> void:
		pass


func _initialize() -> void:
	var meta := FakeMeta.new()
	var albedo := _new_texture(Color(0.8, 0.1, 0.2))
	var hair_mask := _new_texture(Color(0.1, 0.8, 0.2))
	var normal := _new_texture(Color(0.5, 0.5, 1.0))
	var emission := _new_texture(Color(0.2, 0.3, 0.9))
	var grid := _new_texture(Color(0.8, 0.8, 0.8))
	var main_tex := _new_texture(Color(0.9, 0.7, 0.1))
	meta.textures = {
		"albedo": albedo,
		"hair-mask": hair_mask,
		"normal": normal,
		"emission": emission,
		"grid": grid,
		"main": main_tex,
	}

	var alias_material := _create_material(
		meta,
		[
			_tex_env("_Hair_Mask", "hair-mask"),
			_tex_env("_Emission_Map", "emission"),
			_tex_env("_Normal_Map", "normal"),
			_tex_env("_MainTex", "", Vector2.ONE, Vector2.ZERO, 0),
			_tex_env(
				"_Albedo_Map",
				"albedo",
				Vector2(2.0, 3.0),
				Vector2(0.25, 0.5)
			),
		],
		[
			{"_Base_Color": Color(0.25, 0.5, 0.75, 1.0)},
			{"_Emission_Color": Color(2.0, 1.0, 0.5, 1.0)},
		],
		"_EMISSION"
	)
	if alias_material.albedo_texture != albedo:
		_fail("_Albedo_Map was not selected ahead of mask textures.")
		return
	if not alias_material.albedo_color.is_equal_approx(
		Color(0.25, 0.5, 0.75, 1.0)
	):
		_fail("_Base_Color was not mapped to albedo_color.")
		return
	if not alias_material.uv1_scale.is_equal_approx(Vector3(2.0, 3.0, 0.0)):
		_fail("_Albedo_Map scale was not preserved.")
		return
	if not alias_material.uv1_offset.is_equal_approx(Vector3(0.25, 0.5, 0.0)):
		_fail("_Albedo_Map offset was not preserved.")
		return
	if (
		not alias_material.normal_enabled
		or alias_material.normal_texture != normal
	):
		_fail("_Normal_Map was not mapped to the normal texture.")
		return
	if (
		not alias_material.emission_enabled
		or alias_material.emission_texture != emission
	):
		_fail("_Emission_Map was not mapped to the emission texture.")
		return

	var fallback_material := _create_material(
		meta,
		[_tex_env("_Grid", "grid")],
		[]
	)
	if fallback_material.albedo_texture != grid:
		_fail("A safe legacy albedo fallback was not preserved.")
		return

	var base_map_material := _create_material(
		meta,
		[
			_tex_env("_Skin_Mask", "hair-mask"),
			_tex_env("_Base_Map", "albedo"),
		],
		[]
	)
	if base_map_material.albedo_texture != albedo:
		_fail("_Base_Map was not selected ahead of mask textures.")
		return

	var non_albedo_material := _create_material(
		meta,
		[
			_tex_env("_Skin_Mask", "hair-mask"),
			_tex_env("_Normal_Map", "normal"),
			_tex_env("_Emission_Map", "emission"),
		],
		[]
	)
	if non_albedo_material.albedo_texture != null:
		_fail("A non-albedo texture was incorrectly selected as albedo.")
		return

	var main_texture_material := _create_material(
		meta,
		[
			_tex_env("_Grid", "grid"),
			_tex_env("_MainTex", "main"),
		],
		[]
	)
	if main_texture_material.albedo_texture != main_tex:
		_fail("The existing _MainTex preference regressed.")
		return

	print("UNIDOT_MATERIAL_TEXTURE_MAPPING_TEST_PASS")
	quit(0)


func _create_material(
	meta: FakeMeta,
	texture_properties: Array,
	color_properties: Array,
	keywords: String = ""
) -> StandardMaterial3D:
	var adapter := OBJECT_ADAPTER.new()
	var material = adapter.instantiate_unidot_object(
		meta,
		meta.main_object_id,
		0,
		"Material"
	)
	material.keys = {
		"m_Name": "SyntheticMaterial",
		"m_ShaderKeywords": keywords,
		"m_SavedProperties": {
			"m_TexEnvs": texture_properties,
			"m_Colors": color_properties,
			"m_Floats": [],
		},
	}
	return material.create_godot_resource() as StandardMaterial3D


func _tex_env(
	property_name: String,
	texture_guid: String,
	scale: Vector2 = Vector2.ONE,
	offset: Vector2 = Vector2.ZERO,
	file_id: int = 2800000
) -> Dictionary:
	return {
		property_name: {
			"m_Texture": [null, file_id, texture_guid, 0],
			"m_Scale": scale,
			"m_Offset": offset,
		},
	}


func _new_texture(color: Color) -> ImageTexture:
	var image := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _fail(message: String) -> void:
	push_error("UNIDOT_MATERIAL_TEXTURE_MAPPING_TEST_FAIL: " + message)
	quit(1)

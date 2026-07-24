# This file is part of Unidot Importer. See LICENSE.txt for full MIT license.
# Copyright (c) 2021-present Lyuma <xn.lyuma@gmail.com> and contributors
# SPDX-License-Identifier: MIT
@tool
extends RefCounted

# Unity ParticleSystem and Godot GPUParticles3D do not have a one-to-one model.
# This converter deliberately maps the common, deterministic subset and reports
# every enabled module that would otherwise be silently discarded.

const SHARED_COMPONENT_KEYS_META := &"_unidot_particle_component_keys"

const _KNOWN_MODULES := [
	"RotationModule",
	"UVModule",
	"VelocityModule",
	"InheritVelocityModule",
	"ForceModule",
	"ExternalForcesModule",
	"ClampVelocityModule",
	"NoiseModule",
	"SizeBySpeedModule",
	"RotationBySpeedModule",
	"ColorBySpeedModule",
	"CollisionModule",
	"TriggerModule",
	"SubModule",
	"LightsModule",
	"TrailModule",
	"CustomDataModule",
]


static func store_component_keys(
	particles: GPUParticles3D,
	component_type: String,
	keys: Dictionary,
	expose_unidot_keys: bool,
) -> void:
	var component_keys: Dictionary = particles.get_meta(SHARED_COMPONENT_KEYS_META, {}).duplicate(true)
	component_keys[component_type] = keys.duplicate(true)
	particles.set_meta(SHARED_COMPONENT_KEYS_META, component_keys)
	if expose_unidot_keys:
		# A shared particle node represents two Unity components. Keep both
		# payloads instead of letting the later component overwrite the former.
		particles.set_meta("unidot_keys", component_keys.duplicate(true))


static func get_component_keys(
	particles: GPUParticles3D,
	component_type: String,
	fallback: Dictionary,
) -> Dictionary:
	var component_keys: Dictionary = particles.get_meta(SHARED_COMPONENT_KEYS_META, {})
	return component_keys.get(component_type, fallback).duplicate(true)


static func merge_property_overrides(baseline: Dictionary, overrides: Dictionary) -> Dictionary:
	var merged := baseline.duplicate(true)
	for property_path in overrides:
		var tokens := _property_path_tokens(str(property_path))
		merged = _set_nested_property(merged, tokens, overrides[property_path])
	return merged


static func apply_converted_properties(
	particles: GPUParticles3D,
	props: Dictionary,
	resolve_resource: Callable = Callable(),
	warn: Callable = Callable(),
) -> void:
	if props.has("_unidot_particle_system_keys"):
		var system_keys: Dictionary = props["_unidot_particle_system_keys"]
		configure_system(particles, system_keys, warn)
		store_component_keys(particles, "ParticleSystem", system_keys, particles.has_meta("unidot_keys"))
	if props.has("_unidot_particle_renderer_keys"):
		var renderer_keys: Dictionary = props["_unidot_particle_renderer_keys"]
		configure_renderer(particles, renderer_keys, resolve_resource, warn)
		store_component_keys(particles, "ParticleSystemRenderer", renderer_keys, particles.has_meta("unidot_keys"))


static func configure_system(particles: GPUParticles3D, keys: Dictionary, warn: Callable = Callable()) -> void:
	var initial: Dictionary = keys.get("InitialModule", {})
	var emission: Dictionary = keys.get("EmissionModule", {})
	var shape: Dictionary = keys.get("ShapeModule", {})

	var lifetime_range := _curve_range(initial.get("startLifetime", {}))
	particles.lifetime = maxf(0.001, lifetime_range.y)
	particles.randomness = clampf(
		1.0 - maxf(0.0, lifetime_range.x) / particles.lifetime,
		0.0,
		1.0
	)
	particles.one_shot = int(keys.get("looping", 1)) == 0
	particles.speed_scale = maxf(0.0, float(keys.get("simulationSpeed", 1.0)))
	particles.local_coords = int(keys.get("moveWithTransform", 1)) != 0
	particles.preprocess = particles.lifetime if int(keys.get("prewarm", 0)) != 0 and not particles.one_shot else 0.0
	particles.emitting = int(keys.get("playOnAwake", 1)) != 0

	var max_particles := maxi(1, int(initial.get("maxNumParticles", 1000)))
	var rate_range := _curve_range(emission.get("rateOverTime", {}))
	var active_particles := clampi(int(ceil(maxf(0.0, rate_range.y) * particles.lifetime)), 1, max_particles)
	particles.amount = active_particles
	particles.amount_ratio = 1.0 if int(emission.get("enabled", 0)) != 0 else 0.0

	var process := ParticleProcessMaterial.new()
	process.direction = Vector3(0.0, 0.0, -1.0)

	var speed_range := _curve_range(initial.get("startSpeed", {}))
	process.initial_velocity_min = speed_range.x
	process.initial_velocity_max = speed_range.y

	var rotation_range := _curve_range(initial.get("startRotation", {}))
	process.angle_min = rad_to_deg(rotation_range.x)
	process.angle_max = rad_to_deg(rotation_range.y)
	if int(initial.get("randomizeRotationDirection", 0)) != 0:
		var max_angle := maxf(absf(process.angle_min), absf(process.angle_max))
		process.angle_min = -max_angle
		process.angle_max = max_angle

	var gravity_range := _curve_range(initial.get("gravityModifier", {}))
	process.gravity = Vector3(0.0, -9.80665 * gravity_range.y, 0.0)

	var start_size := _curve_range(initial.get("startSize", {}))
	process.scale_min = maxf(0.0, start_size.x)
	process.scale_max = maxf(process.scale_min, start_size.y)

	var start_color: Dictionary = initial.get("startColor", {})
	process.color = _dictionary_to_color(start_color.get("maxColor", Color.WHITE))
	if int(initial.get("size3D", 0)) != 0:
		_warn(warn, "InitialModule 3D start size is approximated with its X value.")
	if int(initial.get("rotation3D", 0)) != 0:
		_warn(warn, "InitialModule 3D start rotation is approximated with its Z value.")

	if int(shape.get("enabled", 0)) != 0:
		_configure_shape(process, shape, warn)

	var color_module: Dictionary = keys.get("ColorModule", {})
	if int(color_module.get("enabled", 0)) != 0:
		var gradient := _gradient_texture(color_module.get("gradient", {}).get("maxGradient", {}))
		if gradient != null:
			process.color_ramp = gradient

	var size_module: Dictionary = keys.get("SizeModule", {})
	if int(size_module.get("enabled", 0)) != 0:
		var scale_curve := _curve_texture(size_module.get("curve", {}))
		if scale_curve != null:
			process.scale_curve = scale_curve
		if int(size_module.get("separateAxes", 0)) != 0:
			_warn(warn, "Particle SizeModule separateAxes is approximated with its X curve.")

	particles.process_material = process

	if int(emission.get("m_BurstCount", 0)) > 0 or not emission.get("m_Bursts", []).is_empty():
		_warn(warn, "Particle emission bursts are not supported; rateOverTime was preserved.")
	if _curve_range(emission.get("rateOverDistance", {})).y != 0.0:
		_warn(warn, "Particle EmissionModule rateOverDistance is not supported.")

	for module_name in _KNOWN_MODULES:
		var module: Variant = keys.get(module_name, {})
		if module is Dictionary and int(module.get("enabled", 0)) != 0:
			_warn(warn, "Enabled particle module " + module_name + " is not supported yet.")


static func configure_renderer(
	particles: GPUParticles3D,
	keys: Dictionary,
	resolve_resource: Callable = Callable(),
	warn: Callable = Callable(),
) -> void:
	particles.visible = int(keys.get("m_Enabled", 1)) != 0
	var layer := int(keys.get("m_Layer", 0))
	particles.layers = (1 << layer) if layer < 24 else (1 << (layer - 8)) | (1 << layer)
	match int(keys.get("m_CastShadows", 1)):
		0:
			particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		2:
			particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_DOUBLE_SIDED
		3:
			particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		_:
			particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

	var material: Material = null
	var materials: Array = keys.get("m_Materials", [])
	if not materials.is_empty() and resolve_resource.is_valid():
		material = resolve_resource.call(materials[0]) as Material

	var render_mode := int(keys.get("m_RenderMode", 0))
	var draw_mesh: Mesh = null
	match render_mode:
		0, 1, 2, 3:
			var quad := QuadMesh.new()
			if render_mode == 1:
				quad.size = Vector2(1.0, maxf(0.001, float(keys.get("m_LengthScale", 2.0))))
				_warn(warn, "Stretched particle billboard is approximated with a length-scaled camera-facing quad.")
			quad.material = _particle_material(material, true, warn)
			draw_mesh = quad
			if render_mode == 2 or render_mode == 3:
				_warn(warn, "Horizontal/vertical particle billboard alignment is approximated as camera-facing.")
		4:
			if resolve_resource.is_valid():
				draw_mesh = resolve_resource.call(keys.get("m_Mesh", [null, 0, "", 0])) as Mesh
			if draw_mesh == null:
				_warn(warn, "Particle mesh render mode has no resolvable mesh; using a billboard quad.")
				var fallback_quad := QuadMesh.new()
				fallback_quad.material = _particle_material(material, true, warn)
				draw_mesh = fallback_quad
			elif material != null:
				draw_mesh = draw_mesh.duplicate()
				var mesh_material := _particle_material(material, false, warn)
				for surface_index in range(draw_mesh.get_surface_count()):
					draw_mesh.surface_set_material(surface_index, mesh_material)
		5:
			particles.visible = false
		_:
			_warn(warn, "Unknown Unity particle render mode " + str(render_mode) + "; using a billboard quad.")
			var fallback_quad := QuadMesh.new()
			fallback_quad.material = _particle_material(material, true, warn)
			draw_mesh = fallback_quad

	if draw_mesh != null:
		particles.draw_passes = 1
		particles.draw_pass_1 = draw_mesh


static func _configure_shape(process: ParticleProcessMaterial, shape: Dictionary, warn: Callable) -> void:
	var shape_type := int(shape.get("type", 0))
	var radius := _scalar_value(shape.get("radius", {}), 1.0)
	match shape_type:
		0, 1, 2, 3:
			process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
			process.emission_sphere_radius = maxf(0.0, radius)
			if shape_type == 1 or shape_type == 3:
				_warn(warn, "Sphere-shell particle shape is approximated as a filled sphere.")
			if shape_type == 2 or shape_type == 3:
				_warn(warn, "Hemisphere particle shape is approximated as a sphere.")
		4, 7, 8, 9:
			process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			process.emission_ring_axis = Vector3(0.0, 0.0, -1.0)
			process.emission_ring_radius = maxf(0.0, radius)
			process.emission_ring_inner_radius = maxf(0.0, radius) if shape_type == 7 or shape_type == 9 else 0.0
			process.emission_ring_height = maxf(0.0, float(shape.get("length", 0.0))) if shape_type == 8 or shape_type == 9 else 0.0
			process.emission_ring_cone_angle = deg_to_rad(float(shape.get("angle", 25.0)))
		5, 15, 16:
			process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			process.emission_box_extents = Vector3(
				maxf(0.0, float(shape.get("boxX", 1.0))) * 0.5,
				maxf(0.0, float(shape.get("boxY", 1.0))) * 0.5,
				maxf(0.0, float(shape.get("boxZ", 1.0))) * 0.5
			)
			if shape_type != 5:
				_warn(warn, "Box shell/edge particle shape is approximated as a filled box.")
		10, 11:
			process.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_RING
			process.emission_ring_axis = Vector3(0.0, 0.0, -1.0)
			process.emission_ring_radius = maxf(0.0, radius)
			process.emission_ring_inner_radius = maxf(0.0, radius) if shape_type == 11 else 0.0
			process.emission_ring_height = 0.0
			process.emission_ring_cone_angle = 0.0
		_:
			_warn(warn, "Unity particle shape type " + str(shape_type) + " is not supported; using point emission.")

	process.spread = float(shape.get("angle", 0.0))


static func _curve_range(curve_data: Variant) -> Vector2:
	if not curve_data is Dictionary:
		var scalar := float(curve_data)
		return Vector2(scalar, scalar)
	var data: Dictionary = curve_data
	var state := int(data.get("minMaxState", 0))
	var scalar := float(data.get("scalar", data.get("value", 0.0)))
	var min_scalar := float(data.get("minScalar", scalar))
	match state:
		0:
			return Vector2(scalar, scalar)
		3:
			return Vector2(minf(min_scalar, scalar), maxf(min_scalar, scalar))
		1:
			return _sampled_curve_range(data.get("maxCurve", {}), scalar)
		2:
			var min_range := _sampled_curve_range(data.get("minCurve", {}), min_scalar)
			var max_range := _sampled_curve_range(data.get("maxCurve", {}), scalar)
			return Vector2(minf(min_range.x, max_range.x), maxf(min_range.y, max_range.y))
		_:
			return Vector2(minf(min_scalar, scalar), maxf(min_scalar, scalar))


static func _sampled_curve_range(curve_data: Variant, multiplier: float) -> Vector2:
	if not curve_data is Dictionary:
		return Vector2(multiplier, multiplier)
	var points: Array = curve_data.get("m_Curve", [])
	if points.is_empty():
		return Vector2(multiplier, multiplier)
	var low := INF
	var high := -INF
	for point in points:
		if point is Dictionary:
			var value := float(point.get("value", 0.0)) * multiplier
			low = minf(low, value)
			high = maxf(high, value)
	return Vector2(low, high) if low != INF else Vector2(multiplier, multiplier)


static func _scalar_value(value: Variant, fallback: float) -> float:
	if value is Dictionary:
		if value.has("value"):
			return float(value.get("value", fallback))
		return _curve_range(value).y
	if value == null:
		return fallback
	return float(value)


static func _curve_texture(curve_data: Variant) -> CurveTexture:
	if not curve_data is Dictionary:
		return null
	var data: Dictionary = curve_data
	var curve_dict: Dictionary = data.get("maxCurve", {})
	var points: Array = curve_dict.get("m_Curve", [])
	if points.is_empty():
		return null
	var multiplier := float(data.get("scalar", 1.0))
	var curve := Curve.new()
	curve.min_value = -1024.0
	curve.max_value = 1024.0
	for point in points:
		if point is Dictionary:
			curve.add_point(Vector2(
				clampf(float(point.get("time", 0.0)), 0.0, 1.0),
				float(point.get("value", 0.0)) * multiplier
			))
	var texture := CurveTexture.new()
	texture.curve = curve
	return texture


static func _gradient_texture(gradient_data: Variant) -> GradientTexture1D:
	if not gradient_data is Dictionary:
		return null
	var data: Dictionary = gradient_data
	var color_count := clampi(int(data.get("m_NumColorKeys", 0)), 0, 8)
	var alpha_count := clampi(int(data.get("m_NumAlphaKeys", 0)), 0, 8)
	if color_count == 0 and alpha_count == 0:
		return null

	var offsets: Array[float] = []
	for index in range(color_count):
		offsets.append(float(data.get("ctime" + str(index), 0)) / 65535.0)
	for index in range(alpha_count):
		var alpha_offset := float(data.get("atime" + str(index), 0)) / 65535.0
		if not offsets.has(alpha_offset):
			offsets.append(alpha_offset)
	offsets.sort()

	var packed_offsets := PackedFloat32Array()
	var packed_colors := PackedColorArray()
	for offset in offsets:
		var rgb := _sample_gradient_color(data, color_count, offset)
		rgb.a = _sample_gradient_alpha(data, alpha_count, offset)
		packed_offsets.append(offset)
		packed_colors.append(rgb)
	if packed_offsets.size() == 1:
		packed_offsets.append(1.0 if packed_offsets[0] < 1.0 else 0.0)
		packed_colors.append(packed_colors[0])
		if packed_offsets[0] > packed_offsets[1]:
			packed_offsets.reverse()
			packed_colors.reverse()

	var gradient := Gradient.new()
	gradient.offsets = packed_offsets
	gradient.colors = packed_colors
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


static func _sample_gradient_color(data: Dictionary, count: int, offset: float) -> Color:
	if count <= 0:
		return Color.WHITE
	var previous_offset := float(data.get("ctime0", 0)) / 65535.0
	var previous_color := _dictionary_to_color(data.get("key0", Color.WHITE))
	for index in range(1, count):
		var next_offset := float(data.get("ctime" + str(index), 0)) / 65535.0
		var next_color := _dictionary_to_color(data.get("key" + str(index), Color.WHITE))
		if offset <= next_offset:
			var weight := inverse_lerp(previous_offset, next_offset, offset) if next_offset > previous_offset else 0.0
			return previous_color.lerp(next_color, weight)
		previous_offset = next_offset
		previous_color = next_color
	return previous_color


static func _sample_gradient_alpha(data: Dictionary, count: int, offset: float) -> float:
	if count <= 0:
		return 1.0
	var previous_offset := float(data.get("atime0", 0)) / 65535.0
	var previous_alpha := _dictionary_to_color(data.get("key0", Color.WHITE)).a
	for index in range(1, count):
		var next_offset := float(data.get("atime" + str(index), 0)) / 65535.0
		var next_alpha := _dictionary_to_color(data.get("key" + str(index), Color.WHITE)).a
		if offset <= next_offset:
			var weight := inverse_lerp(previous_offset, next_offset, offset) if next_offset > previous_offset else 0.0
			return lerpf(previous_alpha, next_alpha, weight)
		previous_offset = next_offset
		previous_alpha = next_alpha
	return previous_alpha


static func _dictionary_to_color(value: Variant) -> Color:
	if value is Color:
		return value
	if value is Dictionary:
		return Color(
			float(value.get("r", 1.0)),
			float(value.get("g", 1.0)),
			float(value.get("b", 1.0)),
			float(value.get("a", 1.0))
		)
	return Color.WHITE


static func _property_path_tokens(property_path: String) -> Array:
	var tokens: Array = []
	var pieces := property_path.split(".")
	for piece_index in range(pieces.size()):
		var piece: String = pieces[piece_index]
		if piece == "Array":
			if piece_index + 1 < pieces.size() and pieces[piece_index + 1] == "size":
				continue
			continue
		if piece == "size" and piece_index > 0 and pieces[piece_index - 1] == "Array":
			tokens.append(&"__array_size__")
		elif piece.begins_with("data[") and piece.ends_with("]"):
			tokens.append(piece.substr(5, piece.length() - 6).to_int())
		else:
			tokens.append(piece)
	return tokens


static func _set_nested_property(container: Variant, tokens: Array, value: Variant) -> Variant:
	if tokens.is_empty():
		return value
	var token: Variant = tokens[0]
	var remaining: Array = tokens.slice(1)
	if token is StringName and token == &"__array_size__":
		var resized: Array = container if container is Array else []
		resized.resize(maxi(0, int(value)))
		return resized
	if token is int:
		var array_value: Array = container if container is Array else []
		var index := int(token)
		if index < 0:
			return array_value
		if array_value.size() <= index:
			array_value.resize(index + 1)
		array_value[index] = _set_nested_property(
			array_value[index],
			remaining,
			value
		)
		return array_value
	if container is Dictionary:
		var dictionary_value: Dictionary = container
		var child: Variant = dictionary_value.get(token, _default_nested_value(remaining))
		dictionary_value[token] = _set_nested_property(child, remaining, value)
		return dictionary_value
	if remaining.is_empty():
		return _set_builtin_component(container, str(token), value)
	var replacement: Variant = _default_nested_value(tokens)
	return _set_nested_property(replacement, tokens, value)


static func _default_nested_value(tokens: Array) -> Variant:
	if not tokens.is_empty() and (
		tokens[0] is int
		or (tokens[0] is StringName and tokens[0] == &"__array_size__")
	):
		return []
	return {}


static func _set_builtin_component(container: Variant, component: String, value: Variant) -> Variant:
	match typeof(container):
		TYPE_VECTOR2:
			var vector2: Vector2 = container
			if component == "x":
				vector2.x = float(value)
			elif component == "y":
				vector2.y = float(value)
			return vector2
		TYPE_VECTOR3:
			var vector3: Vector3 = container
			if component == "x":
				vector3.x = float(value)
			elif component == "y":
				vector3.y = float(value)
			elif component == "z":
				vector3.z = float(value)
			return vector3
		TYPE_VECTOR4:
			var vector4: Vector4 = container
			if component == "x":
				vector4.x = float(value)
			elif component == "y":
				vector4.y = float(value)
			elif component == "z":
				vector4.z = float(value)
			elif component == "w":
				vector4.w = float(value)
			return vector4
		TYPE_QUATERNION:
			var quaternion: Quaternion = container
			if component == "x":
				quaternion.x = float(value)
			elif component == "y":
				quaternion.y = float(value)
			elif component == "z":
				quaternion.z = float(value)
			elif component == "w":
				quaternion.w = float(value)
			return quaternion
		TYPE_COLOR:
			var color: Color = container
			if component == "r":
				color.r = float(value)
			elif component == "g":
				color.g = float(value)
			elif component == "b":
				color.b = float(value)
			elif component == "a":
				color.a = float(value)
			return color
		_:
			var replacement := {}
			replacement[component] = value
			return replacement


static func _particle_material(material: Material, billboard: bool, warn: Callable) -> Material:
	var result: Material = material.duplicate() as Material if material != null else StandardMaterial3D.new()
	if result is BaseMaterial3D:
		(result as BaseMaterial3D).vertex_color_use_as_albedo = true
		(result as BaseMaterial3D).billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES if billboard else BaseMaterial3D.BILLBOARD_DISABLED
		(result as BaseMaterial3D).billboard_keep_scale = true
	elif result != null:
		_warn(warn, "Particle material is not BaseMaterial3D; vertex-color and billboard semantics may differ.")
	return result


static func _warn(warn: Callable, message: String) -> void:
	if warn.is_valid():
		warn.call(message)

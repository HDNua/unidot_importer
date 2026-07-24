extends SceneTree

const ObjectAdapter := preload("../object_adapter.gd")


class FakeDatabase:
	extends Resource
	var enable_unidot_keys := true
	var add_unsupported_components := false


class FakeMeta:
	extends Resource
	var guid := "synthetic-particle-test"
	var main_object_id := 0
	var fileid_to_nodepath := {}
	var prefab_fileid_to_nodepath := {}
	var fileid_to_skeleton_bone := {}
	var prefab_fileid_to_skeleton_bone := {}
	var objects := {}
	var resources := {}
	var warnings: Array[String] = []
	var failures: Array[String] = []
	var database := FakeDatabase.new()

	func lookup(reference: Variant) -> Variant:
		var file_id: int = int(reference[1]) if reference is Array else int(reference)
		return objects.get(file_id)

	func get_database() -> Resource:
		return database

	func get_main_object_name() -> String:
		return "Synthetic"

	func get_godot_resource(reference: Variant) -> Resource:
		var file_id: int = int(reference[1]) if reference is Array else int(reference)
		return resources.get(file_id)

	func log_debug(_file_id: int, _message: String, _field := "", _reference := []) -> void:
		pass

	func log_warn(_file_id: int, message: String, _field := "", _reference := []) -> void:
		warnings.append(message)

	func log_fail(_file_id: int, message: String, _field := "", _reference := []) -> void:
		failures.append(message)


class FakeState:
	extends RefCounted
	var meta: Resource
	var owner: Node
	var scene_contents: Node

	func _init(test_meta: Resource, root: Node) -> void:
		meta = test_meta
		owner = root
		scene_contents = root

	func add_child(child: Node, parent: Node3D, object: RefCounted) -> void:
		parent.add_child(child, true)
		child.owner = owner
		add_fileID(child, object)

	func add_fileID(child: Node, object: RefCounted) -> void:
		meta.fileid_to_nodepath[object.fileID] = scene_contents.get_path_to(child)


func _init() -> void:
	var adapter := ObjectAdapter.new()
	var meta := FakeMeta.new()
	var root := Node3D.new()
	root.name = "Root"
	var state := FakeState.new(meta, root)

	var game_object = adapter.instantiate_unidot_object(meta, 1, 1, "GameObject")
	var transform = adapter.instantiate_unidot_object(meta, 4, 4, "Transform")
	var particle_system = adapter.instantiate_unidot_object(meta, 198, 198, "ParticleSystem")
	var particle_renderer = adapter.instantiate_unidot_object(meta, 199, 199, "ParticleSystemRenderer")
	meta.objects = {
		1: game_object,
		4: transform,
		198: particle_system,
		199: particle_renderer,
	}
	game_object.keys = {
		"m_Name": "Particle Host",
		"m_Component": [
			{"component": [null, 4, "", 0]},
			{"component": [null, 198, "", 0]},
			{"component": [null, 199, "", 0]},
		],
	}
	transform.keys = {"m_GameObject": [null, 1, "", 0]}
	particle_system.keys = {
		"m_GameObject": [null, 1, "", 0],
		"lengthInSec": 2.0,
		"looping": 1,
		"prewarm": 0,
		"playOnAwake": 1,
		"simulationSpeed": 1.0,
		"moveWithTransform": 1,
		"InitialModule": {
			"enabled": 1,
			"maxNumParticles": 32,
			"startLifetime": {"minMaxState": 0, "scalar": 2.0},
			"startSpeed": {"minMaxState": 3, "minScalar": 1.0, "scalar": 3.0},
			"startSize": {"minMaxState": 0, "scalar": 0.5},
			"startColor": {"maxColor": {"r": 1.0, "g": 0.5, "b": 0.25, "a": 1.0}},
			"gravityModifier": {"minMaxState": 0, "scalar": 0.25},
		},
		"EmissionModule": {
			"enabled": 1,
			"rateOverTime": {"minMaxState": 0, "scalar": 8.0},
			"rateOverDistance": {"minMaxState": 0, "scalar": 0.0},
			"m_BurstCount": 0,
			"m_Bursts": [],
		},
		"ShapeModule": {
			"enabled": 1,
			"type": 4,
			"angle": 20.0,
			"length": 1.5,
			"radius": {"value": 0.75},
		},
		"ColorModule": {"enabled": 0},
		"SizeModule": {"enabled": 0},
		"NoiseModule": {"enabled": 1},
	}
	particle_renderer.keys = {
		"m_GameObject": [null, 1, "", 0],
		"m_Enabled": 1,
		"m_RenderMode": 0,
		"m_CastShadows": 0,
		"m_Materials": [],
	}

	var particles := particle_system.create_godot_node(state, root) as GPUParticles3D
	assert(particles != null)
	particle_system.configure_node(particles)
	assert(root.get_child_count() == 1)
	assert(is_equal_approx(particles.lifetime, 2.0))
	assert(particles.amount == 16)
	var process := particles.process_material as ParticleProcessMaterial
	assert(process != null)
	assert(is_equal_approx(process.initial_velocity_min, 1.0))
	assert(is_equal_approx(process.initial_velocity_max, 3.0))
	assert(process.emission_shape == ParticleProcessMaterial.EMISSION_SHAPE_RING)

	var expected_transform := Transform3D(Basis.from_euler(Vector3(0.1, 0.2, 0.3)), Vector3(1.0, 2.0, 3.0))
	particles.transform = expected_transform
	var renderer_return := particle_renderer.create_godot_node(state, root)
	assert(renderer_return == null)
	assert(root.get_child_count() == 1)
	assert(particles.draw_pass_1 is QuadMesh)
	assert(((particles.draw_pass_1 as QuadMesh).material as BaseMaterial3D).vertex_color_use_as_albedo)
	assert(particles.transform.is_equal_approx(expected_transform))
	assert(meta.fileid_to_nodepath[198] == meta.fileid_to_nodepath[199])
	assert(meta.failures.is_empty())
	assert(meta.warnings.any(func(message: String): return "NoiseModule" in message))
	var shared_metadata: Dictionary = particles.get_meta("unidot_keys")
	assert(shared_metadata.has("ParticleSystem"))
	assert(shared_metadata.has("ParticleSystemRenderer"))

	var override_material := StandardMaterial3D.new()
	meta.resources[250] = override_material
	var system_override_props: Dictionary = particle_system.convert_properties(particles, {
		"InitialModule.startSpeed.scalar": 6.0,
	})
	var renderer_override_props: Dictionary = particle_renderer.convert_properties(particles, {
		"m_Materials.Array.size": 1,
		"m_Materials.Array.data[0]": [null, 250, "", 0],
	})
	var simultaneous_props := system_override_props.duplicate(true)
	simultaneous_props.merge(renderer_override_props, true)
	# Prefab modifications sharing one NodePath are applied through whichever
	# component wins nodepath_to_first_virtual_object. Both payloads must survive.
	particle_system.apply_node_props(particles, simultaneous_props)
	process = particles.process_material as ParticleProcessMaterial
	assert(is_equal_approx(particles.lifetime, 2.0))
	assert(particles.amount == 16)
	assert(is_equal_approx(process.initial_velocity_min, 1.0))
	assert(is_equal_approx(process.initial_velocity_max, 6.0))
	assert(process.emission_shape == ParticleProcessMaterial.EMISSION_SHAPE_RING)
	assert(particles.draw_pass_1 is QuadMesh)
	var override_draw_material := (particles.draw_pass_1 as QuadMesh).material as BaseMaterial3D
	assert(override_draw_material != null)
	assert(override_draw_material != override_material)
	assert(override_draw_material.vertex_color_use_as_albedo)

	var disable_emission_props: Dictionary = particle_system.convert_properties(particles, {
		"EmissionModule.enabled": 0,
	})
	particle_system.apply_node_props(particles, disable_emission_props)
	assert(is_equal_approx(particles.amount_ratio, 0.0))
	assert(is_equal_approx(particles.lifetime, 2.0))
	process = particles.process_material as ParticleProcessMaterial
	assert(is_equal_approx(process.initial_velocity_max, 6.0))

	var enable_emission_props: Dictionary = particle_system.convert_properties(particles, {
		"EmissionModule.enabled": 1,
	})
	particle_system.apply_node_props(particles, enable_emission_props)
	assert(is_equal_approx(particles.amount_ratio, 1.0))
	assert(particles.amount == 16)
	assert(is_equal_approx(particles.lifetime, 2.0))
	process = particles.process_material as ParticleProcessMaterial
	assert(is_equal_approx(process.initial_velocity_max, 6.0))
	assert(process.emission_shape == ParticleProcessMaterial.EMISSION_SHAPE_RING)

	var chained_system_props: Dictionary = particle_system.convert_properties(particles, {
		"InitialModule.gravityModifier.scalar": 0.5,
	})
	var chained_renderer_props: Dictionary = particle_renderer.convert_properties(particles, {
		"m_Enabled": 0,
	})
	var chained_simultaneous_props := chained_system_props.duplicate(true)
	chained_simultaneous_props.merge(chained_renderer_props, true)
	particle_renderer.apply_node_props(particles, chained_simultaneous_props)
	process = particles.process_material as ParticleProcessMaterial
	assert(is_equal_approx(process.initial_velocity_max, 6.0))
	assert(is_equal_approx(process.gravity.y, -9.80665 * 0.5))
	assert(not particles.visible)
	assert(particles.draw_pass_1 is QuadMesh)
	assert((particles.draw_pass_1 as QuadMesh).material != null)
	shared_metadata = particles.get_meta("unidot_keys")
	assert(is_equal_approx(
		shared_metadata["ParticleSystem"]["InitialModule"]["startSpeed"]["scalar"],
		6.0
	))
	assert(is_equal_approx(
		shared_metadata["ParticleSystem"]["InitialModule"]["gravityModifier"]["scalar"],
		0.5
	))
	assert(shared_metadata["ParticleSystemRenderer"]["m_Materials"].size() == 1)
	assert(shared_metadata["ParticleSystemRenderer"]["m_Materials"][0][1] == 250)
	assert(shared_metadata["ParticleSystemRenderer"]["m_Enabled"] == 0)

	particle_renderer.keys["m_RenderMode"] = 1
	particle_renderer.keys["m_LengthScale"] = 3.0
	particle_renderer.configure_node(particles)
	assert(particles.draw_pass_1 is QuadMesh)
	assert(is_equal_approx((particles.draw_pass_1 as QuadMesh).size.y, 3.0))

	meta.resources[102] = BoxMesh.new()
	var original_material := StandardMaterial3D.new()
	meta.resources[201] = original_material
	particle_renderer.keys["m_RenderMode"] = 4
	particle_renderer.keys["m_Mesh"] = [null, 102, "", 0]
	particle_renderer.keys["m_Materials"] = [[null, 201, "", 0]]
	particle_renderer.configure_node(particles)
	assert(particles.draw_pass_1 is BoxMesh)
	var converted_mesh_material := particles.draw_pass_1.surface_get_material(0) as BaseMaterial3D
	assert(converted_mesh_material != null)
	assert(converted_mesh_material != original_material)
	assert(converted_mesh_material.vertex_color_use_as_albedo)
	assert(not original_material.vertex_color_use_as_albedo)

	meta.fileid_to_nodepath.clear()
	particle_renderer.keys["m_RenderMode"] = 0
	particle_renderer.keys["m_Materials"] = []
	var reverse_root := Node3D.new()
	reverse_root.name = "Reverse Root"
	var reverse_state := FakeState.new(meta, reverse_root)
	var renderer_first := particle_renderer.create_godot_node(reverse_state, reverse_root) as GPUParticles3D
	assert(renderer_first != null)
	particle_renderer.configure_node(renderer_first)
	assert(reverse_root.get_child_count() == 1)
	var reverse_expected_transform := Transform3D(Basis.from_euler(Vector3(0.3, 0.2, 0.1)), Vector3(3.0, 2.0, 1.0))
	renderer_first.transform = reverse_expected_transform
	var system_second := particle_system.create_godot_node(reverse_state, reverse_root)
	assert(system_second == null)
	assert(reverse_root.get_child_count() == 1)
	assert(renderer_first.transform.is_equal_approx(reverse_expected_transform))
	assert(meta.fileid_to_nodepath[198] == meta.fileid_to_nodepath[199])

	root.free()
	reverse_root.free()
	print("UNIDOT_PARTICLE_SYSTEM_TEST_PASS")
	quit()

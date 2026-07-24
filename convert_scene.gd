# This file is part of Unidot Importer. See LICENSE.txt for full MIT license.
# Copyright (c) 2021-present Lyuma <xn.lyuma@gmail.com> and contributors
# SPDX-License-Identifier: MIT
@tool
extends Resource

const object_adapter_class := preload("./object_adapter.gd")
const scene_node_state_class := preload("./scene_node_state.gd")
const LIGHTING_SETTINGS_META := &"unidot_lighting_settings"


func customComparison(a, b):
	if typeof(a) != typeof(b):
		return typeof(a) < typeof(b)
	elif a.transform != null && b.transform != null:
		return a.transform.rootOrder < b.transform.rootOrder
	else:
		return b.fileID < a.fileID


func smallestTransform(a, b):
	if typeof(a) != typeof(b):
		return typeof(a) < typeof(b)
	elif a.transform != null && b.transform != null:
		return a.transform.fileID < b.transform.fileID
	else:
		return b.fileID < a.fileID


func sceneRootsFileIDComparison(a, b):
	return a.fileID < b.fileID


func _scene_root_candidate_key(asset: Variant) -> String:
	if asset == null:
		return ""
	return str(asset.type) + ":" + str(asset.fileID)


func _resolve_scene_root_candidate(scene_roots: Variant, root_ref: Variant) -> Variant:
	if typeof(root_ref) != TYPE_ARRAY or root_ref.size() < 2:
		scene_roots.log_warn("SceneRoots contains an invalid root reference: " + str(root_ref), "m_Roots")
		return null
	var root_asset: Variant = scene_roots.meta.lookup(root_ref, true)
	if root_asset == null:
		scene_roots.log_warn("SceneRoots references a missing object: " + str(root_ref), "m_Roots", root_ref)
		return null
	if root_asset.type == "Transform" or root_asset.type == "RectTransform":
		if root_asset.is_prefab_reference:
			var prefab_instance: Variant = scene_roots.meta.lookup(root_asset.prefab_instance, true)
			if prefab_instance != null and prefab_instance.type == "PrefabInstance":
				return prefab_instance
			scene_roots.log_warn("SceneRoots references a prefab root transform whose PrefabInstance is missing: " + str(root_ref), "m_Roots", root_ref)
			return null
		var game_object: Variant = root_asset.gameObject
		if game_object == null:
			scene_roots.log_warn("SceneRoots references a transform whose GameObject is missing: " + str(root_ref), "m_Roots", root_ref)
			return null
		return game_object
	if root_asset.type == "GameObject" or root_asset.type == "PrefabInstance":
		return root_asset
	scene_roots.log_warn("SceneRoots references unsupported root object type " + str(root_asset.type) + ": " + str(root_ref), "m_Roots", root_ref)
	return null


func apply_scene_roots_order(pkgasset: Variant, fallback_roots: Array) -> Array:
	var scene_roots_objects: Array = []
	for asset in pkgasset.parsed_asset.assets.values():
		if asset.type == "SceneRoots":
			scene_roots_objects.append(asset)
	if scene_roots_objects.is_empty():
		return fallback_roots
	scene_roots_objects.sort_custom(sceneRootsFileIDComparison)
	var scene_roots: Variant = scene_roots_objects[0]
	if scene_roots_objects.size() > 1:
		scene_roots.log_warn(
			"Scene contains " + str(scene_roots_objects.size()) +
			" SceneRoots objects; using the lowest fileID " + str(scene_roots.fileID) + ".",
			"m_Roots"
		)

	var candidates_by_key: Dictionary = {}
	for candidate in fallback_roots:
		candidates_by_key[_scene_root_candidate_key(candidate)] = candidate

	var ordered_roots: Array = []
	var used_keys: Dictionary = {}
	for root_ref in scene_roots.roots:
		var candidate: Variant = _resolve_scene_root_candidate(scene_roots, root_ref)
		if candidate == null:
			continue
		var candidate_key := _scene_root_candidate_key(candidate)
		if used_keys.has(candidate_key):
			scene_roots.log_warn("SceneRoots contains duplicate root " + candidate_key + ".", "m_Roots", root_ref)
			continue
		if not candidates_by_key.has(candidate_key):
			scene_roots.log_warn("SceneRoots object " + candidate_key + " is not a direct scene root.", "m_Roots", root_ref)
			continue
		ordered_roots.append(candidates_by_key[candidate_key])
		used_keys[candidate_key] = true

	for candidate in fallback_roots:
		var candidate_key := _scene_root_candidate_key(candidate)
		if used_keys.has(candidate_key):
			continue
		scene_roots.log_warn("Direct scene root " + candidate_key + " is missing from SceneRoots; appending it in fallback order.", "m_Roots")
		ordered_roots.append(candidate)
		used_keys[candidate_key] = true
	return ordered_roots


func get_lighting_settings(lightmap_settings: Variant) -> Dictionary:
	var gi_settings: Dictionary = lightmap_settings.keys.get("m_GISettings", {})
	var editor_settings: Dictionary = lightmap_settings.keys.get(
		"m_LightmapEditorSettings",
		{}
	)
	var settings := {
		"enable_baked_lightmaps":
			gi_settings.get("m_EnableBakedLightmaps", 0) != 0,
		"enable_realtime_lightmaps":
			gi_settings.get("m_EnableRealtimeLightmaps", 0) != 0,
		"bounce_scale": float(gi_settings.get("m_BounceScale", 1.0)),
		"indirect_output_scale":
			float(gi_settings.get("m_IndirectOutputScale", 1.0)),
		"lightmap_max_size": int(
			editor_settings.get(
				"m_LightmapMaxSize",
				editor_settings.get("m_AtlasSize", 0)
			)
		),
		"bake_resolution":
			float(editor_settings.get("m_BakeResolution", 0.0)),
		"lightmaps_bake_mode":
			int(editor_settings.get("m_LightmapsBakeMode", 0)),
		"pvr_bounces": int(editor_settings.get("m_PVRBounces", 3)),
	}
	var external_ref: Variant = lightmap_settings.keys.get(
		"m_LightingSettings",
		[null, 0, "", 0]
	)
	if typeof(external_ref) != TYPE_ARRAY or external_ref.size() < 2:
		lightmap_settings.log_warn(
			"LightmapSettings has an invalid m_LightingSettings reference.",
			"m_LightingSettings"
		)
		return settings
	if int(external_ref[1]) == 0:
		return settings
	var external_resource: Resource = lightmap_settings.meta.get_godot_resource(
		external_ref,
		true
	)
	if (
		external_resource == null
		or not external_resource.has_meta(LIGHTING_SETTINGS_META)
	):
		lightmap_settings.log_warn(
			"Unable to load the referenced LightingSettings resource; "
			+ "using the inline scene settings.",
			"m_LightingSettings",
			external_ref
		)
		return settings
	var external_settings: Variant = external_resource.get_meta(
		LIGHTING_SETTINGS_META
	)
	if typeof(external_settings) != TYPE_DICTIONARY:
		lightmap_settings.log_warn(
			"The referenced LightingSettings metadata is invalid; "
			+ "using the inline scene settings.",
			"m_LightingSettings",
			external_ref
		)
		return settings
	settings.merge(external_settings, true)
	return settings


func configure_lightmap_gi(
	lightmap: LightmapGI,
	settings: Dictionary,
	log_asset: Variant = null
) -> void:
	# Keep the complete normalized Unity intent on the generated node. Some
	# settings, notably realtime GI, do not have a direct LightmapGI equivalent.
	lightmap.set_meta(LIGHTING_SETTINGS_META, settings.duplicate(true))
	if bool(settings.get("enable_realtime_lightmaps", false)):
		lightmap.editor_description = (
			"Unidot preserved Unity realtime-GI authoring intent as metadata. "
			+ "Godot LightmapGI does not provide an equivalent realtime conversion."
		)
		_log_lighting_warning(
			log_asset,
			"Unity realtime lightmaps are enabled, but Godot LightmapGI has no "
			+ "equivalent realtime-GI conversion. The source authoring intent "
			+ "was preserved as metadata only."
		)

	lightmap.bounces = maxi(0, int(settings.get("pvr_bounces", 3)))
	var source_energy := (
		float(settings.get("bounce_scale", 1.0))
		* float(settings.get("indirect_output_scale", 1.0))
	)
	lightmap.bounce_indirect_energy = clampf(source_energy, 0.0, 2.0)
	if not is_equal_approx(source_energy, lightmap.bounce_indirect_energy):
		_log_lighting_warning(
			log_asset,
			"Unity indirect-light energy " + str(source_energy)
			+ " was clamped to Godot's supported range."
		)
	lightmap.directional = int(settings.get("lightmaps_bake_mode", 0)) != 0

	var bake_resolution := float(settings.get("bake_resolution", 0.0))
	if bake_resolution > 0.0:
		var source_texel_scale := 1.0 / bake_resolution
		lightmap.texel_scale = clampf(source_texel_scale, 0.01, 100.0)
		if not is_equal_approx(source_texel_scale, lightmap.texel_scale):
			_log_lighting_warning(
				log_asset,
				"Unity bake resolution " + str(bake_resolution)
				+ " texels/unit exceeded Godot's texel-scale range."
			)

	var source_max_size := int(settings.get("lightmap_max_size", 0))
	if source_max_size > 0:
		lightmap.max_texture_size = clampi(source_max_size, 2048, 16384)
		if source_max_size != lightmap.max_texture_size:
			_log_lighting_warning(
				log_asset,
				"Unity lightmap size " + str(source_max_size)
				+ " was clamped to Godot's supported range."
			)


func _log_lighting_warning(log_asset: Variant, message: String) -> void:
	if log_asset != null:
		log_asset.log_warn(message, "m_LightingSettings")


func keeps_lighting_authoring_settings(settings: Dictionary) -> bool:
	return (
		bool(settings.get("enable_baked_lightmaps", false))
		or bool(settings.get("enable_realtime_lightmaps", false))
	)


func get_global_transform(node: Node):
	if not (node is Node3D):
		return Transform3D.IDENTITY
	var n3d = node as Node3D
	if node.get_parent() == null or n3d.top_level:
		return n3d.transform
	return get_global_transform(node.get_parent()) * n3d.transform


func recursive_print(pkgasset, node: Node, indent: String = ""):
	var fnstr = "" if str(node.scene_file_path) == "" else (" (" + str(node.scene_file_path) + ")")
	pkgasset.log_debug(indent + str(node.name) + ": owner=" + str(node.owner.name if node.owner != null else "") + fnstr)
	#pkgasset.log_debug(indent + str(node.name) + str(node) + ": owner=" + str(node.owner.name if node.owner != null else "") + str(node.owner) + fnstr)
	var new_indent: String = indent + "  "
	for c in node.get_children():
		recursive_print(pkgasset, c, new_indent)


func pack_scene(pkgasset, is_prefab) -> PackedScene:
	#for asset in pkgasset.parsed_asset.assets.values():
	#	if asset.type == "GameObject" and asset.toplevel:
	#		pass

	var arr: Array = [].duplicate()

	for asset in pkgasset.parsed_asset.assets.values():
		if (asset.type == "GameObject" or asset.type == "PrefabInstance") and asset.toplevel:
			if asset.is_non_stripped_prefab_reference:
				continue  # We don't want these.
			if asset.is_stripped:
				asset.log_fail("Stripped object " + asset.type + " would be added to arr " + str(asset.meta.guid) + "/" + str(asset.fileID))
			if is_prefab:
				if asset.type == "PrefabInstance":
					var target_prefab_meta = asset.meta.lookup_meta(asset.source_prefab)
					asset.meta.prefab_main_gameobject_id = pkgasset.parsed_meta.xor_or_stripped(target_prefab_meta.prefab_main_gameobject_id, asset.fileID)
					asset.meta.prefab_main_transform_id = pkgasset.parsed_meta.xor_or_stripped(target_prefab_meta.prefab_main_transform_id, asset.fileID)
				else:
					asset.meta.prefab_main_gameobject_id = asset.fileID
					asset.meta.prefab_main_transform_id = asset.transform.fileID
			arr.push_back(asset)

	if arr.is_empty():
		pkgasset.log_fail("Scene " + pkgasset.pathname + " has no nodes.")
		return
	var env: Environment = null
	var bakedlm: LightmapGI = null
	var navregion: NavigationRegion3D = null
	var occlusion: OccluderInstance3D = null
	var dirlight: DirectionalLight3D = null
	var scene_contents: Node3D = null
	var node_map: Dictionary = {}
	if is_prefab:
		if len(arr) > 1:
			pkgasset.log_warn("Prefab " + pkgasset.pathname + " has multiple roots. picking lowest.")
		arr.sort_custom(smallestTransform)
		arr = [arr[0]]
	else:
		scene_contents = Node3D.new()
		scene_contents.name = "RootNode3D"
		var world_env = WorldEnvironment.new()
		world_env.name = "WorldEnvironment"
		env = Environment.new()
		world_env.environment = env
		# TODO: We need to convert all PostProcessingProfile assets into godot Environment objects
		# Then, store an array of list of node path, weight, asset and layer_id.
		# Then, in prefab logic, concat the paths into the outer scene.
		# finally, the actual scene will loop through all environments and add them by wieght
		# then, we can assign the final world environment from all this.
		scene_contents.add_child(world_env, true)
		world_env.owner = scene_contents
		bakedlm = LightmapGI.new()
		bakedlm.name = "LightmapGI"
		scene_contents.add_child(bakedlm, true)
		bakedlm.owner = scene_contents
		navregion = NavigationRegion3D.new()
		navregion.name = "NavigationRegion3D"
		scene_contents.add_child(navregion, true)
		navregion.owner = scene_contents
		occlusion = OccluderInstance3D.new()
		occlusion.name = "OccluderInstance3D"
		scene_contents.add_child(occlusion, true)
		occlusion.owner = scene_contents
		dirlight = DirectionalLight3D.new()
		dirlight.name = "DirectionalLight3D"
		scene_contents.add_child(dirlight, true)
		dirlight.owner = scene_contents
		dirlight.visible = false

	pkgasset.parsed_meta.calculate_prefab_nodepaths_recursive()

	var node_state: Object = scene_node_state_class.new(pkgasset.parsed_meta.get_database(), pkgasset.parsed_meta, scene_contents)

	var ps: RefCounted = node_state.prefab_state
	for asset in pkgasset.parsed_asset.assets.values():
		var parent: RefCounted = null  # UnidotTransform
		if asset.is_stripped:
			pass  # Ignore stripped components.
		elif asset.is_non_stripped_prefab_reference:
			var prefab_instance_id: int = asset.prefab_instance[1]
			var prefab_source_object: int = asset.prefab_source_object[1]
			if not ps.non_stripped_prefab_references.has(prefab_instance_id):
				ps.non_stripped_prefab_references[prefab_instance_id] = [].duplicate()
			ps.non_stripped_prefab_references[prefab_instance_id].push_back(asset)
		elif asset.type == "Transform" or asset.type == "PrefabInstance":
			parent = asset.parent
			if parent != null and parent.is_prefab_reference and (asset.type == "PrefabInstance" or not asset.is_prefab_reference):
				var prefab_instance_id: int = parent.prefab_instance[1]
				var prefab_source_object: int = parent.prefab_source_object[1]
				if not ps.transforms_by_parented_prefab.has(prefab_instance_id):
					ps.transforms_by_parented_prefab[prefab_instance_id] = {}.duplicate()
				if not ps.child_transforms_by_stripped_id.has(parent.fileID):
					ps.child_transforms_by_stripped_id[parent.fileID] = [].duplicate()
				ps.transforms_by_parented_prefab.get(prefab_instance_id)[parent.fileID] = parent
				#ps.transforms_by_parented_prefab_source_obj[str(prefab_instance_id) + "/" + str(prefab_source_object)] = parent
				ps.child_transforms_by_stripped_id[parent.fileID].push_back(asset)
			#elif parent != null and asset.type == "PrefabInstance":
			#	var uk: String = asset.parent.fileID
			#	if not ps.prefab_parents.has(uk):
			#		ps.prefab_parents[uk] = []
			#	ps.prefab_parents[uk].append(asset)
		elif asset.type == "RenderSettings":
			env.fog_enabled = (asset.keys.get("m_Fog", 0) == 1)
			var c: Color = asset.keys.get("m_FogColor", Color.WHITE)
			var max_c: float = max(c.r, max(c.g, c.b))
			if max_c > 1.0:
				c /= max_c
			else:
				max_c = 1.0
			env.fog_light_color = c
			env.fog_light_energy = max_c
			if asset.keys.get("m_FogMode", 3) == 1:  # Linear
				const TARGET_FOG_DENSITY = 0.05
				# It's not possible to emulate linear fog exactly with the level of control we currently have.
				# Multiply by 0.1 because the fog seemed too aggressive.
				env.fog_density = 0.1 * -log(TARGET_FOG_DENSITY) / asset.keys.get("m_LinearFogEnd", 0.0)
			else:
				env.fog_density = asset.keys.get("m_FogDensity", 0.0)
			var sun: Array = asset.keys.get("m_Sun", [null, 0, null, null])
			if sun[1] != 0:
				scene_contents.remove_child(dirlight)
				dirlight = null
			var sky_material: Variant = pkgasset.parsed_meta.get_godot_resource(asset.keys.get("m_SkyboxMaterial"))
			if sky_material == null and asset.keys.get("m_SkyboxMaterial")[1] != 0:
				# Just use a default skybox for now...
				sky_material = ProceduralSkyMaterial.new()
				sky_material.sky_top_color = Color(0.454902, 0.678431, 0.87451, 1)
				sky_material.sky_horizon_color = Color(0.894118, 0.952941, 1, 1)
				sky_material.sky_curve = 0.0731028
				sky_material.ground_bottom_color = Color(0.454902, 0.470588, 0.490196, 1)
				sky_material.ground_horizon_color = Color(1, 1, 1, 1)
			var ambient_mode: int = asset.keys.get("m_AmbientMode", 0)
			if sky_material != null:
				env.background_mode = Environment.BG_SKY
				env.sky = Sky.new()
				env.sky.sky_material = sky_material
			if ambient_mode == 0 and sky_material == null:
				env.background_mode = Environment.BG_COLOR
				var ccol: Color = asset.keys.get("m_AmbientSkyColor", Color.BLACK)
				var eng: float = max(ccol.r, max(ccol.g, ccol.b))
				if eng > 1:
					ccol /= eng
				else:
					eng = 1
				env.background_color = ccol
				env.background_energy_multiplier = eng
				env.ambient_light_color = ccol
				env.ambient_light_energy = eng
				env.ambient_light_sky_contribution = 0
			elif ambient_mode == 1 or ambient_mode == 2 or ambient_mode == 3:
				# modes 1 or 2 are technically a gradient (2 is blank dropdown)
				# mode 3 is solid color (same as 0 + null skybox material)
				var ccol: Color = asset.keys.get("m_AmbientSkyColor", Color.BLACK)
				var eng: float = max(ccol.r, max(ccol.g, ccol.b))
				if eng > 1:
					ccol /= eng
				else:
					eng = 1
				env.ambient_light_color = ccol
				env.ambient_light_energy = eng
				env.ambient_light_sky_contribution = 0
		elif asset.type == "LightmapSettings":
			var lda: Array = asset.keys.get("m_LightingDataAsset", [null, 0, null, null])
			var lighting_settings := get_lighting_settings(asset)
			if bakedlm != null:
				configure_lightmap_gi(bakedlm, lighting_settings, asset)
			var has_baked_data := lda.size() >= 2 and int(lda[1]) != 0
			var keeps_authoring_settings := keeps_lighting_authoring_settings(
				lighting_settings
			)
			# A LightingSettings asset carries bake-authoring settings, not baked
			# lightmap textures. Keep an unbaked LightmapGI when baked authoring
			# is enabled so the scene can be rebaked in Godot. Also keep it for
			# unsupported Unity realtime GI so that intent remains inspectable
			# through node metadata and an explicit editor description.
			if (
				bakedlm != null
				and not has_baked_data
				and not keeps_authoring_settings
			):
				scene_contents.remove_child(bakedlm)
				bakedlm = null
		elif asset.type == "NavMeshSettings":
			var nmd: Array = asset.keys.get("m_NavMeshData", [null, 0, null, null])
			if nmd[1] == 0:
				scene_contents.remove_child(navregion)
				navregion = null
			else:
				navregion.navigation_mesh = NavigationMesh.new()
		elif asset.type == "OcclusionCullingSettings":
			var ocd: Array = asset.keys.get("m_OcclusionCullingData", [null, 0, null, null])
			if ocd[1] == 0:
				scene_contents.remove_child(occlusion)
				occlusion = null
			else:
				occlusion.occluder = SphereOccluder3D.new()  # wrong type
		elif asset.type != "GameObject":
			# alternatively, is it a subclass of UnidotComponent?
			parent = asset.gameObject
			if parent != null and parent.is_prefab_reference:
				var prefab_instance_id: int = parent.prefab_instance[1]
				var prefab_source_object: int = parent.prefab_source_object[1]
				if not ps.gameobjects_by_parented_prefab.has(prefab_instance_id):
					ps.gameobjects_by_parented_prefab[prefab_instance_id] = {}.duplicate()
				if not ps.components_by_stripped_id.has(parent.fileID):
					ps.components_by_stripped_id[parent.fileID] = [].duplicate()
				ps.gameobjects_by_parented_prefab.get(prefab_instance_id)[parent.fileID] = parent
				#ps.gameobjects_by_parented_prefab_source_obj[str(prefab_instance_id) + "/" + str(prefab_source_object)] = parent
				ps.components_by_stripped_id[parent.fileID].push_back(asset)

	var skelleys_with_no_parent: Array = node_state.initialize_skelleys(pkgasset.parsed_asset.assets.values(), is_prefab)

	if len(skelleys_with_no_parent) >= 1:
		if scene_contents == null:
			scene_contents = Node3D.new()
			scene_contents.name = "RootNode3D"
		node_state = node_state.state_with_owner(scene_contents)
		for noparskel in skelleys_with_no_parent:
			if noparskel.humanoid_avatar_meta != null:
				node_state = node_state.state_with_avatar_meta(noparskel.humanoid_avatar_meta)
			scene_contents.add_child(noparskel.godot_skeleton, true)
	#var fileid_to_prefab_nodepath = {}.duplicate()
	#var fileid_to_prefab_ref = {}.duplicate()
	#pkgasset.parsed_meta.fileid_to_prefab_nodepath = {}
	#pkgasset.parsed_meta.fileid_to_prefab_ref = {}

	for asset in pkgasset.parsed_asset.assets.values():
		if str(asset.type) == "SkinnedMeshRenderer":
			var skelley: RefCounted = asset.get_skelley(node_state)
			if skelley != null:
				skelley.skinned_mesh_renderers.append(asset)

	node_state.env = env
	node_state.set_main_name_map(node_state.prefab_state.gameobject_name_map, node_state.prefab_state.prefab_gameobject_name_map)

	arr.sort_custom(customComparison)
	if not is_prefab:
		arr = apply_scene_roots_order(pkgasset, arr)
	for asset in arr:
		if asset.is_stripped:
			asset.log_fail("Stripped object " + asset.type + " added to arr " + str(asset.meta.guid) + "/" + str(asset.fileID))
		var skel: RefCounted = null
		# FIXME: PrefabInstances pointing to a scene whose root node is a Skeleton may not work.
		if asset.transform != null:
			skel = node_state.fileID_to_skelley.get(asset.transform.fileID, null)
		if skel != null:
			if len(skelleys_with_no_parent) >= 1:
				# If a toplevel node is part of a skeleton, insert the skeleton between the actual root and the toplevel node.
				scene_contents.add_child(skel.godot_skeleton, true)
				skel.godot_skeleton.owner = scene_contents
			asset.create_skeleton_bone(node_state, skel)
		else:
			# asset.log_debug(str(asset) + " position " + str(asset.transform.godot_transform))
			var new_root: Node3D = asset.create_godot_node(node_state, scene_contents)
			if scene_contents == null:
				assert(is_prefab)
				scene_contents = new_root
				node_state = node_state.state_with_owner(scene_contents)
			else:
				if is_prefab:
					asset.log_fail("May be a prefab with multiple roots, or hit unusual case.")
				pass
				# assert(not is_prefab)
			if asset.type == "PrefabInstance":
				node_state.add_prefab_to_parent_transform(0, asset.fileID)

	for skelley in skelleys_with_no_parent:
		for smr in skelley.skinned_mesh_renderers:
			var ret: Node = smr.create_skinned_mesh(node_state)
			if ret != null:
				smr.log_debug("Finally added SkinnedMeshRenderer " + str(smr) + " into top-level Skeleton " + str(scene_contents.get_path_to(ret)))

	# scene_contents = node_state.owner
	if scene_contents == null:
		pkgasset.log_fail("Failed to parse scene " + pkgasset.pathname)
		return null

	process_lod_groups(scene_contents, ps)

	if not is_prefab:
		# Remove redundant directional light.
		if dirlight != null:
			var x: LightmapGI = null
			var fileids: Array = [].duplicate()
			for light in node_state.find_objects_of_type("Light"):
				if light.lightType == 1:  # Directional
					scene_contents.remove_child(dirlight)
					dirlight = null
		var main_camera: Camera3D = null
		var pp_layer_bits: int = 0
		for camera_obj in node_state.find_objects_of_type("Camera"):
			#if not (camera.get_parent() is Viewport) and camera.visible:
			var go: RefCounted = node_state.get_gameobject(camera_obj)
			var camera: Camera3D = null
			if camera_obj.enabled and go.enabled:
				# This is a main camera
				camera = node_state.get_godot_node(camera_obj)
			if camera != null:
				main_camera = camera
				if camera.environment != null:
					env.background_mode = camera.environment.background_mode
					env.background_color = camera.environment.background_color
					env.background_energy_multiplier = camera.environment.background_energy_multiplier
				for mono in node_state.get_components(camera_obj, "MonoBehaviour"):
					if str(mono.monoscript[2]) == "948f4100a11a5c24981795d21301da5c":  # PostProcessingLayer
						pp_layer_bits = mono.keys.get("volumeLayer.m_Bits", mono.keys.get("volumeLayer", {}).get("m_Bits", 0))
						break
				break
		for mono in node_state.find_objects_of_type("MonoBehaviour"):
			if str(mono.monoscript[2]) == "8b9a305e18de0c04dbd257a21cd47087":  # PostProcessingVolume
				var go: RefCounted = node_state.get_gameobject(mono)
				if not mono.enabled or not go.enabled:
					continue
				if ((1 << go.keys.get("m_Layer")) & pp_layer_bits) != 0:
					# Enabled PostProcessingVolume with matching layer.
					if mono.keys.get("isGlobal", 0) == 1 and mono.keys.get("weight", 0) > 0.0:
						mono.log_debug("Would merge PostProcessingVolume profile " + str(mono.keys.get("sharedProfile")))

	for plugin in pkgasset.parsed_meta.get_enabled_plugins():
		plugin.setup_post_scene(pkgasset, arr, skelleys_with_no_parent, node_state, scene_contents)

	var light_probes: Array[Node] = scene_contents.find_children("*", "LightmapProbe")
	var heights = []

	for probe in light_probes:
		heights.append(get_global_transform(probe).origin.y)
	# LightmapProbe operations are non-linear.
	# Godot becomes very slow if you have 2600 probes, and it crashes with "Out of memory" if you have more than 2700
	# (Out of memory due to resizing an array over 1 billion elements, not due to actual memory consumption)
	# So we will limit probes scene-wide to 2500.
	var did_warn_too_many: bool = false
	const max_probe_before_sampling: int = 1500
	const max_probe_after_sampling: int = 300
	const probe_sample_denom: int = 13
	var max_height: float = 1000.0
	if len(heights) > max_probe_before_sampling:
		heights.sort()
		max_height = heights[max_probe_before_sampling]
	if len(heights) > max_probe_after_sampling:
		var min_x: int = min(len(heights), max_probe_before_sampling)
		var probe_sample_num: int = max_probe_after_sampling * probe_sample_denom / min_x
		pkgasset.log_warn("Deleting " + str(len(heights) - max_probe_before_sampling) + " light probes above y=" + str(max_height) + " to prevent engine bug.")
		pkgasset.log_warn("Sampling " + str(min_x * probe_sample_num / probe_sample_denom) + " remaining light probes to prevent engine bug.")
		var i: int = 0
		for probe in light_probes:
			var delete_probe: bool = get_global_transform(probe).origin.y >= max_height
			if delete_probe:
				pkgasset.log_debug("Deleting probe " + str(probe.get_parent().name + "/" + str(probe.name)) + " at " + str(probe.transform.origin))
			else:
				i += 1
				if (i % probe_sample_denom) >= probe_sample_num:
					delete_probe = true
					pkgasset.log_debug("Deleting/sampling probe " + str(probe.get_parent().name + "/" + str(probe.name)) + " at " + str(probe.transform.origin))
			if delete_probe:
				if probe.owner != scene_contents:
					pkgasset.log_fail("Unable to delete light probe at " + str(probe.transform.origin) + " because of scene instance. Please modify " + str(probe.owner.scene_file_path))
				probe.owner = null
				probe.get_parent().remove_child(probe)
				probe.queue_free()

	var packed_scene: PackedScene = PackedScene.new()
	packed_scene.pack(scene_contents)
	pkgasset.log_debug("Finished packing " + pkgasset.pathname + " with " + str(scene_contents.get_child_count()) + " nodes.")
	recursive_print(pkgasset, scene_contents)
	return packed_scene


func process_lod_groups(scene_contents: Node, ps: RefCounted):

	for lod_group in ps.lod_groups:
		var prev_distance_m: float = 0.0
		var prev_fade_m: float = 0.0
		# Formula: 0.65 / screenRelativeHeight * m_Size = distance_in_meters
		# For example, 0.65 / 0.8125 * 5 = 4.0
		# or 0.65 / 0.216 * 1 = 3.0
		# LODGroup scale factor is confusingly aspect ratio dependent.
		# We scale by another factor or 2 to account for 16:9 aspect ratio.
		# It seems to make LOD switches less noticeable.
		var size_m = lod_group.keys.get("m_Size", 1.0)
		var animate_crossfade: bool = lod_group.keys.get("m_AnimateCrossFading", 0) == 1
		for lod in lod_group.keys.get("m_LODs", []):
			var screen_relative_height: float = lod.get("screenRelativeHeight", 1.0)
			var distance_m = 2.0 * 0.65 / screen_relative_height * size_m
			var fade_width: float = lod.get("fadeTransitionWidth", 0.0)
			if animate_crossfade:
				fade_width = 0.5 # Hardcode half a meter of fade overlap. No idea...
			else:
				fade_width = fade_width * (distance_m - prev_distance_m) # fraction of the length of this LOD.
			for renderer_ref_dict in lod.get("renderers", []):
				var renderer_ref: Array
				if typeof(renderer_ref_dict) == TYPE_DICTIONARY:
					renderer_ref = renderer_ref_dict["renderer"]
				var np: NodePath = lod_group.meta.fileid_to_nodepath.get(renderer_ref[1], lod_group.meta.prefab_fileid_to_nodepath.get(renderer_ref[1], NodePath()))
				if not np.is_empty():
					var node: Node = scene_contents.get_node(np)
					var visual_inst: VisualInstance3D = node as VisualInstance3D
					if node != null and visual_inst == null:
						visual_inst = node.get_child(0) as VisualInstance3D
					if visual_inst != null:
						visual_inst.visibility_range_begin = prev_distance_m
						visual_inst.visibility_range_begin_margin = prev_fade_m
						visual_inst.visibility_range_end = distance_m
						visual_inst.visibility_range_end_margin = fade_width
						# Dependencies seems buggy, so we use Self and don't set the visibility parent.
						#visual_inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF
						# Self is really hard to work with as it has overlap...
						# So we'll use DISABLED for now... which should act like low-water mark / high-water mark.
						visual_inst.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			prev_distance_m = distance_m
			prev_fade_m = fade_width

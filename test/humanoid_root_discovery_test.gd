# This file is part of Unidot Importer. See LICENSE.txt for full MIT license.
# Copyright (c) 2021 Lyuma <xn.lyuma@gmail.com> and contributors
# SPDX-License-Identifier: MIT
#
# Regression test for humanoid Root bone discovery. The discovery walk climbs
# from an arbitrary mapped bone to the top of the skeleton and may only assign
# the profile "Root" to unmapped bones sitting above every mapped bone (such as
# an Armature node). It must never hijack an unmapped bone that lies inside the
# rig (e.g. a clavicle the auto-mapper left unmapped, as in Synty POLYGON
# Prototype Character_FPSHands_01): doing so drops the bone's original
# orientation and corrupts the rotation delta of every bone below it.
# Uses synthetic rigs only; no external assets.
extends SceneTree

const ASSET_ADAPTER := preload("res://addons/unidot_importer/asset_adapter.gd")


func _make_node(parent: int, name: String, is_bone: bool) -> GLTFNode:
	var node := GLTFNode.new()
	node.parent = parent
	node.resource_name = name
	node.original_name = name
	node.skeleton = 0 if is_bone else -1
	return node


func _run_walk(nodes: Array, bone_map_dict: Dictionary) -> String:
	var human_skin_nodes: Array = []
	var human_skin_set: Dictionary = {}
	for node_idx in range(len(nodes)):
		if bone_map_dict.has(nodes[node_idx].resource_name):
			human_skin_nodes.push_back(node_idx)
			human_skin_set[node_idx] = true
	var internal_data: Dictionary = {}
	return ASSET_ADAPTER.FbxHandler.discover_humanoid_root_bone(nodes, bone_map_dict, human_skin_nodes, human_skin_set, internal_data, func(_msg): pass)


func _run_json_walk(nodes: Array, bone_map_dict: Dictionary) -> String:
	var node_parents: Dictionary = {}
	var human_skin_nodes: Array = []
	var human_skin_set: Dictionary = {}
	for node_idx in range(len(nodes)):
		for child_idx in nodes[node_idx].get("children", []):
			node_parents[int(child_idx)] = node_idx
		var node_bone_name := ASSET_ADAPTER.FbxHandler.sanitize_bone_name(String(nodes[node_idx].get("name", "")))
		if bone_map_dict.has(node_bone_name):
			human_skin_nodes.push_back(node_idx)
			human_skin_set[node_idx] = true
	var internal_data: Dictionary = {}
	return ASSET_ADAPTER.FbxHandler.discover_humanoid_root_bone_from_json(nodes, node_parents, bone_map_dict, human_skin_nodes, human_skin_set, internal_data, func(_msg): pass)


func _initialize() -> void:
	# Rig 1: unmapped clavicle between mapped chest and shoulder; rig root is
	# already mapped to Root. Walking up from the last mapped bone (the right
	# hand) passes through the unmapped clavicle, which must NOT become Root.
	var scene_root := _make_node(-1, "", false)
	var rig1: Array = [
		scene_root,
		_make_node(0, "RigRoot", true),  # mapped Root
		_make_node(1, "Pelvis", true),  # mapped Hips
		_make_node(2, "Back", true),  # mapped Chest
		_make_node(3, "Collar_R", true),  # unmapped hole
		_make_node(4, "Arm_R", true),  # mapped
		_make_node(5, "Palm_R", true),  # mapped; walk starts here
		_make_node(6, "Digit_R", true),  # unmapped leaf
	]
	var map1 := {
		"RigRoot": "Root",
		"Pelvis": "Hips",
		"Back": "Chest",
		"Arm_R": "RightUpperArm",
		"Palm_R": "RightHand",
	}
	var root1 := _run_walk(rig1, map1)
	if root1 == "Collar_R":
		_fail("Interior unmapped bone Collar_R was hijacked as Root.")
		return
	if not root1.is_empty():
		_fail("Expected no new Root candidate, got '" + root1 + "'.")
		return

	# Rig 2: unmapped Armature node above the whole rig must still be
	# discovered as Root (the intended behavior of the walk).
	var rig2: Array = [
		_make_node(-1, "", false),
		_make_node(0, "Armature", true),  # unmapped, above the rig
		_make_node(1, "Pelvis", true),  # mapped Hips
		_make_node(2, "Palm_L", true),  # mapped; walk starts here
	]
	var map2 := {
		"Pelvis": "Hips",
		"Palm_L": "LeftHand",
	}
	var root2 := _run_walk(rig2, map2)
	if root2 != "Armature":
		_fail("Above-rig Armature was not discovered as Root (got '" + root2 + "').")
		return

	# Rig 3: both an interior hole and an above-rig Armature. The interior
	# candidate must be discarded when a mapped ancestor is found above it,
	# and the Armature above everything must win.
	var rig3: Array = [
		_make_node(-1, "", false),
		_make_node(0, "Armature", true),  # unmapped, above the rig
		_make_node(1, "Pelvis", true),  # mapped Hips
		_make_node(2, "Collar_R", true),  # unmapped hole
		_make_node(3, "Palm_R", true),  # mapped; walk starts here
	]
	var map3 := {
		"Pelvis": "Hips",
		"Palm_R": "RightHand",
	}
	var root3 := _run_walk(rig3, map3)
	if root3 != "Armature":
		_fail("Expected Armature as Root with interior hole present (got '" + root3 + "').")
		return

	# External FBX2glTF JSON keeps ':' and '/' while its bone map removes them.
	# A mapped namespaced ancestor must still clear an interior Root candidate.
	var json_rig1: Array = [
		{"name": "mixamorig:Hips", "children": [1]},
		{"name": "Clavicle:R", "children": [2]},
		{"name": "Palm:R", "children": []},
	]
	var json_map1 := {
		"mixamorigHips": "Hips",
		"PalmR": "RightHand",
	}
	var json_root1 := _run_json_walk(json_rig1, json_map1)
	if not json_root1.is_empty():
		_fail("Namespaced mapped ancestor was mistaken for Root (got '" + json_root1 + "').")
		return

	# An actually unmapped node above that rig remains a valid Root candidate,
	# and its returned name stays in the sanitized bone-map namespace.
	var json_rig2: Array = [
		{"name": "Armature/Root", "children": [1]},
		{"name": "mixamorig:Hips", "children": [2]},
		{"name": "Palm:R", "children": []},
	]
	var json_root2 := _run_json_walk(json_rig2, json_map1)
	if json_root2 != "ArmatureRoot":
		_fail("Expected sanitized above-rig Root 'ArmatureRoot' (got '" + json_root2 + "').")
		return

	print("humanoid_root_discovery_test: all cases passed")
	quit(0)


func _fail(message: String) -> void:
	push_error("humanoid_root_discovery_test: " + message)
	quit(1)

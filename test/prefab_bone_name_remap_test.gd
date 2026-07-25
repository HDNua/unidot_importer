# This file is part of Unidot Importer. See LICENSE.txt for full MIT license.
# Copyright (c) 2021 Lyuma <xn.lyuma@gmail.com> and contributors
# SPDX-License-Identifier: MIT
#
# Regression test for prefab-side humanoid bone lookups when a rig contains
# duplicate bone names. Unity deduplicates GameObject names with a space suffix
# ("Digit_01 1") while Godot's FBX import sanitizes them differently
# ("Digit_01_2"). The autodetected bone map and the per-bone rotation deltas
# are recorded under Godot-sanitized names, so prefab conversion (which sees
# the Unity names) must translate through godot_sanitized_to_orig_remap or the
# affected bones lose their humanoid mapping and rotation delta — e.g. the
# right-hand fingers of Synty POLYGON Prototype FPS arm prefabs.
# Uses a synthetic avatar meta only; no external assets.
extends SceneTree

const ASSET_META := preload("res://addons/unidot_importer/asset_meta.gd")
const NODE_STATE := preload("res://addons/unidot_importer/scene_node_state.gd")


func _initialize() -> void:
	var meta = ASSET_META.new()
	meta.path = "synthetic/duplicate_bone_rig.fbx"
	var delta_metacarpal := Transform3D(Basis(Quaternion(0.0, 0.7071067811, 0.0, 0.7071067811)), Vector3.ZERO)
	var delta_digit2 := Transform3D(Basis(Quaternion(0.5, 0.5, 0.5, 0.5)), Vector3.ZERO)
	meta.transform_fileid_to_rotation_delta = {
		400010: delta_metacarpal,
		400012: delta_digit2,
	}
	meta.fileid_to_skeleton_bone = {
		400010: "RightThumbMetacarpal",
		400012: "Digit_02_2",
	}
	meta.autodetected_bone_map_dict = {
		"Digit_01": "LeftThumbMetacarpal",
		"Digit_01_2": "RightThumbMetacarpal",
		"Palm_R": "RightHand",
	}
	meta.internal_data["godot_sanitized_to_orig_remap"] = {
		"bone_name": {
			"Digit_01": "Digit_01",
			"Digit_01_2": "Digit_01 1",
			"Digit_02_2": "Digit_02 1",
			"Palm_R": "Palm_R",
		}
	}

	var state = NODE_STATE.new(null, null, null)
	var new_state = state.state_with_avatar_meta(meta)
	if new_state.active_avatars.is_empty():
		_fail("No avatar state was created.")
		return
	var avatar = new_state.active_avatars[0]

	# The CRC32 keys must correspond to the original Unity names, because
	# prefab GameObjects carry those names.
	var crc_unity_right := avatar.crc32.crc32("Digit_01 1")
	if not avatar.humanoid_bone_map_dict.has(crc_unity_right):
		_fail("Unity-deduplicated name 'Digit_01 1' not found in humanoid bone map.")
		return
	if avatar.humanoid_bone_map_dict[crc_unity_right] != "RightThumbMetacarpal":
		_fail("'Digit_01 1' mapped to '" + str(avatar.humanoid_bone_map_dict[crc_unity_right]) + "', expected RightThumbMetacarpal.")
		return
	var crc_left := avatar.crc32.crc32("Digit_01")
	if avatar.humanoid_bone_map_dict.get(crc_left, "") != "LeftThumbMetacarpal":
		_fail("Non-duplicated name 'Digit_01' lost its mapping.")
		return
	var crc_plain := avatar.crc32.crc32("Palm_R")
	if avatar.humanoid_bone_map_dict.get(crc_plain, "") != "RightHand":
		_fail("Name without remap entry 'Palm_R' lost its mapping.")
		return

	# Rotation deltas must be reachable under the Unity name of bones whose
	# model bone name was sanitized differently.
	if not avatar.human_bone_to_rotation_delta.has("Digit_02 1"):
		_fail("Rotation delta not aliased under Unity name 'Digit_02 1'.")
		return
	if not avatar.human_bone_to_rotation_delta["Digit_02 1"].is_equal_approx(delta_digit2):
		_fail("Aliased rotation delta for 'Digit_02 1' has the wrong value.")
		return
	if not avatar.human_bone_to_rotation_delta.has("Digit_02_2"):
		_fail("Rotation delta no longer reachable under model bone name 'Digit_02_2'.")
		return
	if avatar.human_bone_to_rotation_delta.get("RightThumbMetacarpal", Transform3D.IDENTITY) != delta_metacarpal:
		_fail("Profile-named rotation delta lookup broken.")
		return

	print("prefab_bone_name_remap_test: all cases passed")
	quit(0)


func _fail(message: String) -> void:
	push_error("prefab_bone_name_remap_test: " + message)
	quit(1)

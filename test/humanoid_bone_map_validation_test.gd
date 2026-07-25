# This file is part of Unidot Importer. See LICENSE.txt for full MIT license.
# Copyright (c) 2021 Lyuma <xn.lyuma@gmail.com> and contributors
# SPDX-License-Identifier: MIT
#
# Regression test for structurally invalid humanDescription avatar bone maps.
# Some Unity assets ship avatars that map Hips to the rig root bone, shifting
# the whole spine chain by one level. Trusting such a map scrambles humanoid
# retargeting, so the importer must detect the inconsistency and fall back to
# automatic bone mapping. Uses a synthetic rig only; no external assets.
extends SceneTree

const ASSET_ADAPTER := preload("res://addons/unidot_importer/asset_adapter.gd")

# Synthetic rig hierarchy (child -> parent).
const RIG_PARENTS := {
	"Pelvis": "RigRoot",
	"Back1": "Pelvis",
	"Back2": "Back1",
	"Back3": "Back2",
	"NeckBone": "Back3",
	"HeadBone": "NeckBone",
	"Leg_L": "Pelvis",
	"Leg_R": "Pelvis",
	"Knee_L": "Leg_L",
	"Knee_R": "Leg_R",
	"Collar_L": "Back3",
	"Arm_L": "Collar_L",
	"Fore_L": "Arm_L",
	"Palm_L": "Fore_L",
	"Roll_L": "Arm_L",
}


func _initialize() -> void:
	# 1. A consistent map must validate cleanly.
	var good_map := {
		"Pelvis": "Hips",
		"Back1": "Spine",
		"Back2": "Chest",
		"Back3": "UpperChest",
		"NeckBone": "Neck",
		"HeadBone": "Head",
		"Leg_L": "LeftUpperLeg",
		"Leg_R": "RightUpperLeg",
		"Knee_L": "LeftLowerLeg",
		"Knee_R": "RightLowerLeg",
		"Collar_L": "LeftShoulder",
		"Arm_L": "LeftUpperArm",
		"Fore_L": "LeftLowerArm",
		"Palm_L": "LeftHand",
	}
	var err := ASSET_ADAPTER.FbxHandler.humanoid_bone_map_validation_error(good_map, RIG_PARENTS)
	if not err.is_empty():
		_fail("Consistent bone map was rejected: " + err)
		return

	# 2. The root-shifted pattern (Hips mapped to the rig root) must be rejected:
	# legs stay on the true pelvis, whose mapping shifted to Spine.
	var shifted_map := {
		"RigRoot": "Hips",
		"Pelvis": "Spine",
		"Back1": "Chest",
		"Back2": "UpperChest",
		"NeckBone": "Neck",
		"HeadBone": "Head",
		"Leg_L": "LeftUpperLeg",
		"Leg_R": "RightUpperLeg",
		"Knee_L": "LeftLowerLeg",
		"Knee_R": "RightLowerLeg",
		"Collar_L": "LeftShoulder",
		"Arm_L": "LeftUpperArm",
		"Fore_L": "LeftLowerArm",
		"Palm_L": "LeftHand",
	}
	err = ASSET_ADAPTER.FbxHandler.humanoid_bone_map_validation_error(shifted_map, RIG_PARENTS)
	if err.is_empty():
		_fail("Root-shifted bone map was not rejected.")
		return

	# 3. A map with no Hips at all cannot anchor the profile.
	err = ASSET_ADAPTER.FbxHandler.humanoid_bone_map_validation_error({"Back1": "Spine"}, RIG_PARENTS)
	if err.is_empty():
		_fail("Hips-less bone map was not rejected.")
		return

	# 4. Unmapped helper bones between mapped bones are fine (Roll_L is skipped),
	# and sparse-but-consistent maps validate (e.g. missing UpperChest).
	var sparse_map := {
		"Pelvis": "Hips",
		"Back1": "Spine",
		"Back2": "Chest",
		"NeckBone": "Neck",
		"HeadBone": "Head",
		"Collar_L": "LeftShoulder",
		"Arm_L": "LeftUpperArm",
		"Fore_L": "LeftLowerArm",
		"Palm_L": "LeftHand",
	}
	err = ASSET_ADAPTER.FbxHandler.humanoid_bone_map_validation_error(sparse_map, RIG_PARENTS)
	if not err.is_empty():
		_fail("Sparse consistent bone map was rejected: " + err)
		return

	print("UNIDOT_HUMANOID_BONE_MAP_VALIDATION_TEST_PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error("UNIDOT_HUMANOID_BONE_MAP_VALIDATION_TEST_FAIL: " + message)
	quit(1)

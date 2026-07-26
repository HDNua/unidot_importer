# This file is part of Unidot Importer. See LICENSE.txt for full MIT license.
# Copyright (c) 2021 Lyuma <xn.lyuma@gmail.com> and contributors
# SPDX-License-Identifier: MIT
#
# Regression test for texture lookup on case-insensitive filesystems. A
# lowercase candidate may appear to exist even when the package records the
# canonical directory as "Textures". Exact package paths must win before the
# filesystem fallback so generated resources remain portable to case-sensitive
# filesystems.
extends SceneTree

const ASSET_ADAPTER := preload("res://addons/unidot_importer/asset_adapter.gd")

const LOWER_PATH := "Unidot/Assets/Synty/PolygonGeneric/textures/Generic_Road_01.png"
const UPPER_PATH := "Unidot/Assets/Synty/PolygonGeneric/Textures/Generic_Road_01.png"
const LOWER_RELATIVE := "../textures/Generic_Road_01.png"
const UPPER_RELATIVE := "../Textures/Generic_Road_01.png"


func _initialize() -> void:
	var candidates: Dictionary = {}
	# Preserve the problematic order: the lowercase candidate is encountered
	# first and both spellings appear to exist on a case-insensitive filesystem.
	candidates[LOWER_PATH] = LOWER_RELATIVE
	candidates[UPPER_PATH] = UPPER_RELATIVE
	var package_output_paths := {UPPER_PATH: true}
	var filesystem_checks: Array[String] = []
	var resolved: String = ASSET_ADAPTER.FbxHandler.resolve_texture_candidate(
		candidates,
		package_output_paths,
		func(candidate_path: String) -> bool:
			filesystem_checks.append(candidate_path)
			return true
	)
	if resolved != UPPER_RELATIVE:
		_fail(
			"Exact package path did not win over lowercase filesystem match: "
			+ resolved
		)
		return
	if not filesystem_checks.is_empty():
		_fail("Filesystem fallback ran before exact package candidates were exhausted.")
		return

	# With no package match, retain the existing ordered filesystem fallback.
	filesystem_checks.clear()
	resolved = ASSET_ADAPTER.FbxHandler.resolve_texture_candidate(
		candidates,
		{},
		func(candidate_path: String) -> bool:
			filesystem_checks.append(candidate_path)
			return candidate_path == UPPER_PATH
	)
	if resolved != UPPER_RELATIVE:
		_fail("Filesystem fallback did not return the first existing candidate: " + resolved)
		return
	if filesystem_checks != [LOWER_PATH, UPPER_PATH]:
		_fail("Filesystem fallback did not preserve candidate order: " + str(filesystem_checks))
		return

	print("UNIDOT_TEXTURE_CANDIDATE_CASE_RESOLUTION_TEST_PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error("UNIDOT_TEXTURE_CANDIDATE_CASE_RESOLUTION_TEST_FAIL: " + message)
	quit(1)

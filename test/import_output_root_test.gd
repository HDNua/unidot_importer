extends SceneTree

const PACKAGE_FILE := preload("res://addons/unidot_importer/package_file.gd")


func _initialize() -> void:
	var fixture := ProjectSettings.globalize_path(
		"res://addons/unidot_importer/test/RotationCorrectionTest.unitypackage"
	)
	var package = PACKAGE_FILE.new().init_with_filename(fixture)
	if package == null:
		_fail("Unable to read public unitypackage fixture.")
		return
	if package.guid_to_pkgasset.is_empty():
		_fail("Fixture did not contain any assets.")
		return

	var invalid_roots := [
		"/absolute",
		"user://outside",
		"../outside",
		"res://Unidot/../outside",
		"Unidot//Assets",
		"Unidot\\Assets",
	]
	for invalid_root in invalid_roots:
		if PACKAGE_FILE.validate_output_root(invalid_root).is_empty():
			_fail("Invalid output root was accepted: " + invalid_root)
			return
		if package.apply_output_root(invalid_root) != ERR_INVALID_PARAMETER:
			_fail("Invalid output root did not fail atomically: " + invalid_root)
			return

	var collision_guids: Array = package.guid_to_pkgasset.keys()
	var collision_asset = package.guid_to_pkgasset[collision_guids[1]]
	var collision_orig_path: String = collision_asset.orig_pathname
	collision_asset.orig_pathname = package.guid_to_pkgasset[collision_guids[0]].orig_pathname
	if package.validate_output_mapping("res://Unidot") != ERR_ALREADY_EXISTS:
		_fail("Duplicate mapped output paths were accepted.")
		return
	collision_asset.orig_pathname = collision_orig_path

	if package.apply_output_root("res://Unidot/") != OK:
		_fail("Unable to apply valid output root.")
		return
	if package.output_root != "Unidot":
		_fail("Output root was not normalized.")
		return
	if package.output_path_to_pkgasset.size() != package.guid_to_pkgasset.size():
		_fail("Output path index size differs from selected asset count.")
		return
	if not PACKAGE_FILE.is_output_path_for_source(
		"Unidot",
		"Assets/Example/Foo.mat",
		"Unidot/Assets/Example/Foo.mat.tres"
	):
		_fail("Mapped material output was not recognized.")
		return
	if not PACKAGE_FILE.is_output_path_for_source(
		"Unidot",
		"Assets/Example/Foo.prefab",
		"Unidot/Assets/Example/Foo.prefab.tscn"
	):
		_fail("Mapped prefab output was not recognized.")
		return
	if PACKAGE_FILE.is_output_path_for_source(
		"Unidot",
		"Assets/Example/Foo.mat",
		"Assets/Example/Foo.mat.tres"
	):
		_fail("An output from a different root was accepted.")
		return
	if not PACKAGE_FILE.is_output_path_for_source(
		"",
		"Assets/Example/Foo.scene",
		"Assets/Example/Foo.tscn"
	):
		_fail("Default-root scene output was not recognized.")
		return

	for source_path in package.path_to_pkgasset:
		var asset = package.path_to_pkgasset[source_path]
		if asset.orig_pathname != source_path:
			_fail("Unity source path was modified: " + source_path)
			return
		var expected_path := "Unidot".path_join(source_path)
		if asset.pathname != expected_path:
			_fail("Unexpected mapped path: " + asset.pathname)
			return
		if package.output_path_to_pkgasset.get(expected_path) != asset:
			_fail("Mapped path index does not resolve the source asset.")
			return

	var removed_guid = package.guid_to_pkgasset.keys()[0]
	var removed_asset = package.guid_to_pkgasset[removed_guid]
	package.guid_to_pkgasset.erase(removed_guid)
	package.path_to_pkgasset.erase(removed_asset.orig_pathname)
	if package.apply_output_root("Unidot") != OK:
		_fail("Unable to rebuild output index after selection pruning.")
		return
	if package.output_path_to_pkgasset.has("Unidot".path_join(removed_asset.orig_pathname)):
		_fail("Pruned asset remained in the output path index.")
		return

	if package.apply_output_root("res://") != OK:
		_fail("Unable to restore the backward-compatible project root.")
		return
	for guid in package.guid_to_pkgasset:
		var asset = package.guid_to_pkgasset[guid]
		if asset.pathname != asset.orig_pathname:
			_fail("Default output root changed an asset path.")
			return

	var final_asset_count: int = package.guid_to_pkgasset.size()
	for guid in package.guid_to_pkgasset:
		var asset = package.guid_to_pkgasset[guid]
		asset.icon = null
		asset.packagefile = null
	removed_asset.icon = null
	removed_asset.packagefile = null
	package.path_to_pkgasset.clear()
	package.output_path_to_pkgasset.clear()
	package.guid_to_pkgasset.clear()
	package.paths.clear()
	package = null
	removed_asset = null

	print("UNIDOT_IMPORT_OUTPUT_ROOT_TEST_PASS assets=", final_asset_count)
	quit(0)


func _fail(message: String) -> void:
	push_error("UNIDOT_IMPORT_OUTPUT_ROOT_TEST_FAIL: " + message)
	quit(1)

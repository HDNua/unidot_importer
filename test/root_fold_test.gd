extends SceneTree

const POST_IMPORT_MODEL := preload("res://addons/unidot_importer/post_import_model.gd")


func _initialize() -> void:
	var foldable_root := Node3D.new()
	var mesh_child := MeshInstance3D.new()
	foldable_root.add_child(mesh_child)
	foldable_root.add_child(AnimationPlayer.new())
	foldable_root.add_child(AnimationPlayer.new())

	var foldable_state = POST_IMPORT_MODEL.ParseState.new()
	foldable_state.toplevel_node = foldable_root
	if not foldable_state.fold_root_transforms_into_only_child():
		_fail("Multiple AnimationPlayer helpers prevented root folding.")
		foldable_root.free()
		return
	if foldable_state.toplevel_node != mesh_child:
		_fail("Root folding selected the wrong structural child.")
		foldable_root.free()
		return
	foldable_root.free()

	var ambiguous_root := Node3D.new()
	ambiguous_root.add_child(Node3D.new())
	ambiguous_root.add_child(Node3D.new())
	ambiguous_root.add_child(AnimationPlayer.new())
	var ambiguous_state = POST_IMPORT_MODEL.ParseState.new()
	ambiguous_state.toplevel_node = ambiguous_root
	if ambiguous_state.fold_root_transforms_into_only_child():
		_fail("A root with two structural children was folded.")
		ambiguous_root.free()
		return
	ambiguous_root.free()

	var helper_only_root := Node3D.new()
	helper_only_root.add_child(AnimationPlayer.new())
	helper_only_root.add_child(AnimationPlayer.new())
	var helper_only_state = POST_IMPORT_MODEL.ParseState.new()
	helper_only_state.toplevel_node = helper_only_root
	if helper_only_state.fold_root_transforms_into_only_child():
		_fail("A root containing only helper nodes was folded.")
		helper_only_root.free()
		return
	helper_only_root.free()

	print("UNIDOT_ROOT_FOLD_TEST_PASS")
	quit(0)


func _fail(message: String) -> void:
	push_error("UNIDOT_ROOT_FOLD_TEST_FAIL: " + message)
	quit(1)

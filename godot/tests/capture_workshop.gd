extends SceneTree
var game: Node
var output := ""
func _initialize() -> void: call_deferred("run")
func select_text(picker: OptionButton, text: String) -> void:
	for i in range(picker.item_count):
		if picker.get_item_text(i) == text: picker.select(i); picker.item_selected.emit(i); return
func shot(name: String) -> void:
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	if game.editor.visible and game.editor.get_global_rect().end.y > game.get_viewport_rect().size.y:
		push_error("Workshop footer outside viewport"); quit(1); return
	root.get_texture().get_image().save_png(output.path_join(name + ".png"))
func run() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"): quit(1); return
	output = OS.get_environment("HABITAT_CAPTURE_DIR")
	if output.is_empty(): quit(1); return
	DirAccess.make_dir_recursive_absolute(output)
	game = load("res://scenes/main.tscn").instantiate(); root.add_child(game)
	game.save_enabled = false; game.view.sound_enabled = false; game.world.local_companion.set_enabled(false)
	game._toggle_workshop()
	await shot("people")
	select_text(game.editor.group_picker, "劳动"); select_text(game.editor.action_picker, "砍树"); select_text(game.editor.direction_picker, "左侧")
	game.editor.frame_picker.select(1); game.editor.frame_picker.item_selected.emit(1)
	await shot("labor")
	game.editor.open_art("cottage-blue")
	await shot("building")
	game.editor.structure_toggle.pressed.emit()
	await shot("structure")
	game.editor.open_art("camp-grill")
	await shot("facility")
	game._toggle_workshop(); await shot("closed")
	game._toggle_workshop(); await shot("reopened")
	print("Workshop UI captured; model helper pid=", game.link._pid)
	quit()

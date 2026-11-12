extends SceneTree
const Library = preload("res://scripts/character_library.gd")
const Editor = preload("res://scripts/character_editor.gd")
var checks := 0
var failed := false
func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition: failed = true; push_error(message)
func _initialize() -> void:
	call_deferred("run")
func run() -> void:
	var directory := OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"): quit(1); return
	var library := Library.new(); library.configure(directory)
	var editor := Editor.new(); root.add_child(editor); editor.setup(library); editor.open_art("white-haired-girl")
	await process_frame
	var canvas: Control = editor.canvas
	var original: Array = canvas.art.frames.down_0[0].pixels.duplicate()
	canvas.color = Color("df2351")
	var down := InputEventMouseButton.new(); down.button_index = MOUSE_BUTTON_LEFT; down.pressed = true; down.position = Vector2(1, 1)
	canvas._gui_input(down)
	var up := InputEventMouseButton.new(); up.button_index = MOUSE_BUTTON_LEFT; up.pressed = false; up.position = Vector2(1, 1)
	canvas._gui_input(up)
	check(canvas.art.frames.down_0[0].pixels[0] != original[0], "paint via canvas input adds new contour pixel")
	canvas.undo(); check(canvas.art.frames.down_0[0].pixels == original, "stroke undo exact")
	canvas.redo(); check(canvas.art.frames.down_0[0].pixels[0] != original[0], "redo stroke")
	editor._add_layer(); check(canvas.art.frames.down_0.size() == 2, "new free layer")
	editor._visibility(); check(not canvas.art.frames.down_0[1].visible, "toggle layer")
	editor._delete_layer(); check(canvas.art.frames.down_0.size() == 1, "delete layer")
	editor._publish(); check(library.artworks["white-haired-girl"].frames.down_0[0].pixels[0] != original[0], "save applies same pixels to runtime library")
	editor._undo_publish(); check(library.artworks["white-haired-girl"].frames.down_0[0].pixels == original, "undo applied visual change")
	editor.preview_playing = true; editor._process(.2); check(editor.preview.texture != null, "walking preview renders")
	editor.open_art("cottage")
	check(editor.structure_toggle.visible and not editor.structure_panel.visible and editor.frame_picker.item_count == 5 and canvas.frame == "stage_4", "building editor uses construction frames")
	var old_quote: int = library.compile_blueprint("cottage").wood
	editor.structure_inputs.width.value = 9
	editor._publish()
	check(library.compile_blueprint("cottage").wood > old_quote, "structure UI changes saved cost")
	editor.open_art("camp-grill")
	check(not editor.structure_panel.visible and editor.frame_picker.item_count == 4, "facility editor uses cooking states")
	editor.open_art("white-haired-girl")
	check(editor.frame_picker.item_count == 1 and canvas.art.frames.has("chop_up_1") and editor.character_filters.visible, "character cooking actions editable in same canvas")
	editor.queue_free()
	await process_frame
	print("Editor interaction: %s checks, %s" % [checks, "FAIL" if failed else "PASS"])
	quit(1 if failed else 0)

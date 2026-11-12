# DIRECTION 2026-11-11: additive new Orange work; all original editable works remain.
extends SceneTree
const Library = preload("res://scripts/character_library.gd")
const Workshop = preload("res://scripts/character_editor.gd")
const Catalog = preload("res://scripts/workshop_catalog.gd")
var checks := 0
var failed := false
func check(value: bool, message: String) -> void:
	checks += 1
	if not value: failed = true; push_error(message)
func select_text(picker: OptionButton, value: String) -> void:
	for i in range(picker.item_count):
		if picker.get_item_text(i) == value:
			picker.select(i); picker.item_selected.emit(i); return
	check(false, "missing option " + value)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var directory := OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"): quit(1); return
	var library := Library.new(); library.configure(directory)
	var editor := Workshop.new(); root.add_child(editor); editor.setup(library); editor.toggle_workshop()
	await process_frame
	check(editor.visible and editor.character_id == "white-haired-girl", "first toggle opens companion")
	check(editor.work_picker.item_count == 15 and editor.category_tabs.current_tab == 0, "people category includes five original, eight spare, Suit Hulk and the new Orange character works")
	select_text(editor.group_picker, "劳动"); select_text(editor.action_picker, "砍树"); select_text(editor.direction_picker, "左侧")
	check(editor.frame_picker.item_count == 3 and editor.canvas.frame == "chop_left_0", "labor action and direction isolate three frames")
	editor.frame_picker.select(1); editor.frame_picker.item_selected.emit(1)
	editor.layer_name.text = "测试图层"; editor._add_layer()
	editor.canvas.color = Color("fd1355"); editor.canvas.checkpoint(); editor.canvas.paint(Vector2i(0,0)); editor.canvas.refresh()
	var edited: int = editor.canvas.art.frames.chop_left_1[1].pixels[0]
	var undo_count: int = editor.canvas.undo_stack.size()
	check(editor.dirty and editor.draft_label.text.contains("尚未应用"), "pixel change marks draft")
	check(library.artworks["white-haired-girl"].frames.chop_left_1.size() == 1, "unapplied draft never mutates live art")
	editor.preview_playing = true; editor._process(.2)
	editor.toggle_workshop(); check(not editor.visible, "same toggle closes")
	editor.toggle_workshop(); await process_frame
	check(editor.canvas.frame == "chop_left_1" and editor.canvas.layer == 1 and editor.preview_playing, "reopen preserves exact action layer and preview mode")
	check(editor.canvas.art.frames.chop_left_1[1].pixels[0] == edited and editor.canvas.undo_stack.size() == undo_count, "reopen preserves pixels and undo history")
	editor.category_tabs.current_tab = 1
	check(editor.category == "building" and editor.work_picker.item_count == 3 and editor.canvas.frame == "stage_4", "building tab separates templates and defaults to finished appearance")
	check(not editor.character_filters.visible and editor.structure_toggle.visible and not editor.structure_panel.visible, "building controls separate from character actions")
	editor.structure_toggle.pressed.emit(); editor.structure_inputs.width.value = 9
	check(editor.dirty and library.artworks.cottage.structure.width == 8, "structural draft does not update live costs")
	editor.category_tabs.current_tab = 2
	check(editor.category == "facility" and editor.work_picker.item_count == library.artworks.values().filter(func(art):return art.get("kind")=="facility").size() and editor.frame_picker.item_count == 4 and not editor.use_blueprint.visible, "facility states separated")
	editor.category_tabs.current_tab = 0
	check(editor.canvas.frame == "chop_left_1" and editor.canvas.art.frames.chop_left_1[1].pixels[0] == edited and editor.dirty, "category roundtrip retains character draft")
	select_text(editor.work_picker, "你"); editor.canvas.color = Color("ffdd00"); editor.canvas.checkpoint(); editor.canvas.paint(Vector2i(1,1)); editor.canvas.refresh()
	select_text(editor.work_picker, "小白")
	check(editor.canvas.frame == "chop_left_1" and editor.canvas.art.frames.chop_left_1[1].pixels[0] == edited, "two resident drafts are independent")
	editor.canvas.undo()
	check(editor.canvas.art.frames.chop_left_1[1].pixels[0] == 0, "retained history undoes original stroke")
	editor.canvas.redo(); editor._publish()
	check(not editor.dirty and library.artworks["white-haired-girl"].frames.chop_left_1[1].pixels[0] == edited, "explicit apply publishes only selected draft")
	check(library.artworks.cottage.structure.width == 8 and library.artworks["human-starter"].frames.down_0[0].pixels[97] == 0, "other drafts remain unapplied")
	# Simulate an externally published version while our draft is dirty.
	editor.canvas.checkpoint(); editor.canvas.paint(Vector2i(2,2)); editor.canvas.refresh()
	editor.open_art("furniture-chair")
	check(editor.category == "facility" and editor.canvas.frame == "down" and editor.frame_picker.item_count == 2, "furniture shares facility editor with real orientation frames")
	editor.preview_playing = true; editor._process(.6)
	check(Catalog.preview_frames(editor.canvas.art, "down") == ["down", "up"] and editor.preview.texture != null, "furniture preview never uses character walk-frame names")
	editor.open_art("white-haired-girl")
	var base: int = library.artworks["white-haired-girl"].revision
	check(library.patch("white-haired-girl", {"base_revision":base,"frame":"up_0","layer":0,"pixels":[{"x":0,"y":0,"color":"#001122ff"}]}).ok, "external artwork edit")
	editor.toggle_workshop(); editor.toggle_workshop(); editor._publish()
	check(editor.dirty and editor.feedback.text.contains("草稿仍保留") and editor.base_revision == base, "stale save preserves draft instead of overwriting other author")
	editor._request_discard("reload")
	check(editor.discard_dialog.visible, "explicit destructive reload asks once")
	editor.discard_dialog.hide(); editor._discard_action()
	check(not editor.dirty and editor.base_revision == base + 1, "explicit discard loads latest saved version")
	var keys: Dictionary = {}
	for group in Catalog.GROUPS:
		for key in Catalog.frames(editor.canvas.art, group): keys[key] = true
	check(keys.size() == editor.canvas.art.frames.size(), "every authored frame remains reachable through groups")
	var custom: Dictionary = editor.canvas.art.duplicate(true); custom.frames["wave_custom"] = custom.frames.down_0.duplicate(true)
	check(Catalog.frames(custom, "生活", "自定义动作").has("wave_custom"), "unrecognized creator frames stay accessible")
	var esc := InputEventKey.new(); esc.keycode = KEY_ESCAPE; esc.pressed = true
	editor._input(esc); check(not editor.visible, "Esc closes while retaining draft")
	editor.toggle_workshop()
	var mouse := InputEventMouseButton.new(); mouse.button_index = MOUSE_BUTTON_LEFT; mouse.pressed = true; mouse.position = Vector2(2,2)
	editor.canvas._gui_input(mouse); editor.close_workshop(); editor.toggle_workshop()
	check(not editor.canvas._painting, "close during a stroke cannot leave painting stuck")
	editor.category_tabs.current_tab = 1
	check(editor.canvas.art.structure.width == 9 and editor.structure_panel.visible, "building draft and expanded section survive roundtrip")
	editor._publish()
	check(library.compile_blueprint("cottage").wood > 60, "applying building draft updates template quote")
	editor.queue_free(); await process_frame
	# Actual handbook entry is a toggle, doesn't reopen the default character each time.
	var game: Node = load("res://scenes/main.tscn").instantiate(); root.add_child(game)
	game.save_enabled = false; game.set_process(false); game.view.sound_enabled = false
	await process_frame
	var popup: PopupMenu=game.handbook_menu.get_popup()
	var workshop_index:=-1
	for index in range(popup.item_count):
		if popup.get_item_metadata(index)=="workshop":workshop_index=popup.get_item_id(index);break
	check(workshop_index>=0, "handbook exposes workshop entry")
	popup.id_pressed.emit(workshop_index); game.editor.open_art("camp-grill"); popup.id_pressed.emit(workshop_index)
	check(not game.editor.visible, "toolbar hides workshop")
	popup.id_pressed.emit(workshop_index)
	await process_frame
	await process_frame
	check(game.editor.get_global_rect().end.y < game.get_viewport_rect().size.y, "workshop including save footer fits viewport")
	check(game.editor.visible and game.editor.character_id == "camp-grill", "toolbar reopens last facility")
	check(game.editor.position.y > 65 and game.link._pid == -1, "toolbar stays exposed and editor never starts model")
	game.queue_free(); await process_frame
	print("Workshop categories and drafts: %s checks, %s" % [checks, "FAIL" if failed else "PASS"])
	quit(1 if failed else 0)

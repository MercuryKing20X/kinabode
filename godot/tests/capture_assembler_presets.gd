extends SceneTree
const Library = preload("res://scripts/character_library.gd")
const Assembler = preload("res://scripts/character_assembler.gd")
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var directory := OS.get_environment("HABITAT_DATA_DIR")
	var output := OS.get_environment("HABITAT_RUN_EVIDENCE")
	if not directory.contains("youqi-test-") or output.is_empty(): quit(1); return
	root.size = Vector2i(1280, 800)
	var library := Library.new(); library.configure(directory)
	var background := ColorRect.new(); background.color = Color("334c40"); background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); root.add_child(background)
	var box := HBoxContainer.new(); box.position = Vector2(140, 220); box.add_theme_constant_override("separation", 50); background.add_child(box)
	for name in Assembler.PRESETS:
		var result: Dictionary = Assembler.assemble(library, Assembler.PRESETS[name], name)
		assert(result.ok)
		var col := VBoxContainer.new(); box.add_child(col)
		var label := Label.new(); label.text = name; label.add_theme_font_override("font", load("res://assets/fonts/NotoSansSC.ttf")); col.add_child(label)
		var portrait := TextureRect.new(); portrait.custom_minimum_size = Vector2(192, 256); portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.texture = library.texture(result.id, "down_0"); col.add_child(portrait)
	await process_frame; await process_frame; await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output.path_join("08-four-assembled-presets.png")) == OK)
	quit()

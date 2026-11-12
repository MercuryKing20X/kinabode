extends SceneTree
const Library = preload("res://scripts/character_library.gd")

class ReviewGrid extends Node2D:
	var textures: Array = []
	var title := ""
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, get_viewport_rect().size), Color("334c40"))
		var left: float = (get_viewport_rect().size.x - 768.0) / 2.0
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(left, 17), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("fff0cf"))
		for row in range(3):
			for column in range(4):
				var texture: Texture2D = textures[row * 4 + column]
				draw_texture_rect_region(texture, Rect2(left + column * 192, 20 + row * 200, 192, 200), Rect2(0, 20, 96, 100))

func _initialize() -> void: call_deferred("run")

func run() -> void:
	var directory := OS.get_environment("HABITAT_DATA_DIR")
	var output := OS.get_environment("HABITAT_RUN_EVIDENCE")
	if not directory.contains("youqi-test-") or output.is_empty(): quit(1); return
	var library := Library.new(); library.configure(directory)
	var original: Dictionary = library.artworks["human-starter"]
	var changed: Dictionary = original.duplicate(true)
	changed.outfit = JSON.parse_string(FileAccess.get_file_as_string(output.path_join("human-starter-review-outfit.json")))
	assert(library.valid(changed))
	var grid := ReviewGrid.new(); root.add_child(grid)
	for size in [Vector2i(1280, 800), Vector2i(960, 640)]:
		root.size = size
		for variant in ["before", "after"]:
			grid.textures.clear()
			grid.title = "Human starter · %s · 2x" % variant
			for index in range(3):
				for direction in ["down", "left", "right", "up"]:
					grid.textures.append(ImageTexture.create_from_image(library.render(original if variant == "before" else changed, "%s_%s" % [direction, index])))
			grid.queue_redraw(); await process_frame; await process_frame; await RenderingServer.frame_post_draw
			assert(root.get_texture().get_image().save_png(output.path_join("04-human-%s-%sx%s.png" % [variant, size.x, size.y])) == OK)
	quit()

extends SceneTree
const Places=preload("res://scripts/map_locations.gd")

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var directory := OS.get_environment("HABITAT_DATA_DIR")
	var output := OS.get_environment("HABITAT_CAPTURE_DIR")
	if not directory.contains("youqi-test-") or output.is_empty(): quit(1); return
	DirAccess.make_dir_recursive_absolute(output)
	var game: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(game)
	game.save_enabled = false
	game.set_process(false)
	game.view.set_process(false)
	game.view.sound_enabled = false
	game.view.center = Places.point("p_52_43")
	game.view.zoom = 1.15
	for frame in range(48):
		game.world.advance(1.0 / 12)
		game.view._process(1.0 / 12)
		await process_frame
		await RenderingServer.frame_post_draw
		if frame % 2 == 0: root.get_texture().get_image().save_png(output.path_join("idle-%03d.png" % frame))
	game.world.command("codex", {"intent": "chop", "target_id": "home.tree.01"})
	for tick in range(10000):
		if not game.world._routes.has("codex"): break
		game.world.advance(.02)
	game.view.center = Places.point("p_61_28")
	game.view._process(.3)
	for frame in range(108):
		game.world.advance(1.0 / 12)
		game.view._process(1.0 / 12)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("chop-%03d.png" % frame))
	# Reach chest via the same job and capture handling before real transfer.
	for tick in range(10000):
		game.world.advance(.02)
		if game.world.actors.codex.activity == "putting_down": break
	game.view.center = Places.point("p_48_41")
	for frame in range(18):
		game.world.advance(1.0 / 12)
		game.view._process(1.0 / 12)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("deposit-%03d.png" % frame))
	print("Viewport motion evidence saved to " + output)
	quit()

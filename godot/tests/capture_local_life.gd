extends SceneTree
const Places=preload("res://scripts/map_locations.gd")
var game: Node
var output := ""
func _initialize() -> void: call_deferred("run")
func render_frame() -> void:
	game._process(.1)
	game.view._process(.1)
	await process_frame
	await RenderingServer.frame_post_draw
func run() -> void:
	var directory := OS.get_environment("HABITAT_DATA_DIR")
	output = OS.get_environment("HABITAT_CAPTURE_DIR")
	if not directory.contains("youqi-test-") or output.is_empty(): quit(1); return
	DirAccess.make_dir_recursive_absolute(output)
	game = load("res://scenes/main.tscn").instantiate(); root.add_child(game)
	game.save_enabled = false; game.set_process(false); game.view.set_process(false); game.view.sound_enabled = false
	game.world.local_companion.rng.seed = 28
	game.view.center = Places.point("p_52_43"); game.view.zoom = 1.3
	game._local_interaction(false)
	game.chat.show()
	await render_frame()
	root.get_texture().get_image().save_png(output.path_join("controls.png"))
	game.chat.hide()
	for frame in range(150):
		if frame == 40: game.world.command("human", {"intent": "move", "x":Places.point("p_55_0_45_0").x,"y":Places.point("p_55_0_45_0").y})
		if frame == 55: game._local_interaction(true)
		await render_frame()
		root.get_texture().get_image().save_png(output.path_join("nearby-%03d.png" % frame))
	game.world.local_companion.set_enabled(false)
	game.world.command("codex", {"intent": "move", "x":Places.point("p_26_8_49_0").x,"y":Places.point("p_26_8_49_0").y})
	for tick in range(6000):
		game.world.advance(.1)
		if not game.world._routes.has("codex"): break
	game.world.local_companion.set_enabled(true)
	if not game.world.local_companion._start("rest"): push_error("rest unavailable"); quit(1); return
	game.view.center = Places.point("p_24_47"); game.view.zoom = 1.3
	for frame in range(110):
		await render_frame()
		root.get_texture().get_image().save_png(output.path_join("rest-%03d.png" % frame))
	print("Local-life capture: helper PID ", game.link._pid, ", meals ", game.world.life.station.meals_eaten)
	quit()

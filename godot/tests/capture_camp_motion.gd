extends SceneTree
const Places=preload("res://scripts/map_locations.gd")
var game: Node
var output := ""
func _initialize() -> void: call_deferred("run")
func finish(id: String) -> void:
	for tick in range(6000):
		if not game.world.work.jobs.has(id): return
		game.world.advance(.1)
func capture(prefix: String, count: int) -> void:
	for frame in range(count):
		game.world.advance(.1)
		game.view._process(.1)
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("%s-%03d.png" % [prefix, frame]))
func run() -> void:
	var directory := OS.get_environment("HABITAT_DATA_DIR")
	output = OS.get_environment("HABITAT_CAPTURE_DIR")
	if not directory.contains("youqi-test-") or output.is_empty(): quit(1); return
	DirAccess.make_dir_recursive_absolute(output)
	game = load("res://scenes/main.tscn").instantiate(); root.add_child(game)
	game.save_enabled = false; game.set_process(false); game.view.set_process(false); game.view.sound_enabled = false
	for request in [{"intent": "chop", "target_id": "home.tree.01"}, {"intent": "forage", "target_id": "home.mushrooms.1"}, {"intent": "barbecue", "target_id": "home.barbecue"}]:
		var result: Dictionary = game.world.command("codex", request)
		if not result.ok: push_error(str(result)); quit(1); return
		finish("codex")
	game.view.center = Places.point("p_24_46"); game.view.zoom = 1.5
	await capture("fire", 50)
	for tick in range(140): game.world.advance(.1)
	game.world.command("codex", {"intent": "turn_food", "target_id": "home.barbecue"}); finish("codex")
	# Move both residents nearby through real routes before inviting them to eat.
	game.world.command("human", {"intent": "move", "x":Places.point("p_21_2_50_0").x,"y":Places.point("p_21_2_50_0").y})
	game.world.command("codex", {"intent": "move", "x":Places.point("p_26_8_50_0").x,"y":Places.point("p_26_8_50_0").y})
	for tick in range(2000):
		game.world.advance(.1)
		if game.world._routes.is_empty() and game.world.life.station.state == "ready": break
	game.world.command("human", {"intent": "eat", "target_id": "home.barbecue"})
	game.world.command("codex", {"intent": "eat", "target_id": "home.barbecue"})
	await capture("meal", 135)
	print("Camp viewport captured; meals actually eaten: ", game.world.life.station.meals_eaten)
	quit()

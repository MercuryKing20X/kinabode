extends SceneTree
const Places=preload("res://scripts/map_locations.gd")
var game: Node
var output := ""
func _initialize() -> void: call_deferred("run")
func record_stage(stage: int) -> void:
	game.house_panel.refresh(); game.view._process(.1)
	await process_frame; await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("stage-%s.png" % stage))
func run() -> void:
	var directory := OS.get_environment("HABITAT_DATA_DIR")
	output = OS.get_environment("HABITAT_CAPTURE_DIR")
	if not directory.contains("youqi-test-") or output.is_empty(): quit(1); return
	DirAccess.make_dir_recursive_absolute(output)
	game = load("res://scenes/main.tscn").instantiate(); root.add_child(game)
	game.save_enabled = false; game.set_process(false); game.view.set_process(false); game.view.sound_enabled = false; game.world.local_companion.set_enabled(false)
	game.world.command("human", {"intent": "select_blueprint", "target_id": "home.house.01", "blueprint_id": "cottage-blue"})
	for i in range(1,9):
		game.world.command("codex", {"intent": "chop", "target_id": "home.tree.%02d" % i})
		for tick in range(6000):
			game.world.advance(.1)
			if not game.world.work.jobs.has("codex"): break
	game.view.center = Places.point("p_39_40"); game.view.zoom = 1.0; game.view.selected_id = "home.house.01"; game.house_panel.open_site("home.house.01")
	await record_stage(0)
	for stage in range(1,6):
		var result: Dictionary = game.world.command("codex", {"intent": "build", "target_id": "home.house.01"})
		if not result.ok: push_error(str(result)); quit(1); return
		for tick in range(6000):
			game.world.advance(.1)
			if not game.world.work.jobs.has("codex"): break
		await record_stage(stage)
	print("Built from real harvest; invested wood=",game.world.objects["home.house.01"].invested)
	quit()

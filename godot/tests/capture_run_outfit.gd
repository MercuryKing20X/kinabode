extends "res://tests/capture_home_v3_ui_polish.gd"

func save_view(name: String) -> void:
	game.view.center = game.world.point(game.world.actors.human)
	game.view.motion.advance(.15, game.world.actors, {"human": game.world.is_running("human"), "codex": game.world.is_running("codex")})
	game.view.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output.path_join(name + ".png")) == OK)

func run() -> void:
	output = OS.get_environment("HABITAT_RUN_EVIDENCE")
	if output.is_empty() or not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"): quit(1); return
	root.size = Vector2i(1280, 800)
	game = load("res://scenes/main_v3.tscn").instantiate()
	game.world = preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	root.add_child(game)
	game.save_enabled = false; game.set_process(false); game.view.set_process(false)
	game.view.sound_enabled = false; game.world.director.set_all_enabled(false)
	game.view.zoom = 1; game.view.follow_player = false
	var center: Array = game.world.map_anchor("plaza.center")
	game.world.actors.human.position = [center[0], center[1]]
	game.world.actors.codex.position = [float(center[0]) + 2, center[1]]
	var p: Vector2 = game.world.point(game.world.actors.human)
	var human_route: Array[Vector2] = [p + Vector2(18, 0)]
	var companion_route: Array[Vector2] = [p + Vector2(20, 0)]
	game.world._apply_route("human", human_route)
	game.world._apply_route("codex", companion_route)
	game.world.advance(.1)
	await save_view("01-running")
	# Visual-only fixture in an isolated world; never written to the player save.
	game.world.actors.human.carry = {"wood": 1}
	game.world.advance(.1)
	await save_view("02-carry")
	game.world.actors.human.carry = {}
	companion_route = [game.world.point(game.world.actors.codex) + Vector2(4, 0)]
	game.world._apply_route("codex", companion_route)
	game.world.advance(.1)
	await save_view("03-companion-near")
	quit()

extends SceneTree

var game: Node

func _initialize() -> void:
	call_deferred("run")

func mouse(at: Vector2) -> void:
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.position = at
		event.global_position = at
		root.push_input(event, true)
		await process_frame

func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("HABITAT_PLAYTEST_CAPTURE").path_join(name + ".png"))

func run() -> void:
	var directory := OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-") or OS.get_environment("HABITAT_PLAYTEST_CAPTURE").is_empty():
		quit(1)
		return
	root.size = Vector2i(1280, 800)
	root.content_scale_size = Vector2i.ZERO
	var world = preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	world.residents.provision(world)
	world.library = preload("res://scripts/character_library.gd").new()
	world.library.configure(directory)
	assert(preload("res://scripts/world_opening.gd").apply(world, world.library, "showcase").ok)
	var site: Dictionary = world.leisure.sites["play.gomoku"]
	var point: Vector2 = world.point(site)
	world.actors.human.position = [point.x, point.y + 2]
	assert(preload("res://scripts/save_store.gd").save_world(world, directory))
	OS.set_environment("HABITAT_OPENING", "showcase")
	game = load("res://scenes/main_v3.tscn").instantiate()
	root.add_child(game)
	game.save_enabled = false
	for i in range(30): await process_frame
	game.chat.hide()
	game.view.center = game.world.point(game.world.leisure.sites["play.gomoku"])
	game.view.zoom = 1
	for i in range(5): await process_frame
	var rect: Rect2 = game.view.leisure_renderer.rect(game.view, game.world.leisure.sites["play.gomoku"])
	var at := rect.position + Vector2(rect.size.x / 2, rect.size.y * 0.25)
	print("Table hit: ", game.view.hit(at))
	await mouse(at)
	print("Table popup visible: ", game.chess_choice.visible)
	await capture("original-table")
	game.chess_choice.hide()
	game.island_hud.context_signature = ""
	game.island_hud.refresh_context()
	for button in game.island_hud.context.get_children():
		if button is BaseButton and button.text == preload("res://scripts/localization.gd").text("hud.gomoku"):
			await mouse(button.global_position + button.size / 2)
			print("Bottom popup visible: ", game.chess_choice.visible)
			await capture("original-bottom")
			print("Both real entry clicks captured from saved showcase")
			quit(0)
			return
	push_error("Chess context button absent")
	quit(1)

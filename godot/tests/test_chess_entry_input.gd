extends SceneTree

var game: Node
var failures := 0

func _initialize() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	if not value:
		failures += 1
		push_error(message)

func click(control: Control) -> void:
	var at := control.global_position + control.size / 2
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.position = at
		event.global_position = at
		root.push_input(event, true)
		await process_frame

func button(node: Node, key: String) -> BaseButton:
	if node is BaseButton and node.get_meta("chess_key", "") == key: return node
	for child in node.get_children():
		var found := button(child, key)
		if found != null: return found
	return null

func run() -> void:
	var directory := OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"): quit(1); return
	root.size = Vector2i(1280, 800)
	root.content_scale_size = Vector2i.ZERO
	var world = preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	world.residents.provision(world)
	world.library = preload("res://scripts/character_library.gd").new()
	world.library.configure(directory)
	check(preload("res://scripts/world_opening.gd").apply(world, world.library, "showcase").ok, "showcase fixture")
	var point: Vector2 = world.point(world.leisure.sites["play.gomoku"])
	world.actors.human.position = [point.x, point.y + 2]
	check(preload("res://scripts/save_store.gd").save_world(world, directory), "save fixture")
	OS.set_environment("HABITAT_OPENING", "showcase")
	game = load("res://scenes/main_v3.tscn").instantiate()
	root.add_child(game)
	game.save_enabled = false
	for i in range(30): await process_frame
	game.chat.hide()
	game.island_hud.context_signature = ""
	game.island_hud.refresh_context()
	var entry: BaseButton = game.island_hud.chess_button
	check(entry != null, "nearby chess button")
	if entry == null: quit(1); return
	await click(entry)
	check(game.chess_choice.visible, "bottom opens choice")
	check(game.chess_choice.site_id == "play.gomoku", "bottom binds actual table")
	var jieqi := button(game.chess_choice, "jieqi.title")
	check(jieqi != null, "jieqi option")
	if jieqi != null:
		await click(jieqi)
		check(game.chess_choice.stage == "mode", "jieqi enters mode selection")
		var standard := button(game.chess_choice, "chess.standard")
		check(standard != null, "standard mode")
		if standard != null:
			await click(standard)
			check(game.jieqi_panel.visible, "standard opens opponent picker")
			check(game.jieqi_panel.picker.get_popup().theme.default_font.resource_path.ends_with("NotoSerifSC-Black.ttf"),"chess dropdown keeps Heavy font")
	game.jieqi_panel.hide()
	game.view.center = point
	game.view.zoom = 1
	for i in range(5): await process_frame
	var rect: Rect2 = game.view.leisure_renderer.rect(game.view, game.world.leisure.sites["play.gomoku"])
	var at := rect.position + Vector2(rect.size.x / 2, rect.size.y * 0.25)
	print("Table rect ", rect, " hit ", game.view.hit(at))
	for down in [true, false]:
		var event := InputEventMouseButton.new()
		event.button_index = MOUSE_BUTTON_LEFT
		event.pressed = down
		event.position = at
		event.global_position = at
		root.push_input(event, true)
		await process_frame
	check(game.chess_choice.visible, "table opens choice")
	check(game.chess_choice.site_id == "play.gomoku", "table binds actual table")
	game.queue_free()
	await process_frame
	await process_frame
	# A real saved opponent must remain selected when continuing, even when it
	# differs from the first name in the panel's roster.
	world.jieqi.game = preload("res://scripts/jieqi_rules.gd").initial(17)
	world.jieqi.opponent = "companion-2"
	world.jieqi.match_id = "jieqi-resume-entry"
	world.jieqi.phase = "paused"
	check(preload("res://scripts/save_store.gd").save_world(world, directory), "save retained opponent fixture")
	game = load("res://scenes/main_v3.tscn").instantiate()
	root.add_child(game)
	game.save_enabled = false
	for i in range(30): await process_frame
	game.chat.hide()
	await click(game.island_hud.chess_button)
	var continuation := button(game.chess_choice, "chess.continue")
	check(continuation != null, "saved game offers continuation first")
	if continuation != null:
		await click(continuation)
		check(game.jieqi_panel.visible, "continue opens retained board")
		check(game.jieqi_panel.ids[game.jieqi_panel.picker.selected] == "companion-2", "continue displays actual saved opponent")
		await click(game.jieqi_panel.start_button)
		check(game.world.jieqi.phase in ["arriving", "playing"] and game.world.jieqi.opponent == "companion-2", "explicit resume seats actual saved opponent")
	preload("res://scripts/localization.gd").select(directory, "en")
	root.size = Vector2i(960, 640)
	game.island_hud.refresh()
	await process_frame
	await process_frame
	print("English bottom rectangles: ", game.island_hud.primary_actions.get_global_rect(), " / ", game.island_hud.utility_actions.get_global_rect())
	check(not game.island_hud.primary_actions.get_global_rect().intersects(game.island_hud.utility_actions.get_global_rect()), "four bottom actions keep clear of English utilities at 960")
	print("Chess input failures: ", failures)
	quit(1 if failures else 0)

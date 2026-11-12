extends SceneTree
const H=preload("res://tests/homestead_fixture.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	var game: Node=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false)
	await process_frame
	game.world.director.set_all_enabled(false);game.view.sound_enabled=false
	# Fixture material production precedes the client session, without free meals.
	game.world.hunger.enabled=false
	if not H.stock(game.world):push_error("physical M4 fixture failed");quit(1);return
	game.world.hunger.start()
	game._bind_external_ai("codex",true,false);game._select_chat("codex");game._send("测试客户端处理M4，本轮没有真实模型推理。")
	Engine.time_scale=6;game.set_process(true)

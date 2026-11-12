extends SceneTree
const Fish=preload("res://tests/fishing_fixture.gd")
var game: Node
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false)
	await process_frame
	game.world.director.set_all_enabled(false);game.view.sound_enabled=false;game.world.fishing.rng.seed=101
	if not Fish.coast(game.world,"codex"):quit(1);return
	game.ai_connect_panel.open();game.ai_connect_panel.hide();game._bind_external_ai("codex",true,false)
	game._select_chat("codex");game._send("图鉴外部接口测试消息，仅测试客户端，不调用真实模型。")
	Engine.time_scale=6;game.set_process(true)

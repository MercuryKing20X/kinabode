extends SceneTree
const Fixture=preload("res://tests/fishing_fixture.gd")
var game: Node
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);game.view.sound_enabled=false
	await process_frame
	game.world.director.set_all_enabled(false)
	if not Fixture.coast(game.world,"codex"):quit(1);return
	game.ai_connect_panel.open();game.ai_connect_panel.hide();game._bind_external_ai("codex",true,false)
	game._select_chat("codex");game._send("外部MCP适配器契约测试消息，不是真实模型推理。")
	game.set_process(true)

extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
var game: Node
func _initialize() -> void:call_deferred("run")
func run() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false)
	await process_frame
	game.world.director.set_all_enabled(false);game.view.sound_enabled=false
	# Arrange real farm stock before beginning the hunger-aware client session.
	# The protocol assertions remain unchanged; hunger abandonment has its own probe.
	game.world.hunger.enabled=false
	if not F.harvest(game.world,"turnip"):quit(1);return
	game.world.hunger.start()
	game.ai_connect_panel.open();game.ai_connect_panel.hide();game._bind_external_ai("codex",true,false)
	game._select_chat("codex");game._send("做菜外部接口测试消息，仅测试客户端，不调用真实模型。")
	Engine.time_scale=6;game.set_process(true)

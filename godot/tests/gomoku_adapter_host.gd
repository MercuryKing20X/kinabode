extends SceneTree
var game: Node
func _initialize() -> void:call_deferred("run")
func job(id: String,args: Dictionary) -> bool:
	if not game.world.command(id,args).ok:return false
	for i in range(18000):
		game.world.advance(.1)
		if not game.world.work.jobs.has(id):return true
	return false
func run() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	game=load("res://scenes/main.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return load("res://scripts/external_dialogue_link.gd").new()
	root.add_child(game);game.save_enabled=false;game.set_process(false)
	await process_frame
	game.world.director.set_all_enabled(false);game.view.sound_enabled=false
	if not job("codex",{"intent":"gather_wood","tree_count":10}) or not job("codex",{"intent":"build_facility","target_id":"play.gomoku"}):quit(1);return
	game.ai_connect_panel.open();game.ai_connect_panel.hide();game._bind_external_ai("codex",true,false)
	if not game.world.gomoku.begin_host("play.gomoku","codex",false,"model","normal").ok:quit(1);return
	for i in range(1500):
		game.world.advance(.1)
		if game.world.gomoku.sessions["play.gomoku"].phase=="playing":break
	game._select_chat("codex");game._send("五子棋外部接口测试消息，仅测试客户端，不是真实模型推理。")
	game.set_process(true)

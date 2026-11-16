extends SceneTree
var game:Node
var receipts:Array=[]
var replies:Array=[]
var faults:Array=[]
var round:=0
func _initialize()->void:run.call_deferred()
func wait_idle()->bool:
	var until:=Time.get_ticks_msec()+60000
	while Time.get_ticks_msec()<until:
		if not game.links.codex.is_busy():return true
		await process_frame
	return false
func observe(event:Dictionary)->void:
	if event.kind=="usage":receipts.append(event.duplicate(true))
	if event.kind=="intent_result":replies.append({"round":round,"speech":event.get("speech",""),"intents":event.get("intents",[])})
	if event.kind=="error":faults.append({"round":round,"code":event.get("code","error")})
func finish(ok:bool)->void:
	var report:Dictionary={"ok":ok,"receipts":receipts,"replies":replies,"faults":faults,"rounds":round,"following":game.world.activities.following.has("codex"),"other_models":game.world.actors.keys().filter(func(id):return id not in ["human","codex"] and game.world.director.model_controlled(id))}
	game.memory_books.atomic(OS.get_environment("HABITAT_DATA_DIR").path_join("live-result.json"),report)
	game.connection_pool.stop_all_ai();game.queue_free();await process_frame;quit(0 if ok else 1)
func run()->void:
	var base:=OS.get_environment("HABITAT_DATA_DIR")
	if OS.get_environment("HABITAT_LIVE_TEST")!="1" or not base.contains("habitat-live-test-"):quit(2);return
	var cfg:=ConfigFile.new();cfg.set_value("api","codex","openai");cfg.set_value("openai","chat",OS.get_environment("HABITAT_LIVE_MODEL"));cfg.set_value("openai","thinking",OS.get_environment("HABITAT_LIVE_MODEL"));cfg.save(base.path_join("connection-mode.cfg"))
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game)
	while game.connection_pool==null:await process_frame
	game.save_enabled=false;game.set_process(false);game.memory_life.set_process(false)
	game._record_chat("direct:codex","human","我喜欢雨后的海风。")
	game._simple_connection_action("codex","connect")
	game.links.codex.event_received.connect(observe)
	if not await wait_idle() or game._connection_light("codex").state!="ready":await finish(false);return
	for text in ["小白，我回来啦。","小白跟我来"]:
		round+=1;game._send_direct("codex",text)
		if not await wait_idle() or replies.size()!=round or not faults.is_empty():await finish(false);return
	game._simple_connection_action("codex","disconnect")
	game._simple_connection_action("codex","connect");game.links.codex.event_received.connect(observe)
	if not await wait_idle() or game._connection_light("codex").state!="ready":await finish(false);return
	round+=1;game._send_direct("codex","又连上啦，你还记得我喜欢什么吗？")
	if not await wait_idle():await finish(false);return
	await finish(replies.size()==3 and faults.is_empty())

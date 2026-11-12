extends "res://tests/probe_empowered_live.gd"
var watch:Array=[]
var watch_start:float=0
func save_live()->void:
	game.memory_books.atomic(base.path_join("steward-live-results.json"),{"turn_keys":seen_keys.keys(),"turns":turns,"events":events,"watch":watch,"history":game.intentions.history,"timeline":game.steward.timeline,"log":game.steward.events,"usage":game.autonomy.scheduler.usage("codex"),"elapsed_game_seconds":game.world.forest.clock-watch_start,"checks":checks,"failed":failed})
func chat_live(words:String)->void:
	number+=1
	if seen_keys.size()>=40:return
	var start:int=Time.get_ticks_msec()
	await text_input(words)
	while game.links.codex.is_busy() and Time.get_ticks_msec()-start<100000:
		game._process(.1);await create_timer(.1).timeout
	if game.links.codex.is_busy():game.links.codex.cancel_turn()
	for i in range(3500):
		game._process(.1)
		if i%50==0:await process_frame
		if game.intentions.plans.is_empty():break
	turns.append({"number":number,"human":words,"elapsed_ms":Time.get_ticks_msec()-start,"history":game.intentions.history.duplicate(true),"failure":game.intentions.last_failure.duplicate(true)})
	await picture("steward-live-chat-"+str(number));save_live()
func run()->void:
	base=OS.get_environment("HABITAT_DATA_DIR")
	if OS.get_environment("HABITAT_LIVE_TEST")!="1" or not base.contains("habitat-live-test-") or not base.contains("youqi"):quit(1);return
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	OS.set_environment("HABITAT_OPENING","standard")
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);current_scene=game;game.save_enabled=false;game.set_process(false);game.memory_life.set_process(false);await ready_frames(10)
	await UI.click(self,game.watch_ui.toggle);await ready_frames()
	await picture("one-click-before")
	await UI.click(self,game.steward.setup_button)
	var pool:Node=game.steward.pool
	var begin:int=Time.get_ticks_msec()
	while not game.steward.active and Time.get_ticks_msec()-begin<60000:
		game._process(.1);await create_timer(.1).timeout
	check(game.steward.active,"real one click appointment")
	if not game.steward.active:save_live();quit(1);return
	game.links.codex.event_received.connect(record_event)
	game._select_chat("codex");game.command_page.selected=["codex"]
	await picture("one-click-after")
	await chat_live("所有人去砍树")
	game.chat.hide();game.chat_input.release_focus()
	var clock_start:float=game.world.forest.clock
	watch_start=clock_start
	var interrupted:=false
	while game.world.forest.clock-clock_start<1800 and seen_keys.size()<40:
		game._process(.1)
		if game.links.codex.is_busy():await create_timer(.1).timeout
		elif int(game.world.forest.clock-clock_start)%10==0:await process_frame
		if int(game.world.forest.clock-clock_start)%60==0:watch.append({"elapsed":game.world.forest.clock-clock_start,"timeline":game.steward.timeline.duplicate(true),"hunger":game.steward.hunger.duplicate(true)})
		if game.world.forest.clock-clock_start>600 and not interrupted:
			interrupted=true;game.chat.show();await chat_live("生火烤鱼叫大家来吃");game.chat.hide();game.chat_input.release_focus()
	var owned_pid:int=game.links.codex.get("_pid")
	if owned_pid>0:
		OS.kill(owned_pid)
		var reconnect_start:int=Time.get_ticks_msec()
		while Time.get_ticks_msec()-reconnect_start<80000:
			game._process(.1);await create_timer(.1).timeout
			if pool.states.get("codex",{}).get("state")=="ready" and int(pool.retries.get("codex",0))>0:break
		check(pool.states.get("codex",{}).get("state")=="ready","owned bridge kill automatically reconnects")
	game.steward.player("别管了");save_live();await picture("steward-live-end")
	game.links.codex.shutdown();game.queue_free();await ready_frames();print("STEWARD_LIVE_DONE ",base);quit(1 if failed else 0)

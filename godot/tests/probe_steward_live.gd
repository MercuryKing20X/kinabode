extends "res://tests/probe_empowered_live.gd"
var watch:Array=[]
func save_live()->void:
	game.memory_books.atomic(base.path_join("steward-live-results.json"),{"turn_keys":seen_keys.keys(),"turns":turns,"events":events,"watch":watch,"history":game.intentions.history,"timeline":game.steward.timeline,"log":game.steward.events,"usage":game.autonomy.scheduler.usage("codex"),"checks":checks,"failed":failed})
func chat_live(words:String)->void:
	number+=1
	if seen_keys.size()>=20:return
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
	OS.set_environment("HABITAT_OPENING","showcase")
	var title:Node=load("res://scenes/title.tscn").instantiate();root.add_child(title);current_scene=title;await ready_frames(10)
	await UI.click(self,title.menu.get_node("connections"));await UI.click(self,title.connection_panel.buttons.codex)
	var pool:Node=title.connection_panel.pool
	var begin:int=Time.get_ticks_msec()
	while pool.states.get("codex",{}).get("state")!="ready" and Time.get_ticks_msec()-begin<45000:await create_timer(.1).timeout
	if pool.states.get("codex",{}).get("state")!="ready":quit(1);return
	title.queue_free();await ready_frames()
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);current_scene=game;game.save_enabled=false;game.set_process(false);game.memory_life.set_process(false);await ready_frames(10)
	for id in ["companion-2","npc.mira","npc.nora"]:game.world.director.set_controller(id,"local")
	game.links.codex.event_received.connect(record_event)
	game._select_chat("codex");game.command_page.selected=["codex"]
	game.steward.pool.set_management("codex",true)
	await chat_live("请小蓝去砍树，小橙去收成熟的菜，你也一起安排")
	game.chat.hide();game.chat_input.release_focus();check(game.steward.start("codex"),"explicit manager start accepted")
	var clock_start:float=game.world.forest.clock
	var interrupted:=false
	while game.world.forest.clock-clock_start<1200 and seen_keys.size()<20:
		game._process(.1)
		if game.links.codex.is_busy():await create_timer(.1).timeout
		elif int(game.world.forest.clock-clock_start)%10==0:await process_frame
		if int(game.world.forest.clock-clock_start)%60==0:watch.append({"elapsed":game.world.forest.clock-clock_start,"timeline":game.steward.timeline.duplicate(true),"hunger":game.steward.hunger.duplicate(true)})
		if game.world.forest.clock-clock_start>600 and not interrupted:
			interrupted=true;game.chat.show();await chat_live("先听我说一句，我们慢慢来就好");game.chat.hide();game.chat_input.release_focus()
	game.steward.player("别管了");save_live();await picture("steward-live-end")
	game.links.codex.shutdown();game.queue_free();await ready_frames();print("STEWARD_LIVE_DONE ",base);quit(1 if failed else 0)

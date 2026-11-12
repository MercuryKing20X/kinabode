extends "res://tests/test_intelligence_core_input.gd"
var events:Array=[]
var number:=0
func fresh()->void:
	OS.set_environment("HABITAT_OPENING","standard")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.chat.hide()
	await process_frame;await process_frame
	game.memory_life.set_process(false)
func run()->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR")
	if OS.get_environment("HABITAT_LIVE_TEST")!="1" or not dir.contains("habitat-live-test-") or not dir.contains("youqi-"):quit(1);return
	await fresh()
	game.resident_connections.open("codex");await process_frame
	check(await UI.click(self,game.resident_connections.connect_button),"real input connect")
	var began:=Time.get_ticks_msec()
	while game.links.codex.is_busy() and Time.get_ticks_msec()-began<45000:await create_timer(.1).timeout
	check(game._connection_light("codex").state=="ready","real handshake green")
	await picture("live-handshake")
	game.links.codex.event_received.connect(func(e):
		if e.kind in ["usage","error","intent_result","assistant"]:events.append({"turn":number,"event":e.duplicate(true)}))
	game.resident_connections.close_panel();preload("res://tests/dialogue_ui_fixture.gd").open(game,"codex")
	if game.command_page.commands_mode:await UI.click(self,game.command_page.tabs.get_child(1))
	for words in ["小白，我回来啦。我喜欢下雨。","今天工作有点累，项目一直卡着。","你喜欢岛上的萤火虫吗？","过来陪着我吧。","你还记得我喜欢什么吗？","我想写个整理文件的小工具，应该从哪里开始？"]:
		if game._connection_light("codex").state!="ready":break
		number+=1;events.append({"turn":number,"human":words})
		await text_input(words)
		began=Time.get_ticks_msec()
		while game.links.codex.is_busy() and Time.get_ticks_msec()-began<90000:await create_timer(.1).timeout
		if game.links.codex.is_busy():game.links.codex.cancel_turn();events.append({"turn":number,"timeout":true});break
		await process_frame
	await picture("live-six-turns")
	game.memory_books.atomic(dir.path_join("simple-live-results.json"),{"attempts":number,"events":events,"conversation":game.dialogue.histories.get("direct:codex",[]),"checks":checks,"failed":failed})
	game._simple_connection_action("codex");game.queue_free();await process_frame
	print("SIMPLE_LIVE_RESULT attempts=",number," dir=",dir);quit(1 if failed else 0)

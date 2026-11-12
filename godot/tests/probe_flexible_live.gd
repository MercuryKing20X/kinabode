extends "res://tests/probe_empowered_live.gd"
var all_events:Array=[]
func collect(e:Dictionary)->void:all_events.append(e.duplicate(true))
func run()->void:
	base=OS.get_environment("HABITAT_DATA_DIR")
	if OS.get_environment("HABITAT_LIVE_TEST")!="1" or not base.contains("habitat-live-test-youqi-"):quit(1);return
	OS.set_environment("HABITAT_OPENING","showcase")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);current_scene=game;game.save_enabled=false;game.set_process(false);game.memory_life.set_process(false);await ready_frames(10)
	await UI.click(self,game.watch_ui.toggle);await ready_frames();await UI.click(self,game.steward.setup_button)
	var began:int=Time.get_ticks_msec()
	while not game.steward.active and Time.get_ticks_msec()-began<60000:game._process(.1);await create_timer(.1).timeout
	check(game.steward.active,"one-click real manager connected")
	if not game.steward.active:quit(1);return
	game.links.codex.event_received.connect(collect)
	game._select_chat("codex");game.command_page.selected=["codex"]
	for words in ["小白你好","今天风好舒服","你在想什么呀","我想看看大家干活","去种菜","别着急，慢慢来","让他们去种菜","种地去","大家去种菜","钓一条鱼，然后生火烤这条鱼，叫大家来吃"]:
		if not game.chat.visible:await UI.click(self,game.dialogue_button)
		await text_input(words)
	await picture("ten-inputs")
	began=Time.get_ticks_msec()
	while Time.get_ticks_msec()-began<240000:
		game._process(.1);await create_timer(.05).timeout
		if not game.links.codex.is_busy() and game.next_chat.is_empty() and game.steward.pending.is_empty() and game.intentions.plans.is_empty():break
	var disconnected:Array=all_events.filter(func(e):return e.kind=="state" and e.get("state","")=="disconnected")
	var usage:Array=all_events.filter(func(e):return e.kind=="usage")
	check(disconnected.is_empty(),"zero disconnect state during ten rapid messages")
	await picture("live-finish")
	game.memory_books.atomic(base.path_join("results.json"),{"checks":checks,"failed":failed,"events":all_events,"usage":usage,"queued":game.next_chat,"history":game.intentions.history,"barbecues":game.world.barbecues.values().map(func(c):return c.fireside.state),"fish":game.world.fishing.fish})
	game.steward.stop();game.links.codex.shutdown();await create_timer(1).timeout
	game.queue_free();await ready_frames();quit(1 if failed else 0)

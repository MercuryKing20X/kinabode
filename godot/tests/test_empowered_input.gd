extends "res://tests/test_intent_input.gd"
func run()->void:
	OS.set_environment("HABITAT_OPENING","showcase")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game)
	game.save_enabled=false;game.set_process(false);await process_frame;await process_frame
	var w:RefCounted=game.world
	w.director.set_controller("codex","model")
	if game.links.has("codex"):game.links.codex.queue_free();game.links.erase("codex")
	game.dialogue_adapter_factory=func(_id,_scope):return IntentFake.new()
	game._ensure_link("codex");preload("res://tests/dialogue_ui_fixture.gd").open(game,"codex")
	await text_input("你喜欢泳池吗？")
	var idle_link:Node=game.links.codex
	idle_link._accept_event({"kind":"intent_result","turn_key":idle_link.turn_key,"speech":"喜欢呀。","intents":[{"action":"pool"}]})
	check(not game.intentions.plans.has("codex") and not w.work.jobs.has("codex"),"pure conversation about an activity never grants an action")
	idle_link._accept_event({"kind":"state","state":"ready","turnComplete":true,"turn_key":idle_link.turn_key})
	var human:Dictionary=w.actors.human.duplicate(true)
	var wood_before:int=w.storage.count("wood")
	await text_input("小白去钓条鱼，回来一起烤")
	check(w.work.jobs.get("codex",{}).get("intent")=="fish","real input starts fishing before model response")
	var connection:Node=game.links.codex
	connection._accept_event({"kind":"intent_result","turn_key":connection.turn_key,"speech":"我去钓一条，回来一起烤呀。","intents":[]})
	connection._accept_event({"kind":"state","state":"ready","turnComplete":true,"turn_key":connection.turn_key})
	var before:Vector2=w.point(w.actors.codex)
	for i in range(20):game._process(.1)
	check(w.point(w.actors.codex)!=before,"real displacement within two seconds")
	for i in range(5000):
		game._process(.1)
		if i%100==0:await process_frame
		if not game.intentions.plans.has("codex"):break
	check(game.intentions.history.filter(func(row):return row.actor_id=="codex" and row.result=="completed").size()==3,"actual input completes fish roast invite")
	check(wood_before-w.storage.count("wood")==2,"cold fish roast uses original two wood without duplicate ignition")
	await picture("empowered-fish-roast")
	await text_input("带小蓝去泳池玩")
	connection._accept_event({"kind":"state","state":"ready","turnComplete":true,"turn_key":connection.turn_key})
	for i in range(5000):
		game._process(.1)
		if i%100==0:await process_frame
		if not game.intentions.plans.has("codex"):break
	print("EMPOWERED_HISTORY ",game.intentions.history)
	check(w.resort.using("codex")=="pool" and w.resort.using("companion-2")=="pool","named companion and self really enter pool")
	check(w.actors.human.position==human.position and w.actors.human.region_id==human.region_id,"all real inputs preserve human position")
	await picture("empowered-pool")
	await text_input("先逛逛，再去钓鱼，回来烤鱼")
	for i in range(50):game._process(.1)
	check(connection.is_busy() and w.work.jobs.get("codex",{}).get("intent")=="fish","next accepted step starts while its own model reply is pending")
	connection._accept_event({"kind":"state","state":"ready","turnComplete":true,"turn_key":connection.turn_key})
	for i in range(5000):
		game._process(.1)
		if i%100==0:await process_frame
		if not game.intentions.plans.has("codex"):break
	check(not game.intentions.last_failure.has("codex"),"delayed reply never acts as a false question barrier")
	game.queue_free();await process_frame
	print("EMPOWERED_INPUT ",checks," failed=",failed);quit(1 if failed else 0)

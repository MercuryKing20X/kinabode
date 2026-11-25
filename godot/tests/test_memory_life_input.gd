extends "res://tests/test_intelligence_core_input.gd"
class ProviderStub extends "res://scripts/companion_link.gd":
	var sent:Array=[]
	func uses_intents()->bool:return true
	func _start()->bool:return true
	func _send(message:Dictionary)->bool:sent.append(message.duplicate(true));return true
func fresh()->void:
	game=UI.init_game(self)
	await process_frame;await process_frame
	for pair in [["codex","ai-gpt"],["companion-2","ai-deepseek"],["npc.mira","ai-claude"],["npc.nora","ai-glm"]]:check(game.world.assign_appearance(pair[0],pair[1]),"isolated appearance "+pair[0])
func run()->void:
	await fresh()
	var w:RefCounted=game.world;var b:RefCounted=game.memory_books
	# Repeat natural weather and idle candidates, rather than asking a random
	# weather seed to produce rain inside an arbitrary bounded test window.
	w.weather.weather_seed=1027
	var fixture_seed:=1027
	for routine in w.director.routines.values():
		routine.rng.seed=fixture_seed;fixture_seed+=1
	# Provider-stub output is inspected by the host before any letter is published.
	var dirty_writes:Array=[{"layer":"letters","text":"引用 ID：这是一封夹带系统词的信。"}]
	game.memory_life.attempts.codex={"day":1,"pending":false}
	game.memory_life.check_letter_reply("codex",dirty_writes,{"maintenance":true,"memory_request":{"day":1}})
	check(game.memory_life.letter_retries.get("codex")==1,"first rejected model letter queues exactly its original day for rewriting")
	game.memory_life.letter_retries.clear();game.memory_life.attempts.codex.rewrite=true
	game.memory_life.check_letter_reply("codex",dirty_writes,{"maintenance":true,"memory_request":{"day":1}})
	check(game.memory_life.letter_retries.is_empty() and b.list_for("codex","letters").is_empty(),"second dirty model letter is dropped without another retry or local counterfeit")
	game.memory_life.check_letter_reply("codex",{}, {"maintenance":true})
	check(game.memory_life.letter_retries.is_empty(),"malformed memory payload cannot crash the letter host")
	game.memory_life.attempts.clear()
	game.memory_life.set_process(false)
	w.director.set_controller("codex","model")
	if game.links.has("codex"):game.links.codex.queue_free();game.links.erase("codex")
	game.dialogue_adapter_factory=func(_id,_scope):return ProviderStub.new()
	game._ensure_link("codex");game.chat_actor="codex"
	preload("res://tests/dialogue_ui_fixture.gd").open(game,"codex")
	if game.command_page.commands_mode:await UI.click(self,game.command_page.tabs.get_child(1))
	await text_input("我喜欢下雨")
	var c:Node=game.links.codex;var supplied:Array=c.sent[-1].world.intent_card.memory_sources
	var quoted:String=supplied.filter(func(e):return e.human_quote and e.layer=="facts")[-1].id
	c._accept_event({"kind":"intent_result","turn_key":c.turn_key,"speech":"我记住你喜欢下雨了。","intents":[],"memory":[{"layer":"about_you","text":"你喜欢下雨。","source_ids":[quoted]}]})
	check(b.list_for("codex","about_you").any(func(e):return e.source=="Codex"),"bound model writes grounded about-you note")
	c._accept_event({"kind":"state","state":"ready","turnComplete":true,"turn_key":c.turn_key})
	await picture("memory-rain-note")
	# Teaching is memory only: it must never dispatch embedded barbecue text on this turn.
	await text_input("以后我说小火苗就是叫大家烧烤")
	check(b.resolve("codex","小火苗")=="叫大家烧烤","real input teaches new alias")
	check(not w.barbecues["home.barbecue"].fireside.active(),"teaching does not execute embedded activity")
	c._accept_event({"kind":"state","state":"ready","turnComplete":true,"turn_key":c.turn_key})
	# The normal real farm engine produces the helper proof for both residents.
	var farm:String=game.local_host_commands.parser.nearest_farm(w)
	check(w.command("human",{"intent":"assign_farm","farm_id":farm,"manager_id":"companion-2"}).ok,"host assigns actual manager")
	w.director.set_controller("codex","local")
	check(b.add("codex",w.world_id,"test-goal","facts","memory.goal_offer",{"goal_status":"offered","farm_id":farm,"farm":farm,"expires":w.days.day()+5},w.days.day(),"local",["human","codex"]),"goal card offers a real empty field")
	var goal:String=b.list_for("codex","facts").filter(func(e):return e.event_id=="test-goal")[0].id
	check(b.decide_goal(goal,true),"host explicitly accepts exact wish")
	check(w.farms.host_order("codex",farm,"mixed","plant").ok,"explicit host farming order")
	for tick in range(6000):
		w.advance(.1)
		if w.farms.orders.get("codex",{}).get("status")=="completed":break
	game.memory_life.goals("codex")
	check(b.entries[goal].params.goal_status=="completed","accepted wish completes only after real planting and first water")
	check(b.list_for("companion-2","facts").any(func(e):return e.event_id.begins_with("water-help:")),"real watering generates receiver memory")
	check(b.list_for("codex","facts").any(func(e):return e.event_id.begins_with("water-help:")),"same proof generates helper memory")
	# A genuinely new completed meal produces a photo; old facts do not replay on load.
	game.house_panel.open_site("home.house.01");await process_frame
	check(preload("res://tests/fixture_host_build_all.gd").apply(w).ok,"explicit test-only completed-site prerequisite")
	game.house_panel.hide()
	game.chat.hide();game._refresh_conversation_holds()
	var start:Dictionary=preload("res://tests/barbecue_fixture.gd").start(w,"single:mushroom",["human","codex"])
	print("MEMORY_MEAL_START ",start)
	check(start.ok and preload("res://tests/barbecue_fixture.gd").finish(w,["human","codex"]),"real meal consumes original recipe and completes")
	w.memories.sync();game.memory_life._process(1.1)
	if DisplayServer.get_name()!="headless":
		for i in range(120):
			await process_frame
			if not game.memory_life.photo_busy and game.memory_life.photo_queue.is_empty():break
			game.memory_life._process(1.1)
		check(b.list_for("codex","facts").any(func(e):return not e.photo_id.is_empty()),"real viewport photo attaches to meal fact")
		await picture("memory-photo-scene")
	# Advance the real simulation; preserve original hunger, work and calendar parameters.
	while w.days.day()<7:w.advance(10)
	w.director.routines.codex.set_enabled(true)
	w.director.set_controller("codex","model")
	game.memory_life.anniversary("codex")
	check(b.list_for("codex","facts").any(func(e):return e.event_id=="anniversary:7"),"seventh game day creates anniversary")
	for tick in range(600):
		w.advance(1)
		game.memory_life.speak("codex")
		if w.director.events.any(func(e):return e.context=="memory_reminder" and e.text.contains("7")):break
	if not w.director.events.any(func(e):return e.context=="memory_reminder" and e.text.contains("7")):print("ANNIVERSARY_GATES ",JSON.stringify(memory_gates()))
	check(w.director.events.any(func(e):return e.context=="memory_reminder" and e.text.contains("7")),"anniversary delivered through real local gates")
	game.view._process(10);game._process(0);game.view.follow_player=false;game.view.show_region(w.actors.codex.region_id);game.view.center=w.point(w.actors.codex);game.view.queue_redraw();await picture("anniversary-day7")
	check(b.resolve("codex","小火苗")=="叫大家烧烤","taught alias survives real day advancement")
	var parsed:Dictionary=game.local_host_commands.parser.parse_command(w,"小火苗",["codex"])
	check(parsed.get("action")=="barbecue","next-day alias resolves through original activity parser")
	while w.weather.current().id!="rain" and w.days.day()<20:w.advance(10)
	for tick in range(600):
		w.advance(1);game.memory_life.speak("codex")
		if w.director.events.any(func(e):return e.context=="memory_reminder" and (e.text.begins_with("下雨了") or e.text.begins_with("It’s raining"))):break
	check(w.director.events.any(func(e):return e.context=="memory_reminder" and (e.text.begins_with("下雨了") or e.text.begins_with("It’s raining"))),"natural rain prompts true retained preference through original gates")
	print("RAIN_MEMORY_DIAGNOSTIC ",JSON.stringify({"day":w.days.day(),"weather":w.weather.current().id,"idle":game.memory_life.idle("codex"),"eligible":w.director.memory_reminders.eligible("codex"),"kind":w.director.routines.codex.kind,"held":w.director.routines.codex.held,"position":w.actors.codex.position,"human":w.actors.human.position,"next_speech":w.director.routines.codex.next_speech,"speech_after":w.director.speech_after,"time":w.director.time}))
	game.view._process(10);game._process(0);game.view.follow_player=false;game.view.show_region(w.actors.codex.region_id);game.view.center=w.point(w.actors.codex);game.view.queue_redraw();await picture("rain-reminder")
	check(b.export_html(OS.get_environment("HABITAT_DATA_DIR").path_join("album.html")),"photo album with portrait page exports")
	game.chat.hide();game.book_panel.open();game.book_panel.tabs.select(4);game.book_panel.refresh();await picture("through-her-eyes")
	game.book_panel.hide();game.connection_overview.open();await process_frame
	check(game.connection_overview.get_global_rect().intersects(Rect2(Vector2.ZERO,Vector2(root.size))),"connection overview visible inside viewport")
	await picture("connection-overview")
	game.connection_overview.hide();game.island_hud.refresh();await picture("connection-lights")
	print("MEMORY_LIFE_INPUT ",checks," failed=",failed)
	game.queue_free();await process_frame;quit(1 if failed else 0)

func memory_gates()->Dictionary:
	var w:RefCounted=game.world;var r:RefCounted=w.director.routines.codex
	return {"activity":w.actors.codex.activity,"carry":w.actors.codex.carry,"blocked":r.blocked(),"kind":r.kind,"held":r.held,"route":w._routes.has("codex"),"brain":w.director.brains.codex.current,"provider":w.director.brains.codex.provider_running,"eligible":w.director.memory_reminders.eligible("codex"),"time":r.time,"next_speech":r.next_speech,"speech_after":w.director.speech_after,"personal_after":w.director.memory_reminders.deadline(w.director.memory_reminders.section("codex")),"village_after":w.director.memory_reminders.deadline(w.director.memory_reminders.section()),"forest_clock":w.forest.clock,"reminder_mentions":w.director.memory_reminders.history("codex"),"events":w.director.events}

extends "res://tests/test_empowered_input.gd"
func run()->void:
	OS.set_environment("HABITAT_OPENING","showcase")
	game=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return IntentFake.new()
	root.add_child(game);game.save_enabled=false;game.set_process(false);game.memory_life.set_process(false)
	await process_frame;await process_frame
	var w:RefCounted=game.world
	var shift:float=maxf(0.0,Time.get_unix_time_from_system()+1.0-w.forest.clock)
	w.forest.clock+=shift;w.days.origin+=shift;game.autonomy.scheduler.reset()
	w.director.set_controller("codex","model");w.activities.release_follow("codex");w.director.set_all_enabled(false)
	if game.links.has("codex"):game.links.codex.queue_free();game.links.erase("codex")
	game._ensure_link("codex");game.chat.hide();game.chat_input.release_focus();game.autonomy.refresh_support()
	game.resident_connections.preferences.choose("codex","medium")
	var connection:Node=game.links.codex
	game.autonomy.player_input();game.autonomy.scheduler.enqueue("codex","fixture-off","house_completed","fixture")
	for i in range(60):game._process(.1)
	check(connection.sent.is_empty(),"disabled autonomy creates no inference")
	check(game.resident_connections.preferences.enable_autonomy("codex",true),"explicit temporary opt-in")
	game.autonomy.player_input();game.autonomy.scheduler.enqueue("codex","fixture-on","house_completed","fixture")
	for i in range(60):game._process(.1)
	if connection.sent.size()!=1:print("AUTONOMY_FISH_STATUS ",game.autonomy.status("codex")," queue=",game.autonomy.scheduler.queues.get("codex",[])," messages=",connection.sent.map(func(item):return item.kind))
	check(connection.sent.size()==1 and connection.sent[0].kind=="autonomy_event","original scheduler sends exactly one budgeted wake")
	connection._accept_event({"kind":"intent_result","turn_key":connection.turn_key,"speech":"","intents":[{"action":"fish"}]})
	check(w.work.jobs.get("codex",{}).get("intent")=="fish","budgeted native intention starts actual fishing")
	connection._accept_event({"kind":"usage","turn_key":connection.turn_key,"total_tokens":150,"input_tokens":130,"output_tokens":20,"complete":true})
	connection._accept_event({"kind":"state","turn_key":connection.turn_key,"state":"ready","turnComplete":true})
	for i in range(1600):game._process(.1)
	check(not w.fishing.held("codex").is_empty(),"autonomous stub commits one own actual catch")
	check(connection.sent.size()==1,"completion never chains another inference")
	game.resident_connections.preferences.enable_autonomy("codex",false)
	game.queue_free();await process_frame
	print("EMPOWERED_AUTONOMY ",checks," failed=",failed);quit(1 if failed else 0)

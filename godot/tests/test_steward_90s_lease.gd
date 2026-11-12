extends "res://tests/test_intent_input.gd"
func run()->void:
	OS.set_environment("HABITAT_OPENING","showcase")
	game=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return IntentFake.new()
	root.add_child(game);game.save_enabled=false;game.set_process(false);game.memory_life.set_process(false)
	await process_frame;await process_frame
	game.chat.hide();game.chat_input.release_focus()
	game.world.director.set_controller("codex","model");game._ensure_link("codex")
	game.connection_ui_states["codex:direct"]="ready";game.connection_history.set_value("connected","codex",1);game.steward.pool.set_management("codex",true)
	game.steward.local_only=false
	check(game.steward.start("codex"),"start AI manager")
	game.steward.request_plan()
	check(not game.steward.pending.is_empty(),"one request in flight")
	if game.steward.pending.is_empty():game.queue_free();quit(1);return
	var key:String=game.steward.pending.key
	for i in 450:
		game.world.forest.advance(.2)
		game.steward.reasons.append("queue_low")
		game.steward.request_plan()
	check(game.steward.pending.get("key")==key,"90 seconds queue-low requests retain exact lease")
	check(not game.links.codex._cancelling,"not cancelled before delayed response")
	var jobs_before:Dictionary=game.world.work.jobs.duplicate(true)
	var routes_before:Dictionary=game.world._routes.duplicate(true)
	var preference:String=game.steward.pending.candidates[0].id
	check(game.steward.result("codex",{"kind":"intent_result","turn_key":key,"speech":"","preference":preference,"planning":[{"phase":"now","reason":"walk","intents":[{"action":"wander","actor_ids":["companion-2"]}]}]}),"late valid plan accepted")
	check(game.steward.body_director.ai_used==1 and game.steward.body_director.ai_choice==preference,"delayed candidate preference accepted")
	check(game.steward.queue.is_empty() and game.world.work.jobs==jobs_before and game.world._routes==routes_before,"AI suggestion cannot enqueue actions or move bodies")
	game.steward.stop();game.queue_free();await process_frame
	print("LEASE_90_CHECKS ",checks," failed=",failed);quit(1 if failed else 0)

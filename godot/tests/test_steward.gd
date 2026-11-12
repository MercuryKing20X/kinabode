extends "res://tests/test_intelligence_core_input.gd"
func run()->void:
	OS.set_environment("HABITAT_OPENING","showcase")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);game.memory_life.set_process(false)
	await process_frame;await process_frame
	var w:RefCounted=game.world
	for id in ["codex","companion-2","npc.mira","npc.nora"]:
		check(w.actors[id].role=="companion","all four have same role: "+id)
		w.director.set_controller(id,"local")
	var boss:="npc.mira"
	w.director.set_controller(boss,"model");game.connection_ui_states[boss+":direct"]="ready";game.connection_history.set_value("connected",boss,1)
	check(not game.steward.authorized(boss),"management default off even when connected")
	check(not game.intentions.submit(boss,[{"action":"chop","actor_ids":["all"]}],"direct:"+boss).ok,"no management no delegation")
	game.steward.pool.set_management(boss,true)
	check(game.steward.authorized(boss),"orange manager opt-in accepted")
	var before:Dictionary={};var human:Dictionary=w.actors.human.duplicate(true)
	for id in game.steward.Pool.IDS:before[id]=w.point(w.actors[id])
	var outcome:Dictionary=game.intentions.submit(boss,[{"action":"chop","actor_ids":["all"]}],"direct:"+boss)
	print("DELEGATION ",outcome)
	check(outcome.ok and outcome.accepted.size()==4,"four real independent jobs accepted")
	var job_ids:Dictionary={}
	for id in game.steward.Pool.IDS:
		job_ids[id]=w.work.jobs.get(id,{}).get("id","")
		check(not w.activities.following.has(id),"working recipient stopped following "+id)
	var distance:Dictionary={}
	for i in range(2400):
		var positions:Dictionary={}
		for id in before:positions[id]=w.point(w.actors[id])
		game._process(.1)
		for id in before:distance[id]=float(distance.get(id,0))+positions[id].distance_to(w.point(w.actors[id]))
		if i%100==0:await process_frame
		if game.intentions.plans.is_empty():break
	for id in before:
		var completed:Array=w.work.events.filter(func(event):return event.get("actor_id")==id and event.get("job_id")==job_ids[id] and event.get("status")=="completed")
		print("STEWARD_REAL_WORK ",id," distance=",distance.get(id,0)," receipts=",completed)
		check(float(distance.get(id,0))>0 and not completed.is_empty(),"real movement and exact completed wood receipt: "+id)
	check(w.actors.human==human,"manager never controls or changes human")
	check(not game.steward.assign(boss,[{"action":"chop","actor_ids":["human"]}],"direct:"+boss).ok,"human delegation rejected")
	check(not game.steward.assign(boss,[{"action":"chop","actor_ids":["npc.mira","npc.mira"]}],"direct:"+boss).ok,"duplicate actors rejected")
	var hungry_id:="companion-2"
	w.hunger.ensure(hungry_id);w.hunger.states[hungry_id].elapsed=float(w.hunger.config.thresholds[3])
	var refused:Dictionary=game.steward.assign(boss,[{"action":"chop","actor_ids":[hungry_id]}],"direct:"+boss)
	check(not refused.ok and refused.rejected.get(hungry_id)=="very_hungry","very hungry recipient refuses exact delegated work")
	check(game.steward.bubbles.any(func(entry):return entry.id==boss and entry.text.contains(game.T("local.commands.hungry").left(8))) or game.dialogue.histories.get("direct:"+boss,[]).any(func(entry):return entry.text.contains(game.T("local.commands.hungry"))),"manager truthfully explains hunger refusal")
	var ledger:Dictionary=game.autonomy.scheduler.usage(boss)
	var original_reserved:int=ledger.reserved
	ledger.reserved+=64000;game.autonomy.scheduler.preferences.save_accounting(boss,ledger)
	game.steward.pending={"id":boss,"key":"delayed-complete"}
	game.steward.reservations[boss+":delayed-complete"]={"day":ledger.day,"reserve":64000}
	game.steward.result(boss,{"kind":"error","turn_key":"delayed-complete","message":"invalid_intent_reply"})
	check(game.steward.pending.is_empty(),"semantic error clears pending planner")
	game.steward.result(boss,{"kind":"usage","turn_key":"other-turn","complete":true})
	check(game.autonomy.scheduler.usage(boss).reserved==original_reserved+64000,"foreign usage cannot release reservation")
	game.steward.result(boss,{"kind":"usage","turn_key":"delayed-complete","complete":true})
	check(game.autonomy.scheduler.usage(boss).reserved==original_reserved,"late complete usage releases failed plan reservation")
	game.steward.result(boss,{"kind":"usage","turn_key":"delayed-complete","complete":true})
	check(game.autonomy.scheduler.usage(boss).reserved==original_reserved,"duplicate complete cannot double refund")
	game.steward.pool.set_management(boss,false)
	check(not game.steward.authorized(boss),"management revoke removes model delegation authority")
	check(game.steward.start(boss),"explicit host may still appoint a local director")
	check(not game.steward.ai_manager(boss),"local appointment does not restore model authority")
	game.queue_free();await process_frame
	print("STEWARD_CHECKS ",checks," failed=",failed);quit(1 if failed else 0)

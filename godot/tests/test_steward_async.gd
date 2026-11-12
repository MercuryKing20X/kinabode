extends "res://tests/test_intent_input.gd"
func run()->void:
	OS.set_environment("HABITAT_OPENING","showcase")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	game=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return IntentFake.new()
	root.add_child(game);game.save_enabled=false;game.set_process(false);game.memory_life.set_process(false);game.local_host_commands.set_process(false)
	await process_frame;await process_frame
	var w:RefCounted=game.world
	for id in game.steward.Pool.IDS:w.director.set_controller(id,"local");w.activities.release_follow(id)
	w.director.set_controller("codex","model");game._ensure_link("codex")
	game.connection_ui_states["codex:direct"]="ready";game.connection_history.set_value("connected","codex",1);game.steward.pool.set_management("codex",true)
	game.steward.local_only=false
	game.chat.hide();game.chat_input.release_focus();check(game.steward.start("codex"),"start isolated async steward")
	var waits:Dictionary={};var replies:=0;var max_wait_workers:=0;var samples:Array=[];var static_time:Dictionary={};var last:Dictionary={};var idle_over_20:=0;var meter=preload("res://tests/steward_activity_meter.gd").new()
	for id in game.steward.Pool.IDS:last[id]=w.point(w.actors[id]);static_time[id]=0.0
	for tick in 3000:
		game._process(.2);game.local_host_commands._process(.2)
		var link:Node=game.links.codex
		if not game.steward.pending.is_empty():
			var key:String=game.steward.pending.key
			if not waits.has(key):waits[key]=w.forest.clock
			var workers:int=game.steward.Pool.IDS.filter(func(id):return w._routes.has(id) or w.work.jobs.has(id) or game.intentions.plans.has(id)).size()
			max_wait_workers=maxi(max_wait_workers,workers)
			if w.forest.clock-float(waits[key])>=90:
				link._accept_event({"kind":"intent_result","turn_key":key,"speech":"","preference":game.steward.pending.candidates[0].id,"intents":[],"planning":[{"phase":"现在","reason":"walk","intents":[{"action":"wander","actor_ids":["companion-2"]},{"action":"invent_materials"}]},{"phase":"夜晚","reason":"later","intents":[{"action":"wander","actor_ids":["npc.nora"]}]}]})
				link._accept_event({"kind":"state","turn_key":key,"state":"ready","turnComplete":true});replies+=1
		for id in game.steward.Pool.IDS:static_time[id]=meter.sample(game,id,.2)
		if tick%50==49:
			var sample:Dictionary={"time":w.forest.clock,"actors":{}}
			for id in game.steward.Pool.IDS:
				var at:Vector2=w.point(w.actors[id])
				if static_time[id]>20:idle_over_20+=1
				last[id]=at;sample.actors[id]={"activity":w.actors[id].activity,"stationary_seconds":static_time[id],"hunger":w.hunger.rank(id),"job":w.work.jobs.get(id,{}).get("intent",""),"plan":game.intentions.plans.get(id,{}).get("current",{})}
			samples.append(sample)
			if sample.actors.values().any(func(a):return a.stationary_seconds>20):print("STATIC_SAMPLE ",JSON.stringify(sample))
		if tick%100==0:await process_frame
	check(max_wait_workers>=3,"at least three bodies active during slow plan")
	check(replies>0,"90 second delayed replies accepted")
	check(game.steward.body_director.ai_used==replies,"each delayed legal preference accepted")
	check(not game.intentions.history.any(func(e):return e.action=="invent_materials"),"illegal AI action never reaches executor")
	check(game.steward.queue.is_empty(),"AI planning array cannot become a body queue")
	print("ASYNC_STATISTICS ",JSON.stringify({"samples":samples.size(),"stationary_person_samples_over_20":idle_over_20,"max_workers_during_wait":max_wait_workers,"replies":replies}))
	var report:=FileAccess.open(OS.get_environment("HABITAT_DATA_DIR").path_join("async.json"),FileAccess.WRITE);report.store_string(JSON.stringify(samples));report.close()
	check(idle_over_20==0,"600 seconds physical stationary samples over 20 seconds are zero")
	game.steward.stop();game.queue_free();await process_frame;quit(1 if failed else 0)

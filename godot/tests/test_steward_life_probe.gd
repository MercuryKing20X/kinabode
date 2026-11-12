extends "res://tests/test_intent_input.gd"
func run()->void:
	OS.set_environment("HABITAT_OPENING","showcase")
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);game.memory_life.set_process(false);await process_frame;await process_frame
	var w:RefCounted=game.world
	for id in game.steward.Pool.IDS:w.director.set_controller(id,"local");w.activities.release_follow(id)
	w.director.set_controller("codex","model");game.connection_ui_states["codex:direct"]="ready";game.connection_history.set_value("connected","codex",1);game.steward.pool.set_management("codex",true)
	game.dialogue_adapter_factory=func(_id,_scope):return IntentFake.new()
	game._ensure_link("codex");game.chat.hide();game.chat_input.release_focus();game.steward.start("codex")
	var activities:Dictionary={};var long_idle:Dictionary={};var maximum:Dictionary={};var counter:Dictionary={};var tree_conflicts:=0
	for i in 4500:
		var link:Node=game.links.codex
		if link.is_busy():
			link._accept_event({"kind":"error","turn_key":link.turn_key,"message":"stub_local_fallback"})
			link._accept_event({"kind":"state","turn_key":link.turn_key,"state":"ready","turnComplete":true})
		game._process(.2)
		for id in game.steward.Pool.IDS:
			if not activities.has(id):activities[id]={};long_idle[id]=0;counter[id]=0.0;maximum[id]=0.0
			activities[id][str(w.actors[id].activity)]=true
			if w.actors[id].activity=="idle":counter[id]+=.2
			else:counter[id]=0.0
			maximum[id]=maxf(maximum[id],counter[id])
			if counter[id]>20 and counter[id]<=20.2:long_idle[id]+=1
		var targets:Dictionary={}
		for job in w.work.jobs.values():
			if job.get("intent")=="chop":
				if targets.has(job.get("target_id")):tree_conflicts+=1
				targets[job.get("target_id")]=true
		if i%100==0:await process_frame
	var result:Dictionary={"activities":activities,"idle_over_20":long_idle,"max_idle":maximum,"chases":game.steward.life.chases,"plans":game.intentions.plans.duplicate(true),"circles":game.steward.life.visits,"life_history":game.steward.life.history,"tree_conflicts":tree_conflicts}
	var f:=FileAccess.open(OS.get_environment("HABITAT_DATA_DIR").path_join("life-results.json"),FileAccess.WRITE);f.store_string(JSON.stringify(result,"\t"));f.close();print("LIFE_RESULTS ",result)
	game.steward.stop();game.queue_free();await process_frame;quit()

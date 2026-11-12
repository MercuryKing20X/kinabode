extends "res://tests/test_intelligence_core_input.gd"
func run()->void:
	OS.set_environment("HABITAT_OPENING","showcase")
	await fresh()
	game.local_host_commands.set_process(false)
	game.steward.pool.set_management("codex",true)
	game.world.director.set_controller("codex","model");game.connection_ui_states["codex:direct"]="ready"
	game.connection_history.set_value("connected","codex",1)
	game.steward.start("codex")
	if game.links.has("codex"):game.links.codex.queue_free();game.links.erase("codex")
	var meter=preload("res://tests/steward_activity_meter.gd").new()
	var idle:Dictionary={};var defects:Dictionary={};var kinds:Dictionary={}
	for id in game.steward.Pool.IDS:idle[id]=0.0;defects[id]=0;kinds[id]={}
	for tick in range(2400):
		game.local_host_commands._process(.5);game._process(.5)
		for id in idle:
			var activity:String=str(game.world.actors[id].get("activity",""))
			idle[id]=meter.sample(game,id,.5)
			if idle[id]==0:kinds[id][activity]=true
			if idle[id]==20.5:
				defects[id]+=1
				print("IDLE_DEFECT ",id," tick=",tick," jobs=",game.world.work.jobs.get(id,{})," task=",game.steward.body_director.tasks.get(id,{})," batch=",game.steward.body_director.batch," closing=",game.steward.body_director.closing," slots=",game.steward.body_director.formation_slots," positions=",game.steward.Pool.IDS.map(func(who):return {"id":who,"position":game.world.actors[who].position,"job":game.world.work.jobs.get(who,{}),"task":game.steward.body_director.tasks.get(who,{})})," paused=",game.steward.body_director.paused)
		if tick%100==0:await process_frame
	var output:String=OS.get_environment("HABITAT_UI_EVIDENCE")
	if not output.is_empty():game.memory_books.atomic(output.path_join("idle.json"),{"defects":defects,"activities":kinds,"seconds":1200,"metric":"DIRECTION: no current task, or stationary movement; real work/wait/rest excluded within deadline"})
	print("TWENTY_MINUTE_IDLE ",JSON.stringify({"defects":defects,"activities":kinds}))
	for id in defects:check(defects[id]==0,"no unoccupied twenty-second gap "+id)
	game.queue_free();await process_frame;quit(1 if failed else 0)

extends "res://tests/test_local_command_main_input.gd"
func run()->void:
	game=UI.init_game(self);await process_frame;await process_frame
	var rows:Array=JSON.parse_string(FileAccess.get_file_as_string("res://../production/evidence/2026-11-05-智能一句话与跟随/coverage-cases.json"))
	var begin:int=int(OS.get_environment("HABITAT_COVERAGE_START"))
	var end:int=int(OS.get_environment("HABITAT_COVERAGE_END"))
	if end<=begin:end=rows.size()
	rows=rows.slice(begin,end)
	var output_path:String="/tmp/youqi-one-line-execution-"+str(begin)+".json"
	var result_rows:Array=[]
	for row in rows:
		var w:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");w.residents.provision(w);w.library=game.library
		preload("res://scripts/world_opening.gd").apply(w,game.library,"showcase")
		w.intelligence.activate_presets();w.hunger.start();w.director.set_all_enabled(true)
		game.world=w;game.local_host_commands.tracked.clear();game.local_host_commands.speech_queue.clear()
		var messages:Array=[]
		var callback:Callable=func(line,channel):messages.append(str(line))
		game.local_host_commands.feedback.connect(callback)
		var parsed:Dictionary=game.local_host_commands.parser.parse_command(w,row.text,["codex"])
		if row.meaning in ["stop","unfollow"]:w.activities.set_followers(w.actors.keys().filter(func(id):return id!="human"))
		var result:Dictionary=game.local_host_commands.submit(row.text,["codex"],"coverage")
		for tick in 3:w.advance(.1)
		var expected:String="ready" if row.meaning=="sequence" else row.meaning
		var correct:bool=parsed.get("ok",false) and parsed.get("action")==expected
		var started:bool=not w.work.jobs.is_empty() or not w._routes.is_empty() or not w.activities.following.is_empty() or not w.farms.host_grants.is_empty()
		if expected in ["stop","unfollow"]:started=result.get("parsed",false) and parsed.get("actor_ids",[]).all(func(id):return not w.activities.following.has(id) and not w.work.jobs.has(id))
		if expected=="query_state":started=result.get("parsed",false) and not messages.is_empty()
		if expected=="barbecue":started=started and w.barbecues.values().any(func(life):return not life.fireside.selected_guests.is_empty())
		var saved:Dictionary=row.duplicate(true);saved["parsed"]=correct;saved["executed_first_step"]=correct and started;saved["evidence"]={"jobs":w.work.jobs.keys(),"routes":w._routes.keys(),"following":w.activities.following.keys(),"feedback":messages}
		if not saved.executed_first_step:saved["reason"]="confirmation_required" if is_instance_valid(game.local_host_commands.card) else " / ".join(messages) if not messages.is_empty() else "no validated work/route at the actual initial showcase state"
		result_rows.append(saved)
		game.local_host_commands.feedback.disconnect(callback)
		if is_instance_valid(game.local_host_commands.card):game.local_host_commands.card.queue_free()
		if int(row.id)%20==0:
			var file:=FileAccess.open(output_path,FileAccess.WRITE);file.store_string(JSON.stringify(result_rows,"  "));file.close()
			print("EXECUTION_PROGRESS ",row.id)
	game.queue_free();await process_frame
	print("EXECUTION_DIAGNOSTIC rows=",result_rows.size()," first_steps=",result_rows.filter(func(row):return row.executed_first_step).size());quit()

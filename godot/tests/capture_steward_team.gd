extends "res://tests/test_intent_input.gd"
func run()->void:
	root.size=Vector2i(1280,800)
	OS.set_environment("HABITAT_OPENING","standard")
	game=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return IntentFake.new()
	root.add_child(game);game.save_enabled=false;game.set_process(false);game.memory_life.set_process(false)
	await process_frame;await process_frame
	game.chat.hide()
	for i in 10:await process_frame
	await UI.click(self,game.steward.toggle)
	await UI.click(self,game.steward.setup_button)
	var evidence:String=OS.get_environment("HABITAT_DIRECTOR_EVIDENCE")
	var rows:Array=[]
	var captured:=false
	for i in 2400:
		game._process(.5);game.local_host_commands._process(.5)
		var d:RefCounted=game.steward.body_director
		if i<360 and (i+1)%20==0:
			var actors:Dictionary={}
			for id in game.steward.Pool.IDS:actors[id]={"activity":game.world.actors[id].activity,"job":game.world.work.jobs.get(id,{}).duplicate(true),"task":d.tasks.get(id,{}).duplicate(true)}
			rows.append({"seconds":(i+1)*.5,"actors":actors})
		if i<120 or not captured and not d.batch.is_empty() and d.batch.step.action=="build" and str(d.batch.goal.id)=="pen" and d.batch.phase=="running":
			game.steward.panel.hide();game.resident_connections.hide();game.action_dock.hide()
			game.view.follow_player=false;game.view.follow_actor="";game.view.center=game.world.point(game.world.actors.codex);game.view.queue_redraw()
			await process_frame;RenderingServer.force_draw(false)
			root.get_texture().get_image().save_png(evidence.path_join("opening-%03d.png"%i if i<120 else "pen.png"))
			if i>=120:captured=true
		if i>=360 and captured:break
		if i%40==0:await process_frame
	var f:=FileAccess.open(evidence.path_join("opening.json"),FileAccess.WRITE);f.store_string(JSON.stringify(rows));f.close()
	print("CAPTURE_TEAM pen=",captured)
	game.queue_free();await process_frame;quit()

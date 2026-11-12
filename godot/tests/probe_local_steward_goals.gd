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
	var w:RefCounted=game.world
	var last:String=""
	for i in 5400:
		game._process(.5)
		if i in [1,20] and DisplayServer.get_name()!="headless":
			await process_frame;RenderingServer.force_draw(false)
			root.get_texture().get_image().save_png(OS.get_environment("HABITAT_DATA_DIR").path_join("steward-%d.png"%i))
		if i%120==0:
			var status:String=JSON.stringify(w.standard.board_completed)
			if status!=last:print("GOALS_AT ",w.forest.clock," ",status);last=status
			print("PROBE_AT ",w.forest.clock," goal=",game.steward.current_goal," queue=",game.steward.queue," failures=",game.intentions.last_failure," history=",game.intentions.history.slice(-12)," timeline=",game.steward.timeline," r=",[w.director.routines.codex.held,w.director.routines.codex.enabled,w.director.routines.codex.next_speech,w.director.time,w.director.speech_after]," jobs=",w.work.jobs.keys()," fire=",w.barbecues["home.barbecue"].fireside.state," stock=",w.storage.saved())
			await process_frame
	var out:=FileAccess.open(OS.get_environment("HABITAT_DATA_DIR").path_join("probe.json"),FileAccess.WRITE)
	out.store_string(JSON.stringify({"goals":w.standard.goals.rows(w),"history":game.intentions.history,"stock":w.storage.saved()}));out.close()
	print("HISTORY ",game.intentions.history)
	print("FINAL_GOALS ",w.standard.goals.rows(w))
	game.queue_free();await process_frame;quit()

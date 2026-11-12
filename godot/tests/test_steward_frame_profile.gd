extends "res://tests/test_intent_input.gd"
func run()->void:
	OS.set_environment("HABITAT_OPENING","standard")
	game=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return IntentFake.new()
	root.add_child(game);game.set_process(false);game.memory_life.set_process(false)
	await process_frame;await process_frame
	game.chat.hide()
	for managed in [false,true]:
		if managed:game.steward.start("codex")
		for interval in [4.0,15.0]:
			game.autosave_interval=interval;game.autosave=0;game.saved_revision=-1
			var samples:Array=[]
			for i in 1000:
				var begin:int=Time.get_ticks_usec();game._process(.02);samples.append((Time.get_ticks_usec()-begin)/1000.0)
				if i%100==0:await process_frame
			samples.sort()
			print("FRAME_PROFILE ",JSON.stringify({"managed":managed,"save_interval":interval,"p50_ms":samples[500],"p95_ms":samples[950],"max_ms":samples.back()}))
	game.queue_free();await process_frame;quit()

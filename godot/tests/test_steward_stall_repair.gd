extends "res://tests/test_intent_input.gd"
func run()->void:
	OS.set_environment("HABITAT_OPENING","standard")
	game=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return IntentFake.new()
	root.add_child(game);game.save_enabled=false;game.set_process(false)
	await process_frame;await process_frame
	await UI.click(self,game.steward.toggle);await UI.click(self,game.steward.setup_button)
	var w:RefCounted=game.world
	var d:RefCounted=game.steward.body_director
	# Synthetic isolated fixture, never a player save.
	w.storage._items={"wood":14,"mushroom":6,"seed.turnip":4,"seed.tomato":4}
	w.standard.board_completed["goal.meal"]=true
	d.tasks.clear();d.batch.clear()
	for id in game.steward.Pool.IDS:
		w._routes.erase(id);w.actors[id].activity="idle";w.actors[id].position=[65.2,74.0]
	d.start_batch(game,{"goal":{"id":"field","text":"建菜地"},"intents":[{"action":"build","target_id":"play.standard.hill-field"}]})
	game.steward.failure("Steward complete input exceeds 5000; 5009 bytes")
	var baseline:float=w.forest.clock
	var elapsed:=0.0
	while elapsed<60 and not w.leisure.sites["play.standard.hill-field"].complete:
		game._process(.5);game.local_host_commands._process(.5);elapsed+=.5
		if int(elapsed*2)%10==0:await process_frame
	check(w.leisure.sites["play.standard.hill-field"].complete,"AI oversized failure does not block field within 60 seconds")
	print("STALL_FIXTURE seconds=",elapsed," actual_seconds=",w.forest.clock-baseline)
	var evidence:String=OS.get_environment("HABITAT_DIRECTOR_EVIDENCE")
	if DisplayServer.get_name()!="headless" and not evidence.is_empty():
		for dimensions in [Vector2i(1280,800),Vector2i(960,640)]:
			root.size=dimensions
			for level in range(4):
				game.ui_scale.set_level(level,false)
				d.question(game)
				game.view.center=w.point(w.actors[game.steward.manager])
				for i in 5:await process_frame
				d.position_cards(game)
				await RenderingServer.frame_post_draw
				root.get_texture().get_image().save_png(evidence.path_join("card-%s-%s.png"%[dimensions.x,level]))
	game.queue_free();await process_frame;quit(1 if failed else 0)

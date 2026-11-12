extends "res://tests/test_intelligence_core_input.gd"
func advance(seconds:float)->void:
	for tick in int(seconds*10):
		game._process(.1);game.journey._process(.1)
		if tick%100==0:await process_frame
func run()->void:
	await fresh()
	var w:RefCounted=game.world
	check(game.dialogue_button.text=="对话/指令","command caption")
	await picture("journey-task1")
	check(await UI.click(self,game.journey.guide),"native tutorial guide")
	await advance(150)
	check(game.journey.destination.is_empty(),"forest navigation arrives")
	var tree:Dictionary={}
	for candidate in w.objects.values():
		if candidate.kind=="tree" and candidate.status=="mature" and w.point(candidate).distance_to(w.point(w.actors.human))<6:tree=candidate;break
	check(not tree.is_empty(),"guide really reaches forest")
	if not tree.is_empty():
		game.view.center=w.point(tree);game.view.follow_player=false
		await process_frame
		var at:Vector2=game.view.screen(w.point(tree))
		for down in [true,false]:
			var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;e.position=at;e.global_position=at;root.push_input(e,true);await process_frame
		await advance(2)
		await picture("journey-chopping")
		check(w.work.jobs.has("human"),"native tree click starts chopping")
		check(not game.journey.helpers.is_empty(),"following companion takes different tree")
		var before:int=w.storage.count("wood")
		await advance(60)
		check(w.actors.human.carry.is_empty(),"host harvest never held")
		check(w.storage.count("wood")>=before+3,"real cut reaches warehouse")
		await picture("journey-stored")
	for down in [true,false]:
		var e:=InputEventKey.new();e.keycode=KEY_M;e.pressed=down;root.push_input(e,true);await process_frame
	check(game.atlas.visible,"M opens atlas")
	await picture("journey-map-zh")
	check(await UI.click(self,game.journey.shortcuts.get_child(0)),"native barbecue navigation")
	await advance(150)
	await picture("journey-fire")
	TextLocale()
	game._toggle_atlas(true);await process_frame;await picture("journey-map-en")
	game._toggle_atlas(false);await process_frame;await picture("journey-task-en")
	game.queue_free();await process_frame
	print("HOST_JOURNEY_INPUT ",checks," failed=",failed);quit(1 if failed else 0)
func TextLocale()->void:
	TranslationServer.set_locale("en");preload("res://scripts/localization.gd").events.changed.emit();game.journey._process(0)

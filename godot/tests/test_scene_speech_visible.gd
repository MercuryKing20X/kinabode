extends "res://tests/test_intelligence_core_input.gd"
func run()->void:
	await fresh()
	var seen:Dictionary={};var contexts:Dictionary={};var max_bubbles:=0
	for i in range(1200):
		game._process(.1);max_bubbles=maxi(max_bubbles,game.view.speech_layout().size())
		for e in game.world.director.events:
			if not seen.has(e.serial):seen[e.serial]=true;contexts[e.context]=true
		if i%100==0:await process_frame
	check(max_bubbles<=8,"original viewport cap")
	check(max_bubbles>0,"actual visible speech exists")
	check(contexts.has("scene_morning"),"morning first observation reaches real outlet")
	check(contexts.has("scene_idle") or contexts.has("scene_quiet_company"),"stationary scene reaches real outlet")
	await picture("final-scene-zh")
	TranslationServer.set_locale("en");preload("res://scripts/localization.gd").events.changed.emit()
	await picture("final-scene-en")
	print("VISIBLE_SCENE ",checks," failed=",failed," max_bubbles=",max_bubbles," contexts=",contexts)
	game.queue_free();await process_frame;quit(1 if failed else 0)

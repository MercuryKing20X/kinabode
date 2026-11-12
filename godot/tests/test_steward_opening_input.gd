extends "res://tests/test_intelligence_core_input.gd"
func run()->void:
	OS.set_environment("HABITAT_OPENING","standard")
	root.size=Vector2i(1280,800)
	game=load("res://scenes/main_v3.tscn").instantiate();game.dialogue_adapter_factory=func(_id,_scope):return preload("res://tests/test_intent_input.gd").IntentFake.new()
	root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.memory_life.set_process(false)
	await process_frame;await process_frame
	var w:RefCounted=game.world
	print("OPENING_FOLLOWERS ",w.activities.following.keys())
	check(w.activities.following.size()==4,"new standard has all four followers")
	for i in range(400):game._process(.1)
	for who in game.steward.Pool.IDS:
		print("OPENING_DISTANCE ",who," ",w.point(w.actors[who]).distance_to(w.point(w.actors.human)))
		check(w.point(w.actors[who]).distance_to(w.point(w.actors.human))<15,"all arrive "+who)
	var before:Dictionary=w.activities.following.duplicate()
	w.director.set_controller("codex","model")
	game.connection_ui_states["codex:direct"]="ready";game.connection_history.set_value("connected","codex",1);game.steward.pool.set_management("codex",true)
	check(w.activities.following==before,"connection preserves formation membership")
	check(game.steward.start("codex"),"appoint manager")
	game.steward.reasons.clear()
	game.steward.stop();w.director.set_controller("codex","local")
	check(w.activities.following==before,"immediate stop and disconnect preserve membership")
	w.director.set_controller("codex","model");game.steward.start("codex");game.steward.reasons.clear()
	check(w.activities.following==before,"appointment preserves membership")
	# C: start changes the VBox minimum; settle layout before reveal computes scroll.
	await process_frame;await process_frame
	print("CAMERA_BEFORE ",{"rect":game.steward.camera_switch.get_global_rect(),"scroll":game.steward.lines.get_parent().get_global_rect(),"value":game.steward.lines.get_parent().scroll_vertical})
	await UI.click(self,game.steward.camera_switch)
	var hovered:Control=root.gui_get_hovered_control()
	print("CAMERA_AFTER ",{"rect":game.steward.camera_switch.get_global_rect(),"scroll":game.steward.lines.get_parent().get_global_rect(),"value":game.steward.lines.get_parent().scroll_vertical,"hovered":str(hovered.get_path()) if hovered!=null else "none"})
	check(game.steward.director_camera,"real mouse toggles follow steward")
	var max_distance:=0.0
	for i in range(1200):
		game._process(.1)
		game.view._process(.1)
		max_distance=maxf(max_distance,game.view.center.distance_to(w.point(w.actors.codex)))
	check(max_distance<1,"camera follows steward for 120 seconds")
	print("CAMERA_MAX_DISTANCE ",max_distance)
	for down in [true,false]:
		var event:=InputEventKey.new();event.keycode=KEY_SPACE;event.pressed=down;root.push_input(event,true);await process_frame
	game._process(.1);game.view._process(.1)
	check(game.view.follow_actor=="codex","space resumes configured target")
	await picture("new-opening-follow")
	game.steward.stop();w.director.set_controller("codex","local")

	game.queue_free();await process_frame
	print("OPENING_CHECKS ",checks," failed=",failed);quit(1 if failed else 0)

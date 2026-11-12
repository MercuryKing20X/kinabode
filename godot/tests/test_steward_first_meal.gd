extends "res://tests/test_intelligence_core_input.gd"
func run()->void:
	OS.set_environment("HABITAT_OPENING","standard")
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);game.memory_life.set_process(false)
	await process_frame;await process_frame
	var w:RefCounted=game.world
	w.director.set_controller("codex","model");game.connection_ui_states["codex:direct"]="ready";game.connection_history.set_value("connected","codex",1);game.steward.pool.set_management("codex",true)
	game.steward.start("codex");game.steward.reasons.clear();game.steward.preset()
	for i in range(6000):
		game._process(.1)
		if i%100==0:await process_frame
		if not w.barbecues["home.barbecue"].fireside.state.get("current",{}).is_empty():break
	print("FIRST_MEAL_TIMELINE ",game.steward.timeline," FAILURE ",game.intentions.last_failure," FIRE ",w.barbecues["home.barbecue"].fireside.state)
	check(w.standard.ready("home.barbecue"),"real opening camp built")
	check(not w.barbecues["home.barbecue"].fireside.state.get("current",{}).is_empty(),"first meal cooked from opening")
	game.queue_free();await process_frame
	print("FIRST_MEAL_CHECKS ",checks," failed=",failed);quit(1 if failed else 0)

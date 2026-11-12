extends "res://tests/test_empowered_input.gd"
func run()->void:
	OS.set_environment("HABITAT_OPENING","showcase")
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);game.memory_life.set_process(false)
	await process_frame;await process_frame
	var w:RefCounted=game.world;w.director.set_controller("codex","model")
	game.chat.hide();game.chat_input.release_focus()
	check(game.intentions.submit("codex",[{"action":"fish"}],"direct:codex").ok,"prepare real owned catch")
	for i in range(2500):
		game._process(.1)
		if i%100==0:await process_frame
		if not w.fishing.held("codex").is_empty() and not game.intentions.plans.has("codex"):break
	var fish:Dictionary=w.fishing.held("codex").duplicate(true)
	check(not fish.is_empty(),"real catch exists before choosing recipe")
	var wood:int=w.storage.count("wood")
	check(game.intentions.submit("codex",[{"action":"roast","item_id":"recipe:not-a-real-recipe"}],"direct:codex").ok,"walk to validate requested recipe")
	for i in range(1500):
		game._process(.1)
		if not game.intentions.plans.has("codex"):break
	check(w.fishing.fish.get(fish.get("id",""),{})==fish,"invalid recipe never silently substitutes or consumes held fish")
	check(w.storage.count("wood")==wood,"invalid menu never spends ignition wood")
	check(game.intentions.last_failure.get("codex")=="missing_food","actual reason is retained")
	game.queue_free();await process_frame
	print("RESIDENT_RECIPE_GUARD ",checks," failed=",failed);quit(1 if failed else 0)

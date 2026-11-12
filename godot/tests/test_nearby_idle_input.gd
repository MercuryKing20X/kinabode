extends "res://tests/test_dialogue_bar_input.gd"
func run()->void:
	OS.set_environment("HABITAT_OPENING","showcase")
	var game:Node
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);await frames()
	game.world.director.set_all_enabled(true)
	game.world.activities.set_followers(game.steward.Pool.IDS)
	for tick in range(1200):
		game.world.advance(.1);game.playground.tick(.1)
		if game.steward.Pool.IDS.all(func(id):return game.world.point(game.world.actors[id]).distance_to(game.world.point(game.world.actors.human))<=5.5):break
	var distances:Dictionary={};var actions:Dictionary={}
	for id in game.steward.Pool.IDS:distances[id]=[];actions[id]={}
	for tick in range(6000):
		game.world.advance(.1);game.playground.tick(.1)
		for id in game.steward.Pool.IDS:
			if tick%10==0:distances[id].append(game.world.point(game.world.actors[id]).distance_to(game.world.point(game.world.actors.human)))
			if game.playground.nearby.has(id):actions[id][game.playground.nearby[id].action]=true
		if tick%1000==0:await frames(2);await capture("nearby-"+str(tick))
	var out:=FileAccess.open(OS.get_environment("HABITAT_UI_EVIDENCE").path_join("nearby-stats.json"),FileAccess.WRITE)
	out.store_string(JSON.stringify({"distances":distances,"actions":actions}));out.close()
	for id in game.steward.Pool.IDS:
		check(distances[id].max()<=6,"within six tiles "+id)
		check(actions[id].size()>=5,"five actions "+id)
	print("NEARBY_INPUT ",checks," failed=",failed);game.queue_free();await frames();quit(1 if failed else 0)

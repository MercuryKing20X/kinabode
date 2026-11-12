extends "res://tests/test_dialogue_bar_input.gd"
func run()->void:
	OS.set_environment("HABITAT_OPENING","showcase")
	var game:Node=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);game.world.director.set_all_enabled(false)
	root.size=Vector2i(1280,800);await frames()
	for kind in ["shuttlecock","rope"]:
		check(game.playground.start(kind).ok,"starts "+kind)
		game.view.follow_player=false;game.view.center=game.playground.anchor;game.view.zoom=.8
		for tick in range(85):game.world.advance(.1);game.playground.tick(.1)
		await frames(2);await capture(kind+"-prop")
		game.playground.finish()
	game.queue_free();await frames();quit(1 if failed else 0)

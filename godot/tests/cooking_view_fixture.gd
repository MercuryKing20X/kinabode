extends RefCounted
const F=preload("res://tests/cooking_fixture.gd")
static func present(game: Node,scenario: String) -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):return
	game.world.director.set_all_enabled(false);game.view.sound_enabled=false
	if not F.harvest(game.world,"turnip"):push_error("cooking evidence harvest failed");return
	if not F.serve(game.world,"turnip-soup","",["human","codex","companion-2"]):push_error("cooking evidence serve failed");return
	if scenario=="cooking_meal":

		for tick in range(250):
			game.world.advance(.1)
			if game.world.work.jobs.values().filter(func(job):return job.get("phase")=="fire_eat").size()==3:break
		game.world.advance(.1);game.world.advance(.1)
	game.chat.hide();game.view.follow_player=false;game.view.center=game.world.point(game.world.life.station)+Vector2(4,1);game.view.zoom=.85
	var menu:=preload("res://scripts/fireside_menu.gd").new();game.add_child(menu);menu.setup(game.world.life,game.view.font);menu.popup_centered()

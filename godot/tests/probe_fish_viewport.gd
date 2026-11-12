extends "res://tests/test_intelligence_core_input.gd"
func run()->void:
	var output:String=OS.get_environment("HABITAT_UI_EVIDENCE")
	if output.is_empty() or not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-"):quit(1);return
	OS.set_environment("HABITAT_OPENING","showcase")
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);game.world.director.set_all_enabled(false);await process_frame;await process_frame
	for id in game.steward.Pool.IDS:game.world.activities.release_follow(id)
	game.world.director.set_controller("codex","model") # Offline host execution fixture; no model adapter is started.
	var started:Dictionary=game.intentions.submit("codex",[{"action":"fish"},{"action":"light"},{"action":"roast","item_id":"single:fish"},{"action":"invite","guest_ids":["companion-2","npc.mira","npc.nora"]}],game.Channels.direct("codex"))
	check(started.ok,"explicit host requests actual fish meal")
	if not started.ok:game.queue_free();await process_frame;quit(1);return
	var eaten:=false
	for tick in range(20000):
		game._process(.1)
		if tick%20==0:await process_frame
		for camp in game.world.barbecues.values():
			if camp.fireside.state.get("ate",{}).size()>=4:
				game.chat.hide();game.view.follow_player=false;game.view.center=game.world.point(camp.station);game.view.zoom=1.2
				await process_frame;await process_frame;RenderingServer.force_draw(false)
				root.get_texture().get_image().save_png(output)
				eaten=true;break
		if eaten:break
	check(eaten,"four real fish eaters before screenshot")
	game.queue_free();await process_frame;quit(1 if failed else 0)

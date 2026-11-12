extends "res://tests/capture_route_latched.gd"
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"));output=OS.get_environment("HABITAT_DARK_EVIDENCE");root.size=Vector2i(1280,800)
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");root.add_child(game);await process_frame;await process_frame
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.view.sound_enabled=false
	var e:RefCounted=game.world.dark.discoveries
	if e.found.size()<3 or e.catches.size()<3 or e.star_days.is_empty() or "heather" not in game.world.dark.beacons:failed=true
	await shot("fresh-process-progress")
	FileAccess.open(output.path_join("resume.json"),FileAccess.WRITE).store_string(JSON.stringify({"state":e.saved(),"carry":game.world.actors.human.carry,"beacons":game.world.dark.beacons,"failed":failed},"  "))
	game.queue_free();await process_frame;quit(1 if failed else 0)

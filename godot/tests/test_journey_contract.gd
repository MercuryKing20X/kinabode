extends "res://tests/test_intelligence_core_input.gd"
func run()->void:
	await fresh()
	var w:RefCounted=game.world
	var tree:Dictionary=w.objects["home.tree.01"]
	check(w.command("human",{"intent":"chop","target_id":tree.id}).ok,"host real chopping route")
	for tick in 2500:
		game._process(.1);game.journey._process(.1)
		if w.work.jobs.get("human",{}).get("phase")=="chop":break
	game.journey.assist()
	check(not game.journey.helpers.is_empty(),"following helpers accepted scoped jobs")
	for id in game.journey.helpers:check(w.work.jobs[id].get("first_id",w.work.jobs[id].get("target_id"))!=tree.id,"helper reserves different tree")
	var stock:int=w.storage.count("wood")
	for tick in 1500:game._process(.1);game.journey._process(.1)
	check(w.storage.count("wood")>=stock+3 and w.actors.human.carry.is_empty(),"physical harvest stored, hands empty")
	var dir:String=OS.get_environment("HABITAT_DATA_DIR").path_join("legacy")
	w.actors.human.carry={"wood":4};w.storage.add({"wood":7})
	var total:int=w.storage.count("wood")+4
	var Save=preload("res://scripts/save_store.gd")
	check(Save.save_world(w,dir),"fixture saved")
	var next:RefCounted=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	check(Save.load_world(next,dir).ok,"old held wood load")
	check(next.storage.count("wood")==total and next.actors.human.carry.is_empty(),"load conserves warehouse plus held wood")
	game.queue_free();await process_frame
	print("JOURNEY_CONTRACT ",checks," failed=",failed);quit(1 if failed else 0)

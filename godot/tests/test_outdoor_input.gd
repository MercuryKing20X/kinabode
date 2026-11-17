extends "res://tests/test_home_island_input.gd"
## 2026-11-06 retires the old southern furnishing/foundation workflow.
## The replacement keeps native collection, bridge motion, villas and camp evidence.
func run()->void:
	var probe:Node=UI.init_game(self);await process_frame;await process_frame
	await bridge_walk(probe,Vector2(93,185),"outdoor-retirement")
	check(probe.world.resort.contains(probe.world.point(probe.world.actors.human)) and not probe.world.resort.vacation("human"),"native host enters Flower Isle without retired vacation state")
	var outdoor:Node=null
	for node in probe.get_children():
		if node.get_script()==preload("res://scripts/outdoor_ui.gd"):outdoor=node
	check(outdoor!=null,"original contextual UI owner remains present")
	if outdoor!=null:
		outdoor._process(0)
		check(not outdoor.button.visible,"retired construction button is absent on holiday land")
	check(probe.world.work.jobs.is_empty(),"entering holiday land starts no work")
	probe.queue_free();await process_frame
	await super.run()

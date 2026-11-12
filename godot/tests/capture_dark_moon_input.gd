extends "res://tests/capture_dark_island_input.gd"
## Remaining default/nondefault moon combinations, genuine input with untouched map state.
func run()->void:
	directory=OS.get_environment("HABITAT_DATA_DIR");assert(directory.contains("youqi-test-"));output=OS.get_environment("HABITAT_DARK_EVIDENCE")
	root.content_scale_size=Vector2i.ZERO;root.size=Vector2i(1280,800)
	for opening in ["showcase","standard"]:
		mode=opening;OS.set_environment("HABITAT_DATA_DIR",directory.path_join(opening));OS.set_environment("HABITAT_OPENING","legacy" if opening=="showcase" else "standard")
		game=load("res://scenes/main_v3.tscn").instantiate();game.world=World.new("res://content/home-v3/world.json");root.add_child(game);game.set_process(false);game.view.set_process(false);await process_frame;await process_frame;tick(.1)
		await wardrobe()
		var moon:Vector2=game.world.point(game.world.barbecues["moon.barbecue"].station)+Vector2(8,8)
		if await walk(moon):
			check(game.world.moon.contains(game.world.point(game.world.actors.human)),"actual host crossed original bridge to moon")
			await pair("moon-default-human-four-outfits")
			if await human_outfit():await pair("moon-nondefault-human-four-outfits")
		check(game.world.dark.fires.is_empty() and game.world.dark.beacons.is_empty() and not game.world.dark.torch.owned,"moon regression never starts dark gameplay or grants torch")
		check(game.links.values().all(func(link):return link._pid<=0),"moon combinations launch no model process")
		game.queue_free();await process_frame;await process_frame
	var file:=FileAccess.open(output.path_join("moon-input.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failed":failed,"results":results},"  "));file.close()
	print("Moon combinations input: ",checks," checks failed=",failed);quit(1 if failed else 0)

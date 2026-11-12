extends "res://tests/capture_dark_island_input.gd"
## Fresh-process reload of a genuine mouse-created temporary save; presentation via real UI only.
func run()->void:
	directory=OS.get_environment("HABITAT_DATA_DIR");assert(directory.contains("youqi-test-"));output=OS.get_environment("HABITAT_DARK_EVIDENCE");mode="showcase"
	var meta:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("resume-meta.json")))
	OS.set_environment("HABITAT_OPENING","legacy");root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=World.new("res://content/home-v3/world.json");root.add_child(game);game.set_process(false);game.view.set_process(false);await process_frame;await process_frame
	var d:RefCounted=game.world.dark
	check(game.world.actors.human.region_id=="dark" and game.world.actors.human.position==meta.position,"fresh process loads exact real person and region")
	check(d.fires==meta.state.fires and d.beacons==meta.state.beacons and absf(float(d.torch.remaining)-float(meta.state.torch.remaining))<.1,"fresh process keeps all permanent sources and exact torch seconds")
	check(game.world.work.jobs.is_empty() and game.world._routes.is_empty(),"fresh process restores no action jobs or routes")
	await pair("fresh-process-real-save")
	var popup:PopupMenu=game.handbook_menu.get_popup();var map_id:=-1
	for i in range(popup.item_count):
		if popup.get_item_metadata(i)=="map":map_id=popup.get_item_id(i);break
	await popup_item(game.handbook_menu,map_id)
	check(game.atlas.visible,"real handbook opens map after fresh reload")
	check(await press(game.atlas.panel,"黑暗岛"),"actual atlas island button focuses dark region")
	check(game.atlas.selected_region=="dark","dark atlas is actually selected")
	await pair("focused-lit-dark-map")
	await tap(KEY_ESCAPE)
	var file:=FileAccess.open(output.path_join("resume-input.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failed":failed,"results":results},"  "));file.close()
	game.queue_free();await process_frame;print("Dark fresh-process resume input: ",checks," checks failed=",failed);quit(1 if failed else 0)

extends "res://tests/capture_dark_island_input.gd"
## Narrow real-input regression: occluded small-fire click and genuine process-reload checkpoint.
func run()->void:
	directory=OS.get_environment("HABITAT_DATA_DIR");assert(directory.contains("youqi-test-"));output=OS.get_environment("HABITAT_DARK_EVIDENCE");mode="showcase"
	OS.set_environment("HABITAT_OPENING","legacy");root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=World.new("res://content/home-v3/world.json");root.add_child(game);game.set_process(false);game.view.set_process(false);await process_frame;await process_frame;tick(.1)
	if not await voyage(true):finish();return
	var d:RefCounted=game.world.dark
	await dark_action(d.p(d.config.camp),"dark.barbecue","点火把")
	await dark_action(Vector2(44,82),"","点一堆火 · 2 木材")
	var wood:int=B.wood_total(game.world)
	check(await dark_action(Vector2(44,82),"dark.fire.0","点火把"),"real fire hit outside standing human rectangle")
	check(B.wood_total(game.world)==wood and d.torch.remaining>119,"fire refill is free after exact real hit")
	await dark_action(Vector2(44,66),"","点一堆火 · 2 木材")
	var area:Dictionary=d.config.areas.filter(func(a):return a.has("beacon"))[0]
	await dark_action(d.p(area.beacon),"dark.beacon."+str(area.id),"点亮灯台 · 6 木材")
	check(d.fires.size()==2 and d.beacons.size()==1,"actual input checkpoint owns two real fires and one beacon")
	await pair("checkpoint-two-fires-beacon")
	var before:Dictionary=d.saved();var actor_position:Array=game.world.actors.human.position.duplicate();var data_path:String=game.data_dir
	# The game's own exit handler writes the save. This copies that genuine test file, without edits.
	game.queue_free();await process_frame;await process_frame
	var retained:String="/tmp/youqi-test-dark-input-resume-"+str(Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(retained)
	check(DirAccess.copy_absolute(data_path.path_join("island-v2.json"),retained.path_join("island-v2.json"))==OK,"preserve only genuine isolated autosave for a fresh process")
	var metadata:=FileAccess.open(retained.path_join("resume-meta.json"),FileAccess.WRITE);metadata.store_string(JSON.stringify({"position":actor_position,"state":before,"source":"real InputEvent mouse flow; normal game exit save, copied without modification"},"  "));metadata.close()
	var index:=FileAccess.open("/tmp/youqi-test-dark-input-resume-path.txt",FileAccess.WRITE);index.store_string(retained);index.close()
	print("GENUINE TEST RESUME ",retained)
	finish()
func finish()->void:
	var file:=FileAccess.open(output.path_join("save-input.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failed":failed,"results":results},"  "));file.close()
	print("Dark save-input regression: ",checks," checks failed=",failed);quit(1 if failed else 0)

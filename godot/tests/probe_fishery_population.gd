extends "res://tests/probe_world_work_frames.gd"

func sample(game:Node,pen_id:String)->Dictionary:
	var frame_ms:Array=[]
	var process_ms:Array=[]
	for frame in 90:await RenderingServer.frame_post_draw
	var previous:=Time.get_ticks_usec()
	for frame in 600:
		await RenderingServer.frame_post_draw
		var now:=Time.get_ticks_usec()
		frame_ms.append((now-previous)/1000.0)
		previous=now
		process_ms.append(1000.0*Performance.get_monitor(Performance.TIME_PROCESS))
	return {"fish":game.world.fishing.pen_count(pen_id),"swimmers":game.view.fishing_renderer.swimmers.size(),"frames":frame_ms.size(),"frame_ms":percentiles(frame_ms),"process_ms":percentiles(process_ms)}

func run()->void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-") or DisplayServer.get_name()=="headless":quit(2);return
	root.size=Vector2i(1280,800)
	set_meta("title_opening","standard")
	var game:Node=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return Fake.new()
	root.add_child(game)
	game.save_enabled=false
	var world:RefCounted=game.world
	world.director.set_all_enabled(false)
	var pen_id:="home.fishery.south"
	var pen:Dictionary=world.fishing.pens[pen_id]
	game.view.follow_player=false
	game.view.center=world.catalog.rectangle(pen.rect).get_center()
	# Pin the measurement camera instead of allowing the normal five-second peek.
	var pin_camera:=func():game.view.peek_elapsed=0.0
	process_frame.connect(pin_camera)
	# Keep the HUD mode fixed across the two runs while world processing remains live.
	game.island_hud.set_process(false)
	var empty:=await sample(game,pen_id)
	# A synthetic population exercises render cost only. It is never saved.
	for i in 500:
		world.fishing.add_fish({"id":"fish-%024x"%i,"owner_id":"human","source_id":"home.sea.south","spot_id":"shore-"+"0".repeat(24),"species_id":"bean","color_id":"cream","size_id":"person","scale":1,"location":pen_id,"caught_at":100})
	var stocked:=await sample(game,pen_id)
	print("FISHERY_FRAMES ",JSON.stringify({"empty":empty,"stocked":stocked,"driver":DisplayServer.get_name()}))
	process_frame.disconnect(pin_camera)
	game.queue_free()
	await process_frame
	quit(0 if empty.fish==0 and stocked.fish==500 and stocked.swimmers==world.fishing.DISPLAY_FISH_LIMIT else 1)

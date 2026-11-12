extends "res://tests/capture_gait_v4.gd"
var old_human:Dictionary
func shot_run(name:String)->void:
	view.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK)
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"));output=OS.get_environment("HABITAT_STAGE2_EVIDENCE")
	root.size=Vector2i(960,640);root.content_scale_size=Vector2i.ZERO
	w=World.new("res://content/home-v3/world.json");w.residents.provision(w);w.library=Library.new();w.library.configure(OS.get_environment("HABITAT_DATA_DIR"));assert(Opening.apply(w,w.library,"showcase").ok);w.intelligence.activate_presets();w.director.set_all_enabled(false)
	view=preload("res://scripts/island_v3_view.gd").new();view.world=w;view.library=w.library;view.font=load("res://assets/fonts/NotoSansSC.ttf");view.sound_enabled=false;root.add_child(view);view.set_process(false);view.follow_player=false;view.zoom=2
	var center:Array=w.map_anchor("plaza.center");var start:=Vector2(center[0]-3,center[1]+10)
	old_human=w.intelligence.gait_defaults.human.duplicate(true)
	for mode in ["walk","run-before","run"]:
		move("human",start)
		if mode=="run-before":w.intelligence.gait_defaults.human.merge({"run_bounce":7.1,"run_lean":.134,"run_stretch":.035,"run_dust":.975,"run_frames_per_step":1.0},true)
		else:w.intelligence.gait_defaults.human=old_human.duplicate(true)
		var finish:Vector2=start-Vector2(11 if mode=="walk" else 40,0)
		assert(w.command("human",{"intent":"move","x":finish.x,"y":finish.y}).ok)
		for index in range(60):
			if mode=="walk" and not w._routes.has("human"):
				var next:Vector2=w.point(w.actors.human)-Vector2(8,0)
				assert(w.command("human",{"intent":"move","x":next.x,"y":next.y}).ok)
			step(.05);view.center=w.point(w.actors.human)+Vector2(0,-1)
			var m:Dictionary=w.motion_state("human")
			frames.append({"id":"human","mode":mode,"index":index,"position":w.actors.human.position.duplicate(),"facing":m.facing,"moving":m.moving,"running":w.is_running("human"),"step":view.motion.states.human.step,"run_pixels":view.motion.states.human.get("run_pixels",0)})
			await shot_run("human-"+mode+"-"+str(index).pad_zeros(2))
		wait("human");await shot_run("human-"+mode+"-brake")
	w.intelligence.gait_defaults.human=old_human.duplicate(true)
	var ids:Array=["human","codex","companion-2","npc.mira","npc.nora"]
	for n in range(5):move(ids[n],start+Vector2(n*3,0))
	for n in range(5):
		var finish:Vector2=w.point(w.actors[ids[n]])-Vector2(40,0)
		assert(w.command(ids[n],{"intent":"move","x":finish.x,"y":finish.y}).ok)
	view.zoom=1
	for index in range(60):
		step(.05);view.center=w.point(w.actors.human)+Vector2(6,-1)
		await shot_run("five-run-"+str(index).pad_zeros(2))
	var f:=FileAccess.open(output.path_join("distance-trace.json"),FileAccess.WRITE);f.store_string(JSON.stringify(frames,"  "));f.close()
	view.queue_free();await process_frame;quit()

extends "res://tests/capture_gait_v4.gd"
func shot_run(name:String)->void:
	view.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK)
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"));output=OS.get_environment("HABITAT_STAGE2_EVIDENCE")
	if OS.get_environment("HABITAT_RUN_OUTFITS")=="1":output=output.path_join("outfits")
	root.size=Vector2i(960,640);root.content_scale_size=Vector2i.ZERO
	w=World.new("res://content/home-v3/world.json");w.residents.provision(w);w.library=Library.new();w.library.configure(OS.get_environment("HABITAT_DATA_DIR"));assert(Opening.apply(w,w.library,"showcase").ok);w.intelligence.activate_presets();w.director.set_all_enabled(false)
	if OS.get_environment("HABITAT_RUN_OUTFITS")=="1":
		# Supplementary render fixture only, not a claimed wardrobe/mouse acceptance.
		var assignments:Dictionary={"codex":"ai-gpt","companion-2":"ai-deepseek","npc.mira":"ai-claude","npc.nora":"ai-glm"}
		for actor_id in assignments:assert(w.assign_appearance(actor_id,assignments[actor_id],false,false))
	view=preload("res://scripts/island_v3_view.gd").new();view.world=w;view.library=w.library;view.font=load("res://assets/fonts/NotoSansSC.ttf");view.sound_enabled=false;root.add_child(view);view.set_process(false);view.follow_player=false;view.zoom=2
	var center:Array=w.map_anchor("plaza.center");var start:=Vector2(center[0]-3,center[1]+10)
	for id in ["companion-2","codex","npc.mira","npc.nora"]:
		for mode in ["walk","run"]:
			move(id,start)
			var finish:Vector2=start+Vector2(11 if mode=="walk" else 40,0)
			assert(w.command(id,{"intent":"move","x":finish.x,"y":finish.y}).ok)
			for index in range(60):
				step(.05);view.center=w.point(w.actors[id])+Vector2(0,-1)
				var m:Dictionary=w.motion_state(id)
				frames.append({"id":id,"mode":mode,"index":index,"position":w.actors[id].position.duplicate(),"moving":m.moving,"running":w.is_running(id),"step":view.motion.states[id].step,"run_pixels":view.motion.states[id].get("run_pixels",0)})
				await shot_run(id+"-"+mode+"-"+str(index).pad_zeros(2))
			wait(id)
			await shot_run(id+"-"+mode+"-brake")
		move(id,start)
	var f:=FileAccess.open(output.path_join("distance-trace.json"),FileAccess.WRITE);f.store_string(JSON.stringify(frames,"  "));f.close()
	view.queue_free();await process_frame;quit()

extends "res://tests/capture_gait_v4.gd"
func shot_run(name:String)->void:
	view.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
	assert(root.get_texture().get_image().save_png(output.path_join(name+".png"))==OK)
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"));output=OS.get_environment("HABITAT_STAGE2_EVIDENCE")
	root.size=Vector2i(960,640);root.content_scale_size=Vector2i.ZERO
	w=World.new("res://content/home-v3/world.json");w.residents.provision(w);w.library=Library.new();w.library.configure(OS.get_environment("HABITAT_DATA_DIR"));assert(Opening.apply(w,w.library,"showcase").ok);w.intelligence.activate_presets();w.director.set_all_enabled(false)
	assert(w.assign_appearance("npc.nora","ai-glm",false,false))
	view=preload("res://scripts/island_v3_view.gd").new();view.world=w;view.library=w.library;view.font=load("res://assets/fonts/NotoSansSC.ttf");view.sound_enabled=false;root.add_child(view);view.set_process(false);view.follow_player=false;view.zoom=2
	var center:Array=w.map_anchor("plaza.center");var start:=Vector2(center[0]-3,center[1]+10)
	var full:Dictionary=view.action_atlases.manifests.run.duplicate(true)
	for id in ["human","companion-2","npc.nora"]:
		for mode in ["walk","fallback","run"]:
			move(id,start)
			view.action_atlases.manifests.run=full.duplicate(true)
			if mode=="fallback":
				for spec in view.action_atlases.manifests.run.works.values():spec.status="unavailable"
			var finish:Vector2=start-Vector2(11 if mode=="walk" else 40,0)
			assert(w.command(id,{"intent":"move","x":finish.x,"y":finish.y}).ok)
			for index in range(60):
				if mode=="walk" and not w._routes.has(id):
					var next:Vector2=w.point(w.actors[id])-Vector2(8,0)
					assert(w.command(id,{"intent":"move","x":next.x,"y":next.y}).ok)
				step(.05);view.center=w.point(w.actors[id])+Vector2(0,-1)
				var m:Dictionary=w.motion_state(id)
				frames.append({"id":id,"mode":mode,"index":index,"position":w.actors[id].position.duplicate(),"facing":m.facing,"moving":m.moving,"running":w.is_running(id),"step":view.motion.states[id].step,"run_pixels":view.motion.states[id].get("run_pixels",0),"column":view.motion.run_column(id,w.intelligence.gait(id))})
				await shot_run(id+"-"+mode+"-"+str(index).pad_zeros(2))
			wait(id)
		move(id,start)
	var f:=FileAccess.open(output.path_join("distance-trace.json"),FileAccess.WRITE);f.store_string(JSON.stringify(frames,"  "));f.close()
	view.queue_free();await process_frame;quit()

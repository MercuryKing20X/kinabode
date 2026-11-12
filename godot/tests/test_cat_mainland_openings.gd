extends SceneTree
var failed:=false
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	if not ok:failed=true;push_error(label)
func run()->void:
	var output:String=OS.get_environment("HABITAT_PLAYTEST_CAPTURE")
	for opening in ["standard","showcase"]:
		OS.set_environment("HABITAT_OPENING","legacy" if opening=="showcase" else "standard")
		var w:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
		w.residents.provision(w);w.library=preload("res://scripts/character_library.gd").new();w.library.configure(OS.get_environment("HABITAT_DATA_DIR").path_join(opening))
		check(preload("res://scripts/world_opening.gd").apply(w,w.library,opening).ok,"real opening applies "+opening)
		var appearances:Dictionary={"codex":"ai-gpt","companion-2":"ai-deepseek","npc.mira":"ai-claude","npc.nora":"ai-glm"}
		for actor_id in appearances:w.actors[actor_id].appearance_id=appearances[actor_id]
		w.cat.initialize();w.director.set_all_enabled(false)
		check(w.cat.discovered and w.cat.region=="home" and w.cat.position.y<128 and w.cat.memories.is_empty(),"mainland pet no invented discovery/contact "+opening)
		var g:Node=load("res://scenes/main_v3.tscn").instantiate();g.world=w;root.add_child(g);g.save_enabled=false;g.set_process(false);g.view.set_process(false);g.view.sound_enabled=false;g.view.follow_player=false;g.view.center=w.cat.position;await process_frame;await process_frame
		if not output.is_empty() and DisplayServer.get_name()!="headless":
			RenderingServer.force_draw(false);root.get_texture().get_image().save_png(output.path_join("cat-"+opening+".png"))
		var visited:=false;var returned:=false;var trace:Array=[]
		for i in range(2400):
			w.advance(.5)
			if i%20==0:trace.append({"seconds":w.cat.clock,"position":[w.cat.position.x,w.cat.position.y],"phase":w.cat.excursion_phase})
			if w.cat.excursion_phase==2:visited=true
			if visited and w.cat.excursion_phase==0 and w.cat.position.y<128:returned=true;break
		check(visited and returned,"pet walks to southern shelter and back itself "+opening)
		if not output.is_empty():
			var f:=FileAccess.open(output.path_join("cat-"+opening+"-trace.json"),FileAccess.WRITE);f.store_string(JSON.stringify(trace,"  "))
		g.queue_free();await process_frame
	print("cat mainland openings failed=",failed);quit(1 if failed else 0)

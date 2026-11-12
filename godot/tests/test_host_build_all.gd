extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	# Start from a genuine formal opening so every default facility is unfinished.
	var initial=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	initial.residents.provision(initial)
	initial.library=preload("res://scripts/character_library.gd").new();initial.library.configure(OS.get_environment("HABITAT_DATA_DIR"))
	assert(preload("res://scripts/world_opening.gd").apply(initial,initial.library,"standard").ok)
	assert(preload("res://scripts/save_store.gd").save_world(initial,OS.get_environment("HABITAT_DATA_DIR")))
	var game:Node=UI.init_game(self)
	await process_frame
	var w:RefCounted=game.world
	var before:Dictionary=w.storage.saved().duplicate(true)
	var records:Dictionary=w.memories.saved().duplicate(true)
	var positions:Dictionary={}
	for site in w.objects.values():
		if site.kind=="construction_site":positions[site.id]=[site.position.duplicate(),w.site_size(site)]
	w.actors.codex.position=[100.540412902832,46.4340438842773]
	# DIRECTION v0.6: remove player entry; keep completion implementation for tests only.
	game.view.follow_player=false;game.view.center=w.point(w.objects["home.house.01"])
	await process_frame
	var at:Vector2=game.view.screen(w.point(w.objects["home.house.01"]))
	for down in [true,false]:
		var e:=InputEventMouseButton.new();e.position=at;e.global_position=at;e.pressed=down;e.button_index=MOUSE_BUTTON_LEFT;root.push_input(e,true);await process_frame
	assert(game.house_panel.visible)
	assert(game.house_panel.find_children("*","Button",true,false).all(func(b):return b.text!=preload("res://scripts/localization.gd").text("buildall.action")))
	assert(preload("res://scripts/host_build_all.gd").apply(w).ok)
	assert(w.walkable("home",w.point(w.actors.codex)) and w.point(w.actors.codex).distance_to(Vector2(100.540412902832,46.4340438842773))>0.1)
	w.cat.discovered=true;w.cat.region="home";w.cat.position=Vector2(101,47);w.cat.carrier=""
	w.drops["rescue-test"]={"id":"rescue-test","region_id":"home","position":[101.0,47.0],"wood":3}
	w.rescue_obstructed()
	assert(w.walkable("home",w.cat.position) and w.walkable("home",w.point(w.drops["rescue-test"])) and w.drops["rescue-test"].wood==3)
	w.drops.erase("rescue-test")
	for site in w.objects.values():
		if site.kind=="construction_site":assert(site.stage_index==5 and site.position==positions[site.id][0] and w.site_size(site)==positions[site.id][1])
	for site in w.leisure.sites.values():
		if not site.complete:print("UNBUILT ",site.id," ",site.template_id," available=",w.library.artworks.has(site.template_id)," status=",game.status.text)
	assert(w.leisure.sites.values().all(func(s):return s.complete) and w.homestead.completed())
	var original_position:Array=w.actors.codex.position.duplicate()
	w.actors.codex.position=[101.0,47.0]
	if not w.walkable("home",w.point(w.actors.codex)):
		w._grids.clear()
		assert(not w.find_route("codex",w.point(w.actors.human)).is_empty() and w.walkable("home",w.point(w.actors.codex)))
	w.actors.codex.position=original_position
	assert(w.storage.saved()==before and w.memories.saved()==records)
	assert(preload("res://scripts/save_store.gd").save_world(w,OS.get_environment("HABITAT_DATA_DIR").path_join("built")))
	var loaded=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");loaded.residents.provision(loaded)
	assert(preload("res://scripts/save_store.gd").load_world(loaded,OS.get_environment("HABITAT_DATA_DIR").path_join("built")).ok)
	assert(not loaded.homestead.site.completion.get("id","").is_empty())
	var path:String=OS.get_environment("HABITAT_DATA_DIR").path_join("built/island-v2.json")
	var legacy:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	legacy.homestead.site.completion={}
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(legacy));file.close()
	var restored=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");restored.residents.provision(restored)
	assert(preload("res://scripts/save_store.gd").load_world(restored,OS.get_environment("HABITAT_DATA_DIR").path_join("built")).ok)
	assert(not restored.homestead.site.completion.get("id","").is_empty())
	assert(restored.homestead.site.completion.at==0 and restored.homestead.site.contributions.is_empty())
	restored.advance(0.1)
	assert(preload("res://scripts/save_store.gd").save_world(restored,OS.get_environment("HABITAT_DATA_DIR").path_join("repaired")))
	var reloaded=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");reloaded.residents.provision(reloaded)
	assert(preload("res://scripts/save_store.gd").load_world(reloaded,OS.get_environment("HABITAT_DATA_DIR").path_join("repaired")).ok)
	assert(reloaded.homestead.site.completion.id==restored.homestead.site.completion.id and reloaded.homestead.site.completion.at==0 and reloaded.homestead.site.completion.actor_id=="human" and reloaded.homestead.site.completion.recipe_id==restored.homestead.site.completion.recipe_id)
	game.house_panel.hide()
	var output:String=OS.get_environment("HABITAT_BUILDING_CAPTURE")
	if not output.is_empty() and DisplayServer.get_name()!="headless":
		game.view.follow_player=false;game.view.zoom=1
		for site in w.objects.values():
			if site.kind!="construction_site" or site.region_id!="home":continue
			game.view.center=w.point(site);game.view.queue_redraw()
			await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join(site.id+".png"))
		game.view.center=w.homestead.area().get_center();game.view.queue_redraw()
		await process_frame;await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(output.path_join("flowerbed.png"))
		for site in w.leisure.sites.values():
			game.view.center=w.point(site);game.view.queue_redraw()
			await process_frame;await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join(site.id+".png"))
	game.queue_free();await process_frame
	print("HOST BUILD ALL native input, all sites, conservation, save/reload PASS")
	quit()

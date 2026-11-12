extends SceneTree
const World=preload("res://scripts/world_state.gd")
func _initialize()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"))
	var w:=World.new("res://content/home-v3/world.json");w.residents.provision(w);w.library=preload("res://scripts/character_library.gd").new();w.library.configure(OS.get_environment("HABITAT_DATA_DIR"));assert(preload("res://scripts/world_opening.gd").apply(w,w.library).ok);w.director.set_all_enabled(false)
	var routes:Array=[];var center:Array=w.map_anchor("plaza.center")
	for p in w.catalog.regions.home.layout.residential:
		if str(p.owner_id).is_empty():continue
		routes.append({"id":p.owner_id+"-plaza","start":w.point(w.objects[p.site_id])+Vector2(0,26-float(w.objects[p.site_id].position[1])),"end":Vector2(w.map_anchor("plaza.north")[0],w.map_anchor("plaza.north")[1])})
	for f in w.farms.farms.values():routes.append({"id":f.id,"start":Vector2(center[0],center[1]),"end":Vector2(f.entrance[0],f.entrance[1])})
	for id in ["dock.south.entry","dock.west.entry","logging.entry","moon.lookout"]:routes.append({"id":id,"start":Vector2(center[0],center[1]),"end":Vector2(w.map_anchor(id)[0],w.map_anchor(id)[1])})
	for row in routes:
		w.actors.human.position=[row.start.x,row.start.y]
		assert(w.command("human",{"intent":"move","x":row.end.x,"y":row.end.y}).ok)
		# Measurement-only inert accepted-work marker disables automatic empty-hand running.
		w.work.jobs.human={"intent":"distance_probe","phase":"distance_probe"};var seconds:=0.0
		while w._routes.has("human") and seconds<120:w.advance(.05);seconds+=.05
		w.work.jobs.erase("human");assert(w.point(w.actors.human).distance_to(row.end)<.001)
		row.seconds=snappedf(seconds,.05);row.speed_pixels=World.SPEED*32
	var f:=FileAccess.open(OS.get_environment("HABITAT_STAGE2_EVIDENCE").path_join("A-walking-times.json"),FileAccess.WRITE);f.store_string(JSON.stringify(routes,"  "));f.close();print("Walking v2 measured ",routes.size()," routes at unchanged 150px/s");quit()

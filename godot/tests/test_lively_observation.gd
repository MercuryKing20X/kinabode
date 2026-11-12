extends SceneTree
func _initialize()->void:call_deferred("run")
func sample(on:bool)->Dictionary:
	var w:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");w.residents.provision(w)
	w.library=preload("res://scripts/character_library.gd").new();w.library.configure(OS.get_environment("HABITAT_DATA_DIR"))
	preload("res://scripts/world_opening.gd").apply(w,w.library,"showcase")
	w.intelligence.activate_presets();w.director.set_all_enabled(true);w.lively.enabled=on
	var BBQ=preload("res://tests/barbecue_fixture.gd")
	assert(BBQ.approach(w))
	assert(BBQ.start(w,"single:mushroom",w.director.routines.keys()).ok)
	for tick in range(6000):
		w.advance(.1)
		if w.director.routines.keys().all(func(id):return id in w.life.fireside.state.current.get("eaters",[])):break
	assert(w.director.routines.keys().all(func(id):return id in w.life.fireside.state.current.get("eaters",[])))
	w.life.fireside.end_circle("host ends observation preparation meal")
	var near:=0
	for frame in range(1200):
		w.advance(.5)
		if w.actors["npc.mira"].region_id==w.actors.human.region_id and w.point(w.actors["npc.mira"]).distance_to(w.point(w.actors.human))<=8:near+=1
	return {"enabled":on,"seconds":600,"orange_within8_percent":float(near)/12,"actions":w.lively.counts.duplicate(true),"pairs":w.lively.pair_counts.duplicate(true),"cat_interactions":w.cat.interactions.duplicate(true)}
func run()->void:
	var report:Dictionary={"before":sample(false),"after":sample(true)}
	print("LIVELY_OBSERVATION ",JSON.stringify(report))
	var destination:=OS.get_environment("LIVELY_OBSERVATION_REPORT")
	if destination.is_empty():destination=OS.get_environment("HABITAT_DATA_DIR").path_join("lively-observation.json")
	var f:=FileAccess.open(destination,FileAccess.WRITE)
	if f!=null:f.store_string(JSON.stringify(report,"\t"));f.close()
	quit()

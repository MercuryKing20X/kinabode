# DIRECTION 2026-11-10: default idle life remains near player (2-6 tiles); free schedules are separately exercised. Physical receipts/interruption assertions unchanged.
extends "res://tests/test_local_life_15d.gd"
func run()->void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	DURATION=4500
	world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");world.residents.provision(world)
	world.library=preload("res://scripts/character_library.gd").new();world.library.configure(OS.get_environment("HABITAT_DATA_DIR"))
	check(preload("res://scripts/world_opening.gd").apply(world,world.library).ok,"new-map real showcase baseline")
	world.weather.weather_seed=1027;world.fishing.rng.seed=1027;world.fishing.life.rng.seed=1028
	var i:=0
	for id in world.director.routines:
		behavior[id]={};timelines[id]=[];world.director.routines[id].rng.seed=1027+i;i+=1;world.director.routines[id].set_enabled(true)
	check(world.memories.records.is_empty() and world.relationships.states.is_empty(),"showcase starts without invented history")
	var tree:Dictionary=world.objects.values().filter(func(o):return o.kind=="tree" and o.zone_id=="home.forest")[0]
	check(job("human",{"intent":"gather_wood","zone_id":tree.zone_id,"target_id":tree.id,"tree_count":1}),"scripted human cuts and hauls one actual tree")
	var plot:Dictionary=world.farms.farm_plots("farm.home").filter(func(p):return world.farms.stage(p)=="mature")[0]
	check(job("human",{"intent":"harvest","target_id":plot.id}),"real mature opening crop harvested")
	if plot.crop_id.is_empty():check(job("human",{"intent":"plant","target_id":plot.id,"crop_id":"turnip"}) and job("human",{"intent":"water","target_id":plot.id}),"human plants with a real shared seed")
	daily_fishing();daily_meal()
	# This opening already has a flowerbed. Refuse replay rather than claim another completion.
	check(not command("human",{"intent":"homestead_start","site_id":world.homestead.config.site.id}).ok,"preset flowerbed cannot generate a fake new construction event")
	for id in world.director.routines:
		check(go_near(id),"player walks to real scheduled resident "+id)
		var end:float=minf(DURATION,elapsed+110)
		while elapsed<end:frame()
	while elapsed<DURATION:frame()
	var data:=report();data["map_template"]="home-v3";data["opening"]="showcase";data["total_physical_public_wood"]=data.physical_wood_from_three_trees;data.erase("physical_wood_from_three_trees")
	check(elapsed==4500 and world.days.day()==4,"9000 real half-second frames advance three whole days")
	check(interruptions.is_empty(),"zero interruptions of accepted real tasks")
	check(data.max_same_line_in_any_hour<=2 and speech.all(func(e):return e.source=="local_rules"),"honest bounded local speech")
	check(data.residents.values().all(func(r):return r.within8_fraction>=.8 and r.default_follow_distance>=1.0),"all four default companions genuinely follow through World routes and remain near the player")
	check(data.total_physical_public_wood==27,"24 opening wood plus exactly one configured three-wood tree")
	check(data.fish_instances==1 and data.shared_meals.size()==2,"one actual fish, two actually eaten and cleaned meals")
	check(preload("res://scripts/save_store.gd").save_world(world,OS.get_environment("HABITAT_DATA_DIR")),"three-day actual world saves")
	var loaded=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");loaded.residents.provision(loaded);loaded.library=world.library
	var restored:Dictionary=preload("res://scripts/save_store.gd").load_world(loaded,OS.get_environment("HABITAT_DATA_DIR"))
	check(restored.ok and restored.loaded and loaded.work.jobs.is_empty() and loaded.work.claims.is_empty(),"new map reload keeps real state without tasks/claims")
	var output:=OS.get_environment("HABITAT_STAGE2_EVIDENCE")
	if not output.is_empty():
		var f:=FileAccess.open(output.path_join("simulation-3d.json"),FileAccess.WRITE);f.store_string(JSON.stringify(data,"  "))
	print("Home v3 three-day simulation: %s checks, failed=%s; utterances=%s interruptions=%s"%[checks,failed,speech.size(),interruptions.size()]);quit(1 if failed else 0)

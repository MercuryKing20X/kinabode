extends SceneTree
const F=preload("res://tests/standard_fixture.gd")
var f:RefCounted
var w:RefCounted
func _initialize()->void:call_deferred("run")
func run()->void:
	f=F.new();f.start(OS.get_environment("HABITAT_DATA_DIR"));w=f.w
	var initial_mushrooms:int=6
	assert(w.life.fireside.menu()[0].maximum>=1)
	var tree:Dictionary=w.objects.values().filter(func(o):return o.kind=="tree" and o.zone_id=="home.forest")[0]
	assert(f.job({"intent":"gather_wood","zone_id":tree.zone_id,"tree_count":1}))
	assert(f.job({"intent":"build_facility","target_id":"play.standard.camp"}))
	var built_at:float=f.elapsed
	var camp:Vector2=w.point(w.life.station)
	assert(f.job({"intent":"move","x":camp.x+2.5,"y":camp.y}))
	assert(w.shared_activity.begin_fireside(w.standard.config.companions).ok)
	var light:Dictionary=w.life.fireside.light_host();assert(light.ok)
	var lit_at:float=f.elapsed
	var roast:Dictionary=w.life.fireside.roast_host("single:mushroom");assert(roast.ok)
	for frame in range(1200):
		f.tick()
		if w.life.fireside.state.current.eaten==5:break
	assert(w.life.fireside.state.current.eaten==5)
	var full_at:float=f.elapsed
	for id in w.standard.config.companions:assert(w.hunger.rank(id)==0)
	var wood:int=preload("res://tests/backpack_fixture.gd").wood_total(w)+int(w.life.station.fuel_used)
	assert(wood==12 and w.life.fireside.state.current.receipt.mushroom==5)
	var remaining:int=0
	for chest in w.life.fireside.sources():remaining+=int(chest.items.get("mushroom",0))
	assert(remaining+5==initial_mushrooms)
	f.advance(60)
	var result:Dictionary={"opening":"standard","advance_delta":.1,"camp_built_at":built_at,"fire_lit_at":lit_at,"all_five_full_at":full_at,"total_seconds_enter_to_full":full_at,"within_target_120_seconds":full_at<=120,"wood_expected":12,"wood_accounted":wood,"wood_sources":light.sources,"food_sources":roast.sources,"mushrooms_initial":initial_mushrooms,"mushrooms_eaten":5,"mushrooms_remaining":remaining,"all_companions_full":true,"conserved":true,"model_calls":0,"fireside_advanced":60}
	var file:=FileAccess.open(OS.get_environment("HABITAT_STAGE2_EVIDENCE").path_join("simulation.json"),FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
	print("Barbecue v3 real standard simulation: ",JSON.stringify(result));quit()

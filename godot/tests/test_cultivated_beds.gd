extends SceneTree
func _initialize()->void:
	var w=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	w.residents.provision(w);w.library=preload("res://scripts/character_library.gd").new();w.library.configure(OS.get_environment("HABITAT_DATA_DIR"));w.director.set_all_enabled(false)
	assert(preload("res://scripts/world_opening.gd").apply(w,w.library,"showcase").ok)
	assert(w.farms.farms.has("farm.bed.homestead") and w.farms.ready("farm.bed.homestead"))
	assert(w.farms.farm_plots("farm.bed.homestead").size()==2)
	assert(w.farms.farm_plots("farm.bed.homestead").all(func(p):return p.crop_id.is_empty() and w.can_approach("human",p)))
	assert(w.farms.fences(w.farms.farms["farm.bed.homestead"]).is_empty())
	var before:Dictionary=w.storage.saved().duplicate(true)
	var added:Dictionary={}
	for at in [Vector2(78,45),Vector2(35,42),Vector2(95,187)]:
		added=w.leisure.place("outdoor-flowers",at)
		if added.ok:break
	assert(added.ok)
	var id:String="farm.bed."+str(added.site_id)
	w.farms.sync_beds();assert(w.farms.farms.has(id) and not w.farms.ready(id))
	assert(w.storage.saved()==before,"derived empty beds grant no seed or food")
	# Explicit completed-site contract fixture; native construction is tested separately.
	var site:Dictionary=w.leisure.sites[added.site_id]
	assert(w.storage.take({"wood":w.leisure.cost(site)}).ok)
	site.artwork=w.library.artworks[site.template_id].duplicate(true);site.invested=w.leisure.cost(site);site.complete=true
	assert(w.farms.ready(id) and w.farms.farm_plots(id)[0].crop_id.is_empty())
	var data:Dictionary=w.farms.saved().duplicate(true)
	assert(w.farms.validated_saved(data,w.actors,w.leisure.sites))
	var forged:Dictionary=data.duplicate(true);forged.farms[id].rect[0]+=1
	assert(not w.farms.validated_saved(forged,w.actors,w.leisure.sites),"saved farm geometry cannot override validated site")
	forged=data.duplicate(true);forged.plots[id+".plot.01"].position[0]+=1
	assert(not w.farms.validated_saved(forged,w.actors,w.leisure.sites),"saved plot cannot escape site")
	for absent in data.farms.keys():
		if str(absent).begins_with("farm.bed."):data.farms.erase(absent)
	for absent in data.plots.keys():
		if str(absent).begins_with("farm.bed."):data.plots.erase(absent)
	assert(w.farms.validated_saved(data,w.actors,w.leisure.sites),"old saves derive empty beds only")
	assert(preload("res://scripts/save_store.gd").save_world(w,OS.get_environment("HABITAT_DATA_DIR").path_join("roundtrip")))
	var other=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");other.residents.provision(other);other.library=w.library
	assert(preload("res://scripts/save_store.gd").load_world(other,OS.get_environment("HABITAT_DATA_DIR").path_join("roundtrip")).ok)
	assert(other.farms.farms.has(id) and other.farms.plots[id+".plot.01"].crop_id.is_empty() and other.storage.saved()==w.storage.saved())
	var legacy_path:String=OS.get_environment("HABITAT_DATA_DIR").path_join("roundtrip/island-v2.json")
	var legacy:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(legacy_path));legacy.farming=data
	var f:=FileAccess.open(legacy_path,FileAccess.WRITE);f.store_string(JSON.stringify(legacy));f.close()
	var old_loaded=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");old_loaded.residents.provision(old_loaded);old_loaded.library=w.library
	assert(preload("res://scripts/save_store.gd").load_world(old_loaded,OS.get_environment("HABITAT_DATA_DIR").path_join("roundtrip")).ok)
	assert(old_loaded.farms.plots[id+".plot.01"].crop_id.is_empty() and old_loaded.storage.saved()==w.storage.saved())
	var core=preload("res://scripts/world_state.gd").new()
	assert(core.farms.farms.size()==4 and core.farms.plots.size()==48)
	for opening in ["standard","showcase"]:
		var initial=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");initial.residents.provision(initial);initial.library=w.library
		assert(preload("res://scripts/world_opening.gd").apply(initial,w.library,opening).ok)
		var folder:String=OS.get_environment("HABITAT_DATA_DIR").path_join(opening)
		var stock:Dictionary=initial.storage.saved().duplicate(true)
		assert(preload("res://scripts/save_store.gd").save_world(initial,folder))
		var restored=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");restored.residents.provision(restored);restored.library=w.library
		assert(preload("res://scripts/save_store.gd").load_world(restored,folder).ok)
		assert(restored.storage.saved()==stock and restored.farms.farm_plots("farm.bed.homestead").all(func(p):return p.crop_id.is_empty()))
	print("CULTIVATED BEDS strict derivation/no grants/edge routes/save roundtrip/core isolation PASS")
	quit()

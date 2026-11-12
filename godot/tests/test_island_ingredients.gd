extends SceneTree
func _initialize()->void:
	var w=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	assert(w.error.is_empty(),w.error)
	assert(w.ingredients.config.items.size()>=14)
	assert(w.ingredients.valid(w.ingredients.saved()))
	assert(not w.ingredients.valid({"ready_at":{"bogus":10}}))
	assert(not w.ingredients.valid({"discovered":["honey","honey"]}))
	assert(w.farms.crops.has("potato") and w.farms.crops.has("corn"))
	assert(w.farms.farms.has("farm.theirs"))
	assert(not w.farms.ready("farm.theirs"))
	var saved:Dictionary=w.farms.saved().duplicate(true)
	assert(w.farms.valid_saved(saved,w.actors))
	saved.farms.erase("farm.theirs")
	for id in saved.plots.keys():
		if saved.plots[id].farm_id=="farm.theirs":saved.plots.erase(id)
	assert(w.farms.valid_saved(saved,w.actors))
	for item in w.ingredients.config.items:
		if item.get("metadata_only",false):continue
		assert(w.walkable(item.region,Vector2(item.position[0],item.position[1])),item.id)
	assert(not w.ingredients.valid({"drying":{"fish_id":"","ready_at":1,"collect":false}}))
	w.ingredients.drying={"fish_id":"fish-retained-proof","ready_at":600,"collect":true}
	var pending_save:Dictionary=w.ingredients.saved()
	assert(not pending_save.drying.collect)
	w.ingredients.restore({"drying":{"fish_id":"fish-retained-proof","ready_at":600,"collect":true}})
	assert(not w.ingredients.drying.collect and w.ingredients.drying.fish_id=="fish-retained-proof")
	print("INGREDIENT CONTRACT PASS; no input acceptance claimed")
	quit()

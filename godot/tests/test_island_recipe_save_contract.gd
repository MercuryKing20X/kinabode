extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
const BBQ=preload("res://tests/barbecue_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
var failed:=false
var count:=0
func check(okay:bool,label:String)->void:
	count+=1
	if not okay:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var prototype:RefCounted=F.fresh()
	for recipe_id in prototype.recipes.metadata:
		if not prototype.recipes.recipe_catalog.has(recipe_id):continue
		var w:RefCounted=F.fresh();var recipe:Dictionary=w.recipes.recipe_catalog[recipe_id]
		# Isolated stock and unique-fish validation fixture, not gathering evidence.
		w.storage.add({"wood":20})
		for ingredient in recipe.ingredients:w.storage.add({ingredient:20})
		if recipe.fish:
			var species:String=str(w.recipes.metadata[recipe_id].get("fish_species",""))
			if species.is_empty():species="eel"
			w.fishing.add_fish({"id":"fish-000000000000000000000000","owner_id":"human","location":"pending","source_id":"home.sea.east","species_id":species,"size_id":"large","color_id":"cream","scale":2})
		check(BBQ.start(w,"recipe:"+recipe_id).ok and BBQ.ready(w),"original cook transaction "+recipe_id)
		var life:Dictionary=w.life.state()
		check(Save._valid_life(w,life,w.actors),"new recipe state strict save validation "+recipe_id)
		var copy:Dictionary=JSON.parse_string(JSON.stringify(life))
		check(Save._valid_life(w,copy,w.actors),"new recipe JSON roundtrip "+recipe_id)
		var required_species:String=str(w.recipes.metadata[recipe_id].get("fish_species",""))
		if not required_species.is_empty():
			var wrong_species:Dictionary=JSON.parse_string(JSON.stringify(life))
			wrong_species.station.fireside.current.fish.species_id="eel" if required_species!="eel" else "cutlass"
			check(w.life.fireside.valid_fish(wrong_species.station.fireside.current.fish),"tampered species is another KNOWN otherwise-valid fish "+recipe_id)
			check(not Save._valid_life(w,wrong_species,w.actors),"recipe-specific fish save mismatch rejected "+recipe_id)
		if not copy.station.fireside.current.receipt.is_empty():
			copy.station.fireside.current.receipt[recipe.ingredients.keys()[0]]+=1
			check(not Save._valid_life(w,copy,w.actors),"extra receipt still rejected "+recipe_id)
	var dried:RefCounted=F.fresh();dried.storage.add({"wood":20,"dried_fish":2})
	check(BBQ.start(dried,"single:dried_fish").ok and BBQ.ready(dried),"actual dried fish single transaction")
	check(dried.life.fireside.state.current.food_id=="dried_fish" and dried.life.fireside.state.current.receipt=={"dried_fish":2} and dried.life.fireside.state.current.fish.is_empty(),"dried fish exact source identity retained")
	var dried_copy:Dictionary=JSON.parse_string(JSON.stringify(dried.life.state()))
	check(Save._valid_life(dried,dried_copy,dried.actors),"dried fish strict JSON save roundtrip")
	check(BBQ.finish(dried),"dried fish real diners finish and shared meal commits")
	var meals:Dictionary=dried.read_memories("human",{"kind":"shared_barbecue"})
	check(meals.total==1 and meals.memories[0].facts.foods.human[0].food_id=="dried_fish" and meals.memories[0].facts.foods.human[0].category=="fish","dried single history retains source identity despite fish category")
	if meals.total==1:
		check(dried.memories.fireside_facts_valid(meals.memories[0].facts,meals.memories[0].participants,dried.actors),"real dried-fish shared facts validate without unique pending fish")
		var json_memories:Dictionary=JSON.parse_string(JSON.stringify(dried.memories.saved()))
		check(dried.memories.valid_saved(json_memories,dried.actors,dried.world_id),"actual dried-fish meal memory strict save roundtrip")
	var earned:String=OS.get_environment("HABITAT_EARNED_SIGNATURE_SAVE")
	if not earned.is_empty():
		var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(earned.path_join("island-v2.json")))
		var world:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");world.residents.provision(world)
		var loaded:Dictionary=Save.load_world(world,earned)
		check(loaded.ok,"actual earned signature snapshot full reload "+str(loaded))
		var actual_stock:Dictionary=world.storage.saved().items
		check(actual_stock.size()==source.storage.items.size() and source.storage.items.keys().all(func(item):return actual_stock.has(item) and int(actual_stock[item])==int(source.storage.items[item])),"earned warehouse unchanged, JSON int/float equivalent")
		check(world.read_memories("human",{"kind":"signature_taste"}).total==2,"earned white/orange signatures survive actual full reload")
	print("RECIPE_SAVE_CONTRACT ",count," checks failed=",failed);quit(1 if failed else 0)

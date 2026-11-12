extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
const BBQ=preload("res://tests/barbecue_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
var failed:=false
func check(value:bool,what:String)->void:
	if not value:failed=true;push_error(what)
func _initialize()->void:call_deferred("run")
func run()->void:
	var w:RefCounted=F.fresh()
	check(w.error.is_empty(),"content valid")
	var text=preload("res://scripts/localization.gd")
	text.ensure()
	for recipe in w.recipes.recipe_catalog.values():
		for ingredient in recipe.ingredients:
			check(text.entries.has("content.ingredients."+ingredient),"cookbook ingredient translated "+ingredient)
			check(text.entries.has("content.cookbook.island_"+w.recipes.ingredient_island(ingredient)),"cookbook derived source translated "+ingredient)
	# Explicit isolated contract fixture, distinct from native-gather acceptance.
	w.storage.add({"wood":20,"herb":20,"kelp":20,"chestnut":20,"moonflower":20,"potato":20,"wild_berry":20})
	check(BBQ.light(w),"normal World route and original fire payment")
	for recipe_id in ["eel-herb","cutlass-chestnut","noodle-moon-soup","kite-berry-skewer"]:
		var wanted:String=w.recipes.metadata[recipe_id].fish_species
		var fish:Dictionary={"id":"fish-000000000000000000000000","owner_id":"human","location":"pending","source_id":"home.sea.east","species_id":"eel" if wanted!="eel" else "cutlass","size_id":"person","color_id":"cream","scale":1}
		w.fishing.fish={fish.id:fish}
		var before:Dictionary=w.storage.saved()
		var option:Array=w.life.fireside.menu().filter(func(d):return d.id=="recipe:"+recipe_id)
		check(option.size()==1 and option[0].maximum==0,"wrong species menu blocked "+recipe_id)
		check(not w.life.fireside.roast_host("recipe:"+recipe_id).ok and w.storage.saved()==before and w.fishing.fish.has(fish.id),"root roast rejects wrong fish atomically "+recipe_id)
	check(Save._valid_tastes(w,{"version":1,"known":true,"by_actor":{},"cooked":["eel-herb"]},w.actors),"optional exact cooked IDs accepted")
	for bad in [["unknown"],["eel-herb","eel-herb"],[42]]:
		check(not Save._valid_tastes(w,{"version":1,"known":true,"by_actor":{},"cooked":bad},w.actors),"strict cooked rejection "+str(bad))
	var fact:Dictionary={"actor_id":"codex","recipe_id":"honey-berry-apple"}
	check(w.memories.engine_facts_valid("signature_taste",fact,["codex"],w.actors),"resident-only signature fact accepted")
	check(w.memories.engine_facts_valid("signature_taste",fact,["human","codex"],w.actors),"exact human witness accepted")
	for invalid in [["codex","npc.mira"],["human"],["human","codex","npc.mira"],["codex","codex"]]:
		check(not w.memories.engine_facts_valid("signature_taste",fact,invalid,w.actors),"other participants rejected "+str(invalid))
	check(not w.memories.engine_facts_valid("signature_taste",{"actor_id":"codex","recipe_id":"turnip-soup"},["codex"],w.actors),"non-signature recipe rejected")
	w.intelligence.assign("codex","resident-black")
	check(w.memories.engine_facts_valid("signature_taste",fact,["codex"],w.actors),"canonical past facts independent of current intelligence")
	print("ISLAND_RECIPE_CONTRACT failed=",failed);quit(1 if failed else 0)

class_name BarbecueRecipes
extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
## Pure recipe content for both firesides; no separate cooking workflow.
const INGREDIENT_IDS := ["turnip","pumpkin","tomato","mushroom","blueberry","apple","potato","corn","wild_berry","chestnut","clam","crab","kelp","moonflower","glow_mushroom","black_truffle","honey","petals","herb","dried_fish","star_berry","night_nut"]
var _owner: WeakRef
var world: RefCounted:
	get:return _owner.get_ref()
var recipes: Dictionary={}
var recipe_catalog: Dictionary={}
var recipe_locks: Dictionary={}
var config: Dictionary={}
var metadata:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/island-recipes.json")).recipes
func _init(source: RefCounted) -> void:
	_owner=weakref(source)
	var value: Variant=world.locations.read("recipes")
	if not value is Dictionary or value.get("version")!=1 or not value.get("recipes") is Array or value.recipes.is_empty() or value.recipes.size()>40 or not value.get("station") is Dictionary:world.error=LocalText.text("system.barbecue_recipes.recipe_settings_are_invalid");return
	var station: Dictionary=value.station
	if not count(value.get("job_timeout"),900) or value.job_timeout<30 or not value.get("fish_portions") is Dictionary or value.fish_portions.size()!=4:world.error=LocalText.text("system.barbecue_recipes.cooking_time_limits_or_fish_portions_are_invalid");return
	for pair in [["person",1],["large",2],["huge",4],["giant",8]]:
		if value.fish_portions.get(pair[0])!=pair[1]:world.error=LocalText.text("system.barbecue_recipes.fish_portion_settings_are_invalid");return
	var locks: Variant=value.get("recipe_locks",{})
	if not locks is Dictionary:world.error=LocalText.text("system.barbecue_recipes.recipe_unlock_settings_are_invalid");return
	recipe_locks=locks
	for recipe in value.recipes:
		if not valid_recipe(recipe) or recipe_catalog.has(recipe.id):world.error=LocalText.text("system.barbecue_recipes.recipe_content_is_invalid");return
		recipe_catalog[recipe.id]=recipe.duplicate(true)
		if not recipe_locks.has(recipe.id):recipes[recipe.id]=recipe.duplicate(true)
	for id in recipe_locks:
		if not recipe_catalog.has(id) or not recipe_locks[id] is String or recipe_locks[id].is_empty() or recipe_locks[id].length()>128:world.error=LocalText.text("system.barbecue_recipes.recipe_unlock_settings_are_invalid");return
	config=value
func count(value: Variant,maximum: int) -> bool:return (value is int or value is float) and is_finite(value) and value==floor(value) and value>=0 and value<=maximum
func valid_recipe(value: Variant) -> bool:
	if not value is Dictionary or value.size()!=6 or not value.get("id") is String or value.id.is_empty() or value.id.length()>64 or not value.get("name") is String or value.name.is_empty() or value.name.length()>32 or not value.get("ingredients") is Dictionary or value.ingredients.is_empty() or value.ingredients.size()>(6 if value.get("id")=="harvest-stew" else 4) or not value.get("fish") is bool:return false
	if not count(value.get("portions"),8) or value.portions<1 or not world.catalog._number(value.get("seconds")) or value.seconds<1 or value.seconds>60:return false
	for key in value.ingredients:
		if key not in INGREDIENT_IDS or not count(value.ingredients[key],24) or value.ingredients[key]<1:return false
	return true
func sources(_id:String)->Array:
	return []

func display_name(id:String)->String:
	if not recipe_catalog.has(id):return ""
	if TranslationServer.get_locale().begins_with("en"):
		var english:String=str(metadata.get(id,{}).get("name_en",""))
		if not english.is_empty():return english
	return LocalText.content(str(recipe_catalog[id].name))

func ingredient_island(id:String)->String:
	for item in world.ingredients.config.items:
		if item.id==id:return str(item.island)
	return "main"

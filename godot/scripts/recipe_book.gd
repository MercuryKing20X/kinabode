extends AcceptDialog
const Text=preload("res://scripts/localization.gd")
func setup(world:RefCounted,font:Font)->void:
	title=Text.text("content.cookbook.title");theme=Theme.new();theme.default_font=font;theme.default_font_size=16
	var scroll:=ScrollContainer.new();scroll.custom_minimum_size=Vector2(690,440);add_child(scroll)
	var column:=VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(column)
	var discovered:Array=world.ingredients.discovered
	var stock:Dictionary=world.available_items("human")
	for recipe in world.recipes.recipe_catalog.values():
		var cooked:bool=recipe.id in world.barbecue_tastes.get("cooked",[])
		var known:bool=cooked or (recipe.fish and "fish" in discovered) or recipe.ingredients.keys().any(func(id):return id in discovered)
		var card:=VBoxContainer.new();card.add_theme_constant_override("separation",6);column.add_child(card)
		var name_label:=Label.new();card.add_child(name_label)
		name_label.text=Text.content(recipe.name)+" · "+Text.text("content.cookbook.cooked" if cooked else "content.cookbook.known") if known else Text.text("content.cookbook.unknown")
		if cooked:name_label.modulate=Color(1,.8,.4)
		if known and ResourceLoader.exists("res://assets/island-food/"+str(recipe.id)+".png"):
			var dish_icon:=TextureRect.new();dish_icon.texture=load("res://assets/island-food/"+str(recipe.id)+".png");dish_icon.custom_minimum_size=Vector2(48,48);dish_icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;dish_icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;card.add_child(dish_icon)
		var production:String=production_hint(world,recipe)
		if not production.is_empty():
			var production_label:=Label.new();production_label.text=production;production_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;card.add_child(production_label)
		if not known:
			var clue:=Label.new();clue.text=Text.text("content.cookbook.hint");card.add_child(clue)
			continue
		var ingredient_ids:Array=recipe.ingredients.keys()
		if recipe.fish:ingredient_ids.append("fish")
		for id in ingredient_ids:
			var ingredient_row:=HBoxContainer.new();card.add_child(ingredient_row)
			var icon_path:String="res://assets/island-food/"+str(id)+".png"
			if ResourceLoader.exists(icon_path):
				var icon:=TextureRect.new();icon.texture=load(icon_path);icon.custom_minimum_size=Vector2(28,28);icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;ingredient_row.add_child(icon)
			var label:=Label.new();ingredient_row.add_child(label);label.text=Text.text("content.ingredients."+id) if Text.entries.has("content.ingredients."+id) else id
			var origin:String=world.recipes.ingredient_island(id)
			label.text+=" · "+Text.text("content.cookbook.island_"+origin)
			var island_icon:=TextureRect.new();island_icon.texture=load("res://assets/island-food/island-"+origin+".png");island_icon.custom_minimum_size=Vector2(26,20);island_icon.tooltip_text=Text.text("content.cookbook.island_"+origin);ingredient_row.add_child(island_icon)
			var available:bool=int(stock.get(id,0))>=int(recipe.ingredients.get(id,1))
			if id=="fish":
				var required:String=str(world.recipes.metadata.get(recipe.id,{}).get("fish_species",""))
				var held:Dictionary=world.fishing.held("human")
				available=not held.is_empty() and (required.is_empty() or held.get("species_id")==required)
				for species in world.fishing.rules.species:
					if species.id==required:label.text=Text.content(species.name)+" · "+Text.text("content.cookbook.island_"+origin);break
			label.modulate=Color.WHITE if available else Color(.6,.6,.6)
		var meta:Dictionary=world.recipes.metadata.get(recipe.id,{})
		if not meta.get("favorite_traits",[]).is_empty():
			for id in world.actors:
				if id!="human" and world.intelligence.tag(id) in meta.favorite_traits:
					var row:=HBoxContainer.new();card.add_child(row)
					var portrait:=TextureRect.new();portrait.texture=world.library.texture(world.actors[id].appearance_id,"down_0");portrait.custom_minimum_size=Vector2(36,48);portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;row.add_child(portrait)
					var favorite:=Label.new();favorite.text=("♥ " if world.intelligence.tag(id)==meta.get("signature_trait","") else "")+Text.resident(world,id);row.add_child(favorite)
		var method:=Label.new();method.text=Text.text("content.cookbook.method");card.add_child(method)
	get_ok_button().pressed.connect(queue_free);close_requested.connect(queue_free)
	popup_centered(Vector2i(740,530))

func production_hint(world:RefCounted,recipe:Dictionary)->String:
	var names:Array=[]
	for id in recipe.ingredients:
		var template:String="produce-fishrack" if id=="dried_fish" else ""
		var owner:String="companion-2" if id=="dried_fish" else ""
		for item in world.ingredients.config.items:
			if item.id==id and item.has("facility"):template=str(item.facility);owner=str(item.owner);break
		if template.is_empty() or world.ingredients.facility(template,owner).is_empty():continue
		var name:String=Text.text("ingredients.facility."+template)
		if name not in names:names.append(name)
	return "" if names.is_empty() else Text.text("content.cookbook.built_source")%" / ".join(names)

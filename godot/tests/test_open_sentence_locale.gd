extends SceneTree

const Text=preload("res://scripts/localization.gd")
var checks:=0
var failures:=0
var wrong:=RegEx.new()

func verify(sentence:String,label:String)->void:
	checks+=1
	if sentence.is_empty() or wrong.search(sentence)!=null or "%s" in sentence or "{" in sentence:
		failures+=1;push_error(label+": "+sentence)

func _initialize()->void:
	Text.ensure()
	var w=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	w.residents.provision(w)
	var library=preload("res://scripts/character_library.gd").new()
	library.configure(OS.get_environment("HABITAT_DATA_DIR"))
	var needs=preload("res://scripts/resident_needs.gd").new()
	for lang in ["zh","en"]:
		TranslationServer.set_locale(lang)
		wrong.compile("[A-Za-z]+" if lang=="zh" else "[\\x{3400}-\\x{9FFF}]")
		for food in w.recipes.recipe_catalog:
			var name:String=w.recipes.display_name(food)
			verify(name,lang+":recipe:"+food)
			for tag in needs.content.favorite:
				for template in needs.content.favorite[tag][lang]:
					verify(str(template)%name,lang+":favorite:"+food+":"+tag)
		for id in w.actors:
			for tag in ["gentle","lively","laborious","quiet"]:
				for need in ["meal","wood","camp","field","harvest","help"]:
					verify(Text.text("open.coordination."+tag+".suggest")%[Text.resident(w,id),Text.text("open.need."+need)],lang+":coordination:"+need)
		for fish in w.fishing.rules.species:
			verify(Text.text("intent.caught")%Text.content(fish.name),lang+":fish:"+fish.id)
		var placement:RefCounted=w.flower_creation.creations
		for item in placement.catalog():
			verify(placement.catalog()[item][lang],lang+":piece:"+item)
		for tag in placement.RemovalLines:
			for line in placement.RemovalLines[tag]:
				verify(line[0 if lang=="zh" else 1],lang+":removal:"+tag)
		verify(placement.rejection(placement.phrase("仓库","Warehouse"),placement.phrase("桥东端","East bridge end")).message,lang+":piece_blocked")
		for ingredient in w.ingredients.config.items:
			verify(str(ingredient.get("name_en",Text.content(ingredient.name))) if lang=="en" else str(ingredient.name),lang+":ingredient:"+ingredient.id)
		for region in w.catalog.regions.values():
			var place:String=Text.content(region.name)
			verify(place,lang+":place:"+region.id)
		for id in library.artworks:
			if not preload("res://scripts/workshop_catalog.gd").NAMES.has(id):continue
			var art:Dictionary=library.artworks[id]
			if art.get("kind","character")!="character":continue
			var label:String=library.display_name(id)
			# Third-party product names are proper nouns in both locales.
			if lang=="zh" and id.begins_with("ai-"):continue
			verify(label,lang+":appearance:"+id)
	print("OPEN_SENTENCES ",checks," failed=",failures)
	quit(1 if failures else 0)

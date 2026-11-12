extends "res://tests/test_ingredient_south_input.gd"
func build_original_field(farm_id:String)->bool:
	var id:String=game.world.standard.site_for(farm_id)
	if id.is_empty():return false
	await click_world(game.world.point(game.world.leisure.sites[id]));await process_frame
	if not game.leisure_panel.visible or game.leisure_panel.site_id!=id:print("SEED_FIELD_PANEL ",farm_id," actual=",game.leisure_panel.site_id," hit=",game.view.hit(game.view.screen(game.world.point(game.world.leisure.sites[id]))));return false
	var build:Button=named_button(game.leisure_panel,Text.text("panels.choose_builder_build"))
	if build==null or not await UI.click(self,build):print("SEED_FIELD_BUILDER ",farm_id);return false
	for who in game.participant_picker.toggles:
		var box:CheckBox=game.participant_picker.toggles[who]
		if box.button_pressed!=(who=="human") and not await UI.click(self,box):return false
	if not await UI.click(self,game.participant_picker.get_ok_button()):return false
	for i in range(3200):
		game.world.advance(.5)
		if game.world.standard.ready(farm_id):break
	game.leisure_panel.hide()
	var ready:bool=game.world.standard.ready(farm_id)
	if not ready:print("SEED_FIELD_COMPLETION ",farm_id," job=",game.world.work.jobs.get("human")," invested=",game.world.leisure.sites[id].invested," events=",game.world.work.events.slice(-2)," status=",game.status.text)
	return ready
func run()->void:
	OS.set_environment("HABITAT_OPENING","standard");root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	var w=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");w.residents.provision(w)
	w.library=preload("res://scripts/character_library.gd").new();w.library.configure(OS.get_environment("HABITAT_DATA_DIR"))
	var initial:Dictionary=preload("res://scripts/world_opening.gd").apply(w,w.library,"standard")
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=w;root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.view.sound_enabled=false;game.island_hud.set_process(false);w.director.set_all_enabled(false);game.chat.hide()
	await process_frame;await process_frame
	for pair in [["codex","ai-gpt"],["companion-2","ai-deepseek"],["npc.mira","ai-claude"],["npc.nora","ai-glm"]]:w.actors[pair[0]].appearance_id=pair[1]
	var okay:bool=initial.ok and w.storage.count("seed.turnip")==4 and w.storage.count("seed.tomato")==4
	var gate_checks:bool=true
	for item in w.ingredients.sources():
		if item.id in ["seed.apple","seed.blueberry","seed.daisy"]:gate_checks=gate_checks and not w.ingredients.available(item) and w.storage.count(item.id)==0
	okay=okay and gate_checks
	print("STANDARD_SEED_GATES ",okay)
	okay=okay and await gather_wood(7,25)
	var hill:bool=okay and await build_original_field("farm.hill")
	var lake:bool=hill and await build_original_field("farm.lake")
	print("STANDARD_REAL_FIELD_BUILD ",hill," ",lake)
	okay=okay and hill and lake
	for id in ["seed.apple","seed.blueberry","seed.pumpkin","seed.daisy"]:
		var picked:bool=await collect(id) if okay else false
		print("STANDARD_REAL_SEED ",id," ",picked)
		okay=okay and picked and w.storage.count(id)==1
	# The source transfers seed only; no fruit, vegetables or recipe discovery is granted.
	for id in ["apple","blueberry","pumpkin","daisy"]:okay=okay and w.storage.count(id)==0 and id not in w.ingredients.discovered
	var first:Dictionary={}
	for item in w.ingredients.sources():
		if item.id=="seed.daisy":first=item
	okay=okay and not w.ingredients.available(first)
	w.advance(601)
	var ui:Node=game.get_node("IngredientUI");ui._process(0)
	okay=okay and ui.selection=="seed.daisy" and await UI.click(self,ui.button)
	for i in range(5):w.advance(.2)
	okay=okay and w.storage.count("seed.daisy")==2
	print("STANDARD_REAL_SEED_REGEN ",okay)
	var f:=FileAccess.open(OS.get_environment("HABITAT_DATA_DIR").path_join("standard-seed-results.json"),FileAccess.WRITE);f.store_string(JSON.stringify({"gates":gate_checks,"hill":hill,"lake":lake,"seed_only_and_regeneration":okay},"  "));f.close()
	game.queue_free();await process_frame;quit(0 if okay else 1)

extends "res://tests/test_ingredient_south_input.gd"
func harvest_bed(id:String,amount:int)->bool:
	var plots:Array=game.world.farms.farm_plots(id)
	if plots.size()!=amount:return false
	await click_world(game.world.point(plots[0]));await process_frame
	if not game.farm_panel.visible or game.farm_panel.farm_id!=id:print("BED INPUT no field ",id);return false
	if not await select_option(game.farm_panel.fill_picker,"potato"):return false
	await capture(id+"-empty",game.world.point(plots[0]))
	if not await UI.click(self,game.farm_panel.fill_button):return false
	await settle()
	if not plots.all(func(p):return p.crop_id=="potato" and p.watered):print("BED INPUT planting ",id," ",game.world.farms.orders.get("human"));return false
	await capture(id+"-planted",game.world.point(plots[0]))
	game.world.advance(3601)
	await capture(id+"-mature",game.world.point(plots[0]))
	var before:int=game.world.storage.count("potato")
	if not await UI.click(self,game.farm_panel.harvest_button):return false
	await settle()
	return game.world.storage.count("potato")==before+amount*3
func run()->void:
	game=UI.init_game(self);await process_frame;await process_frame
	for pair in [["codex","ai-gpt"],["companion-2","ai-deepseek"],["npc.mira","ai-claude"],["npc.nora","ai-glm"]]:game.world.actors[pair[0]].appearance_id=pair[1]
	await click_world(game.world.point(game.world.actors.human))
	var seed:bool=await collect("potato")
	game.world.advance(601)
	var ui:Node=game.get_node("IngredientUI");ui._process(0)
	seed=seed and ui.selection=="potato" and await UI.click(self,ui.button)
	for i in range(5):game.world.advance(.2)
	var m4:bool=seed and await harvest_bed("farm.bed.homestead",2)
	print("NATIVE_M4_TRUE_BED ",m4)
	var location:=Vector2.INF
	for candidate in [Vector2(35,42),Vector2(75,46),Vector2(95,187)]:
		if game.world.leisure.validate_place("outdoor-flowers",candidate.snapped(Vector2.ONE)+Vector2(.5,.5)).ok:location=candidate;break
	var built:bool=location.is_finite() and await build_production("outdoor-flowers",location)
	game.world.advance(.2)
	var id:=""
	for site in game.world.leisure.sites.values():
		if site.template_id=="outdoor-flowers" and site.complete:id="farm.bed."+str(site.id)
	var outside:bool=built and not id.is_empty() and await collect("potato") and await harvest_bed(id,1)
	print("NATIVE_OUTDOOR_TRUE_BED ",outside)
	var f:=FileAccess.open(OS.get_environment("HABITAT_DATA_DIR").path_join("raised-bed-results.json"),FileAccess.WRITE);f.store_string(JSON.stringify({"m4":m4,"outdoor_built":built,"outdoor_sow_harvest":outside},"  "));f.close()
	game.queue_free();await process_frame;quit(0 if m4 and outside else 1)

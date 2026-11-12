extends "res://tests/test_ingredient_native_input.gd"
const Text=preload("res://scripts/localization.gd")
func select_option(picker:OptionButton,id:String)->bool:
	await UI.click(self,picker)
	if not picker.get_popup().visible:await key(KEY_SPACE)
	for i in range(picker.item_count+2):
		var focus:int=picker.get_popup().get_focused_item()
		if focus>=0 and str(picker.get_item_metadata(focus))==id:
			await key(KEY_ENTER);return str(picker.get_item_metadata(picker.selected))==id
		await key(KEY_DOWN)
	await key(KEY_ESCAPE);return false
func named_button(node:Node,label:String)->Button:
	for child in UI.descendants(node):
		if child is Button and child.text==label:return child
	return null
func build_production(template:String,at:Vector2)->bool:
	# All foundation placement, builder selection and construction are native input.
	var site:Dictionary=game.world.leisure.sites["play.swing"]
	await click_world(game.world.point(site));await process_frame
	if not game.leisure_panel.visible:print("BUILD FAIL initial panel");return false
	if not await select_option(game.leisure_panel.templates,template):print("BUILD FAIL template");return false
	var place:Button=named_button(game.leisure_panel,Text.text("panels.place_a_new_facility_foundation"))
	if place==null or not await UI.click(self,place):print("BUILD FAIL place button");return false
	await click_world(at);await process_frame
	if not game.leisure_panel.visible:print("BUILD FAIL new panel ",game.status.text);return false
	var id:String=game.leisure_panel.site_id
	if game.world.leisure.sites[id].template_id!=template:return false
	var build:Button=named_button(game.leisure_panel,Text.text("panels.choose_builder_build"))
	if build==null or not await UI.click(self,build):print("BUILD FAIL builder");return false
	for who in game.participant_picker.toggles:
		var box:CheckBox=game.participant_picker.toggles[who]
		if box.button_pressed!=(who=="human"):
			if not await UI.click(self,box):return false
	if not await UI.click(self,game.participant_picker.get_ok_button()):return false
	for i in range(12000):
		game.world.advance(.2)
		if game.world.leisure.sites[id].complete:break
		if i%200==0:await process_frame
	game.leisure_panel.hide()
	if not game.world.leisure.sites[id].complete:print("BUILD FAIL completion ",game.status.text);return false
	return true
func south_crop()->bool:
	if not await collect("potato"):return false
	var ui:Node=game.get_node("IngredientUI")
	for i in range(5):
		game.world.advance(601);ui._process(0)
		if ui.selection!="potato" or not await UI.click(self,ui.button):return false
		for t in range(5):game.world.advance(.2)
	var plot:Dictionary=game.world.farms.farm_plots("farm.theirs")[0]
	await click_world(game.world.point(plot));await process_frame
	if not game.farm_panel.visible or game.farm_panel.farm_id!="farm.theirs":print("SOUTH FIELD FAIL open");return false
	if not await select_option(game.farm_panel.fill_picker,"potato"):return false
	await capture("south-empty-field",game.world.point(plot))
	if not await UI.click(self,game.farm_panel.fill_button):return false
	await settle()
	var plots:Array=game.world.farms.farm_plots("farm.theirs")
	if not plots.all(func(p):return p.crop_id=="potato" and p.watered):
		preload("res://scripts/save_store.gd").save_world(game.world,OS.get_environment("HABITAT_DATA_DIR").path_join("failed"))
		print("SOUTH PHYSICAL ",plots.map(func(p):return [p.id,game.world.walkable("home",game.world.point(p)),game.world.find_route("human",game.world.point(p)).size()])," human=",game.world.actors.human)
		print("SOUTH FIELD FAIL plant ",game.farm_panel.note.text," order=",game.world.farms.orders.get("human")," job=",game.world.work.jobs.get("human")," plots=",plots," seeds=",game.world.available_items("human"));return false
	await capture("south-potato-planted")
	game.world.advance(3601)
	await capture("south-potato-mature")
	var before:int=game.world.storage.count("potato")
	if not await UI.click(self,game.farm_panel.harvest_button):return false
	await settle()
	var close:Button=named_button(game.farm_panel,"×")
	if close==null or not await UI.click(self,close):return false
	if not await UI.click(self,game.island_hud.stock_button):return false
	if not game.storage_panel.deposit_button.disabled and not await UI.click(self,game.storage_panel.deposit_button):return false
	var gain:int=game.world.storage.count("potato")-before
	print("SOUTH_FIELD_GAIN ",gain)
	return gain==plots.size()*3
func gather_wood(tree_count:int=3,minimum:int=45)->bool:
	for count in range(tree_count):
		var trees:Array=game.world.objects.values().filter(func(o):return o.kind=="tree" and o.status=="mature")
		trees.sort_custom(func(a,b):return game.world.point(a).distance_squared_to(game.world.point(game.world.actors.human))<game.world.point(b).distance_squared_to(game.world.point(game.world.actors.human)))
		var clicked:=false
		for tree in trees:
			game.view.center=game.world.point(tree);game.view.follow_player=false;await process_frame
			for lift in [40,80,120,160,200]:
				var at:Vector2=game.view.screen(game.world.point(tree))-Vector2(0,lift)
				if game.view.hit(at)!=tree.id:continue
				for down in [true,false]:
					var e:=InputEventMouseButton.new();e.position=at;e.global_position=at;e.pressed=down;e.button_index=MOUSE_BUTTON_LEFT;root.push_input(e,true);await process_frame
				clicked=true;break
			if clicked:break
		if not clicked:return false
		await settle()
	return game.world.storage.count("wood")+int(game.world.actors.human.carry.get("wood",0))>=minimum
func retired_production_flow()->void:
	game=UI.init_game(self);await process_frame;await process_frame
	for pair in [["codex","ai-gpt"],["companion-2","ai-deepseek"],["npc.mira","ai-claude"],["npc.nora","ai-glm"]]:game.world.actors[pair[0]].appearance_id=pair[1]
	await click_world(game.world.point(game.world.actors.human))
	var wood:bool=await gather_wood();print("NATIVE_WOOD ",wood)
	var honey_built:bool=await build_production("produce-flowerhouse",Vector2(33,226))
	print("NATIVE_FLOWERHOUSE ",honey_built)
	var honey:bool=honey_built and await collect("honey")
	print("NATIVE_HONEY ",honey)
	await capture("south-honey")
	var garden_built:bool=await build_production("produce-herbgarden",Vector2(105,226))
	print("NATIVE_GARDEN ",garden_built)
	var crop:bool=garden_built and await south_crop()
	print("NATIVE_SOUTH_CROP ",crop)
	var f:=FileAccess.open(OS.get_environment("HABITAT_DATA_DIR").path_join("south-results.json"),FileAccess.WRITE);f.store_string(JSON.stringify({"flowerhouse":honey_built,"honey":honey,"garden":garden_built,"crop":crop},"  "));f.close()
	game.queue_free();await process_frame;quit(0 if honey and garden_built and crop else 1)

func run()->void:
	# DIRECTION 2026-11-06 retires the entire southern production flow.
	game=UI.init_game(self);await process_frame;await process_frame
	var w:RefCounted=game.world
	var before:Dictionary=w.storage.saved().duplicate(true)
	var memories:Array=w.memories.records.duplicate(true)
	var blocked:bool=not w.farms.ready("farm.theirs")
	for template in ["produce-flowerhouse","produce-herbgarden","produce-fishrack"]:
		var result:Dictionary=w.leisure.place(template,Vector2(57,226))
		blocked=blocked and not result.ok and result.get("error")=="vacation_only"
	blocked=blocked and w.storage.saved()==before and w.memories.records==memories and w.work.jobs.is_empty()
	game.queue_free();await process_frame
	print("VACATION_PRODUCTION_REJECTED ",blocked);quit(0 if blocked else 1)

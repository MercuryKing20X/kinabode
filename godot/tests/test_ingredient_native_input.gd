extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
var game:Node
var results:Array=[]
func _initialize()->void:call_deferred("run")
func click_world(at:Vector2)->void:
	game.chat.hide();game.farm_panel.hide();game.house_panel.hide();game.view.follow_player=false;game.view.center=at;game.view.zoom=1
	await process_frame
	var p:Vector2=game.view.screen(at)
	for down in [true,false]:
		var e:=InputEventMouseButton.new();e.position=p;e.global_position=p;e.pressed=down;e.button_index=MOUSE_BUTTON_LEFT;root.push_input(e,true);await process_frame
func walk(at:Vector2)->bool:
	await click_world(at)
	for i in range(6000):
		game.world.advance(.2)
		if not game.world._routes.has("human"):break
	var okay:bool=game.world.point(game.world.actors.human).distance_to(at)<1
	if not okay:print("WALK FAIL ",at," actual=",game.world.point(game.world.actors.human)," status=",game.status.text)
	return okay
func capture(id:String,focus_at:Vector2=Vector2.INF)->void:
	if DisplayServer.get_name()=="headless":return
	if game.farm_panel.visible:game.farm_panel.refresh()
	game.view.center=focus_at if focus_at.is_finite() else game.world.point(game.world.actors.human);game.view.queue_redraw()
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("HABITAT_DATA_DIR").path_join(id+".png"))
func collect(id:String)->bool:
	var item:Dictionary={}
	for i in game.world.ingredients.sources():
		if i.id==id:item=i
	if item.is_empty():return false
	var approach:=Vector2(98,56) if id=="wild_berry" else Vector2(item.position[0],item.position[1])
	if id.begins_with("seed."):
		for offset in [Vector2.ZERO,Vector2(0,1),Vector2(1,0),Vector2(-1,0),Vector2(0,-1),Vector2(0,2),Vector2(2,0),Vector2(-2,0),Vector2(0,-2)]:
			var candidate:Vector2=Vector2(item.position[0],item.position[1])+offset
			game.view.center=candidate;game.view.follow_player=false
			if game.view.hit(game.view.screen(candidate)).is_empty() and not game.world.find_route("human",candidate).is_empty():approach=candidate;break
	if not await walk(approach):return false
	var ui:Node=game.get_node("IngredientUI")
	for i in range(3000):
		if game.world.ingredients.available(item):break
		game.world.advance(1)
	ui._process(0)
	# At this exact point, nearest available collection selects this source.
	if ui.selection!=id:print("SELECT FAIL ",id," selected=",ui.selection," clock=",game.world.forest.clock);return false
	var old:int=game.world.storage.count(id)
	if not await UI.click(self,ui.button):return false
	for i in range(50):game.world.advance(.2)
	await capture(id)
	return game.world.storage.count(id)==old+int(item.amount)
func key(code:Key)->void:
	for down in [true,false]:
		var e:=InputEventKey.new();e.keycode=code;e.pressed=down;root.push_input(e,true);await process_frame
func settle()->void:
	for i in range(12000):
		game.world.advance(.2)
		if not game.world.work.jobs.has("human") and not game.world._routes.has("human") and not game.world.farms.active("human"):break
func farm_crop()->bool:
	# Each additional seed is picked from a genuinely regrown wild potato plant.
	if not await collect("potato"):return false
	var ui:Node=game.get_node("IngredientUI")
	for i in range(11):
		game.world.advance(601);ui._process(0)
		if ui.selection!="potato" or not await UI.click(self,ui.button):return false
		for t in range(5):game.world.advance(.2)
	var first:Dictionary=game.world.farms.farm_plots("farm.home")[0]
	game.world.advance(86401)
	await click_world(game.world.point(first))
	await settle()
	if not game.farm_panel.visible:return false
	if not await UI.click(self,game.farm_panel.harvest_button):return false
	await settle()
	await process_frame
	await UI.click(self,game.farm_panel.fill_picker)
	await key(KEY_SPACE)
	for i in range(5):await key(KEY_DOWN)
	await key(KEY_ENTER)
	if game.farm_panel.fill_picker.get_item_metadata(game.farm_panel.fill_picker.selected)!="potato":print("PICK FAIL ",game.farm_panel.fill_picker.selected," ",game.farm_panel.fill_picker.get_item_metadata(game.farm_panel.fill_picker.selected));return false
	if not await UI.click(self,game.farm_panel.fill_button):return false
	await settle()
	var plots:Array=game.world.farms.farm_plots("farm.home")
	var potatoes:Array=plots.filter(func(p):return p.crop_id=="potato" and p.watered)
	if potatoes.is_empty():print("PLOT FAIL no actual potato planting");return false
	await capture("potato-planted")
	game.world.advance(3601)
	await capture("potato-mature")
	var old:int=game.world.storage.count("potato")
	if not await UI.click(self,game.farm_panel.harvest_button):return false
	await settle()
	for i in range(20):game.world.advance(.2)
	if not await UI.click(self,game.island_hud.stock_button):return false
	if not game.storage_panel.deposit_button.disabled and not await UI.click(self,game.storage_panel.deposit_button):return false
	print("POTATO PLOTS ",potatoes.size()," carry=",game.world.actors.human.carry)
	print("HARVEST ",old," -> ",game.world.storage.count("potato")," note=",game.farm_panel.note.text)
	return game.world.storage.count("potato")==old+potatoes.size()*3
func dark_collection()->bool:
	if not await UI.click(self,game.dark_ui.entry_button):return false
	var depart:Button=null
	for control in UI.descendants(game.dark_ui.menu):
		if control is Button and control.text==preload("res://scripts/localization.gd").text("ui.dark.depart"):depart=control
	if depart==null or not await UI.click(self,depart):return false
	for i in range(8000):
		game.world.advance(.2)
		if i%20==0:await process_frame
		if game.world.actors.human.region_id=="dark":break
	if game.world.actors.human.region_id!="dark":print("DARK FAIL crossing ",game.status.text);return false
	if not await UI.click(self,game.dark_ui.fire_button):return false
	return await collect("glow_mushroom")
func run()->void:
	game=UI.init_game(self);await process_frame;await process_frame
	var appearances:Dictionary={"codex":"ai-gpt","companion-2":"ai-deepseek","npc.mira":"ai-claude","npc.nora":"ai-glm"}
	for id in appearances:game.world.actors[id].appearance_id=appearances[id]
	await click_world(game.world.point(game.world.actors.human))
	var collection_ids:Array=[] if OS.get_environment("HABITAT_TEST_CROP")=="1" else ["potato","corn","wild_berry","clam","moonflower"]
	for id in collection_ids:
		var okay:bool=await collect(id);results.append({"id":id,"ok":okay});print("NATIVE_COLLECT ",id," ",okay)
	if OS.get_environment("HABITAT_TEST_DARK")=="1":
		var okay:bool=await dark_collection();results.append({"id":"glow_mushroom","ok":okay});print("NATIVE_DARK ",okay)
	if OS.get_environment("HABITAT_TEST_CROP")=="1":
		var okay:bool=await farm_crop();results.append({"id":"potato_farm","ok":okay});print("NATIVE_FARM ",okay)
	var f:=FileAccess.open(OS.get_environment("HABITAT_DATA_DIR").path_join("input-results.json"),FileAccess.WRITE);f.store_string(JSON.stringify(results,"  "));f.close()
	game.queue_free();await process_frame;quit(0 if results.all(func(r):return r.ok) else 1)

extends "res://tests/test_ingredient_south_input.gd"
## Long standalone acceptance, deliberately outside default suite. Official showcase only.
var failed:=false
var trace:Array=[]
func check(okay:bool,label:String)->void:
	trace.append({"ok":okay,"label":label,"clock":game.world.forest.clock if game!=null else 0});print("JOURNEY ",okay," ",label)
	if not okay:failed=true
func tick(dt:float=.2)->void:
	game._process(dt);game.view._process(dt)
func record(stage:String)->void:
	var f:=FileAccess.open(OS.get_environment("HABITAT_DATA_DIR").path_join("journey.json"),FileAccess.WRITE);f.store_string(JSON.stringify(trace,"  "));f.close()
	preload("res://scripts/save_store.gd").save_world(game.world,OS.get_environment("HABITAT_DATA_DIR").path_join(stage))
func stop(stage:String)->void:
	record(stage);game.queue_free();await process_frame;quit(1)
func mouse(at:Vector2)->void:
	for down in [true,false]:
		var e:=InputEventMouseButton.new();e.position=at;e.global_position=at;e.pressed=down;e.button_index=MOUSE_BUTTON_LEFT;root.push_input(e,true);await process_frame
func meal(id:String,guests:Array,signature:String="")->bool:
	game.storage_panel.hide();game.farm_panel.hide();game.leisure_panel.hide();game.chat.hide()
	var w:RefCounted=game.world
	await click_world(w.point(w.life.station))
	for i in range(6000):
		tick()
		if UI.shown(game,"res://scripts/fireside_panel.gd")!=null:break
	var panel:Node=UI.shown(game,"res://scripts/fireside_panel.gd")
	if panel==null:print("MEAL panel missing ",game.status.text);return false
	if not w.life.fireside.burning() and not await UI.click(self,panel.light_button):return false
	if not w.life.fireside.burning():print("MEAL could not light ",game.status.text);return false
	if not await UI.click(self,panel.roast_button):return false
	var invite:Node=UI.shown(game,"res://scripts/fireside_invitation.gd")
	if invite==null:return false
	for who in guests:
		if not await UI.click(self,invite.checks[who]):return false
	if not await UI.click(self,invite.get_ok_button()):return false
	var menu:Node=UI.shown(game,"res://scripts/fireside_menu.gd")
	if menu==null:return false
	if id.begins_with("single:"):
		var expand:Button=UI.descendants(menu).filter(func(n):return n is Button and n.get_meta("expand_basics",false))[0]
		if not await UI.click(self,expand):return false
	var options:Array=UI.descendants(menu).filter(func(n):return n is Button and n.get_meta("menu_id","")==id)
	if options.is_empty():return false
	var choose:Button=options[0];menu.scroll.ensure_control_visible(choose);await process_frame;await process_frame
	if choose.disabled:print("MEAL disabled ",id," stock=",w.available_items("human"));return false
	if not await UI.click(self,choose) or not await UI.click(self,menu.start_button):return false
	await process_frame
	if UI.shown(game,"res://scripts/fireside_menu.gd")!=null:print("MEAL start rejected ",menu.note.text);return false
	var speech_seen:bool=signature.is_empty();var line:String=str(w.recipes.metadata.get(id.trim_prefix("recipe:"),{}).get("signature_line",""))
	for i in range(6000):
		tick()
		if not signature.is_empty() and str(game.view.speech_by_actor.get(signature,{}).get("text",""))==line and not speech_seen:
			speech_seen=true;await capture(id.trim_prefix("recipe:")+"-real-signature",w.point(w.life.station))
		if guests.all(func(who):return who in w.life.fireside.state.current.get("eaters",[])) and speech_seen:break
	var okay:bool=guests.all(func(who):return who in w.life.fireside.state.current.get("eaters",[])) and speech_seen
	if not signature.is_empty():
		var records:Dictionary=w.read_memories("human",{"kind":"signature_taste"})
		okay=okay and records.memories.any(func(entry):return entry.facts.recipe_id==id.trim_prefix("recipe:") and entry.facts.actor_id==signature)
	game.island_hud.refresh();await process_frame
	var ends:Array=UI.descendants(game.island_hud.task).filter(func(n):return n is Button and n.text=="×")
	if ends.size()!=1 or not await UI.click(self,ends[0]):print("MEAL failed end ",ends.size());return false
	return okay
func feed()->bool:
	var guests:Array=["codex","companion-2","npc.mira","npc.nora"]
	for item in ["mushroom","turnip","tomato","blueberry","pumpkin","apple"]:
		if int(game.world.available_items("human").get(item,0))>=5:return await meal("single:"+item,guests)
	print("FEED no5real food stock=",game.world.available_items("human"));return false
func orchard()->bool:
	var farm:Dictionary=game.world.farms.farms["farm.hill"]
	var plot:Dictionary=game.world.farms.farm_plots(farm.id)[0]
	await click_world(game.world.point(plot));await settle();await process_frame
	if not game.farm_panel.visible:return false
	if not await UI.click(self,game.farm_panel.harvest_button):return false
	await settle();await process_frame
	if not await UI.click(self,game.island_hud.stock_button):return false
	if not game.storage_panel.deposit_button.disabled and not await UI.click(self,game.storage_panel.deposit_button):return false
	game.storage_panel.hide();game.farm_panel.hide()
	return game.world.storage.count("apple")>0 and game.world.storage.count("blueberry")>0
func boat(home:bool)->bool:
	if home:
		var edge:Array=game.world.dark.config.walking_connection.dark_end
		await click_world(Vector2(edge[0],edge[1]))
		for i in range(8000):
			tick()
			if i%20==0:await process_frame
			if game.world.actors.human.region_id=="home":return true
		return false
	game.dark_ui._process(0)
	if not await UI.click(self,game.dark_ui.entry_button):return false
	var button:Button=named_button(game.dark_ui.menu,Text.text("ui.dark.return_home" if home else "ui.dark.depart"))
	if button==null or not await UI.click(self,button):return false
	for i in range(8000):
		tick()
		if i%20==0:await process_frame
		if game.world.actors.human.region_id==("home" if home else "dark"):return true
	return false
func catch_native()->bool:
	var at:Array=game.world.map_anchor("dock.south.end")
	if not await walk(Vector2(at[0],at[1])):return false
	if not await UI.click(self,game.actions_button):return false
	var fish_buttons:Array=UI.descendants(game.action_dock.menu).filter(func(n):return n is Button and n.text=="钓鱼")
	if fish_buttons.is_empty():print("FISH no native action ",game.island_hud.context_signature);return false
	if not await UI.click(self,fish_buttons[0]):return false
	if not await UI.click(self,game.action_dock.popup.get_ok_button()):return false
	for i in range(3000):
		tick()
		if not game.world.fishing.held("human").is_empty():return true
	return false
func book(state:String)->bool:
	if not await UI.click(self,game.handbook_menu):return false
	var popup:PopupMenu=game.handbook_menu.get_popup();var index:int=-1
	for i in range(popup.item_count):
		if popup.get_item_metadata(i)=="recipes":index=i
	if index<0:return false
	await mouse(Vector2(popup.position)+Vector2(popup.size.x*.5,(index+.5)*float(popup.size.y)/float(popup.item_count)))
	await process_frame;await process_frame
	var panel:Node=UI.shown(game,"res://scripts/recipe_book.gd")
	if panel==null:return false
	var labels:Array=UI.descendants(panel).filter(func(n):return n is Label and str(n.text).begins_with("黑松露发光蘑菇汤"))
	var okay:bool=labels.is_empty() if state=="unknown" else not labels.is_empty()
	if state=="cooked" and not labels.is_empty():okay=okay and "做过" in labels[0].text
	await capture("real-book-"+state)
	return await UI.click(self,panel.get_ok_button()) and okay
func run()->void:
	OS.set_environment("HABITAT_OPENING","legacy");root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.chat.hide();await process_frame;await process_frame
	for pair in [["codex","ai-gpt"],["companion-2","ai-deepseek"],["npc.mira","ai-claude"],["npc.nora","ai-glm"]]:game.world.actors[pair[0]].appearance_id=pair[1]
	if OS.get_environment("HABITAT_JOURNEY_FIFTH")=="1":
		var loaded:Dictionary=preload("res://scripts/save_store.gd").load_world(game.world,OS.get_environment("HABITAT_JOURNEY_RESUME"))
		check(loaded.ok,"resume actual four-signature complete checkpoint")
		if not loaded.ok:await stop("fifth-resume-failed");return
		check(await collect("chestnut"),"fifth dish real regrown forest chestnut")
		check(await collect("honey"),"fifth dish real flowerhouse honey")
		if failed:await stop("fifth-gather-failed");return
		var before:Dictionary=game.world.storage.saved()
		check(await meal("recipe:chestnut-honey",["codex"]),"fifth true cross-island dish cooked and eaten")
		check(game.world.storage.count("chestnut")==int(before.items.get("chestnut",0))-1 and game.world.storage.count("honey")==int(before.items.get("honey",0))-1,"fifth actual forest+their island exact warehouse debit")
		check(game.world.read_memories("human",{"kind":"signature_taste"}).total==4,"fifth retains all four witnessed signature memories")
		await capture("fifth-cross-island-real",game.world.point(game.world.life.station));record("fifth-complete" if not failed else "fifth-failed")
		print("GATHERED_FIFTH failed=",failed);game.queue_free();await process_frame;quit(1 if failed else 0);return
	if OS.get_environment("HABITAT_JOURNEY_FINISH")=="1":
		var path:String=OS.get_environment("HABITAT_JOURNEY_RESUME")
		var loaded:Dictionary=preload("res://scripts/save_store.gd").load_world(game.world,path)
		check(loaded.ok,"resume true three-signature checkpoint "+str(loaded))
		if not loaded.ok:await stop("final-resume-failed");return
		check(await release_native(),"actual pending catch released before additional chestnut")
		if failed:await stop("release-failed");return
		check(await feed(),"actual apple maintenance meal before blue")
		if failed:await stop("apple-feed-failed");return
		check(await collect("chestnut"),"second truly regrown chestnut for blue after six-ingredient orange")
		if failed:await stop("chestnut-failed");return
		check(await native_large_catch(),"actual fish caught last, sufficient original size for host plus blue")
		check(await meal("recipe:sea-land-skewers",["companion-2"],"companion-2"),"genuine blue signature speech and human memory")
		check(game.world.read_memories("human",{"kind":"signature_taste"}).total==4,"same world all four witnessed signatures")
		record("complete" if not failed else "finish-failed");print("GATHERED_SIGNATURE_FINISH failed=",failed);game.queue_free();await process_frame;quit(1 if failed else 0);return
	var resume:String=OS.get_environment("HABITAT_JOURNEY_RESUME")
	if not resume.is_empty():
		var restored:Dictionary=preload("res://scripts/save_store.gd").load_world(game.world,resume)
		check(restored.ok,"resume actual earned main-signatures checkpoint")
		if not restored.ok:await stop("resume-failed");return
		var original_trace:String=OS.get_environment("HABITAT_DATA_DIR").path_join("journey.json")
		if FileAccess.file_exists(original_trace):trace=JSON.parse_string(FileAccess.get_file_as_string(original_trace))
	else:
		check(await book("unknown"),"same-world new book unknown")
		check(await orchard(),"real ready showcase orchard harvested apple and blueberries")
		if failed:await stop("orchard-failed");return
		for batch in range(4):
			check(await gather_wood(),"three actual trees harvested batch"+str(batch))
			if failed:await stop("wood-failed");return
		check(await build_production("produce-flowerhouse",Vector2(33,226)),"real flowerhouse built")
		check(await build_production("produce-herbgarden",Vector2(105,226)),"real herb workshop built")
		check(await feed(),"first true maintenance meal")
		if failed:await stop("build-failed");return
		for id in ["potato","corn","chestnut","clam","kelp"]:
			check(await collect(id),"native gather "+id)
			if failed:await stop("gather-failed");return
		check(await feed(),"second maintenance meal")
		if failed:await stop("second-feed-failed");return
		record("moon-gathered")
		check(await collect("honey"),"actual facility honey collected")
		check(await collect("herb"),"actual facility herb collected")
		if failed:await stop("production-collect-failed");return
		check(await meal("recipe:honey-berry-apple",["codex"],"codex"),"real gathered white signature speech memory")
		if failed:await stop("white-failed");return
		check(await meal("recipe:harvest-stew",["npc.mira"],"npc.mira"),"real gathered orange signature speech memory")
		if failed:await stop("orange-failed");return
		record("main-signatures")
	check(await feed(),"true maintenance before dark crossing")
	check(await boat(false),"native bridge to dark")
	game.dark_ui._process(0)
	check(await UI.click(self,game.dark_ui.fire_button),"real torch lit")
	check(await collect("glow_mushroom"),"native lit mushroom")
	check(await collect("black_truffle"),"native lit black truffle")
	record("dark-collected")
	check(await boat(true),"native bridge return")
	if failed:await stop("return-failed");return
	check(await book("known"),"same-world actual discovery book")
	# Herb was honestly used by orange; wait for a real second harvest.
	check(await collect("herb"),"second regrown herb")
	if failed:await stop("second-herb-failed");return
	check(await meal("recipe:dark-truffle-soup",["npc.nora"],"npc.nora"),"real gathered black signature speech memory")
	check(await book("cooked"),"same-world actual cooked book")
	check(await feed(),"true maintenance before final fish")
	check(await collect("herb"),"third regrown herb for blue")
	check(await collect("chestnut"),"second real chestnut after orange six-ingredient recipe")
	check(await feed(),"actual apple maintenance after final harvests")
	check(await native_large_catch(),"native unique fish caught last, original size sufficient for two diners")
	check(await meal("recipe:sea-land-skewers",["companion-2"],"companion-2"),"real gathered blue signature speech memory")
	record("complete" if not failed else "failed")
	print("GATHERED_SIGNATURE_JOURNEY failed=",failed);game.queue_free();await process_frame;quit(1 if failed else 0)

func release_native()->bool:
	var shore:Array=game.world.map_anchor("dock.south.end")
	if not await walk(Vector2(shore[0],shore[1])):return false
	game.island_hud.refresh();await process_frame;await process_frame
	var buttons:Array=UI.descendants(game.island_hud.notifications).filter(func(n):return n is Button and n.text==Text.text("hud.release") and n.is_visible_in_tree())
	if buttons.is_empty():print("RELEASE missing ",game.island_hud.notification_data());return false
	return await UI.click(self,buttons[0]) and game.world.fishing.held("human").is_empty()
func native_large_catch()->bool:
	for attempt in range(12):
		if not await catch_native():return false
		var fish:Dictionary=game.world.fishing.held("human")
		if fish.size_id!="person":return true
		if not await release_native():return false
	return false

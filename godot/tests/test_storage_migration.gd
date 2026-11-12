extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Save=preload("res://scripts/save_store.gd")
const Library=preload("res://scripts/character_library.gd")
const UI=preload("res://tests/barbecue_ui_fixture.gd")
const Opening=preload("res://scripts/world_opening.gd")
var errors:=0
func _initialize()->void:call_deferred("run")
func check(v:bool,label:String)->void:
	if not v:errors+=1;push_error(label)
func fresh(directory:String)->RefCounted:
	var world:=World.new("res://content/home-v3/world.json")
	world.residents.provision(world)
	var library:=Library.new();library.configure(directory);world.library=library
	Opening.apply(world,library,"showcase");world.director.set_all_enabled(false)
	return world
func run()->void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-"):quit(1);return
	var original:=fresh(directory)
	check(Save.save_world(original,directory),"write isolated legacy fixture base")
	var path:=directory.path_join("island-v2.json")
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path));data["storage"]={"items":{}}
	var legacy:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/legacy-storage.json")).objects
	for spec in [["home.chest.01",{"wood":7,"mushroom":3}],["dark.chest",{"wood":9}]]:
		var old:Dictionary=legacy[spec[0]][-1].duplicate(true);old.items=spec[1];data.objects[old.id]=old
	data.farming["containers"]={}
	for spec in [["home.tools.seed","seed",{"seed.turnip":4}],["home.tools.harvest","harvest",{"tomato":5}]]:
		data.farming.containers[spec[0]]={"id":spec[0],"kind":"chest","region_id":"home","position":original.farms.farms["farm.home"][str(spec[1])+"_at"].duplicate(),"farm_id":"farm.home","role":spec[1],"capacity":240,"items":spec[2]}
	data.interior.serial=maxi(int(data.interior.serial),1000)
	data.interior.furniture["furniture.1000"]={"id":"furniture.1000","kind":"chest","recipe_id":"chest","name":"Legacy","region_id":"room.home.house.01","position":[3.5,3],"facing":"down","holder_id":"","invested":6,"capacity":80,"items":{"wood":2,"mushroom":1},"artwork":{}}
	data.actors.human.carry={"wood":3};data.actors.codex.carry={"tomato":2}
	var appearances:Array=["ai-gpt","ai-deepseek","ai-claude","ai-glm"];var ids:Array=["codex","companion-2","npc.mira","npc.nora"]
	for i in ids.size():data.actors[ids[i]].appearance_id=appearances[i];data.actors[ids[i]]["custom_appearance"]=true
	# Already-paid real meal fixture: historic source is provenance, never inventory.
	var station:Dictionary=data.shared_life.station
	station.portions=2;station.state="ready"
	station["fireside"]={"version":4,"id":"012345678901234567890123","remaining":150,"suspended":false,"consent":true,"invited":["codex"],"attended":[],"ate":{},"committed":false,"light_by":"human","roast_by":"human","current":{"id":"123456789012345678901234","food_id":"mushroom","menu_id":"single:mushroom","name":"Legacy meal","category":"mushroom","receipt":{"mushroom":2},"fish":{},"total":2,"eaten":0,"wasted":0,"sources":{"backpack":{},"chests":{"home.chest.01":{"mushroom":2}}},"elapsed":3,"seconds":3,"ready":true,"eaters":[]}}
	var forged:Dictionary=data.duplicate(true)
	forged.farming.containers["fake.box"]=forged.farming.containers["home.tools.seed"].duplicate(true);forged.farming.containers["fake.box"].id="fake.box"
	check(not preload("res://scripts/storage_migration.gd").migrate(forged,original),"unknown extra legacy container rejected before migration")
	forged=data.duplicate(true);forged.interior.furniture["furniture.1000"].position=[999,999]
	check(not preload("res://scripts/storage_migration.gd").migrate(forged,original),"invalid legacy furniture position cannot mint refund")
	var old_encoded:=JSON.stringify(data)
	var f:=FileAccess.open(path,FileAccess.WRITE);f.store_string(old_encoded);f.close()
	var next:=fresh(directory.path_join("new"))
	var loaded:=Save.load_world(next,directory)
	check(loaded.ok,"all-source legacy save loads "+str(loaded))
	if not loaded.ok:quit(1);return
	check(next.storage.saved().items=={"wood":27,"mushroom":4,"seed.turnip":4,"tomato":5},"every legacy storage source plus invested six wood refunded exactly")
	check(next.actors.human.carry.is_empty() and next.storage.count("wood")==27 and int(next.actors.codex.carry.get("tomato",0))==2 and next.life.item_count(next.actors.codex.carry)==2,"legacy human carry is merged exactly once while companion carry stays physical")
	check(next.objects.values().all(func(o):return o.kind!="chest") and next.interior.furniture.values().all(func(o):return o.kind!="chest"),"no world or furniture chests remain")
	check(next.life.fireside.state.current.sources=={"backpack":{},"storage":{"mushroom":2}} and next.life.station.portions==2,"paid barbecue provenance converted with food intact")
	check(next.life.fireside.jobs.is_empty() and not next.life.fireside.state.consent,"reload creates no job or invitation")
	check(Save.save_world(next,directory),"new save writes")
	var written:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	check(not written.farming.has("containers") and not JSON.stringify(written).contains('"kind":"chest"') and not written.shared_life.station.fireside.current.sources.has("chests"),"new save has no chest objects containers or sources")
	var last:=fresh(directory.path_join("last"));check(Save.load_world(last,directory).ok and last.storage.saved()==next.storage.saved(),"second load cannot duplicate migrated contents or refund")
	# The production scene now starts from the original legacy file; actions below
	# use the real HUD/input chain and never set live actor coordinates.
	f=FileAccess.open(path,FileAccess.WRITE);f.store_string(old_encoded);f.close()
	OS.set_environment("HABITAT_OPENING","legacy");root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	var game:Node=load("res://scenes/main_v3.tscn").instantiate();game.world=last;root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.chat.hide()
	for i in range(8):await process_frame
	check(last.storage.count("wood")==27 and last.storage.count("tomato")==5,"production scene reads legacy fixture and migrates on startup")
	check(await UI.click(self,game.island_hud.stock_button) and game.storage_panel.visible,"legacy startup actual HUD opens storage")
	check(game.storage_panel.deposit_button.disabled,"automatic legacy merge requires no manual deposit")
	for unit in range(3):
		var wood_row:Node=null
		for row in game.storage_panel.rows.get_children():
			if row is HBoxContainer and str(row.get_child(0).text).begins_with(preload("res://scripts/storage_panel.gd").item_name(last,"wood")+" "):wood_row=row;break
		check(wood_row!=null and await UI.click(self,wood_row.get_child(2)),"explicit native withdrawal of one real legacy wood")
	check(last.actors.human.carry.get("wood",0)==3 and last.storage.count("wood")==24,"explicit withdrawal conserves the same legacy three wood")
	check(await UI.click(self,game.storage_panel.deposit_button),"legacy actual all-in button")
	check(last.actors.human.carry.is_empty() and last.storage.count("wood")==27,"legacy actor three wood deposits exactly")
	check(await UI.click(self,game.storage_panel.close_button),"legacy actual close")
	# Resume only through a fresh, explicit host invitation using actual map input.
	game.view.follow_player=false;game.view.center=last.point(last.life.station)
	var at:Vector2=game.view.screen(last.point(last.life.station))
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.position=at;event.global_position=at;root.push_input(event,true);await process_frame
	for i in range(600):
		game._process(.1);game.view._process(.1)
		if not last._routes.has("human"):break
	var panel:Node=null
	for child in game.get_children():
		if child.get_script()==load("res://scripts/fireside_panel.gd") and child.visible:panel=child
	check(panel!=null,"legacy paid meal visible through real fire click")
	if panel!=null:
		check(await UI.click(self,panel.roast_button),"real invitation for retained paid meal")
		var invitation:Node=null
		for child in game.get_children():
			if child.get_script()==load("res://scripts/fireside_invitation.gd") and child.visible:invitation=child
		check(invitation!=null,"retained meal invitation visible")
		if invitation!=null:
			if not OS.get_environment("HABITAT_UI_EXTRA_CAPTURE").is_empty():
				var issues:Array=await preload("res://tests/storage_ui_extra_capture.gd").capture(self,game,invitation,"legacy-paid-meal-invitation")
				check(issues.is_empty(),"migrated paid meal invitation bilingual four viewport scan "+str(issues))
			check(await UI.click(self,invitation.checks.codex),"real re-invite Snow only")
			check(await UI.click(self,invitation.get_ok_button()),"real invitation confirmation")
			for i in range(600):
				game._process(.1);game.view._process(.1)
				if int(last.life.fireside.state.current.eaten)>0:break
			check(int(last.life.fireside.state.current.eaten)>0,"retained paid meal actually eaten after legacy load")
	if not OS.get_environment("HABITAT_UI_EXTRA_CAPTURE").is_empty():
		# The source actors already have non-default appearances in the legacy
		# file; map clicks open the original house panel and invitation UI.
		game.view.center=last.point(last.objects["home.house.01"])
		var house_at:Vector2=game.view.screen(last.point(last.objects["home.house.01"]))
		for down in [true,false]:
			var mouse:=InputEventMouseButton.new();mouse.button_index=MOUSE_BUTTON_LEFT;mouse.pressed=down;mouse.position=house_at;mouse.global_position=house_at;root.push_input(mouse,true);await process_frame
		check(game.house_panel.visible,"real migrated house map click opens panel")
		if game.house_panel.visible:
			check(await UI.click(self,game.house_panel.companion_button),"real migrated house invite opens participant picker")
			check(game.participant_picker.visible,"participant picker actually visible")
			if game.participant_picker.visible:
				var issues:Array=await preload("res://tests/storage_ui_extra_capture.gd").capture(self,game,game.participant_picker,"legacy-nondefault-participant-picker")
				check(issues.is_empty(),"nondefault participant names bilingual four viewport scan "+str(issues))
				check(await UI.click(self,game.participant_picker.get_cancel_button()),"real participant cancel")
	game.queue_free();await process_frame
	print("Storage migration errors=",errors," totals=",next.storage.saved().items)
	quit(1 if errors else 0)

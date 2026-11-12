extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
const Text=preload("res://scripts/localization.gd")
var failures:Array=[]
var game:Node
var motion:Dictionary={}
var last:Dictionary={}
var samples:Array=[]
var label:String
func check(value:bool,message:String)->void:
	if not value:failures.append(message);push_error(message)
func _initialize()->void:call_deferred("run")
func click_at(at:Vector2)->void:
	for down in [true,false]:
		var e:=InputEventMouseButton.new();e.position=at;e.global_position=at;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;e.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;root.push_input(e,true);await process_frame
func tick()->void:
	game._process(.1)
	if game.dark_ui!=null:game.dark_ui._process(.1)
	for id in ["human","npc.mira","companion-2"]:
		var a:Dictionary=game.world.actors[id];var at:Vector2=game.world.point(a)
		if last.has(id) and last[id].region==a.region_id:motion[id]=float(motion.get(id,0))+at.distance_to(last[id].at)
		last[id]={"region":a.region_id,"at":at}
	if samples.size()<600 and int(game.world.forest.clock*10)%20==0:samples.append({"clock":game.world.forest.clock,"actors":["human","npc.mira","companion-2"].map(func(id):return {"id":id,"region":game.world.actors[id].region_id,"position":game.world.actors[id].position.duplicate()})})
func settle()->void:
	for i in range(6000):
		tick()
		if not game.world.work.jobs.has("human") and not game.world._routes.has("human") and not game.dark_ui.boat_pending and game.pending_camp.is_empty():return
	check(false,"host route settles "+label)
func capture(suffix:String)->void:
	var out:String=OS.get_environment("BBQ_WALK_OUTPUT")
	if out.is_empty() or DisplayServer.get_name()=="headless":return
	game.view.queue_redraw();await process_frame;await process_frame;RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(out.path_join(label+"-"+suffix+".png"))
func run()->void:
	var opening:String=OS.get_environment("BBQ_WALK_OPENING");if opening.is_empty():opening="showcase"
	var station:String=OS.get_environment("BBQ_WALK_STATION");if station.is_empty():station="home.barbecue"
	label=opening+"-"+station
	var directory:String=OS.get_environment("HABITAT_DATA_DIR")
	var initial=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");initial.residents.provision(initial)
	initial.library=preload("res://scripts/character_library.gd").new();initial.library.configure(directory)
	check(preload("res://scripts/world_opening.gd").apply(initial,initial.library,opening).ok,"genuine "+opening+" opening")
	for pair in [["codex","ai-gpt"],["companion-2","ai-deepseek"],["npc.mira","ai-claude"],["npc.nora","ai-glm"]]:initial.actors[pair[0]].appearance_id=pair[1]
	check(Save.save_world(initial,directory),"save actual new opening with only authorized appearance fixture")
	OS.set_environment("HABITAT_OPENING","legacy");root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.view.sound_enabled=false;game.island_hud.set_process(false);game.chat.hide()
	await process_frame;await process_frame
	var w:RefCounted=game.world
	check(w.opening_id==opening,"loaded exact actual opening")
	if opening=="standard":
		game.view.center=w.point(w.objects["home.house.01"]);game.view.follow_player=false;await process_frame
		await click_at(game.view.screen(w.point(w.objects["home.house.01"])))
		check(game.house_panel.visible and await UI.click(self,game.house_panel.build_all_button),"explicit native host build-all prepares locked camp; not claimed hand-built")
		game.house_panel.hide()
	check(await UI.click(self,game.gathering_button),"native open follow picker")
	await capture("follow-menu")
	for id in ["companion-2","npc.mira"]:
		await capture("follow-before-"+id)
		check(await UI.click(self,game.follow_ui.checks[id]),"native follow checkbox "+id)
	check(await UI.click(self,game.follow_ui.menu.get_ok_button()),"native close follow picker")
	check(w.activities.following.has("npc.mira") and w.activities.following.has("companion-2"),"two real host followers committed")
	for i in range(150):tick()
	var life:RefCounted=w.barbecues[station]
	var unlimited:bool=OS.get_environment("BBQ_UNLIMITED")=="1"
	if unlimited:
		var mushroom:int=int(w.available_items("human").get("mushroom",0))
		if mushroom>0:check(w.pay_costs("human",{"mushroom":mushroom}).ok,"fixture clears mushroom stock")
	var stock_before:Dictionary=w.storage.saved().duplicate(true)
	if station=="dark.barbecue":
		check(await UI.click(self,game.dark_ui.entry_button),"native north bridge menu")
		var depart:Array=UI.descendants(game.dark_ui.menu).filter(func(n):return n is Button and n.text==Text.text("ui.dark.depart"))
		check(depart.size()==1 and await UI.click(self,depart[0]),"native cross original dark bridge with selected followers")
		settle()
		check(w.actors.human.region_id=="dark","real north bridge crossing reaches dark camp")
	game.view.show_region(w.actors.human.region_id);game.view.center=w.point(life.station);game.view.follow_player=false;await process_frame
	await click_at(game.view.screen(w.point(life.station)));settle();await process_frame
	if station=="dark.barbecue":
		var fire_entry:Array=UI.descendants(game.dark_ui.menu).filter(func(n):return n is Button and n.text==Text.text("ui.dark.fireside"))
		check(fire_entry.size()==1 and await UI.click(self,fire_entry[0]),"native dark fireside action")
		settle();await process_frame
	var panel:Node=UI.shown(game,"res://scripts/fireside_panel.gd")
	check(panel!=null,"native walk opens exact selected camp")
	if panel!=null:
		check(await UI.click(self,panel.light_button),"native light with real opening wood")
		await capture("before-roast")
		check(await UI.click(self,panel.roast_button),"native open invitation")
		var invitation:Node=UI.shown(game,"res://scripts/fireside_invitation.gd")
		check(invitation!=null,"exact camp invitation opens")
		if invitation!=null:
			if unlimited:check(await UI.click(self,invitation.all_box),"native invite all")
			else:
				for id in ["npc.mira","companion-2"]:check(await UI.click(self,invitation.checks[id]),"native invitation checkbox "+id)
			check(await UI.click(self,invitation.get_ok_button()),"native invitation next")
			var menu:Node=UI.shown(game,"res://scripts/fireside_menu.gd")
			check(menu!=null,"exact food menu")
			if menu!=null:
				var expand:Array=UI.descendants(menu).filter(func(n):return n is Button and n.get_meta("expand_basics",false))
				if not expand.is_empty():check(await UI.click(self,expand[0]),"native expand basic grills")
				var choose:Array=UI.descendants(menu).filter(func(n):return n is Button and n.get_meta("menu_id","")=="single:mushroom")
				check(not choose.is_empty() and await UI.click(self,choose[0]),"native mushroom selection from actual opening stock")
				check(await UI.click(self,menu.start_button),"native roast exact selected two")
				for i in range(1600):
					tick()
					if (life.fireside.state.get("current",{}).get("eaters",[]).size()==5 if unlimited else ["npc.mira","companion-2"].all(func(id):return id in life.fireside.state.get("current",{}).get("eaters",[]))):break
	var meal:Dictionary=life.fireside.state.get("current",{})
	for id in ["npc.mira","companion-2"]:
		check(id in meal.get("eaters",[]),"selected resident really walks and eats "+id)
		check(float(motion.get(id,0))>1,"real actor route distance recorded "+id)
	if unlimited:check(meal.get("eaters",[]).size()==5 and w.storage.count("mushroom")==0,"all five eat with zero mushroom stock")
	else:check(meal.get("eaters",[]).all(func(id):return id in ["human","npc.mira","companion-2"]),"uninvited actors never eat")
	if not meal.is_empty():check(int(meal.total)==int(meal.eaten)+int(meal.wasted)+int(life.station.portions),"real pot quantity conserved")
	check(int(stock_before.items.wood)-w.storage.count("wood")==2 and int(stock_before.items.get("mushroom",0))-w.storage.count("mushroom")==0,"exact opening stock debit wood2 and no mushrooms")
	game.view.center=w.point(life.station)+Vector2(3,0);game.island_hud.refresh();await capture("eaten")
	var result:Dictionary={"opening":opening,"station":station,"failures":failures,"actor_tile_distances":motion,"route_samples":samples,"stock_before":stock_before,"stock_after":w.storage.saved(),"meal":meal.duplicate(true),"notes":"formal camp prerequisite uses native host build-all; no actor coordinates or inventory injected; only appearance preset in initial temporary save"}
	var out:String=OS.get_environment("BBQ_WALK_OUTPUT")
	if not out.is_empty():
		var f:=FileAccess.open(out.path_join(label+".json"),FileAccess.WRITE);f.store_string(JSON.stringify(result,"  "))
	game.queue_free();await process_frame
	print("BBQ_WALK ",label," failures=",failures);quit(1 if not failures.is_empty() else 0)

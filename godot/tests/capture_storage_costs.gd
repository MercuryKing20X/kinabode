extends SceneTree
## Standalone real-input acceptance. Not registered in the full suite.
## Initial inventory/positions are explicitly serialized QA fixtures. Runtime
## interaction is exclusively InputEvent -> viewport.push_input -> normal UI.
const UI=preload("res://tests/barbecue_ui_fixture.gd")
const World=preload("res://scripts/world_state.gd")
const Save=preload("res://scripts/save_store.gd")
const Text=preload("res://scripts/localization.gd")
var game:Node
var records:Array=[]
var paths:Array=[]
var base:String
var failures:int=0
var case_name:String
var target:Vector2
var previous:Vector2
var distance:float=0.0
var material_distance:float=0.0
var initial:Dictionary={}
var captures:Array=[]
func _initialize()->void:call_deferred("run")
func fail(label:String)->void:
	failures+=1;push_error(case_name+": "+label)
func button(label:String)->BaseButton:
	for n in UI.descendants(game):
		if n is BaseButton and n.is_visible_in_tree() and n.text==label:return n
	return null
func shown(path:String)->Node:return UI.shown(game,path)
func mouse(at:Vector2)->void:
	for down in [true,false]:
		var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;e.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;e.position=at;e.global_position=at;root.push_input(e,true);await process_frame
func click(b:BaseButton,label:String)->bool:
	if b==null:fail("missing visible button: "+label);return false
	var ok:bool=await UI.click(self,b)
	if not ok:fail("input rejected: "+label)
	return ok
func tick()->void:
	game._process(.1);game.view._process(.1)
	var w:RefCounted=game.world
	var now:Vector2=w.point(w.actors.human);var moved:float=now.distance_to(previous);previous=now;distance+=moved
	var job:Dictionary=w.work.jobs.get("human",{})
	var stage:String=str(job.get("step",job.get("phase","idle")))
	if paths.is_empty() or paths[-1].stage!=stage:paths.append({"stage":stage,"intent":job.get("intent",""),"position":[now.x,now.y]})
	if stage in ["build_load","load","load_seed","load_harvest","host_food_take","farm_take"]:material_distance+=moved
func settle(limit:int=3000)->void:
	for i in range(limit):
		tick()
		var w:RefCounted=game.world
		if not w._routes.has("human") and not w.work.jobs.has("human") and not w.farms.active("human") and w.dark.pending.is_empty() and game.pending_camp.is_empty():break
		if i%40==0:await process_frame
	await process_frame;await process_frame
func shot(label:String)->void:
	var out:String=OS.get_environment("HABITAT_PLAYTEST_CAPTURE")
	if out.is_empty() or DisplayServer.get_name()=="headless":return
	DirAccess.make_dir_recursive_absolute(out);game.island_hud.refresh();await process_frame;await RenderingServer.frame_post_draw
	var path:String=out.path_join(case_name+"-"+label+".png")
	root.get_texture().get_image().save_png(path);captures.append(path)
func prepare(kind:String)->bool:
	case_name=kind;paths=[];distance=0;material_distance=0;captures=[]
	var action:String=kind.trim_prefix("standard-")
	var directory:String=base.path_join(kind);OS.set_environment("HABITAT_DATA_DIR",directory);OS.set_environment("HABITAT_OPENING","legacy")
	var w:RefCounted=World.new("res://content/home-v3/world.json");w.residents.provision(w)
	w.library=preload("res://scripts/character_library.gd").new();w.library.configure(directory)
	var opening:String="standard" if kind.begins_with("standard-") else "showcase"
	if not preload("res://scripts/world_opening.gd").apply(w,w.library,opening).ok:return false
	if opening=="standard":
		# Explicit saved-fixture precondition, not a claim of UI construction.
		# Original unbuilt-gate behavior stays covered by unchanged opening tests.
		for site_id in ["play.standard.camp","play.standard.moon-camp","play.standard.moon-platform"]:
			if w.leisure.sites.has(site_id):
				var site:Dictionary=w.leisure.sites[site_id]
				site.artwork=w.leisure.art(site).duplicate(true);site.invested=w.leisure.cost(site);site.complete=true
	# Declared initial QA stock, not generated during play or a player save.
	w.storage.restore({"items":{"wood":200,"mushroom":20,"turnip":12,"tomato":12,"pumpkin":12,"seed.turnip":12,"seed.tomato":12,"seed.pumpkin":12}})
	w.actors.human.carry={}
	for id in ["codex","companion-2","npc.mira","npc.nora"]:
		w.actors[id].appearance_id={"codex":"ai-gpt","companion-2":"ai-deepseek","npc.mira":"ai-claude","npc.nora":"ai-glm"}[id];w.actors[id]["custom_appearance"]=true
	if action in ["home-fire","moon-fire"]:
		var station:String="home.barbecue" if action=="home-fire" else "moon.barbecue"
		target=w.point(w.barbecues[station].station)
	elif action=="house":target=w.point(w.objects["home.house.06"])
	elif action=="furniture":
		w.actors.human.region_id="room.home.house.01";var door:Vector2=w.interior.door(w.actors.human.region_id);w.actors.human.position=[door.x,door.y];target=Vector2(4.5,6.5)
	elif action=="plant":
		for plot in w.farms.farm_plots("farm.home"):plot.crop_id="";plot.watered=false;plot.planted_at=0.0
		target=w.point(w.farms.farm_plots("farm.home")[0])
	elif action.begins_with("dark"):
		w.actors.human.region_id="dark";w.actors.human.position=w.dark.config.arrival.duplicate()
		target=w.dark.p(w.dark.config.camp)
		if action=="dark-beacon":target=w.dark.p(w.dark.config.areas.filter(func(a):return a.has("beacon"))[0].beacon)
	if not Save.save_world(w,directory):return false
	initial=w.storage.saved().items.duplicate(true)
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=World.new("res://content/home-v3/world.json");root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.chat.hide();game.world.director.set_all_enabled(false)
	for i in range(8):await process_frame
	Text.select(directory,"en");game.view.follow_player=false;game.view.center=target;game.view.zoom=1;game.view.show_region(game.world.actors.human.region_id);game.view.center=target
	previous=game.world.point(game.world.actors.human);tick();await process_frame
	return game.world.actors.human.carry.is_empty() and game.world.storage.saved().items==initial
func record(kind:String,expect:Dictionary)->void:
	var w:RefCounted=game.world;var spent:Dictionary={}
	var end:Dictionary=w.storage.saved().items
	for item in initial:
		var n:int=int(initial[item])-int(end.get(item,0))
		if n!=0:spent[item]=n
	var ok:bool=spent==expect and is_zero_approx(material_distance)
	if not ok:fail("cost or supply-route mismatch expected="+str(expect)+" actual="+str(spent))
	records.append({"case":kind,"initial_fixture":initial,"warehouse_after":end,"actual_spent":spent,"expected_spent":expect,"passed":ok,"total_human_route_tiles":distance,"material_pickup_route_tiles":material_distance,"path_stages":paths.duplicate(true),"screenshots":captures.duplicate(),"visible_locale_violations":preload("res://tests/visible_locale_audit.gd").violations(game,"en"),"status_text":game.status.text})
func run()->void:
	base=OS.get_environment("HABITAT_DATA_DIR")
	if not base.contains("youqi-"):quit(1);return
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	for kind in ["home-fire","moon-fire","standard-home-fire","standard-moon-fire","house","furniture","plant","dark-torch","dark-beacon"]:
		if not OS.get_environment("HABITAT_COST_CASES").is_empty() and kind not in OS.get_environment("HABITAT_COST_CASES").split(","):continue
		var action:String=kind.trim_prefix("standard-")
		if not await prepare(kind):fail("isolated load fixture failed");continue
		var w:RefCounted=game.world
		if action in ["home-fire","moon-fire"]:
			await mouse(game.view.screen(target));await settle()
			var panel:Node=shown("res://scripts/fireside_panel.gd")
			if panel==null:fail("fire body input did not open fire panel")
			else:
				await click(panel.light_button,"light");await settle();await shot("lit")
				record(kind+"-light",{"wood":2})
				initial=w.storage.saved().items.duplicate(true);distance=0;material_distance=0;paths=[]
				await click(panel.roast_button,"barbecue");await process_frame
				var invite:Node=shown("res://scripts/fireside_invitation.gd")
				if invite==null:fail("invite absent")
				else:
					await click(invite.get_ok_button(),"invitation next")
					var menu:Node=shown("res://scripts/fireside_menu.gd")
					if menu==null:fail("food menu absent")
					else:
						await click(menu.start_button,"start grilling");tick();await shot("grill")
						record(kind+"-grill",{"mushroom":1})
		elif action=="house":
			await mouse(game.view.screen(target));await process_frame
			for stage in range(5):
				await click(game.house_panel.build_button,"build house stage "+str(stage+1));await settle();game.house_panel.refresh();await process_frame
			await shot("built")
			if int(w.objects["home.house.06"].stage_index)!=5:fail("house did not finish actual construction")
			record(kind,{"wood":w.work.stage_costs(w.objects["home.house.06"]).reduce(func(n,c):return n+int(c),0)})
		elif action=="furniture":
			await click(button(Text.text("hud.arrange_room")),"arrange")
			var recipe:BaseButton=null
			for n in UI.descendants(game.interior_panel):
				if n is BaseButton and n.get_meta("recipe_id","")=="chair":recipe=n;break
			await click(recipe,"chair recipe");await mouse(game.view.screen(target));await settle();await shot("placed")
			record(kind,{"wood":int(w.interior.RECIPES.chair.wood)})
		elif action=="plant":
			await mouse(game.view.screen(target));await settle()
			await click(game.farm_panel.fill_button,"plant all");await settle();await shot("planted")
			var costs:Dictionary={}
			for plot in w.farms.farm_plots("farm.home"):
				if not plot.crop_id.is_empty():var seed:String="seed."+str(plot.crop_id);costs[seed]=int(costs.get(seed,0))+1
			if w.farms.farm_plots("farm.home").any(func(p):return p.crop_id.is_empty() or not p.watered):fail("all twelve plots must be genuinely planted and watered")
			record(kind,costs)
		elif action=="dark-torch":
			await click(game.dark_ui.fire_button,"portable torch");await settle();await shot("torch")
			record(kind,{"wood":1})
		elif action=="dark-beacon":
			await click(game.dark_ui.fire_button,"beacon prerequisite portable torch");tick()
			record(kind+"-torch-prerequisite",{"wood":1})
			initial=w.storage.saved().items.duplicate(true);distance=0;material_distance=0;paths=[]
			await mouse(game.view.screen(target)+Vector2(0,-25));await process_frame
			await click(button(Text.text("ui.dark.light_beacon")),"light beacon");await settle();await shot("beacon")
			record(kind,{"wood":6})
		game.queue_free();await process_frame;await process_frame
	var out:String=base.path_join("storage-costs-input.json")
	var f:=FileAccess.open(out,FileAccess.WRITE);f.store_string(JSON.stringify({"source":"viewport.push_input","fixture":"isolated serialized initial stock, empty human carry","failures":failures,"cases":records},"\t"));f.close()
	print("Storage costs input failures=",failures," report=",out)
	quit(1 if failures else 0)

extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
const IDS=["codex","companion-2","npc.mira","npc.nora"]
var game:Node
var failures:Array=[]
var distances:Dictionary={}
var last:Dictionary={}
func check(ok:bool,message:String)->void:
	if not ok:failures.append(message);push_error(message)
func _initialize()->void:call_deferred("run")
func click_at(at:Vector2)->void:
	for control in UI.descendants(game):
		if control is Control and control.is_visible_in_tree() and control.mouse_filter==Control.MOUSE_FILTER_STOP and control.get_global_rect().has_point(at):print("STUCK_CLICK_OVERLAY ",at," ",control.get_path())
	for down in [true,false]:
		var e:=InputEventMouseButton.new();e.position=at;e.global_position=at;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;e.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
		root.push_input(e,true);await process_frame
func tick()->void:
	game._process(.1)
	for id in IDS:
		var p:Vector2=game.world.point(game.world.actors[id])
		if last.has(id):distances[id]=float(distances.get(id,0))+p.distance_to(last[id])
		last[id]=p
func capture(name:String)->void:
	var output:String=OS.get_environment("STUCK_CAPTURE")
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	game.view.queue_redraw();await process_frame;await process_frame;RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(output.path_join(name+".png"))
func measure_walk()->Dictionary:
	var w:RefCounted=game.world;var origin:Vector2=w.point(w.actors.human)
	var frames:Array=[];var visited:Array=[]
	game.view.follow_player=false;game.view.zoom=1
	for offset in [Vector2(12,0),Vector2(12,12),Vector2(0,12),Vector2.ZERO]:
		var target:Vector2=Vector2.INF
		for correction in [Vector2.ZERO,Vector2(2,0),Vector2(-2,0),Vector2(0,2),Vector2(0,-2),Vector2(4,0),Vector2(-4,0),Vector2(0,4),Vector2(0,-4)]:
			var candidate:Vector2=origin+offset+correction
			game.view.center=(candidate+w.point(w.actors.human))/2
			if w.walkable("home",candidate) and not w.find_route("human",candidate).is_empty() and game.view.hit(game.view.screen(candidate)).is_empty():target=candidate;break
		if not target.is_finite():continue
		await process_frame
		await click_at(game.view.screen(target))
		for i in range(100):
			var started:int=Time.get_ticks_usec();tick();game.view.queue_redraw();await process_frame
			frames.append(float(Time.get_ticks_usec()-started)/1000.0)
		visited.append(w.actors.human.position.duplicate())
	if frames.is_empty():return {"frames":0,"visited":visited}
	return {"frames":frames.size(),"average_ms":frames.reduce(func(a,b):return a+b,0.0)/frames.size(),"worst_ms":frames.max(),"visited":visited}
func run()->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR")
	assert(dir.contains("youqi-"))
	var initial=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");initial.residents.provision(initial)
	initial.library=preload("res://scripts/character_library.gd").new();initial.library.configure(dir)
	check(preload("res://scripts/world_opening.gd").apply(initial,initial.library,"standard").ok,"standard opening")
	check(preload("res://scripts/host_build_all.gd").apply(initial).ok,"fixture host completed")
	initial.intelligence.activate_presets();initial.hunger.start()
	initial.activities.set_followers(IDS)
	for pair in [["human","suit-hulk"],["codex","ai-gpt"],["companion-2","ai-deepseek"],["npc.mira","ai-claude"],["npc.nora","black-scarf-girl"]]:initial.actors[pair[0]].appearance_id=pair[1]
	for id in ["codex","npc.mira"]:initial.hunger.states[id].elapsed=3600.0;initial.hunger.states[id].full_meal=false
	for id in ["companion-2","npc.nora"]:initial.hunger.states[id].elapsed=0.0;initial.hunger.states[id].full_meal=true
	check(Save.save_world(initial,dir),"fixture saved")
	var path:String=dir.path_join("island-v2.json");var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	data.homestead.site.completion={}
	data["following"]=IDS.duplicate()
	var near:Array=[]
	for radius in range(0,6):
		for x in range(-radius,radius+1):
			for y in range(-radius,radius+1):
				var position:=Vector2(101+x+.5,47+y+.5)
				if initial.walkable("home",position) and not near.has(position):near.append(position)
		if near.size()>=2:break
	check(near.size()>=2,"walkable positions near player save location")
	if near.size()>=2:
		data.actors.codex.position=[100.540412902832,46.4340438842773];data.actors["npc.mira"].position=[102.34041595459,47.4340438842773]
	data.wishes.states["codex"]={"active":{"id":"wish-0123456789abcdef01234567","resident_id":"codex","template_id":"flowerbed","target_id":initial.homestead.config.site.id,"created_day":1,"expires_day":3,"announced":false,"baseline":[],"proof_id":""},"last_created_day":1,"next_day":3,"history":["flowerbed"]}
	data.storage.items["wood"]=24;data.storage.items["mushroom"]=12
	var f:=FileAccess.open(path,FileAccess.WRITE);f.store_string(JSON.stringify(data));f.close()
	OS.set_environment("HABITAT_OPENING","legacy");root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.view.sound_enabled=false;game.island_hud.set_process(false);game.chat.hide()
	await process_frame;await process_frame
	var w:RefCounted=game.world
	var rescued:Dictionary={}
	for id in ["codex","npc.mira"]:
		rescued[id]=w.actors[id].position.duplicate()
		check(w.walkable("home",w.point(w.actors[id])),"loaded resident leaves obstacle "+id)
	await capture("rescued")
	check(w.homestead.site.get("host_completion_source")=="unstarted" and not w.homestead.site.completion.get("id","").is_empty(),"legacy completion repaired on load")
	check(w.wishes.active("codex").get("template_id","")=="flowerbed","unfinished homestead wish restored")
	check(w.wishes.proofs(w.wishes.active("codex")).is_empty(),"host-built site has no real construction proof")
	check(IDS.all(func(id):return w.activities.following.has(id)),"four followers restored")
	check(w.hunger.rank("codex")==3 and w.hunger.rank("npc.mira")==3,"both very hungry after load")
	for i in range(30):tick()
	check(w.wishes.active("codex").get("proof_id","").is_empty(),"host-built site is not a real construction proof")
	var start:Dictionary={};for id in IDS:start[id]=w.point(w.actors[id]);distances[id]=0.0;last[id]=start[id]
	game.view.follow_player=false;game.view.zoom=1;game.view.center=w.point(w.actors.human);await process_frame
	var goal:=Vector2.INF
	for x in range(-16,17,2):
		for y in range(-12,13,2):
			var at:Vector2=w.point(w.actors.human)+Vector2(x,y);var screen:Vector2=game.view.screen(at)
			if Vector2(x,y).length()<7 or screen.x<180 or screen.x>1100 or screen.y<150 or screen.y>650:continue
			if UI.descendants(game).any(func(control):return control is Control and control.is_visible_in_tree() and control.mouse_filter==Control.MOUSE_FILTER_STOP and control.get_global_rect().has_point(screen)):continue
			if w.walkable("home",at) and game.view.hit(screen).is_empty() and not w.find_route("human",at).is_empty():goal=at;break
		if goal.is_finite():break
	check(goal.is_finite(),"visible reachable destination")
	var human_start:Vector2=w.point(w.actors.human)
	if goal.is_finite():await click_at(game.view.screen(goal))
	for i in range(350):tick()
	check(w.point(w.actors.human).distance_to(human_start)>3,"clicked ground moves host selected="+str(game.selected_id)+" status="+game.status.text)
	for id in IDS:
		check(float(distances.get(id,0))>1.0,"follower moves "+id)
		check(w.point(w.actors[id]).distance_to(w.point(w.actors.human))<8.0,"follower reaches host "+id)
	var follow_distances:Dictionary=distances.duplicate()
	await capture("follow")
	var life:RefCounted=w.barbecues["home.barbecue"]
	game.view.center=w.point(life.station);await process_frame
	await click_at(game.view.screen(w.point(life.station)))
	for i in range(1500):
		tick()
		if not w._routes.has("human") and game.pending_camp.is_empty():break
	await process_frame
	var panel:Node=UI.shown(game,"res://scripts/fireside_panel.gd")
	check(panel!=null,"camp panel opens")
	if panel!=null:
		check(await UI.click(self,panel.light_button),"light camp")
		check(await UI.click(self,panel.roast_button),"roast opens invitation")
		var invitation:Node=UI.shown(game,"res://scripts/fireside_invitation.gd")
		check(invitation!=null,"invitation opens")
		if invitation!=null:
			check(await UI.click(self,invitation.all_box),"invite all")
			check(await UI.click(self,invitation.get_ok_button()),"confirm invitation")
			var menu:Node=UI.shown(game,"res://scripts/fireside_menu.gd")
			check(menu!=null,"food menu opens")
			if menu!=null:
				var expand:Array=UI.descendants(menu).filter(func(n):return n is Button and n.get_meta("expand_basics",false))
				if not expand.is_empty():await UI.click(self,expand[0])
				var choose:Array=UI.descendants(menu).filter(func(n):return n is Button and n.get_meta("menu_id","")=="single:mushroom")
				check(not choose.is_empty() and await UI.click(self,choose[0]),"choose mushroom")
				check(await UI.click(self,menu.start_button),"start actual roast")
				for i in range(900):
					tick()
					if ["codex","npc.mira"].all(func(id):return id in life.fireside.state.get("current",{}).get("eaters",[])):break
	var eaters:Array=life.fireside.state.get("current",{}).get("eaters",[])
	for id in ["codex","npc.mira"]:check(id in eaters,"hungry resident ate "+id)
	await capture("meal")
	var performance:Dictionary={}
	if OS.get_environment("STUCK_MEASURE")=="1":performance=await measure_walk()
	var output:String=OS.get_environment("STUCK_CAPTURE")
	if not output.is_empty():
		var result:=FileAccess.open(output.path_join("result.json"),FileAccess.WRITE)
		result.store_string(JSON.stringify({"rescued_positions":rescued,"follow_distances":follow_distances,"eaters":eaters,"failures":failures,"performance":performance},"  "));result.close()
	print("STUCK_SAVE_INPUT distances=",distances," eaters=",eaters," failures=",failures)
	game.queue_free();await process_frame;quit(1 if not failures.is_empty() else 0)

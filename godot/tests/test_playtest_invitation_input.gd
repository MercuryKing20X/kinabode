# DIRECTION 2026-11-07: 主角鱼直接入库；以原真实实例验证后续流程。
extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
var checks:=0
var failed:=false
var prefix:=""
var rows:Array=[]
var base_dir:String
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func click_at(pos:Vector2)->void:
	for down in [true,false]:
		var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;e.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;e.position=pos;e.global_position=pos;root.push_input(e,true);await process_frame
func capture(name:String)->void:
	var output:=OS.get_environment("HABITAT_PLAYTEST_CAPTURE")
	if output.is_empty() or DisplayServer.get_name()=="headless":return
	await process_frame;await process_frame;RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(output.path_join(prefix+"-"+name+".png"))
func wardrobe(game:Node)->void:
	var assignments:Dictionary={"codex":"ai-gpt","companion-2":"ai-deepseek","npc.mira":"ai-claude","npc.nora":"ai-glm"}
	for id in assignments:
		game.island_hud.refresh();await process_frame;await process_frame
		check(await UI.click(self,game.island_hud.appearance_buttons[id]),"wardrobe open "+id)
		var panel:Node=game.island_hud.wardrobe
		var matches:Array=UI.descendants(panel.grid).filter(func(n):return n is Button and n.get_meta("work_id","")==assignments[id])
		check(matches.size()==1,"appearance exists "+id)
		if matches.is_empty():continue
		var target:Button=matches[0];var scroll:ScrollContainer=panel.grid.get_parent()
		for attempt in range(30):
			if scroll.get_global_rect().has_point(target.get_global_rect().get_center()):break
			var at:Vector2=scroll.get_global_rect().get_center()
			for down in [true,false]:
				var event:=InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=MOUSE_BUTTON_WHEEL_DOWN;event.pressed=down;root.push_input(event,true);await process_frame
		check(await UI.click(self,target),"select appearance "+id)
		var confirm:Array=UI.descendants(panel).filter(func(n):return n is Button and n.text=="确定")
		check(confirm.size()==1 and await UI.click(self,confirm[0]),"confirm wardrobe "+id)
		check(game.world.actors[id].appearance_id==assignments[id],"actual appearance bound "+id)
func run()->void:
	base_dir=OS.get_environment("HABITAT_DATA_DIR")
	for station in ["home.barbecue","moon.barbecue"]:
		for all_first in [true,false]:await scenario(station,all_first)
	var output:String=OS.get_environment("HABITAT_PLAYTEST_CAPTURE")
	if not output.is_empty():
		var file:=FileAccess.open(output.path_join("invitation-input.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failed":failed,"script_sha256":FileAccess.get_sha256("res://tests/test_playtest_invitation_input.gd"),"cases":rows},"  "))
	print("Playtest direct invite input: ",checks," checks failed=",failed);quit(1 if failed else 0)
func scenario(station:String,all_first:bool)->void:
	prefix=station+"-"+str(all_first)
	OS.set_environment("HABITAT_DATA_DIR",base_dir.path_join(prefix))
	DisplayServer.window_set_size(Vector2i(1280,800))
	var dir:String=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-test-"));OS.set_environment("HABITAT_OPENING","legacy")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	var w:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");w.residents.provision(w);w.library=preload("res://scripts/character_library.gd").new();w.library.configure(dir);assert(preload("res://scripts/world_opening.gd").apply(w,w.library,"showcase").ok);w.intelligence.activate_presets();w.hunger.start()
	var game:Node=load("res://scenes/main_v3.tscn").instantiate();game.world=w;root.add_child(game);game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.view.sound_enabled=false;game.island_hud.set_process(false);game.chat.hide();await process_frame;await process_frame
	await wardrobe(game)
	var camp:Dictionary=w.barbecues[station].station
	var destination:=Vector2.INF
	for offset in [Vector2(8,0),Vector2(-8,0),Vector2(0,8),Vector2(0,-8)]:
		var point:Vector2=w.point(camp)+offset
		game.view.center=point;game.view.follow_player=false
		if w.walkable("home",point) and game.view.hit(game.view.screen(point)).is_empty() and not w.find_route("human",point).is_empty():destination=point;break
	check(destination.is_finite(),"walkable island destination")
	if not destination.is_finite():game.queue_free();await process_frame;return
	await click_at(game.view.screen(destination))
	for frame in range(3000):
		game._process(.1);game.view._process(.1)
		if not w._routes.has("human"):break
	var target:Dictionary={}
	for spot in w.fishing.nearby_shores("human",32):
		var p:=Vector2(spot.position[0],spot.position[1]);game.view.center=p;game.view.follow_player=false;game.view.zoom=1
		if p.distance_to(w.point(w.actors.human))>=4 and game.view.hit(game.view.screen(p)).is_empty() and not w.find_route("human",p).is_empty():target=spot;break
	check(not target.is_empty(),"reachable distant shore")
	if target.is_empty():game.queue_free();await process_frame;return
	await click_at(game.view.screen(Vector2(target.position[0],target.position[1])))
	for i in range(3000):
		game._process(.1);game.view._process(.1)
		if not w._routes.has("human"):break
	check(not w.fishing.shore("human").is_empty(),"mouse route arrives")
	check(await UI.click(self,game.actions_button),"mouse opens actions")
	var buttons:Array=UI.descendants(game.action_dock.menu).filter(func(n):return n is Button and n.text=="钓鱼")
	check(not buttons.is_empty() and await UI.click(self,buttons[0]),"mouse opens fishing")
	check(await UI.click(self,game.action_dock.popup.get_ok_button()),"mouse starts solo fishing")
	for i in range(3000):
		game._process(.1);game.view._process(.1)
		if not preload("res://tests/fishing_fixture.gd").unplaced(w).is_empty():break
	var fish:Dictionary=preload("res://tests/fishing_fixture.gd").unplaced(w);check(not fish.is_empty(),"one real catch")
	if fish.is_empty():game.queue_free();await process_frame;return
	game.island_hud.notices_signature="";game.island_hud.refresh();await process_frame;await process_frame
	for dimensions in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=dimensions;game.island_hud.notices_signature="";game.island_hud.refresh();await process_frame;await process_frame
		var rect:=Rect2(Vector2.ZERO,Vector2(dimensions))
		for control in UI.descendants(game.island_hud.notifications):
			if control is Button and control.visible:check(rect.encloses(control.get_global_rect()),"fish card fits "+str(dimensions))
		await capture("fish-card-"+str(dimensions.x))
	root.size=Vector2i(1280,800);game.island_hud.notices_signature="";game.island_hud.refresh();await process_frame;await process_frame
	var wood_before:int=int(w.barbecues[station].fireside.available().get("wood",0))
	var actions:Array=UI.descendants(game.island_hud.notifications).filter(func(n):return n is Button and n.text=="直接烧烤")
	check(not actions.is_empty() and await UI.click(self,actions[0]),"mouse chooses grill on fish card")
	var dialogs:Array=game.get_children().filter(func(n):return n is ConfirmationDialog and n.title=="选择营火" and n.visible)
	check(dialogs.size()==1 and await UI.click(self,dialogs[0].get_ok_button()),"mouse selects camp")
	for i in range(4000):
		game._process(.1);game.view._process(.1)
		if not w.fishing.fish.has(fish.id):break
	check(not w.fishing.fish.has(fish.id),"same fish leaves pending after actual walk")
	var life:RefCounted=w.barbecues[station]
	check(life.fireside.state.get("current",{}).get("fish",{}).get("id")==fish.id,"same fish ID on fire")
	var panels:Array=game.get_children().filter(func(n):return n.get_script()==preload("res://scripts/fireside_panel.gd") and n.visible)
	for dimensions in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=dimensions;await process_frame;await process_frame
		await capture("call-companion-"+str(dimensions.x))
	root.size=Vector2i(1280,800);await process_frame;await process_frame
	check(not panels.is_empty() and await UI.click(self,panels[0].invite_button),"mouse clicks call")
	var invites:Array=game.get_children().filter(func(n):return n.get_script()==preload("res://scripts/fireside_invitation.gd") and n.visible)
	check(not invites.is_empty(),"invitation visible")
	if invites.is_empty():game.queue_free();await process_frame;return
	var first:Node=invites[0]
	if all_first:check(await UI.click(self,first.all_box),"first all")
	else:
		check(await UI.click(self,first.checks.codex),"first codex");check(await UI.click(self,first.checks["companion-2"]),"first companion2")
	check(await UI.click(self,first.get_ok_button()),"confirm first")
	var retained:Array=life.fireside.state.invited.duplicate()
	var wood_after_grill:int=int(life.fireside.available().get("wood",0))
	check(wood_after_grill==wood_before-2,"cold fire exactly two wood")
	game.view.center=w.point(life.station);await click_at(game.view.screen(w.point(life.station)))
	for frame in range(20):game._process(.1);game.view._process(.1)
	var panel:Node=UI.shown(game,"res://scripts/fireside_panel.gd")
	check(panel!=null and panel.invite_button!=null and await UI.click(self,panel.invite_button),"second call through camp")
	var second:Node=UI.shown(game,"res://scripts/fireside_invitation.gd")
	check(second!=null,"second invitation visible")
	if second!=null:
		await capture("repeat-invitation")
		for id in retained:check(second.checks[id].disabled,"existing actual guest disabled "+id)
		check(await UI.click(self,second.all_box),"second all skips existing")
		check(second.selected_ids().all(func(id):return id not in retained),"second only adds new")
		check(await UI.click(self,second.get_ok_button()),"confirm second")
	check(life.fireside.state.invited.size()==4,"four unique actual guests")
	for frame in range(1600):
		game._process(.1);game.view._process(.1)
		if frame%50==0 and frame<=900:
			var trace:Dictionary={"station":station,"all_first":all_first,"frame":frame,"now":w.director.time,"timer":life.fireside.state.current.get("meal_remaining",-1),"eaters":life.fireside.state.current.eaters.duplicate(),"guests":life.fireside.state.invited.duplicate(),"selected_guests":life.fireside.selected_guests.duplicate(),"closed":life.fireside.circle_closed,"seats":life.fireside.seats.duplicate(),"diners":{}}
			for id in ["codex","companion-2","npc.mira","npc.nora"]:
				var routine:RefCounted=w.director.routines[id];var job:Dictionary=w.work.jobs.get(id,{});var route:Array=w._routes.get(id,[]);var own_follow:Dictionary=w.hunger.owned_routes.get(id,{})
				trace.diners[id]={"position":w.actors[id].position.duplicate(),"distance":w.point(w.actors[id]).distance_to(w.point(life.station)),"activity":w.actors[id].activity,"phase":job.get("phase",""),"job_id":job.get("id",""),"fire_job_id":life.fireside.jobs.get(id,""),"job_time":job.get("time",0),"seat":job.get("seat_id",""),"route":route.duplicate(),"r_owns_route":routine.owns_route,"follows":w.activities.following.has(id),"own_follow_route":not route.is_empty() and own_follow.has("route") and is_same(own_follow.route,w._routes.get(id)),"rank":w.hunger.rank(id),"held":life.fireside.held(id),"quiet_until":routine.visual_quiet_until,"r_kind":routine.kind,"suppressed_until":life.fireside.suppressed.get(id,0)}
			trace["work_events"]=w.work.events.slice(-12).duplicate(true)
			print("INVITATION_MIDTRACE ",JSON.stringify(trace))
		if life.fireside.state.current.get("eaten",0)==4:break
	if life.fireside.state.current.get("eaten",0)!=4:
		var diagnostic:Dictionary={"station":station,"all_first":all_first,"now":w.director.time,"fire_remaining":life.fireside.state.remaining,"current":life.fireside.state.current.duplicate(true),"invited":life.fireside.state.invited.duplicate(),"circle_closed":life.fireside.circle_closed,"away":life.fireside.away,"diners":{}}
		for id in ["codex","companion-2","npc.mira","npc.nora"]:
			var routine:RefCounted=w.director.routines[id]
			diagnostic.diners[id]={"position":w.actors[id].position,"activity":w.actors[id].activity,"job":w.work.jobs.get(id,{}).duplicate(true),"route":w._routes.get(id,[]),"fire_held":life.fireside.held(id),"quiet_until":routine.visual_quiet_until,"fish_quiet_until":w.fishing.life.quiet_until.get(id,0),"r_held":routine.held,"activities_held":w.activities.held.get(id,false),"commanded":w.activities.commanded(id),"r_kind":routine.kind,"r_owns_route":routine.owns_route,"rush":w.hunger.rushes.get(id,{}).duplicate(true),"member":w.activities.members.has(id),"suppressed_until":life.fireside.suppressed.get(id,0)}
		print("INVITATION_4_EATERS_DIAGNOSTIC ",JSON.stringify(diagnostic))
	check(life.fireside.state.current.get("eaten",0)==4 and life.fireside.state.current.eaters.size()==4,"four unique real eaters once")
	check(int(life.fireside.available().get("wood",0))==wood_after_grill,"repeat invitations never debit wood")
	check(life.fireside.state.current.fish.id==fish.id,"same exact fish remains on meal record")
	check(not w.fishing.fish.has(fish.id),"fish not duplicated in fishing")

	rows.append({"station":station,"all_first":all_first,"fish_id":fish.id,"fish_in_pending":w.fishing.fish.has(fish.id),"wood_before":wood_before,"wood_after":int(life.fireside.available().get("wood",0)),"eaters":life.fireside.state.current.eaters,"eaten":life.fireside.state.current.eaten,"invited":life.fireside.state.invited.duplicate()})
	print("Direct grill mouse: ",checks," checks failed=",failed)
	game.queue_free();await process_frame

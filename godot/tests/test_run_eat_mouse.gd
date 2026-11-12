extends SceneTree
const ConstructionUI=preload("res://tests/standard_construction_ui_fixture.gd")
const World=preload("res://scripts/world_state.gd")
const WardrobeUI=preload("res://tests/barbecue_ui_fixture.gd")
const UI=preload("res://tests/test_camp_binding_v4.gd")
const CampPanel=preload("res://scripts/fireside_panel.gd")
const Invite=preload("res://scripts/fireside_invitation.gd")
const Menu=preload("res://scripts/fireside_menu.gd")
var game:Node
var w:RefCounted
var ui:SceneTree
var failures:=false
var checks:=0
var captures:String
var stage_started:int=Time.get_ticks_msec()
func stage(label:String)->void:
	print("RUN_EAT_STAGE ",label," wall_ms=",Time.get_ticks_msec()-stage_started)
func check(ok:bool, label:String)->void:
	checks+=1
	if not ok:failures=true;push_error(label)
func _initialize()->void:call_deferred("run")
func mouse(pos:Vector2,button:int=MOUSE_BUTTON_LEFT)->void:
	var motion:=InputEventMouseMotion.new();motion.position=pos;motion.global_position=pos;root.push_input(motion,true)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=button;event.pressed=pressed
		event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0;event.position=pos;event.global_position=pos
		root.push_input(event,true);await process_frame
func click_button(button:Button)->bool:
	if button==null:return false
	await process_frame;await process_frame
	var seen:Dictionary={"count":0};button.pressed.connect(func():seen.count+=1,CONNECT_ONE_SHOT)
	var pos:Vector2=button.get_global_rect().get_center();var viewport:Viewport=button.get_viewport()
	if viewport is Window and viewport.is_embedded():pos+=Vector2(viewport.position);viewport=root
	var motion:=InputEventMouseMotion.new();motion.position=pos;motion.global_position=pos;viewport.push_input(motion,true)
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
		event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0;event.position=pos;event.global_position=pos
		viewport.push_input(event,true);await process_frame
	return seen.count==1
func advance()->void:
	game._process(.1);game.view._process(.1)
func wait_route()->bool:
	for i in range(3000):
		advance()
		if not w._routes.has("human"):return true
	return false
func screenshot(name:String)->void:
	if captures.is_empty():return
	game.view.queue_redraw();game.island_hud.refresh()
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var im:Image=root.get_texture().get_image()
	assert(im.get_size()==root.size);assert(im.save_png(captures.path_join(name+".png"))==OK)
func clickable_ground(at:Vector2)->bool:
	var pixel:Vector2=game.view.screen(at)
	if not game.view.hit(pixel).is_empty():return false
	# IslandView handles need bubbles BEFORE ordinary world hit testing.
	for entry in game.view.speech_layout():
		var context:String=str(game.view.speech_by_actor.get(entry.actor_id,{}).get("context",""))
		if context.begins_with("need_") and entry.box.has_point(pixel):return false
	return true
func rush_origin_failure(stage:String,life:RefCounted,at:Vector2)->bool:
	print("RUSH_ORIGIN_FAILURE ",stage," target=",at," human=",w.point(w.actors.human)," blue=",w.point(w.actors["companion-2"])," job=",w.work.jobs.get("companion-2",{})," route=",w._routes.has("companion-2")," panel=",game.resident_connections.visible)
	for seat in life.seats():print("RUSH_SEAT_DISTANCE ",w.point(seat).distance_to(w.point(w.actors["companion-2"])))
	return false
func prepare_visible_rush_origin(life:RefCounted)->bool:
	# This test observes actual running, so first establish an actual distance to run.
	# Local rest can legitimately leave blue already at the nearest dining seat.
	var center:Vector2=w.point(life.station);var at:=Vector2.INF
	game.view.follow_player=false;game.view.zoom=1
	for radius in [10.0,9.0,8.0]:
		for i in range(32):
			var candidate:Vector2=center+Vector2.from_angle(TAU*i/32)*radius
			game.view.center=candidate
			if not w.walkable(life.station.region_id,candidate) or not clickable_ground(candidate) or w.find_route("human",candidate).is_empty():continue
			# The existing come-near action chooses one of these four walkable offsets.
			var near:Array=[Vector2(2,0),Vector2(-2,0),Vector2(0,2),Vector2(0,-2)];var valid_origin:=false
			for offset in near:
				if not w.walkable(life.station.region_id,candidate+offset):continue
				# ResidentActivity.start chooses the FIRST walkable offset. An
				# arbitrary later safe offset cannot establish this precondition.
				valid_origin=not w.find_route("companion-2",candidate+offset).is_empty()
				for seat in life.seats():
					if w.point(seat).distance_to(candidate+offset)<=3.5:valid_origin=false;break
				break
			if valid_origin:at=candidate;break
		if at.is_finite():break
	if not at.is_finite():return rush_origin_failure("stage 22",life,at)
	game.view.center=at;await mouse(game.view.screen(at))
	if not wait_route() or w.point(w.actors.human).distance_to(at)>.1:return rush_origin_failure("stage 24",life,at)
	var hud:Node=game.island_hud
	hud.refresh();await process_frame;await process_frame
	if not await WardrobeUI.click(self,hud.manage_connections):return rush_origin_failure("stage 27",life,at)
	# This fixture freezes HUD processing; explicitly refresh presentation after opening a panel.
	hud.refresh();await process_frame;await process_frame
	var panel:Control=game.resident_connections
	var blue_index:int=panel.resident_ids.find("companion-2")
	if blue_index<0:return rush_origin_failure("stage 32",life,at)
	await mouse(panel.residents.get_global_rect().position+panel.residents.get_item_rect(blue_index).get_center())
	if panel.selected_id!="companion-2":return rush_origin_failure("stage 34",life,at)
	await mouse(panel.tabs.get_global_rect().position+panel.tabs.get_tab_rect(1).get_center())
	if panel.tabs.current_tab!=1 or not game.daily_controls.is_visible_in_tree():return rush_origin_failure("stage 36",life,at)
	var call_button:Button;var call_count:=0
	for node in WardrobeUI.descendants(game.daily_controls):
		if node is Button and node.text=="过来陪我":call_button=node;call_count+=1
	if call_count!=1:return rush_origin_failure("stage 40",life,at)
	for attempt in range(40):
		if panel.details_scroll.get_global_rect().encloses(call_button.get_global_rect()):break
		var scroll_at:Vector2=panel.details_scroll.get_global_rect().get_center()
		var motion:=InputEventMouseMotion.new();motion.position=scroll_at;motion.global_position=scroll_at;root.push_input(motion,true)
		for pressed in [true,false]:
			var wheel:=InputEventMouseButton.new();wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;wheel.pressed=pressed;wheel.button_mask=0;wheel.position=scroll_at;wheel.global_position=scroll_at;root.push_input(wheel,true);await process_frame
	if not await WardrobeUI.click(self,call_button):return rush_origin_failure("stage 47",life,at)
	var actual_job:String=str(w.work.jobs.get("companion-2",{}).get("id",""))
	if actual_job.is_empty() or w.work.jobs["companion-2"].get("intent")!="come_near":return rush_origin_failure("stage 49",life,at)
	for pressed in [true,false]:
		var escape:=InputEventKey.new();escape.keycode=KEY_ESCAPE;escape.pressed=pressed;root.push_input(escape,true);await process_frame
	if panel.visible:return rush_origin_failure("stage 52",life,at)
	hud.refresh();await process_frame;await process_frame
	for frame in range(3000):
		advance()
		if not w.work.jobs.has("companion-2") and not w._routes.has("companion-2"):break
	if w.work.jobs.has("companion-2") or w._routes.has("companion-2"):return rush_origin_failure("stage 57",life,at)
	# Wait the original command cooldown; do not stop blue (which would mean120 seconds).
	while w.director.time<float(w.hunger.quiet_until.get("companion-2",0))+.1:advance()
	for seat in life.seats():
		if w.point(seat).distance_to(w.point(w.actors["companion-2"]))<=3:return rush_origin_failure("stage 61",life,at)
	return true
func modes()->Array:
	return [OS.get_environment("HABITAT_MOTION_CASE")] if not OS.get_environment("HABITAT_MOTION_CASE").is_empty() else ["standard","showcase"]
func run()->void:
	var temp:String=OS.get_environment("HABITAT_DATA_DIR");assert(temp.contains("youqi-test-"))
	captures=OS.get_environment("HABITAT_MOTION_CAPTURES")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	for mode in modes():
		for station_id in ["home.barbecue","moon.barbecue"]:
			print("CAMP CASE ",mode," ",station_id)
			stage(station_id+" opening begins")
			var case_dir:String=temp.path_join(mode+station_id.replace(".","-"))
			OS.set_environment("HABITAT_DATA_DIR",case_dir)
			OS.set_environment("HABITAT_OPENING","legacy" if mode=="showcase" else "standard")
			w=World.new("res://content/home-v3/world.json");w.world_id="00000000-0000-4000-8000-000000001027";w.residents.provision(w)
			# Main owns library loading and initial opening setup. Do not load and
			# validate every pixel work a second time before the real startup path.
			game=load("res://scenes/main_v3.tscn").instantiate();game.world=w
			game.dialogue_adapter_factory=func(_id,_scope):return preload("res://tests/test_intent_input.gd").IntentFake.new()
			root.add_child(game)
			check(w.opening_id==mode,"actual opening "+mode)
			# Stable fixture choreography, after Main has installed the real presets.
			w.weather.weather_seed=1027
			var seed_index:=0
			for id in w.director.routines:
				w.director.routines[id].rng.seed=1027+seed_index;seed_index+=1
			game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.view.sound_enabled=false;game.island_hud.set_process(false)
			ui=UI.new();ui.game=game;ui.w=w
			await process_frame;await process_frame;game.chat.hide()
			stage(station_id+" wardrobe begins")
			var hud:Node=game.island_hud
			var assignments:Dictionary={"codex":"ai-gpt","companion-2":"ai-deepseek","npc.mira":"ai-claude","npc.nora":"ai-glm"}
			for actor_id in assignments:
				hud.refresh();await process_frame;await process_frame
				check(await WardrobeUI.click(self,hud.appearance_buttons[actor_id]),mode+" actual wardrobe button "+actor_id)
				var wardrobe:Node=hud.wardrobe;await process_frame;await process_frame
				check(wardrobe.visible and wardrobe.selected_actor==actor_id,mode+" wardrobe binds resident "+actor_id)
				var matches:Array=WardrobeUI.descendants(wardrobe.grid).filter(func(n):return n is Button and n.get_meta("work_id","")==assignments[actor_id])
				check(matches.size()==1,mode+" target appearance exists "+assignments[actor_id])
				if matches.is_empty():continue
				var target:Button=matches[0];var scroll:ScrollContainer=wardrobe.grid.get_parent()
				for attempt in range(30):
					if scroll.get_global_rect().has_point(target.get_global_rect().get_center()):break
					await mouse(scroll.get_global_rect().get_center(),MOUSE_BUTTON_WHEEL_DOWN)
				check(await WardrobeUI.click(self,target) and wardrobe.selected_work==assignments[actor_id],mode+" actual appearance selection "+actor_id)
				var confirm:Array=WardrobeUI.descendants(wardrobe).filter(func(n):return n is Button and n.text=="确定")
				check(confirm.size()==1 and await WardrobeUI.click(self,confirm[0]) and w.actors[actor_id].appearance_id==assignments[actor_id],mode+" actual confirm changes selected appearance "+actor_id)
			if mode=="standard":
				stage(station_id+" construction begins")
				var required:int=ConstructionUI.required_wood(w,station_id)
				for chop in range(ceili(float(maxi(0,required-w.storage.count("wood")))/float(w.forest.settings.normal_wood))+1):
					if w.storage.count("wood")>=required:break
					var trees:Array=w.objects.values().filter(func(o):return o.kind=="tree" and o.status=="mature" and not w.work.claims.has(o.id))
					trees.sort_custom(func(a,b):return w.point(a).distance_squared_to(w.point(w.actors.human))<w.point(b).distance_squared_to(w.point(w.actors.human)))
					var tree:Dictionary={};var at:=Vector2.ZERO;var tree_click:=Vector2.ZERO
					for candidate in trees:
						at=w.point(candidate);game.view.center=at;game.view.follow_player=false;game.view.zoom=1
						for lift in [40,80,120,160,200]:
							var pixel:Vector2=game.view.screen(at)-Vector2(0,lift)
							if game.view.hit(pixel)==candidate.id and ConstructionUI.unobstructed_tree_click(game.view,pixel):tree=candidate;tree_click=pixel;break
						if not tree.is_empty():break
					check(not tree.is_empty(),"a real tree has a clear mouse hit")
					if tree.is_empty():continue
					await mouse(tree_click)
					check(w.work.jobs.get("human",{}).get("intent") in ["chop","gather_wood"],"mouse starts real tree job")
					for frame in range(5000):
						advance()
						if not w.work.jobs.has("human"):break
				var fire_at:Vector2=w.point(w.barbecues[station_id].station);game.view.center=fire_at
				await mouse(game.view.screen(fire_at))
				check(game.leisure_panel.visible,"mouse opens actual unbuilt camp")
				var builders:Array=WardrobeUI.descendants(game.leisure_panel).filter(func(n):return n is Button and n.text=="选择建造者 · 施工")
				check(builders.size()==1 and await WardrobeUI.click(self,builders[0]),"mouse opens builder selection")
				for id in game.participant_picker.toggles:
					var box:CheckBox=game.participant_picker.toggles[id]
					if box.button_pressed!=(id=="human"):check(await WardrobeUI.click(self,box),"mouse chooses only host builder")
				check(await WardrobeUI.click(self,game.participant_picker.get_ok_button()),"mouse confirms real construction")
				for frame in range(8000):
					advance()
					if not w.work.jobs.has("human"):break
				check(w.standard.ready(station_id),"actual material delivery finishes camp without preset grants")
				game.leisure_panel.hide()
			stage(station_id+" hunger advance begins")
			# Advance actual elapsed time without changing hunger parameters or inventory.
			for elapsed in range(1200):game._process(.5);game.view._process(.5)
			stage(station_id+" rush origin begins")
			var life:RefCounted=w.barbecues[station_id];var center:Vector2=w.point(life.station)
			check(await prepare_visible_rush_origin(life),mode+" "+station_id+" actual mouse call establishes blue away from every dining seat")
			stage(station_id+" running clicks begin")
			for direction in [Vector2.UP,Vector2.DOWN,Vector2.LEFT,Vector2.RIGHT]:
				var found:=false
				for angle in [-.6,-.3,0.0,.3,.6]:
					var p:Vector2=center+direction.rotated(angle)*4.5
					if w.walkable(life.station.region_id,p):found=true;break
				check(found,mode+" "+station_id+" four-direction walkable point")
			var ground:=Vector2.INF
			game.view.center=center;game.view.follow_player=false;game.view.zoom=1
			for i in range(32):
				var p:Vector2=center+Vector2.from_angle(TAU*i/32)*4.0
				# Native mouse input is quantized to whole viewport pixels. Keep
				# the original .01 world-distance assertion against the actual click.
				p=game.view.local_point(game.view.screen(p).round())
				if w.walkable("home",p) and clickable_ground(p) and not w.find_route("human",p).is_empty():ground=p;break
			check(ground.is_finite(),mode+" "+station_id+" has clickable ground close to fire")
			if ground.is_finite():
				await mouse(game.view.screen(ground))
				if not w._routes.has("human"):print("GROUND_CLICK_DIAGNOSTIC ",ground," human=",w.point(w.actors.human)," hover=",root.gui_get_hovered_control()," chat=",game.chat.visible," panel=",game.resident_connections.visible)
				var ground_started:bool=w._routes.has("human")
				var ground_arrived:bool=wait_route() if ground_started else false
				var ground_distance:float=w.point(w.actors.human).distance_to(ground)
				if not ground_started or not ground_arrived or ground_distance>=.01:print("GROUND_ARRIVAL_DIAGNOSTIC target=",ground," actual=",w.point(w.actors.human)," started=",ground_started," arrived=",ground_arrived," distance=",ground_distance," route=",w._routes.get("human",{})," job=",w.work.jobs.get("human",{})," pending_camp=",game.pending_camp)
				check(ground_started and ground_arrived and ground_distance<.01,mode+" "+station_id+" surrounding ground click walks normally")
			var far:=Vector2.INF
			for i in range(32):
				var p:Vector2=center+Vector2.from_angle(TAU*i/32)*16
				game.view.center=p;game.view.follow_player=false;game.view.zoom=1
				if w.walkable("home",p) and clickable_ground(p) and not w.find_route("human",p).is_empty():far=p;break
			check(far.is_finite(),mode+" "+station_id+" reachable distant ground")
			if not far.is_finite():game.queue_free();ui.free();continue
			game.view.center=far;await mouse(game.view.screen(far))
			check(w._routes.has("human") and wait_route() and w.point(w.actors.human).distance_to(center)>=15,mode+" "+station_id+" mouse walks to distant start")
			game.view.center=center;await process_frame
			check(game.view.hit(game.view.screen(center))==station_id,mode+" "+station_id+" fire body mouse hit")
			if not captures.is_empty():await screenshot("approach-"+station_id+"-far")
			await mouse(game.view.screen(center))
			check(not game.pending_camp.is_empty() and w._routes.has("human"),mode+" "+station_id+" fire click creates real route")
			if not captures.is_empty():
				for i in range(8):advance()
				await screenshot("approach-"+station_id+"-walking")
			check(wait_route(),mode+" "+station_id+" route arrives")
			await process_frame;await process_frame
			var panel:Node=ui.shown_script(CampPanel)
			check(panel!=null and life.fireside.near("human",5),mode+" "+station_id+" panel opens after arrival within five")
			if panel==null:game.queue_free();ui.free();continue
			if not captures.is_empty():await screenshot("approach-"+station_id+"-arrived")
			var before:int=int(life.fireside.available().get("wood",0))
			check(await click_button(panel.light_button) and life.fireside.burning() and int(life.fireside.available().get("wood",0))==before-2,mode+" "+station_id+" actual mouse lights real fire")
			if mode=="showcase":panel.hide();await screenshot("approach-"+station_id+"-lit");panel.show()
			check(await click_button(panel.roast_button),mode+" "+station_id+" mouse selects barbecue")
			var invite:Node=ui.shown_script(Invite)
			if invite==null:check(false,mode+" "+station_id+" invitation appears");game.queue_free();ui.free();continue
			check(await click_button(invite.all_box) and invite.selected_ids().size()==4,mode+" "+station_id+" All selects four")
			check(await click_button(invite.get_ok_button()),mode+" "+station_id+" next")
			var menu:Node=ui.shown_script(Menu)
			if menu==null:check(false,mode+" "+station_id+" menu appears");game.queue_free();ui.free();continue
			var expand:Button=WardrobeUI.descendants(menu).filter(func(n):return n is Button and n.get_meta("expand_basics",false))[0]
			check(await click_button(expand),"native expands basic grills")
			var mushroom_button:Button=WardrobeUI.descendants(menu).filter(func(n):return n is Button and n.get_meta("menu_id","")=="single:mushroom")[0]
			menu.scroll.ensure_control_visible(mushroom_button);await process_frame;await process_frame
			check(await click_button(mushroom_button),"native selects exact real mushroom")
			check(await click_button(menu.start_button),mode+" "+station_id+" actual mouse roasts")
			var run_columns:Dictionary={}
			var captured:=false;var rush_seen:bool=w.hunger.rushing("companion-2")
			for tick in range(3000):
				advance();rush_seen=rush_seen or w.hunger.rushing("companion-2")
				if w.display_running("companion-2") and w.motion_state("companion-2").moving:run_columns[game.view.motion.run_column("companion-2",w.intelligence.gait("companion-2"),true)]=true
				if not captured and w.work.jobs.values().any(func(j):return j.get("phase")=="fire_eat"):
					captured=true
					for dimensions in [Vector2i(1280,800),Vector2i(960,640)]:
						root.size=dimensions;game.view.center=center
						await screenshot(mode+"-"+station_id+"-eating-"+str(dimensions.x))
					root.size=Vector2i(1280,800)
				if life.fireside.state.current.get("eaten",0)>=5:break
			check(rush_seen,mode+" hungry invited blue uses real rush route")
			check(run_columns.size()>1,mode+" rushing uses changing run atlas columns")
			check(life.fireside.state.current.get("eaten",0)==5,mode+" "+station_id+" five actual eaters")
			stage(station_id+" eating complete")
			game.queue_free();ui.free();await process_frame;await process_frame
	print("Run eat wardrobe mouse: ",checks," checks, failed=",failures)
	quit(1 if failures else 0)

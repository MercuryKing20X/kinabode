extends SceneTree
## UI/Visual integration; production/evidence/playtest-fix-1031; ADVISORY viewport + BLOCKING input distance.
const UI=preload("res://tests/barbecue_ui_fixture.gd")
var failed:=false
var count:=0
var output:String
var records:Array=[]
func check(value:bool,label:String)->void:
	count+=1
	if not value:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func key(down:bool)->void:
	var event:=InputEventKey.new();event.keycode=KEY_RIGHT;event.physical_keycode=KEY_RIGHT;event.pressed=down;Input.parse_input_event(event);root.push_input(event,true)
	await process_frame
func capture(game:Node,label:String)->void:
	game.view.queue_redraw();game.island_hud.refresh();await process_frame;await process_frame;RenderingServer.force_draw(false)
	var image:=root.get_texture().get_image();check(image.get_size()==root.size,"viewport matches "+label)
	if not output.is_empty():image.save_png(output.path_join(label+".png"))
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
		scroll.ensure_control_visible(target);await process_frame;await process_frame
		var selected:bool=await UI.click(self,target)
		if not selected and not output.is_empty():
			await process_frame;RenderingServer.force_draw(false);root.get_texture().get_image().save_png(output.path_join("wardrobe-rejected-"+id+".png"))
		check(selected,"select appearance "+id)
		var confirm:Array=UI.descendants(panel).filter(func(n):return n is Button and n.text=="确定")
		check(confirm.size()==1 and await UI.click(self,confirm[0]),"confirm wardrobe "+id)
		check(game.world.actors[id].appearance_id==assignments[id],"actual appearance bound "+id)
func far_visit(game:Node,opening:String)->void:
	var w:RefCounted=game.world
	w.activities.set_followers([]) # Explicit host dismissal before measuring free residents returning.
	# Match the existing follow-picker deselection: this scene measures free social return visits.
	for id in w.director.routines:
		w.activities.default_follow_excluded[id]=true
	var start:Vector2=w.point(w.actors.human);var target:=Vector2.INF
	# Avoid treating the first short radial step as isolation when it lands in
	# the forest residents are actively using. Prefer the more distant route.
	for radius in [72.0,60.0,52.0,44.0,36.0]:
		for index in range(24):
			var point:Vector2=start+Vector2.from_angle(TAU*index/24)*radius
			if w.actors.values().filter(func(actor):return actor.id!="human").all(func(actor):return w.point(actor).distance_to(point)>=32) and w.walkable("home",point) and not w.find_route("human",point).is_empty():
				game.view.center=point;game.view.follow_player=false
				if game.view.hit(game.view.screen(point)).is_empty():target=point;break
		if target.is_finite():break
	check(target.is_finite(),"reachable far destination")
	if not target.is_finite():return
	var at:Vector2=game.view.screen(target)
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;root.push_input(event,true);await process_frame
	check(w._routes.has("human"),"far mouse click starts original route")
	var autonomous_work:=false
	for frame in range(2600):
		game._process(.1);game.view._process(.1)
		autonomous_work=autonomous_work or w.director.brains.values().any(func(brain):return brain.owns_local_job())
	check(autonomous_work,"background work remains active during the trip "+opening)
	check(w.point(w.actors.human).distance_to(target)<.1,"human reaches clicked far destination")
	var arrivals:Dictionary={};var total:=0
	for id in w.director.routines:
		arrivals[id]=w.director.routines[id].return_visit.arrivals.duplicate(true);total+=arrivals[id].size()
	if total==0:
		print("RETURN_VISIT target=",target)
		for id in w.director.routines:
			var routine:RefCounted=w.director.routines[id]
			print("RETURN_VISIT ",id," time=",routine.time," last_seen=",routine.return_visit.last_seen," due=",routine.return_visit.due," attempts=",routine.return_visit.diagnostics," current=",w.director.brains[id].current," job=",w.work.jobs.get(id,{}))
	check(total>0,"idle residents return after real far-away player route "+opening)
	records.append({"opening":opening,"far_input_target":[target.x,target.y],"seconds_advanced":260,"return_arrivals":arrivals})
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"));output=OS.get_environment("HABITAT_PLAYTEST_CAPTURE")
	root.content_scale_size=Vector2i.ZERO
	for opening in ["showcase","standard"]:
		OS.set_environment("HABITAT_OPENING","legacy")
		var w:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");w.residents.provision(w);w.library=preload("res://scripts/character_library.gd").new();w.library.configure(OS.get_environment("HABITAT_DATA_DIR").path_join(opening));assert(preload("res://scripts/world_opening.gd").apply(w,w.library,opening).ok);w.intelligence.activate_presets();w.hunger.start()
		OS.set_environment("HABITAT_OPENING","legacy" if opening=="showcase" else "standard")
		var game:Node=load("res://scenes/main_v3.tscn").instantiate();game.set_script(preload("res://tests/playtest_camera_before.gd"));game.world=w;root.add_child(game);game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.view.sound_enabled=false;game.island_hud.set_process(false);game.chat.hide();await process_frame;await process_frame
		await wardrobe(game)
		for dimensions in [Vector2i(1280,800),Vector2i(960,640)]:
			DisplayServer.window_set_size(dimensions);root.size=dimensions;await process_frame
			var anchor:Vector2=w.point(w.actors.human)
			for state in ["before-reference","after"]:
				game.view.center=anchor;game.view.follow_player=false;game.view.zoom=.8 if state=="before-reference" else 1.0
				await capture(game,opening+"-"+state+"-%dx%d"%[dimensions.x,dimensions.y])
			game.view.center=anchor;game.view.zoom=.8;game.test_pan_factor=.5
			await key(true)
			var old_start:Vector2=game.view.center
			for frame in range(60):game._process(1.0/60.0)
			await key(false)
			var old_distance:float=(game.view.center-old_start).length()*32.0*game.view.zoom
			check(absf(old_distance-620)<.1,"old logic real key input gives 620 screen pixels")
			game.test_pan_factor=1.0;game.view.center=anchor;game.view.zoom=1.0
			await key(true)
			var start:Vector2=game.view.center
			for frame in range(60):game._process(1.0/60.0)
			await key(false)
			var distance:float=(game.view.center-start).length()*32.0*game.view.zoom
			check(absf(distance-1240.0)<.1,"one second real key event gives 1240 screen pixels")
			records.append({"opening":opening,"width":dimensions.x,"height":dimensions.y,"seconds":1,"screen_pixels":distance,"old_screen_pixels_measured":old_distance,"old_reference":"test-only inherited old camera delta/zoom logic; real key input, not old binary"})
		await far_visit(game,opening)
		check(game.links.values().all(func(link):return link._pid<=0),"zero model processes")
		game.queue_free();await process_frame;await process_frame
	if not output.is_empty():var file:=FileAccess.open(output.path_join("camera-input.json"),FileAccess.WRITE);file.store_string(JSON.stringify(records,"  "))
	print("Playtest camera input: ",count," checks failed=",failed);quit(1 if failed else 0)

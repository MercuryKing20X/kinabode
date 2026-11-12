extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
var game:Node
var output:String
var records:Array=[]
var trace:Array=[]
var failed:=false
func _initialize()->void:call_deferred("run")
func shot(label:String)->void:
	await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
func click(at:Vector2,shift:bool=false,double:bool=false)->void:
	for down in [true,false]:
		var e:=InputEventMouseButton.new();e.position=at;e.global_position=at;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;e.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;e.shift_pressed=shift;e.double_click=double;root.push_input(e,true)
	await process_frame
func click_button(button:BaseButton)->bool:
	if button==null:return false
	await process_frame;await process_frame
	var count:Dictionary={"n":0};button.pressed.connect(func():count.n+=1,CONNECT_ONE_SHOT)
	var at:Vector2=button.get_global_rect().get_center();var viewport:Viewport=button.get_viewport()
	if viewport is Window and viewport.is_embedded():at+=Vector2(viewport.position)
	await click(at)
	return count.n==1
func step()->void:
	game._process(1.0/60);game.view._process(1.0/60);await process_frame
func route(label:String,distance:float,expected:bool,shift:bool=false,double:bool=false,interrupt:bool=false)->void:
	var w:RefCounted=game.world;var start:Vector2=w.point(w.actors.human);var target:=Vector2.INF
	game.view.center=start;game.view.follow_player=false;game.view.zoom=1.25
	var sides:Array=[-distance,distance]
	if label.begins_with("host-away") and w.point(w.actors["companion-2"]).x>start.x:sides=[-distance,distance]
	elif label.begins_with("host-away"):sides=[distance,-distance]
	for dx in sides:
		var p:=start+Vector2(dx,0)
		if w.walkable(w.actors.human.region_id,p) and not w.find_route("human",p).is_empty() and game.view.hit(game.view.screen(p)).is_empty():target=p;break
	if not target.is_finite():failed=true;push_error("no visible side ground "+label);return
	await click(game.view.screen(target),shift,double)
	var frames:=0;var runs:=0;var walks:=0;var near_shot:=false;var switched:=false;var wrong:=0;var columns:Dictionary={}
	for i in range(1800):
		if not w._routes.has("human"):break
		var running:bool=w.is_running("human")
		await step()
		var m:Dictionary=w.motion_state("human")
		if m.moving:
			trace.append({"label":label,"frame":i,"position":w.actors.human.position.duplicate(),"running":w.display_running("human"),"column":game.view.motion.run_column("human",w.intelligence.gait("human")),"remaining":w.point(w.actors.human).distance_to(target)})
			frames+=1
			if w.display_running("human"):columns[game.view.motion.run_column("human",w.intelligence.gait("human"))]=true
			var texture:Texture2D=game.view.action_atlases.texture("run",game.library,w.actors.human,game.view.motion.run_column("human",w.intelligence.gait("human")))
			if w.display_running("human") and texture!=null:runs+=1
			else:walks+=1
			if w.display_running("human")!=(expected and not switched):wrong+=1
		if interrupt and frames==40:
			var next:Vector2=w.point(w.actors.human)+Vector2(6 if target.x>start.x else -6,0)
			await click(game.view.screen(next));target=next;switched=true
		if frames==1:await shot(label+"-start")
		if frames==40:await shot(label+"-middle")
		if not near_shot and w.point(w.actors.human).distance_to(target)<=3:near_shot=true;await shot(label+"-last3")
	await shot(label+"-stop")
	records.append({"label":label,"distance":distance,"frames":frames,"run":runs,"walk":walks,"expected_run":expected,"interrupt":interrupt,"wrong":wrong,"columns":columns.keys(),"arrived":w.point(w.actors.human).distance_to(target)<.2})
	if expected and runs>12 and columns.size()<3:failed=true
	if frames==0 or wrong>0 or (runs!=frames if expected else walks!=frames) and not interrupt:failed=true
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"))
	output=OS.get_environment("HABITAT_DARK_EVIDENCE");root.size=Vector2i(1280,800);root.gui_embed_subwindows=true
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");root.add_child(game);await process_frame;await process_frame
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.view.sound_enabled=false;game.island_hud.set_process(false);game.chat.hide();game.world.director.set_all_enabled(false)
	await route("home-long",15,true)
	if OS.get_environment("ROUTE_BASELINE").is_empty():
		await route("home-interrupt",15,true,false,false,true)
		await route("home-short",6,false);await route("home-shift",5,true,true);await route("home-double",5,true,false,true)
		await UI.click(self,game.dark_ui.entry_button)
		var buttons:Array=UI.descendants(game.dark_ui.menu).filter(func(n):return n is Button and n.text=="出发")
		if not buttons.is_empty():await UI.click(self,buttons[0])
		for i in range(10000):
			await step()
			if game.world.actors.human.region_id=="dark" and not game.world._routes.has("human") and not game.dark_ui.boat_pending:break
		if game.world.actors.human.region_id!="dark":failed=true
		else:
			await route("dark-long",15,true);await route("dark-interrupt",15,true,false,false,true);await route("dark-short",6,false);await route("dark-shift",5,true,true);await route("dark-double",5,true,false,true)
			var fires_before:int=game.world.dark.fires.size()
			var stock_before:int=int(game.world.dark.life.fireside.available().get("wood",0))
			await UI.click(self,game.dark_ui.fire_button)
			if game.world.dark.fires.size()!=fires_before or game.world.dark.torch.remaining<=0 or int(game.world.dark.life.fireside.available().get("wood",0))!=stock_before-1:failed=true
			await route("dark-torch",15,true)

	FileAccess.open(output.path_join("frames.json"),FileAccess.WRITE).store_string(JSON.stringify(records,"  "))
	FileAccess.open(output.path_join("trace.json"),FileAccess.WRITE).store_string(JSON.stringify(trace,"  "))
	print(JSON.stringify(records));game.queue_free();await process_frame;quit(1 if failed else 0)

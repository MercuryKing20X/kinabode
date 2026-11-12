extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Opening=preload("res://scripts/world_opening.gd")
const Library=preload("res://scripts/character_library.gd")
const UI=preload("res://tests/test_camp_binding_v4.gd")
const CampPanel=preload("res://scripts/fireside_panel.gd")
const Invitation=preload("res://scripts/fireside_invitation.gd")
var game:Node
var w:RefCounted
var helper:SceneTree
var checks:=0
var failed:=false
func check(ok:bool,msg:String)->void:
	checks+=1
	if not ok:failed=true;push_error(msg)
func _initialize()->void:call_deferred("run")
func click(button:Button)->bool:
	if button==null:return false
	await process_frame;await process_frame
	var pressed:Dictionary={"n":0};button.pressed.connect(func():pressed.n+=1,CONNECT_ONE_SHOT)
	var pos:Vector2=button.get_global_rect().get_center();var viewport:Viewport=button.get_viewport()
	if viewport is Window and viewport.is_embedded():pos+=Vector2(viewport.position);viewport=root
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;event.position=pos;event.global_position=pos
		viewport.push_input(event,true);await process_frame
	return pressed.n==1
func wait()->void:
	for i in range(3000):
		game._process(.1)
		if not w._routes.has("human"):return
	assert(false,"host route timed out")
func run()->void:
	var temp:String=OS.get_environment("HABITAT_DATA_DIR");assert(temp.contains("youqi-test-"))
	OS.set_environment("HABITAT_OPENING","legacy");root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	w=World.new("res://content/home-v3/world.json");w.residents.provision(w);w.library=Library.new();w.library.configure(temp);assert(Opening.apply(w,w.library,"showcase").ok)
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=w;root.add_child(game);game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.view.sound_enabled=false;game.island_hud.set_process(false)
	helper=UI.new();helper.game=game;helper.w=w;await process_frame;await process_frame
	var fire:RefCounted=w.life.fireside;check(not fire.near("human",5),"host begins outside fire range")
	game._show_barbecue_menu("home.barbecue");await process_frame;await process_frame
	var panel:Node=helper.shown_script(CampPanel);var wood:int=int(fire.available().get("wood",0))
	check(panel!=null and await click(panel.light_button),"actual light button accepted at distance")
	check(game.pending_camp.get("action")=="light" and w._routes.has("human") and int(fire.available().get("wood",0))==wood and panel.feedback.text.contains("正在走到火边"),"walk first, feedback visible, no premature debit")
	wait()
	check(fire.burning() and int(fire.available().get("wood",0))==wood-2,"arrival automatically lights and debits exactly two")
	panel.queue_free();await process_frame
	var center:Vector2=w.point(w.life.station);var far:=Vector2.INF
	for i in range(32):
		var p:=center+Vector2.from_angle(TAU*i/32)*16
		game.view.center=p;game.view.follow_player=false;game.view.zoom=1
		if w.walkable("home",p) and game.view.hit(game.view.screen(p)).is_empty() and not w.find_route("human",p).is_empty():far=p;break
	check(far.is_finite(),"real distant walkable ground")
	if far.is_finite():
		var pos:Vector2=game.view.screen(far)
		for down in [true,false]:
			var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;event.position=pos;event.global_position=pos
			root.push_input(event,true);await process_frame
		wait();check(not fire.near("human",5),"mouse walks away again")
		game._show_barbecue_menu("home.barbecue");await process_frame;await process_frame
		panel=helper.shown_script(CampPanel);var food:int=int(fire.available().get("mushroom",0))
		check(panel!=null and await click(panel.roast_button),"actual remote barbecue button accepted")
		check(game.pending_camp.get("action")=="roast" and w._routes.has("human") and int(fire.available().get("mushroom",0))==food,"remote barbecue walks before invitation and food debit")
		wait();await process_frame
		check(helper.shown_script(Invitation)!=null and int(fire.available().get("mushroom",0))==food,"arrival opens invitation without fabricating or consuming food")
	helper.free();game.queue_free();await process_frame
	print("Remote camp panel actions: ",checks," checks, failed=",failed);quit(1 if failed else 0)

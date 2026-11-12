extends SceneTree
const ConstructionUI=preload("res://tests/standard_construction_ui_fixture.gd")
const World=preload("res://scripts/world_state.gd")
const Opening=preload("res://scripts/world_opening.gd")
const Library=preload("res://scripts/character_library.gd")
const Standard=preload("res://tests/standard_fixture.gd")
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
func check(ok:bool, label:String)->void:
	checks+=1
	if not ok:failures=true;push_error(label)
func _initialize()->void:call_deferred("run")
func mouse(pos:Vector2)->void:
	for pressed in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed
		event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0;event.position=pos;event.global_position=pos
		root.push_input(event,true);await process_frame
func click_button(button:Button)->bool:
	if button==null:return false
	await process_frame;await process_frame
	var seen:Dictionary={"count":0};button.pressed.connect(func():seen.count+=1,CONNECT_ONE_SHOT)
	var pos:Vector2=button.get_global_rect().get_center();var viewport:Viewport=button.get_viewport()
	if viewport is Window and viewport.is_embedded():pos+=Vector2(viewport.position);viewport=root
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
	assert(im.get_size()==Vector2i(1280,800));assert(im.save_png(captures.path_join(name+".png"))==OK)
func run()->void:
	var temp:String=OS.get_environment("HABITAT_DATA_DIR");assert(temp.contains("youqi-test-"))
	captures=OS.get_environment("HABITAT_FIRE_GLM_SCREENSHOTS")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	for mode in ["standard","showcase"]:
		for station_id in ["home.barbecue","moon.barbecue"]:
			print("CAMP CASE ",mode," ",station_id)
			var case_dir:String=temp.path_join(mode+station_id.replace(".","-"))
			OS.set_environment("HABITAT_DATA_DIR",case_dir)
			OS.set_environment("HABITAT_OPENING","legacy" if mode=="showcase" else "standard")
			if mode=="standard":
				var fixture:=Standard.new();fixture.start(case_dir)
				w=fixture.w
				var count:int=maxi(1,ceili(float(maxi(0,ConstructionUI.required_wood(w,station_id)-w.storage.count("wood")))/float(w.forest.settings.normal_wood)))
				check(fixture.job({"intent":"gather_wood","zone_id":"home.forest","tree_count":count}),"real opening construction wood")
				var site:String="play.standard.camp" if station_id=="home.barbecue" else "play.standard.moon-camp"
				check(fixture.job({"intent":"build_facility","target_id":site}),"real opening facility construction")
			else:
				w=World.new("res://content/home-v3/world.json");w.residents.provision(w)
				w.library=Library.new();w.library.configure(case_dir)
				check(Opening.apply(w,w.library,"showcase").ok,"actual showcase opening")
				w.intelligence.activate_presets();w.hunger.start();w.director.set_all_enabled(true)
			game=load("res://scenes/main_v3.tscn").instantiate();game.world=w;root.add_child(game)
			game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.view.sound_enabled=false;game.island_hud.set_process(false)
			ui=UI.new();ui.game=game;ui.w=w
			await process_frame;await process_frame;game.chat.hide()
			var life:RefCounted=w.barbecues[station_id];var center:Vector2=w.point(life.station)
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
				if w.walkable("home",p) and game.view.hit(game.view.screen(p)).is_empty() and not w.find_route("human",p).is_empty():ground=p;break
			check(ground.is_finite(),mode+" "+station_id+" has clickable ground close to fire")
			if ground.is_finite():
				await mouse(game.view.screen(ground))
				check(w._routes.has("human") and wait_route() and w.point(w.actors.human).distance_to(ground)<.01,mode+" "+station_id+" surrounding ground click walks normally")
			var far:=Vector2.INF
			for i in range(32):
				var p:Vector2=center+Vector2.from_angle(TAU*i/32)*16
				game.view.center=p;game.view.follow_player=false;game.view.zoom=1
				if w.walkable("home",p) and game.view.hit(game.view.screen(p)).is_empty() and not w.find_route("human",p).is_empty():far=p;break
			check(far.is_finite(),mode+" "+station_id+" reachable distant ground")
			if not far.is_finite():game.queue_free();ui.free();continue
			game.view.center=far;await mouse(game.view.screen(far))
			check(w._routes.has("human") and wait_route() and w.point(w.actors.human).distance_to(center)>=15,mode+" "+station_id+" mouse walks to distant start")
			game.view.center=center;await process_frame
			check(game.view.hit(game.view.screen(center))==station_id,mode+" "+station_id+" fire body mouse hit")
			if mode=="showcase":await screenshot("approach-"+station_id+"-far")
			await mouse(game.view.screen(center))
			check(not game.pending_camp.is_empty() and w._routes.has("human"),mode+" "+station_id+" fire click creates real route")
			if mode=="showcase":
				for i in range(8):advance()
				await screenshot("approach-"+station_id+"-walking")
			check(wait_route(),mode+" "+station_id+" route arrives")
			await process_frame;await process_frame
			var panel:Node=ui.shown_script(CampPanel)
			check(panel!=null and life.fireside.near("human",5),mode+" "+station_id+" panel opens after arrival within five")
			if panel==null:game.queue_free();ui.free();continue
			if mode=="showcase":await screenshot("approach-"+station_id+"-arrived")
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
			check(await click_button(menu.start_button),mode+" "+station_id+" actual mouse roasts")
			for tick in range(3000):
				advance()
				if life.fireside.state.current.get("eaten",0)>=5:break
			check(life.fireside.state.current.get("eaten",0)==5,mode+" "+station_id+" five actual eaters")
			game.queue_free();ui.free();await process_frame;await process_frame
	print("Camp mouse approach: ",checks," checks, failed=",failures)
	quit(1 if failures else 0)

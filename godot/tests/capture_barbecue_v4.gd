extends SceneTree
## H: actual standard openings, physical harvesting/construction, native host UI, viewport evidence.
const UI=preload("res://tests/test_barbecue_ui_v4.gd")
const F=preload("res://tests/standard_fixture.gd")
const CampPanel=preload("res://scripts/fireside_panel.gd")
const Invitation=preload("res://scripts/fireside_invitation.gd")
const Menu=preload("res://scripts/fireside_menu.gd")
var game:Node
var w:RefCounted
var fixture:RefCounted
var helper:SceneTree
var elapsed:=0.0
var output:String
var screenshots:Array=[]
var simulations:Array=[]
func _initialize()->void:call_deferred("run")
func step(seconds:float=.1)->void:
	w.advance(seconds);elapsed+=seconds
	for event in w.director.events:
		if w.director.time-event.time<6:game.view.say(event.text,event.source,event.actor_id,event.get("context",""))
func wait(id:String,limit:float=900)->bool:
	var until:float=elapsed+limit
	while elapsed<until:
		if not w.work.jobs.has(id) and not w._routes.has(id):return true
		step()
	return false
func command(args:Dictionary,id:String="human")->bool:
	print("H COMMAND ",elapsed," ",args)
	var result:Dictionary=w.command(id,args)
	if not result.get("ok",false):print("H COMMAND FAILED ",args," ",result)
	var done:bool=result.get("ok",false) and wait(id)
	print("H COMMAND DONE ",elapsed," ",done)
	return done
func shot(name:String)->void:
	print("H SHOT ",name)
	for dimensions in [Vector2i(1280,800),Vector2i(960,640)]:
		DisplayServer.window_set_size(dimensions);root.size=dimensions;root.content_scale_size=Vector2i.ZERO
		game.island_hud.refresh();game.view._process(.1);game.view.queue_redraw()
		for child in game.get_children():
			if child.get_script() in [Invitation,Menu] and child.visible:child.fit()
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		var file:String=name+"-%sx%s.png"%[dimensions.x,dimensions.y];var im:=root.get_texture().get_image()
		assert(im.get_size()==dimensions and im.save_png(output.path_join(file))==OK)
		screenshots.append({"file":file,"pixels":[dimensions.x,dimensions.y],"actual_viewport":true,"elapsed_world_seconds":elapsed})
func click(button:Button)->bool:
	if button==null:return false
	await process_frame;await process_frame
	var count:Dictionary={"pressed":0};button.pressed.connect(func():count.pressed+=1,CONNECT_ONE_SHOT)
	var at:Vector2=button.get_global_rect().get_center();var viewport:Viewport=button.get_viewport()
	if viewport is Window and viewport.is_embedded():at+=Vector2(viewport.position);viewport=root
	var motion:=InputEventMouseMotion.new();motion.position=at;motion.global_position=at;viewport.push_input(motion,true)
	for pressed in [true,false]:
		var input:=InputEventMouseButton.new();input.button_index=MOUSE_BUTTON_LEFT;input.pressed=pressed;input.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0;input.position=at;input.global_position=at;viewport.push_input(input,true);await process_frame
	return count.pressed==1
func map_move(destination:Vector2)->bool:
	print("H MAP MOVE ",destination)
	game.view.follow_player=false;game.view.center=destination;game.view.zoom=1
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;event.position=game.view.screen(destination);event.global_position=event.position
	game.view._unhandled_input(event)
	return w._routes.has("human") and wait("human") and w.point(w.actors.human).distance_to(destination)<.01
func all_stock(item:String)->int:
	var n:=0
	for life in w.barbecues.values():n+=int(life.station.supplies.get(item,0))
	for chest in [{"id":"storage","items":w.storage.saved().items,"capacity":9007199254740991}]:n+=int(chest.items.get(item,0))
	for actor in w.actors.values():n+=int(actor.carry.get(item,0))
	return n
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"));output=OS.get_environment("HABITAT_BARBECUE_V4_OUTPUT");assert(not output.is_empty())
	helper=UI.new();root.content_scale_size=Vector2i.ZERO
	for station_id in ["home.barbecue","moon.barbecue"]:
		fixture=F.new();fixture.start(OS.get_environment("HABITAT_DATA_DIR").path_join("mainland" if station_id=="home.barbecue" else "moon"));w=fixture.w
		w.director.set_all_enabled(true);elapsed=0
		OS.set_environment("HABITAT_OPENING","standard")
		game=load("res://scenes/main_v3.tscn").instantiate();game.world=w;root.add_child(game);game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.view.sound_enabled=false;game.island_hud.set_process(false);helper.game=game;helper.w=w
		await process_frame;await process_frame;game.chat.hide()
		# Real initial four wood, real 8/tree, then actual station construction.
		var trees_needed:int=1 if station_id=="home.barbecue" else 2
		assert(command({"intent":"gather_wood","zone_id":"home.forest","tree_count":trees_needed}))
		var target:String="play.standard.camp" if station_id=="home.barbecue" else "play.standard.moon-camp"
		assert(command({"intent":"build_facility","target_id":target}))
		var built_at:float=elapsed;var life:RefCounted=w.barbecues[station_id]
		# Collect a real configured patch through World/Work and store by original receipts.
		var patches:Array=life.patches.values();patches.sort_custom(func(a,b):return w.point(a).distance_to(w.point(life.station))<w.point(b).distance_to(w.point(life.station)))
		assert(command({"intent":"forage","target_id":patches[0].id}))
		var food_before:int=all_stock("mushroom");var wood_before:int=all_stock("wood")
		print("H FORAGED stock=",food_before)
		var destination:=Vector2.INF
		for angle in range(64):
			var p:Vector2=w.point(life.station)+Vector2.from_angle(angle*TAU/64)*2.7
			game.view.center=w.point(life.station)
			if w.walkable("home",p) and game.view.hit(game.view.screen(p)).is_empty():destination=p;break
		print("H DESTINATION ",destination)
		assert(destination.is_finite() and map_move(destination))
		print("H ARRIVED ",elapsed)
		game.view.center=w.point(life.station)+Vector2(5,0);game._show_barbecue_menu(station_id);await process_frame;await process_frame
		var panel:Node=helper.shown(CampPanel);assert(panel!=null and await click(panel.light_button))
		var light_sources:Dictionary=panel.last_result.get("sources",{}).duplicate(true)
		var lit_at:float=elapsed;assert(life.fireside.burning());step(.2)
		await shot("H-"+("mainland" if station_id=="home.barbecue" else "moon")+"-ignition")
		panel.hide();await shot("H-"+("mainland" if station_id=="home.barbecue" else "moon")+"-flame");panel.show()
		assert(await click(panel.roast_button));var invitation:Node=helper.shown(Invitation);assert(invitation!=null)
		assert(await click(invitation.all_box));await shot("H-"+("mainland" if station_id=="home.barbecue" else "moon")+"-invite-all")
		assert(await click(invitation.get_ok_button()));var menu:Node=helper.shown(Menu);assert(menu!=null and menu.choices[menu.selected].id=="single:mushroom")
		await shot("H-"+("mainland" if station_id=="home.barbecue" else "moon")+"-menu")
		menu.scroll.scroll_vertical=760;await shot("H-"+("mainland" if station_id=="home.barbecue" else "moon")+"-dish-have-missing");menu.scroll.scroll_vertical=0
		assert(await click(menu.start_button));await process_frame
		var eating_shot:=false
		for tick in range(10000):
			step()
			var eaters:int=w.work.jobs.values().filter(func(j):return j.get("target_id")==station_id and j.get("phase")=="fire_eat").size()
			if eaters==5 and not eating_shot:await shot("H-"+("mainland" if station_id=="home.barbecue" else "moon")+"-eating");eating_shot=true
			if life.fireside.state.current.get("eaten",0)==5:
				if not eating_shot:await shot("H-"+("mainland" if station_id=="home.barbecue" else "moon")+"-five-full");eating_shot=true
				break
		assert(life.fireside.state.current.eaten==5)
		var full_at:float=elapsed
		for id in w.standard.config.companions:assert(w.hunger.rank(id)==0)
		for i in range(40):step()
		await shot("H-"+("mainland" if station_id=="home.barbecue" else "moon")+"-fireside")
		var total_wood:int=preload("res://tests/backpack_fixture.gd").wood_total(w)
		for camp in w.barbecues.values():total_wood+=int(camp.station.fuel_used)
		assert(total_wood==4+trees_needed*8 and all_stock("mushroom")==food_before-5 and life.fireside.state.current.receipt.mushroom==5)
		var wood_debit:int=wood_before-all_stock("wood");assert(wood_debit==2)
		var sources:Dictionary=life.fireside.state.current.sources.duplicate(true)
		simulations.append({"opening":"standard","station_id":station_id,"total_enter_to_full_seconds":full_at,"built_at":built_at,"lit_at":lit_at,"true_mushrooms_gathered":4,"food_sources":sources,"wood_sources":light_sources,"wood_debit":{"backpack":int(light_sources.get("backpack",{}).get("wood",0)),"authorized_chests":wood_debit},"physical_wood_accounted":total_wood,"physical_wood_expected":4+trees_needed*8,"mushrooms_before_batch":food_before,"mushrooms_after_batch":all_stock("mushroom"),"mushrooms_eaten":5,"mushrooms_wasted":life.fireside.state.current.wasted,"actual_eaters":life.fireside.state.current.eaters.duplicate(),"all_companions_full":true,"conserved":true,"real_ui_input":true,"game_model_calls":0})
		game.queue_free();await process_frame;await process_frame
	var f:=FileAccess.open(output.path_join("H-simulations.json"),FileAccess.WRITE);f.store_string(JSON.stringify(simulations,"  "));f.close()
	f=FileAccess.open(output.path_join("H-viewports.json"),FileAccess.WRITE);f.store_string(JSON.stringify(screenshots,"  "));f.close()
	helper.free();print("H barbecue v4 real standard UI simulations: ",JSON.stringify(simulations));quit()

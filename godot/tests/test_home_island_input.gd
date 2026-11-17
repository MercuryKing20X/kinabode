extends SceneTree
# DIRECTION 2026-11-11：“五座别墅只留一座”“泳池、躺椅、吊床等拿掉”“旧‘度假状态’取消”。
const UI=preload("res://tests/barbecue_ui_fixture.gd")
var failed:=false
func check(ok:bool,label:String)->void:
	if not ok:failed=true;push_error(label)
func click_at(at:Vector2)->void:
	for down in [true,false]:
		var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;e.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;e.position=at;e.global_position=at;root.push_input(e,true);await process_frame
func settle(game:Node)->void:
	for i in range(6000):
		game._process(.1)
		if not game.world.work.jobs.has("human") and not game.world._routes.has("human"):break
func capture(name:String)->void:
	var out:String=OS.get_environment("HABITAT_ISLAND_CAPTURE")
	if out.is_empty() or DisplayServer.get_name()=="headless":return
	await process_frame;await process_frame;RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(out.path_join(OS.get_environment("HABITAT_ISLAND_VARIANT")+"-"+name+".png"))
func _initialize()->void:call_deferred("run")
func run()->void:
	var game:Node=UI.init_game(self)
	configure_view()
	await process_frame;await process_frame
	check(not game.world.catalog.regions.has("homelands"),"southern land has no separate playable region")
	var initial_wood:int=game.world.storage.count("wood")
	# Additional fuel is obtained from an existing real tree by native clicks.
	for tree in game.world.objects.values():
		if tree.kind!="tree" or tree.get("status")!="mature":continue
		if game.world.storage.count("wood")>=initial_wood+3:break
		game.view.center=game.world.point(tree);game.view.follow_player=false
		await process_frame
		await click_at(game.view.screen(game.world.point(tree)))
		settle(game)
	check(game.world.storage.count("wood")>=initial_wood+3,"native tree harvest supplies actual warehouse wood")
	for patch in game.world.all_mushrooms().values():
		if patch.region_id!="home" or int(patch.amount)<1:continue
		game.view.center=game.world.point(patch);await process_frame
		await click_at(game.view.screen(game.world.point(patch)));settle(game)
		if game.world.storage.count("mushroom")+int(game.world.actors.human.carry.get("mushroom",0))>0:break
	await bridge_walk(game,Vector2(93,185),"south")
	check(game.world.home_island.here(),"World continuously walks long bridge to southern home land")
	check(game.world.objects.values().filter(func(o):return o.id.begins_with("homelands.house.") and o.region_id=="home" and o.kind=="construction_site").is_empty(),"zero retired southern build sites")
	check(game.world.barbecues.has("homelands.barbecue"),"fourth real Fireside registered")
	check(game.world.memories.records.any(func(r):return r.kind=="home_island_arrival"),"first landing retained canonical fact")
	# DIRECTION Flower Isle 2026-11-11: retain only the greenhouse, remove the shared pool.
	check(game.world.resort.config.villas.size()==1,"exactly one configured greenhouse")
	check(game.world.objects.values().filter(func(o):return str(o.id).begins_with("resort.villa.") and o.stage_index==5 and o.invested==0).size()==1,"one complete preset greenhouse with zero invented investment")
	check(game.world.resort.activities.values().filter(func(a):return a.kind=="pool").size()==0,"retired shared pool is absent")
	check(game.world.farms.farms.keys().filter(func(id):return str(id).begins_with("farm.theirs") and game.world.farms.ready(id)).is_empty(),"no southern farm available for production")
	var before:int=game.world.storage.count("wood")
	var villa:Dictionary=game.world.resort.config.villas[0]
	game.view.center=Vector2(villa.door[0],villa.door[1]);game.view.follow_player=false
	await process_frame
	await click_at(game.view.screen(Vector2(villa.door[0],villa.door[1])))
	var resort_ui:Node=game.get_node("ResortUI")
	check(is_instance_valid(resort_ui.menu) and resort_ui.menu.visible and resort_ui.target_id==villa.id,"native click opens exact existing villa card")
	check(game.world.storage.count("wood")==before,"opening a completed villa card never debits resources")
	if is_instance_valid(resort_ui.menu):check(await UI.click(self,resort_ui.menu.get_ok_button()),"native existing villa card closes")
	game.view.queue_redraw();await capture("island-villas")
	game.view.center=Vector2(81,185);await process_frame
	await click_at(game.view.screen(Vector2(81,185)));settle(game);await process_frame
	var panels:Array=game.get_children().filter(func(n):return n.get_script()==preload("res://scripts/fireside_panel.gd"))
	check(not panels.is_empty(),"native island camp opens after World approach")
	if not panels.is_empty():
		check(await UI.click(self,panels[0].light_button),"native light fourth camp")
		check(game.world.barbecues["homelands.barbecue"].fireside.burning(),"fourth camp burns using real wood")
		check(await UI.click(self,panels[0].roast_button),"native fourth camp barbecue menu")
		await process_frame
		var invitations:Array=game.get_children().filter(func(n):return n.get_script()==preload("res://scripts/fireside_invitation.gd"))
		if not invitations.is_empty():
			check(await UI.click(self,invitations[0].get_ok_button()),"native no-guest confirmation")
			await process_frame
			var menus:Array=game.get_children().filter(func(n):return n.get_script()==preload("res://scripts/fireside_menu.gd"))
			if not menus.is_empty():
				var expanders:Array=UI.descendants(menus[0]).filter(func(n):return n is Button and n.get_meta("expand_basics",false))
				check(not expanders.is_empty() and await UI.click(self,expanders[0]),"native expand basic grills")
				var buttons:Array=UI.descendants(menus[0]).filter(func(n):return n is Button and n.get_meta("menu_id","")=="single:mushroom")
				if not buttons.is_empty():menus[0].scroll.ensure_control_visible(buttons[0]);await process_frame;await process_frame
				if not buttons.is_empty():check(await UI.click(self,buttons[0]),"native actual mushroom selection")
				check(await UI.click(self,menus[0].start_button),"native start fourth fire meal")
				for tick in range(150):game._process(.1)
				check(game.world.barbecues["homelands.barbecue"].fireside.state.current.get("eaten",0)>0,"real fourth fire meal consumed")
	game.view.queue_redraw();await capture("island-camp-meal")
	await process_frame
	await bridge_walk(game,Vector2(81,108),"north")
	check(game.world.actors.human.region_id=="home" and not game.world.home_island.here(),"walks bridge back with no region switch or teleport")
	game.queue_free();await process_frame
	await formal_cat()
	print("home island native input failed=",failed);quit(1 if failed else 0)

func formal_cat()->void:
	var base:String=OS.get_environment("HABITAT_DATA_DIR")
	OS.set_environment("HABITAT_DATA_DIR",base.path_join("formal-cat"))
	OS.set_environment("HABITAT_OPENING","standard")
	var game:Node=load("res://scenes/main_v3.tscn").instantiate()
	game.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	root.add_child(game)
	configure_view()
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.view.sound_enabled=false;game.island_hud.set_process(false);game.world.director.set_all_enabled(false);game.chat.hide()
	await process_frame;await process_frame
	check(game.world.opening_id=="standard" and game.world.cat.discovered,"formal opening starts with cat on main island")
	await bridge_walk(game,Vector2(93,185),"formal-south")
	check(game.world.home_island.here(),"formal original World route reaches southern land")
	game.view.center=Vector2(79,180);game.view.follow_player=false
	await process_frame
	await click_at(game.view.screen(Vector2(79,180)))
	settle(game)
	check(game.world.cat.discovered and game.world.cat.region=="home","cat remains available after real southern walk")
	game.view.queue_redraw();await capture("formal-cat-discovered")
	await bridge_walk(game,Vector2(81,108),"formal-north")
	check(game.world.actors.human.region_id=="home" and game.world.cat.discovered and game.world.cat.region=="home","formal discovered cat follows original World bridge route home")
	game.view.queue_redraw();await capture("formal-cat-home")
	game.queue_free();await process_frame
	OS.set_environment("HABITAT_DATA_DIR",base)

func bridge_walk(game:Node,target:Vector2,label:String)->void:
	for panel in game.get_children():
		if panel is Window and panel.visible:panel.hide()
	game.view.center=target;game.view.follow_player=false
	await process_frame
	await click_at(game.view.screen(target))
	var crossed:Dictionary={};var last:Vector2=game.world.point(game.world.actors.human)
	var max_step:=0.0
	for step in range(6000):
		game._process(.1)
		var at:Vector2=game.world.point(game.world.actors.human)
		max_step=maxf(max_step,at.distance_to(last));last=at
		if at.y>115 and at.y<165:
			check(at.x>=79.5 and at.x<=82.5,"bridge motion stays on original World plank surface")
			crossed[int(at.y)/5]=true
		if not game.world._routes.has("human"):break
	check(last.distance_to(target)<1,"native destination reached "+label)
	check(max_step<=game.world.RUN_SPEED*.1+.01,"no teleport: original configured maximum continuous step "+label)
	check(crossed.size()>=9,"entire bridge actually traversed "+label)
	game.view.center=Vector2(81,142);game.view.queue_redraw();await capture(label+"-bridge")

func configure_view()->void:
	var variant:String=OS.get_environment("HABITAT_ISLAND_VARIANT")
	if variant.is_empty():return
	var pair:PackedStringArray=variant.split("-")
	TranslationServer.set_locale(pair[0]);preload("res://scripts/localization.gd").events.changed.emit()
	root.size=Vector2i(960,640) if pair[1]=="960" else Vector2i(1280,800)

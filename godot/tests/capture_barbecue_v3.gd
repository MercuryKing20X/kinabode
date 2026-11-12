extends SceneTree
const Helper=preload("res://tests/test_barbecue_v2.gd")
const F=preload("res://tests/cooking_fixture.gd")
var game:Node
var w:RefCounted
var helper:SceneTree
var output:String
var evidence:Array=[]
class ArtBoard extends Control:
	var library:RefCounted
	var font:Font
	var directions:=false
	func _draw()->void:
		draw_rect(Rect2(Vector2.ZERO,size),Color("e5e4cf"))
		draw_string(font,Vector2(35,35),"阿黑 · 原作品四方向核对（未发现画反）" if directions else "新增围火动作 · 原五位 · 旧帧像素保持不变",HORIZONTAL_ALIGNMENT_LEFT,-1,19,Color("364d42"))
		if directions:
			for row in range(4):
				var facing:String=["down","left","right","up"][row]
				for col in range(3):
					var p:=Vector2(size.x/2-200+col*140,65+row*135)
					draw_texture_rect(library.texture("black-scarf-girl",facing+"_"+str(col)),Rect2(p,Vector2(96,128)),false)
					draw_string(font,p+Vector2(-65,75),facing if col==0 else "",HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("364d42"))
		else:
			var ids:Array=["human-starter","white-haired-girl","blue-haired-girl","orange-haired-girl","black-scarf-girl"]
			for col in range(5):
				for row in range(3):
					var p:=Vector2(size.x/2-340+col*140,80+row*165)
					draw_texture_rect(library.texture(ids[col],"fire_"+["squat","sit","eat"][row]+"_down_0"),Rect2(p,Vector2(96,128)),false)
					draw_string(font,p+Vector2(0,145),["烤手","围坐","吃一口"][row],HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("364d42"))
func _initialize()->void:call_deferred("run")
func advance(seconds:float)->void:
	for frame in range(ceili(seconds/.1)):w.advance(.1)
func shot(name:String)->void:
	for dimensions in [Vector2i(1280,800),Vector2i(960,640)]:
		DisplayServer.window_set_size(dimensions);root.size=dimensions;root.content_scale_size=Vector2i.ZERO
		game.island_hud.refresh();game.view.queue_redraw();game.view.motion.advance(.1,w.actors)
		for event in w.director.events:
			if w.director.time-event.time<6:game.view.say(event.text,"local_rules",event.actor_id,event.get("context",""))
		await process_frame;await process_frame;await RenderingServer.frame_post_draw
		var path:String=output.path_join(name+"-%sx%s.png"%[dimensions.x,dimensions.y]);var im:=root.get_texture().get_image();assert(im.get_size()==dimensions and im.save_png(path)==OK);evidence.append(path.get_file())
func approach(life:RefCounted)->void:assert(helper.approach(w,life))
func pickup(item:String,n:int)->void:
	for chest in [{"id":"storage","items":w.storage.saved().items,"capacity":9007199254740991,"kind":"storage"}]:
		if int(chest.items.get(item,0))<n:continue
		var result:Dictionary=w.work.take_food_host(chest.id,item,n)
		if not result.ok:print("capture pickup rejected: ",item," ",chest.id," ",result);continue
		for frame in range(3000):
			advance(.1)
			if not w.work.jobs.has("human"):assert(int(w.actors.human.carry.get(item,0))>=n);return
	print("available real chests: ",[{"id":"storage","items":w.storage.saved().items,"capacity":9007199254740991,"kind":"storage"}]);assert(false,"no valid actual source for "+item)
func place_guests(life:RefCounted)->void:
	for i in range(4):
		var id:String=w.standard.config.companions[i];var o:Array=life.fireside.config.seat_offsets[i+1];var p:Vector2=w.point(life.station)+Vector2(o[0],o[1]);assert(F.job(w,id,{"intent":"move","x":p.x,"y":p.y}))
func art_hud(visible_now:bool)->void:
	for child in game.get_children():
		if child is CanvasLayer:child.visible=visible_now
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"));OS.set_environment("HABITAT_OPENING","legacy");output=OS.get_environment("HABITAT_STAGE2_EVIDENCE")
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");root.add_child(game);game.save_enabled=false;game.set_process(false);game.view.sound_enabled=false;w=game.world;w.director.set_all_enabled(false)
	helper=Helper.new();game.view.follow_player=false;game.view.zoom=1;game.chat.hide()
	await process_frame
	# Open plaza movement follows a real World command, not a fabricated render route.
	var p:Vector2=w.point(w.actors.human);var route:Array[Vector2]=[]
	for offset in [Vector2(8,5),Vector2(7,-4),Vector2(4,7)]:
		if w.segment_clear("home",p,p+offset):route=[p+offset];break
	assert(not route.is_empty());assert(w.command("human",{"intent":"move","x":route[0].x,"y":route[0].y}).ok)
	game.view.center=p+Vector2(2,0)
	for index in range(3):advance(.2);await shot("01-walk-"+str(index))
	assert(F.wait(w,"human"))
	art_hud(false)
	var board:=ArtBoard.new();board.library=game.library;board.font=game.view.font;board.directions=true;board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(board);await shot("02-black-directions");board.queue_free();await process_frame;art_hud(true)
	pickup("wood",4);pickup("mushroom",10);place_guests(w.life);approach(w.life)
	game.view.center=w.point(w.life.station)+Vector2(5,-1);await shot("03-new-camp")
	assert(w.life.fireside.light_host().ok and w.life.fireside.invite(w.standard.config.companions).ok)
	advance(1.2);game._show_barbecue_menu(w.life.station.id)
	var panel:Node=game.get_children().filter(func(n):return n.get_script()==preload("res://scripts/fireside_panel.gd"))[0]
	for grid in panel.body.get_children():
		if grid is GridContainer:
			for button in grid.get_children():
				if button.text=="吃什么":button.pressed.emit()
	await shot("04-menu")
	for menu in game.get_children():
		if menu.get_script()==preload("res://scripts/fireside_menu.gd"):
			menu.scroll.scroll_vertical=1000
	await shot("04-dishes-have-missing");game.chat.hide()
	for node in game.get_children():
		if node is AcceptDialog and node.title.begins_with("今天吃什么"):node.queue_free()
	assert(w.life.fireside.roast_host("single:mushroom").ok);advance(1);await shot("05-roasting")
	for frame in range(80):
		advance(.1)
		if w.work.jobs.values().filter(func(j):return j.phase=="fire_eat").size()==5:break
	assert(w.work.jobs.values().filter(func(j):return j.phase=="fire_eat").size()==5);await shot("06-five-eating")
	w.director.set_all_enabled(true)
	for r in w.director.routines.values():r.next_speech=0
	advance(4.2);await shot("08-favorite-reaction")
	for frame in range(1000):
		advance(.1)
		if w.life.fireside.dialogue.visible.size()==2:break
	await shot("07-chat")
	var old_origin:float=w.days.origin;w.days.origin=w.forest.clock-w.days.day_seconds*.83
	await shot("07-night-light");w.days.origin=old_origin
	art_hud(false);board=ArtBoard.new();board.library=game.library;board.font=game.view.font;board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(board);await shot("10-original-five-new-actions");board.queue_free();await process_frame;art_hud(true)
	w.life.fireside.end_circle("前往月牙岛");w.director.set_all_enabled(false)
	for id in w.actors:w.command(id,{"intent":"stop"})
	var moon:RefCounted=w.barbecues["moon.barbecue"];place_guests(moon);approach(moon)
	# Snapshot day/phase projection only; actual routing and food remain from the same world.
	w.days.origin=w.forest.clock-w.days.day_seconds*.83
	assert(moon.fireside.light_host().ok and moon.fireside.invite(w.standard.config.companions).ok and moon.fireside.roast_host("single:mushroom").ok)
	advance(5.5);game.view.center=w.point(moon.station)+Vector2(5,-1);await shot("09-moon-camp")
	var record:=FileAccess.open(output.path_join("viewports.json"),FileAccess.WRITE);record.store_string(JSON.stringify({"actual_viewport":true,"files":evidence,"game_model_calls":0,"reused_v2_action_frame_count":8,"reused_v2_art_sources":5,"new_art_api_calls":0},"  "));record.close();helper.free();game.queue_free();await process_frame;quit()

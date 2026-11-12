extends SceneTree
## Real viewport mouse route; no actor-coordinate or artwork mutations.
const UI=preload("res://tests/barbecue_ui_fixture.gd")
var game:Node
var output:String
var records:Array=[]
var failures:=0
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	if not ok:failures+=1;push_error(label)
func shot(label:String)->void:
	game.view.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join(label+".png"))
func mouse(at:Vector2,button:int=MOUSE_BUTTON_LEFT)->void:
	for down in [true,false]:
		var e:=InputEventMouseButton.new();e.position=at;e.global_position=at;e.button_index=button;e.pressed=down;e.button_mask=MOUSE_BUTTON_MASK_LEFT if down and button==MOUSE_BUTTON_LEFT else 0;root.push_input(e,true);await process_frame
func human_outfit()->bool:
	var menus:Array=UI.descendants(game).filter(func(n):return n is MenuButton and n.text=="设置" and n.is_visible_in_tree())
	if menus.size()!=1:return false
	var opening:=InputEventMouseButton.new();opening.position=menus[0].get_global_rect().get_center();opening.global_position=opening.position;opening.button_index=MOUSE_BUTTON_LEFT;opening.pressed=true;opening.button_mask=MOUSE_BUTTON_MASK_LEFT;root.push_input(opening,true);await process_frame
	var popup:PopupMenu=menus[0].get_popup();var selected:=false
	var index:int=popup.get_item_index(90)
	var at:Vector2=Vector2(popup.position)+Vector2(popup.size.x*.5,(index+.5)*popup.size.y/popup.item_count)
	await mouse(at)
	await process_frame
	selected=not popup.visible
	if not selected:
		print("HUMAN MENU ",popup.visible," position=",popup.position," size=",popup.size," count=",popup.item_count," embedded=",popup.is_embedded())
		await shot("settings-menu-debug");return false
	var confirms:Array=UI.descendants(game).filter(func(n):return n is ConfirmationDialog and n.visible and n.title=="我自己的外观")
	if confirms.size()!=1 or not await UI.click(self,confirms[0].get_ok_button()):return false
	await process_frame;await process_frame
	var panel:Node=game.island_hud.wardrobe
	var label:String=game.library.artworks["ai-gpt"].name
	var choices:Array=UI.descendants(panel.grid).filter(func(n):return n is Button and n.text.begins_with(label))
	if choices.size()!=1:return false
	var target:Button=choices[0];var scroll:ScrollContainer=panel.grid.get_parent()
	for attempt in range(30):
		if scroll.get_global_rect().has_point(target.get_global_rect().get_center()):break
		await mouse(scroll.get_global_rect().get_center(),MOUSE_BUTTON_WHEEL_DOWN)
	if not await UI.click(self,target):return false
	var apply:Array=UI.descendants(panel).filter(func(n):return n is Button and n.text=="确定")
	if apply.size()!=1 or not await UI.click(self,apply[0]):return false
	await process_frame
	confirms=UI.descendants(game).filter(func(n):return n is ConfirmationDialog and n.visible and n.title=="更换我的外观")
	if confirms.size()!=1 or not await UI.click(self,confirms[0].get_ok_button()):return false
	return game.world.actors.human.appearance_id=="ai-gpt"
func run_route(label:String)->void:
	var w:RefCounted=game.world
	var start:Vector2=w.point(w.actors.human);var target:=Vector2.INF
	for offset in [Vector2(45,0),Vector2(-45,0),Vector2(0,45),Vector2(0,-45)]:
		if w.walkable("home",start+offset) and not w.find_route("human",start+offset).is_empty():target=start+offset;break
	check(target.is_finite(),"far walkable destination "+label)
	if not target.is_finite():return
	game.view.center=target;game.view.zoom=1.25;game.view.follow_player=false;await process_frame
	await mouse(game.view.screen(target))
	check(w._routes.has("human"),"real ground click creates route "+label)
	for index in range(60):
		game._process(.05);game.view._process(.05);game.view.center=w.point(w.actors.human)+Vector2(0,-1)
		var motion:Dictionary=w.motion_state("human");var atlas:Dictionary=game.view.action_atlases.spec("run",game.library,w.actors.human)
		records.append({"case":label,"index":index,"position":w.actors.human.position.duplicate(),"running":w.is_running("human"),"moving":motion.moving,"facing":motion.facing,"appearance":w.actors.human.appearance_id,"atlas":not atlas.is_empty(),"column":game.view.motion.run_column("human",w.intelligence.gait("human")),"run_pixels":game.view.motion.states.human.get("run_pixels",0)})
		await shot(label+"-run-%02d"%index)
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"))
	output=OS.get_environment("HABITAT_MOTION_EVIDENCE");DirAccess.make_dir_recursive_absolute(output)
	OS.set_environment("HABITAT_OPENING","legacy");root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");root.add_child(game);await process_frame;await process_frame
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.view.sound_enabled=false;game.island_hud.set_process(false);game.chat.hide();game.world.director.set_all_enabled(false)
	var w:RefCounted=game.world
	for dimensions in [Vector2i(1280,800),Vector2i(960,640)]:
		DisplayServer.window_set_size(dimensions);root.size=dimensions;await process_frame
		game.view.center=w.point(w.actors.human);game.view.follow_player=false
		for zoom in [1.0,1.25]:
			game.view.zoom=zoom;await shot("camera-%dx%d-%.2f"%[dimensions.x,dimensions.y,zoom])
	root.size=Vector2i(1280,800);DisplayServer.window_set_size(root.size);await process_frame
	if OS.get_environment("MOTION_UI_ONLY").is_empty():await run_route("human")
	check(await human_outfit(),"real settings/wardrobe selects nondefault human appearance")
	await run_route("ai-gpt")
	var f:=FileAccess.open(output.path_join("trace.json"),FileAccess.WRITE);f.store_string(JSON.stringify(records,"  "));f.close()
	print("Motion camera capture failures=",failures)
	game.queue_free();await process_frame;quit(1 if failures else 0)

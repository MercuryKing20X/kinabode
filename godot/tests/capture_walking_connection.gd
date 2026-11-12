extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
var game:Node
var bridge_shot:=false
func _initialize()->void:call_deferred("run")
func mouse(at:Vector2)->void:
	for down in [true,false]:
		var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.position=at;e.global_position=at;e.pressed=down;e.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;root.push_input(e,true);await process_frame
func press(text:String)->void:
	var buttons:Array=UI.descendants(game.dark_ui.menu).filter(func(n):return n is Button and n.text==text)
	assert(buttons.size()==1);assert(await UI.click(self,buttons[0]))
func walk_region(region:String)->void:
	for tick in range(12000):
		game._process(.05);game.view._process(.05);game.dark_ui._process(.05)
		if not bridge_shot and game.world.actors.human.region_id=="home" and game.world.point(game.world.actors.human).y<12:
			bridge_shot=true;game.view.queue_redraw();await process_frame;await process_frame;RenderingServer.force_draw(false)
			root.get_texture().get_image().save_png(OS.get_environment("HABITAT_DARK_EVIDENCE").path_join("actually-walking-on-bridge.png"))
		if game.world.actors.human.region_id==region and not game.world._routes.has("human"):return
	assert(false,"real bridge traversal must arrive")
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"))
	game=UI.init_game(self);await process_frame;await process_frame
	var w:RefCounted=game.world
	# All coordinates below are camera positions or mouse destinations, never actor writes.
	for id in ["home","dark"]:
		var at:Vector2=w.dark.p(w.dark.config.walking_connection.home_end if id=="home" else w.dark.config.walking_connection.dark_end)
		assert(w.walkable(id,at))
	game.view.center=Vector2(129,20);game.view.queue_redraw();await process_frame
	await mouse(game.view.screen(Vector2(129,17)))
	await press("叫伙伴一起去")
	var all:Array=UI.descendants(game.dark_ui.menu).filter(func(n):return n is CheckBox and n.text=="所有人")
	assert(all.size()==1 and await UI.click(self,all[0]))
	await press("选好了");await press("出发")
	await walk_region("dark")
	assert(w.point(w.actors.human).distance_to(Vector2(34,101))<.2)
	assert(w.actors.values().all(func(a):return a.region_id=="dark"),"all selected companions actually walk together")
	game.view.queue_redraw();await process_frame;await process_frame;RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("HABITAT_DARK_EVIDENCE").path_join("walked-to-dark.png"))
	await mouse(game.view.screen(Vector2(34,105)));await press("回主岛")
	await walk_region("home")
	assert(w.point(w.actors.human).distance_to(Vector2(129,20))<.2)
	assert(w.actors.values().all(func(a):return a.region_id=="home"),"all return together")
	# Direct ground clicks at the seam also cross without a boat/confirmation dialog.
	game.view.center=Vector2(129,8);game.view.queue_redraw();await process_frame
	await mouse(game.view.screen(Vector2(129,1)));await walk_region("dark")
	game.view.center=Vector2(34,127);game.view.queue_redraw();await process_frame
	await mouse(game.view.screen(Vector2(34,127)))
	await walk_region("home")
	# Equal world tile units on the atlas; seam coordinates agree on both sides.
	var home_origin:Vector2=Vector2(w.catalog.regions.home.origin[0],w.catalog.regions.home.origin[1])
	var dark_origin:Vector2=Vector2(w.catalog.regions.dark.origin[0],w.catalog.regions.dark.origin[1])
	assert(home_origin+Vector2(129,0)==dark_origin+Vector2(34,128))
	game.atlas.world=w;game.atlas.focus("home");var scale:float=game.atlas.scale_factor
	assert(is_equal_approx(game.atlas.screen_position(home_origin+Vector2(160,0)).distance_to(game.atlas.screen_position(home_origin)),160*scale))
	game.atlas.fit_regions(["home","dark"]);game.atlas.visible=true;await process_frame;await process_frame;RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("HABITAT_DARK_EVIDENCE").path_join("equal-scale-map.png"))
	game.queue_free();await process_frame
	print("Walking bridge mouse round trip and exact atlas tile/seam scale passed")
	quit()

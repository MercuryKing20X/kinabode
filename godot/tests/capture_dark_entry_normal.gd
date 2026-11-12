extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
var game:Node
var bridge_shown:=false
func _initialize()->void:call_deferred("run")
func shot(name:String)->void:
	await process_frame;await process_frame;RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("HABITAT_DARK_EVIDENCE").path_join(name+".png"))
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"))
	game=UI.init_game(self);await process_frame;await process_frame
	# Normal scene processing, normal starting camera. No manual world/UI advance,
	# camera coordinates, actor coordinates or internal action calls.
	game.set_process(true);game.view.set_process(true);game.island_hud.set_process(true)
	await shot("normal-start-visible-entry")
	assert(game.dark_ui.entry_button.is_visible_in_tree())
	assert(await UI.click(self,game.dark_ui.entry_button))
	var buttons:Array=UI.descendants(game.dark_ui.menu).filter(func(n):return n is Button and n.text=="出发")
	assert(buttons.size()==1 and await UI.click(self,buttons[0]))
	assert(game.view.follow_player)
	var arrived:=false
	for tick in range(900):
		await create_timer(.1).timeout
		if not bridge_shown and game.world.actors.human.region_id=="home" and game.world.point(game.world.actors.human).y<4:
			bridge_shown=true;await shot("normal-near-bridge-visible-other-island")
		if game.world.actors.human.region_id=="dark" and not game.world._routes.has("human"):
			arrived=true;break
	assert(arrived,"normal real frame processing must walk from original start into dark")
	await shot("normal-walk-arrived-dark")
	assert(game.world.point(game.world.actors.human).distance_to(Vector2(34,101))<.3)
	# Pan with actual right-drag, then click the visible other side of the map seam.
	var start:=Vector2(640,400)
	var down:=InputEventMouseButton.new();down.button_index=MOUSE_BUTTON_RIGHT;down.pressed=true;down.position=start;root.push_input(down,true);await process_frame
	for index in range(3):
		var motion:=InputEventMouseMotion.new();motion.position=start+Vector2(0,-200*(index+1));motion.relative=Vector2(0,-200);motion.button_mask=MOUSE_BUTTON_MASK_RIGHT;root.push_input(motion,true);await process_frame
	var up:=InputEventMouseButton.new();up.button_index=MOUSE_BUTTON_RIGHT;up.pressed=false;up.position=Vector2(640,0);root.push_input(up,true);await process_frame
	# One more smaller drag keeps the ground target above the bottom HUD.
	down=InputEventMouseButton.new();down.button_index=MOUSE_BUTTON_RIGHT;down.pressed=true;down.position=start;root.push_input(down,true);await process_frame
	var extra:=InputEventMouseMotion.new();extra.position=Vector2(640,0);extra.relative=Vector2(0,-400);extra.button_mask=MOUSE_BUTTON_MASK_RIGHT;root.push_input(extra,true);await process_frame
	up=InputEventMouseButton.new();up.button_index=MOUSE_BUTTON_RIGHT;up.pressed=false;up.position=Vector2(640,0);root.push_input(up,true);await process_frame
	var target:Vector2=game.view.screen(Vector2(34,130))
	assert(Rect2(Vector2(0,100),Vector2(900,550)).has_point(target),"cross-seam target visible after genuine drag")
	for pressed in [true,false]:
		var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=pressed;click.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0;click.position=target;root.push_input(click,true);await process_frame
	var returned:=false
	for tick in range(900):
		await create_timer(.1).timeout
		if game.world.actors.human.region_id=="home" and not game.world._routes.has("human"):returned=true;break
	assert(returned,"clicking neighboring region must route across the bridge rather than reject coordinates")
	await shot("normal-cross-seam-click-returned")
	assert(game.links.values().all(func(link):return link._pid<=0))
	game.queue_free();await process_frame
	print("Normal camera + visible entry button + actual engine frames reach dark, no manual advance")
	quit()

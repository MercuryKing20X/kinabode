extends "res://tests/test_dialogue_bar_input.gd"
func run()->void:
	OS.set_environment("HABITAT_OPENING","showcase")
	var game:Node=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false)
	root.size=Vector2i(1280,800);await frames()
	check(game.view.follow_actor=="human","camera follows the player by default")
	game.view.follow_player=false;game.view.center+=Vector2(20,20)
	var key:=InputEventKey.new();key.pressed=true;key.keycode=KEY_SPACE;root.push_input(key,true);await frames()
	check(game.view.follow_player and game.view.center.distance_to(game.world.point(game.world.actors.human))<.01,"Space centers human")
	game.view.follow_player=false;game.view.center+=Vector2(20,20)
	for i in 51:game.view._process(.1)
	check(game.view.follow_player,"temporary view returns after five seconds")
	game.connection_overview.open();await frames();await capture("connection-five-points")
	var points:Array=UI.descendants(game.connection_overview).filter(func(n):return n.get_script()==preload("res://scripts/reasoning_points.gd"))
	check(points.size()==4 and points[0].get_child(0).get_popup().item_count==5,"five choices per resident")
	await select_level(points[0],4);await frames();await capture("lifeblood-warning-shallow")
	var dialogs:Array=UI.descendants(points[0]).filter(func(n):return n is ConfirmationDialog)
	check(dialogs.size()==1 and dialogs[0].visible and dialogs[0].get_ok_button().disabled,"warning requires acknowledgement")
	dialogs[0].hide();game.connection_overview.hide()
	game.island_hud.show_card("codex");await frames()
	check(await select_level(game.island_hud.reasoning_points,2),"avatar selects deep")
	check(game.resident_connections.preferences.preference("codex").level=="high","shared runtime setting updates")
	game.island_hud.resident_card.hide();game.book_panel.open();await frames()
	check(await select_level(game.book_panel.reasoning_points,0),"memory header selects light")
	await capture("memory-five-points")
	check(game.resident_connections.preferences.preference("codex").level=="low","memory and runtime synchronized")
	game.book_panel.hide();game.connection_overview.open();await frames();await capture("connection-synchronized")
	game.queue_free();await frames();print("CAMERA_POINTS ",checks," failed=",failed);quit(1 if failed else 0)

func select_level(points:Node,index:int)->bool:
	var button:MenuButton=points.get_child(0)
	if not await UI.click(self,button):return false
	await frames()
	var popup:PopupMenu=button.get_popup()
	if not popup.visible:return false
	var viewport:Viewport=popup
	var at:=Vector2(popup.size.x/2.0,popup.size.y*(index+.5)/popup.item_count)
	if popup.is_embedded():at+=Vector2(popup.position);viewport=root
	for pressed in [true,false]:
		var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=pressed;click.position=at;click.global_position=at;viewport.push_input(click,true);await frames()
	return true

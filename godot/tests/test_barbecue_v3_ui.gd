extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
var checks:=0
var failed:=false
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failed=true;push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	OS.set_environment("HABITAT_OPENING","legacy")
	var game:Node=load("res://scenes/main_v3.tscn").instantiate();game.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");root.add_child(game);game.save_enabled=false;game.set_process(false);game.view.sound_enabled=false
	var before:Dictionary=game.world.actors.human.duplicate(true);var stock:Dictionary=game.world.life.fireside.available()
	for dimensions in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=dimensions
		for mode in ["小","标准","大"]:
			game.island_hud.set_interface_size(mode,false)
			var menu:AcceptDialog=preload("res://scripts/fireside_menu.gd").new();game.add_child(menu);menu.setup(game.world.life,game.view.font);menu.popup_centered();await process_frame;await process_frame
			check(menu.size.x<=dimensions.x-20 and menu.size.y<=dimensions.y-20,"menu fits "+str(dimensions)+mode)
			check(menu.scroll.get_v_scroll_bar().max_value>menu.scroll.size.y,"both sections remain reachable through scrolling")
			check(menu.choices[0].id=="single:mushroom" and menu.choices.any(func(c):return c.category=="dish"),"two menu sections and mushroom first")
			check(not menu.get_property_list().any(func(p):return p.name=="amount") and not UI.descendants(menu).any(func(n):return n is SpinBox),"quantity controls completely absent")
			check(not UI.descendants(menu).any(func(n):return n is Label and (n.text.contains("份") or n.text.contains("剩菜") or n.text.contains("打包"))),"no serving count leftovers or packing copy")
			check(UI.descendants(menu).any(func(n):return n is Button and n.disabled and n.text=="缺少食材"),"unavailable cards remain visible disabled")
			check(menu.start_button.size.x>=180 and menu.start_button.size.y>=42,"large roast button")
			menu.scroll.scroll_vertical=10000;await process_frame
			for card in menu.cards:
				check(card.size.x<=menu.scroll.size.x and card.size.x>180,"card grid stays inside viewport")
			menu.queue_free();await process_frame
	check(game.world.actors.human==before and game.world.life.fireside.available()==stock,"read-only menu never moves human or changes resources")
	game.queue_free();await process_frame;print("Barbecue v3 UI: ",checks," checks, failed=",failed);quit(1 if failed else 0)

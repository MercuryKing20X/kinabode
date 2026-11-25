extends "res://tests/test_simple_connection_input.gd"
# B: DIRECTION 2026-11-09: [对话/指令][地图][托管]，对话框平时收起。
func run()->void:
	OS.set_environment("HABITAT_OPENING","showcase")
	var game:Node=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false)
	root.content_scale_size=Vector2i.ZERO;await frames()
	for dimensions in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=dimensions;await frames();game.island_hud.layout_primary_actions();await frames()
		check(not game.chat.visible,"collapsed default "+str(dimensions))
		var buttons:Array=game.watch_ui.bar.get_children().filter(func(n):return n is Button and n.visible)
		check(buttons==[game.dialogue_button,game.journey.map_button,game.island_hud.watch_button,game.gathering_button],"exactly ordered four buttons")
		check(absf(game.watch_ui.bar.get_global_rect().get_center().x-dimensions.x/2.0)<3,"centered")
		await capture("closed-"+str(dimensions.x))
		check(await UI.click(self,game.dialogue_button),"real open click")
		check(game.chat.visible and game.chat.is_ancestor_of(game.action_dock.action_tabs),"commands and chat one panel")
		await capture("open-"+str(dimensions.x))
		check(await UI.click(self,game.dialogue_button) and not game.chat.visible,"real reclick collapse")
		await UI.click(self,game.dialogue_button);game.chat_input.grab_focus()
		var key:=InputEventKey.new();key.keycode=KEY_ESCAPE;key.pressed=true;root.push_input(key,true);await frames()
		check(not game.chat.visible and not game.chat_input.has_focus(),"Escape collapses and releases focus")
	game.queue_free();await frames();print("DIALOGUE_BAR ",checks," failed=",failed);quit(1 if failed else 0)
func capture(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	var directory:String=OS.get_environment("HABITAT_UI_EVIDENCE")
	if directory.is_empty():return
	DirAccess.make_dir_recursive_absolute(directory);await process_frame;RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(directory.path_join(name+".png"))

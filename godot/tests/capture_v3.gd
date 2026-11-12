extends SceneTree
var game:Node
func _initialize()->void:call_deferred("run")
func run()->void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	game=load("res://scenes/main.tscn").instantiate();root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.world.director.set_all_enabled(false);game.view.set_process(false);game.view.sound_enabled=false
	for child in game.get_children():
		if child is CanvasLayer and "--ui" not in OS.get_cmdline_user_args():child.hide()
	var args:=OS.get_cmdline_user_args();var camera:="plaza";var output:="/tmp/v3.png"
	for arg in args:
		if arg.begins_with("--camera="):camera=arg.trim_prefix("--camera=")
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg=="--night":
			for n in range(16000):
				if game.world.days.phase().id=="night":break
				game.world.advance(.1)
	var p:Array=game.world.catalog.regions.home.layout.art_cameras[camera]
	game.view.center=Vector2(p[0],p[1]);game.view.follow_player=false;game.view.zoom=1
	if camera=="island":game.view.overview=true;game.view.overview_factor=5 if root.size.x>=1280 else 6
	for arg in args:
		if arg.begins_with("--card="):game.island_hud.show_card(arg.trim_prefix("--card="))
	game.island_hud.refresh()
	game.view.queue_redraw();await process_frame;await process_frame;await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output);print("Viewport: ",output);quit()

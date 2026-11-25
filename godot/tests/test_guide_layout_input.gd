extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-"))
	OS.set_environment("HABITAT_OPENING","standard");root.size=Vector2i(1280,800)
	var game:Node=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.chat.hide()
	await process_frame;await process_frame
	var out:String=OS.get_environment("GUIDE_CAPTURE")
	var failures:Array=[]
	for locale in ["zh","en"]:
		preload("res://scripts/localization.gd").select(dir,locale)
		for dimensions in [Vector2i(960,640),Vector2i(1280,800)]:
			root.size=dimensions
			for index in range(4):
				game.ui_scale.set_level(index);game.journey._process(.01);game.dark_ui._process(.01);game.island_hud.refresh();await process_frame;await process_frame
				var controls:Array=[game.day_label,game.handbook_menu,game.island_hud.find_child("WorldDoor",true,false),game.island_hud.find_child("WorldPlacement",true,false),game.island_hud.residents_panel]
				for i in controls.size():
					if not controls[i].is_visible_in_tree():continue
					var rect:Rect2=controls[i].get_global_rect()
					if not Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(rect):failures.append("bounds "+locale+str(dimensions)+str(index)+str(i)+str(rect))
					for j in range(i+1,controls.size()):
						if controls[j].is_visible_in_tree() and rect.intersects(controls[j].get_global_rect()):failures.append("overlap "+locale+str(dimensions)+str(index)+str([i,j]))
				if not out.is_empty() and DisplayServer.get_name()!="headless":await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(out.path_join(locale+"-"+str(dimensions.x)+"-"+str(index)+".png"))
	print("GUIDE_LAYOUT failures=",failures)
	game.queue_free();await process_frame;quit(1 if not failures.is_empty() else 0)

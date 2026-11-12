extends SceneTree
const World=preload("res://scripts/world_state.gd")
var game:Node
var output:String
func _initialize()->void:call_deferred("run")
func shot(name:String)->void:
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var img:=root.get_texture().get_image();img.save_png(output.path_join(name+".png"))
func run()->void:
	var dir:=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-test-"));output=OS.get_environment("HABITAT_WARDROBE_EVIDENCE");assert(not output.is_empty())
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=World.new("res://content/home-v3/world.json");root.add_child(game)
	game.save_enabled=false;game.view.sound_enabled=false;game.set_process(false);game.world.director.set_all_enabled(false)
	var hud:Control=game.island_hud
	for size in [Vector2i(1280,800),Vector2i(960,640)]:
		DisplayServer.window_set_size(size);root.size=size;root.content_scale_size=Vector2i.ZERO
		await process_frame;await process_frame
		var suffix:="-%sx%s"%[size.x,size.y]
		hud.open_appearance("codex");await shot("01-wardrobe"+suffix)
		hud.wardrobe.selected_work="ai-gpt";hud.wardrobe.apply_selection();game.view.center=game.world.point(game.world.actors.codex);game.view.queue_redraw();await shot("02-applied"+suffix)
		var settings:MenuButton
		for node in hud.get_children():
			if node is HBoxContainer:
				for child in node.get_children():
					if child is MenuButton and child.text=="设置":settings=child
		if settings!=null:settings.get_popup().id_pressed.emit(90);await shot("03-human-confirm"+suffix)
		for node in hud.ui_root.get_children():
			if node is ConfirmationDialog and node.title=="我自己的外观":node.canceled.emit()
		game._toggle_workshop();game.editor.open_art("human-starter");hud.refresh();await shot("04-workshop"+suffix)
		var menus:Array=game.editor.find_children("*","MenuButton",true,false)
		for menu in menus:
			if menu.text=="文件 ▾":menu.show_popup();break
		await shot("05-files"+suffix)
		for menu in menus:menu.get_popup().hide()
		game.editor.close_workshop();hud.set_interface_size("大");hud.refresh();await shot("06-large-ui"+suffix)
		var ids:=["human","codex","companion-2","npc.mira","npc.nora"]
		var center:Array=game.world.map_anchor("plaza.center")
		for i in range(ids.size()):
			var actor:Dictionary=game.world.actors[ids[i]];actor.position=[float(center[0])+float(i-2)*3,float(center[1])+5];actor.activity="idle";actor.facing="down"
			actor.appearance_id=["human-starter","white-haired-girl","blue-haired-girl","orange-haired-girl","black-scarf-girl"][i]
		game.view.center=Vector2(center[0],center[1]+4);game.view.motion.advance(15,game.world.actors)
		var strip:=GridContainer.new();strip.columns=5;hud.ui_root.add_child(strip);strip.position=Vector2(50,100)
		for frame_index in range(3):
			for work_id in ["human-starter","white-haired-girl","blue-haired-girl","orange-haired-girl","black-scarf-girl"]:
				var portrait:=TextureRect.new();portrait.texture=game.library.texture(work_id,"think_down_"+str(frame_index));portrait.custom_minimum_size=Vector2(100,120);portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;portrait.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;strip.add_child(portrait)
		game.view.queue_redraw();await shot("07-five-poses"+suffix);strip.queue_free();await process_frame
		var routine:RefCounted=game.world.director.routines.codex;routine.enabled=true;routine.time=200;routine.visual_quiet_until=0
		game.view.motion.time=float(40-posmod(hash("codex"),40));game.view.motion.states.codex.activity_age=15.0
		game.view.queue_redraw();await shot("08-scene"+suffix)
		routine.enabled=false
		hud.set_interface_size("标准");hud.refresh();await shot("09-layout"+suffix)
	game.queue_free();await process_frame;await create_timer(.5).timeout
	print("Wardrobe viewport captures completed")
	quit()

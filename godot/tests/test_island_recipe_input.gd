extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
var failed:=false
func check(ok:bool,msg:String)->void:
	if not ok:failed=true;push_error(msg)
func _initialize()->void:call_deferred("run")
func mouse(at:Vector2)->void:
	for down in [true,false]:
		var e:=InputEventMouseButton.new();e.position=at;e.global_position=at;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;e.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;root.push_input(e,true);await process_frame
func click(button:BaseButton)->bool:
	for i in range(2):await process_frame
	return await UI.click(self,button)
func run()->void:
	DirAccess.make_dir_recursive_absolute("/tmp/youqi-recipe-capture")
	var dir:String=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-test-"));OS.set_environment("HABITAT_OPENING","legacy")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO;DisplayServer.window_move_to_foreground()
	var w:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");w.residents.provision(w);w.library=preload("res://scripts/character_library.gd").new();w.library.configure(dir);assert(preload("res://scripts/world_opening.gd").apply(w,w.library,"showcase").ok);w.intelligence.activate_presets();w.hunger.start()
	w.world_id="playtest-speech-fixed-1031"
	for id in w.director.routines:w.director.routines[id].rng.seed=hash("speech-input:"+str(id))
	var g:Node=load("res://scenes/main_v3.tscn").instantiate();g.world=w;root.add_child(g);g.save_enabled=false;g.set_process(false);g.view.set_process(false);g.island_hud.set_process(false);g.chat.hide();print("speech input init");await process_frame;await process_frame
	g.view.center=w.point(w.life.station);g.view.follow_player=false;g.view.zoom=1
	await mouse(g.view.screen(w.point(w.life.station)))
	for i in range(5000):
		g._process(.05);g.view._process(.05)
		if UI.shown(g,"res://scripts/fireside_panel.gd")!=null:break
	print("speech input walked");var panel:Node=UI.shown(g,"res://scripts/fireside_panel.gd");check(panel!=null,"mouse fire route opens panel")
	if panel==null:quit(1);return
	check(await click(panel.light_button),"mouse lights real fire");check(await click(panel.roast_button),"mouse barbecue")
	print("speech input opened invitation");var invite:Node=UI.shown(g,"res://scripts/fireside_invitation.gd");check(invite!=null,"invitation opens")
	if invite==null:quit(1);return
	check(await click(invite.all_box) and await click(invite.get_ok_button()),"mouse invites all")
	print("speech input opened menu");var menu:Node=UI.shown(g,"res://scripts/fireside_menu.gd");check(menu!=null,"menu opens")
	if menu==null:quit(1);return
	for lang in ["zh_CN","en"]:
		preload("res://scripts/localization.gd").select(dir,lang)
		for dimensions in [Vector2i(960,640),Vector2i(1280,800)]:
			root.size=dimensions;menu.refresh_locale();await process_frame;await process_frame;menu.reset_size();menu.fit();await process_frame;await process_frame
			RenderingServer.force_draw(false)
			root.get_texture().get_image().save_png("/tmp/youqi-recipe-capture/"+lang+"-"+str(dimensions.x)+".png")
	print("RECIPE_CAPTURE menu choices=",menu.choices.size()," failed=",failed)
	g.queue_free();await process_frame;quit(1 if failed else 0)

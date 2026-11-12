extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
var checks:=0
func verify(ok:bool,message:String)->void:
	checks+=1
	if not ok:push_error(message);quit(1)
func _initialize()->void:call_deferred("run")
func click(control:Control)->void:
	await UI.click(self,control)
	await process_frame
func wait_frames()->void:
	for i in range(40):await process_frame
func shot(name:String)->void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("/tmp/youqi-title-demo/"+name+".png")
func run()->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-"));DirAccess.make_dir_recursive_absolute("/tmp/youqi-title-demo")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	var w:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");w.residents.provision(w)
	var library:=preload("res://scripts/character_library.gd").new();library.configure(dir)
	preload("res://scripts/world_opening.gd").apply(w,library,"showcase");w.intelligence.activate_presets()
	var pos:Vector2=w.point(w.actors.human)
	verify(Save.save_world(w,dir),"fixture saved")
	var title:Node=load("res://scenes/title.tscn").instantiate();root.add_child(title);current_scene=title;await wait_frames()
	verify(title.menu.get_child(0).name=="continue","continue first");await shot("zh-1280")
	await click(title.languages.get_node("en"));verify(title.heading.text=="Kinabode","instant English")
	root.size=Vector2i(960,640);DisplayServer.window_set_size(root.size);await wait_frames();await shot("en-960")
	await click(title.menu.get_node("settings"));verify(title.audio_dialog.visible,"shared settings open")
	await click(title.audio_dialog.get_ok_button());verify(not title.audio_dialog.visible,"settings close")
	await click(title.menu.get_node("continue"));await wait_frames()
	var game:Node=current_scene;verify(game.get("world")!=null,"continue entered game");verify(game.world.point(game.world.actors.human).distance_to(pos)<.01,"saved human position");verify(game.language=="en","game language synced")
	game.set_process(false)
	# Open the actual game menu and select its actual Return to Title entry.
	var menus:Array=UI.descendants(game).filter(func(n):return n is MenuButton and n.get_popup().get_item_index(101)>=0)
	verify(menus.size()==1,"return item exists")
	await click(menus[0]);await process_frame
	var pop:PopupMenu=menus[0].get_popup();var index:int=pop.get_item_index(101)
	# Popup input is local to its viewport.
	for down in [true,false]:
		var e:=InputEventMouseButton.new();e.position=Vector2(30,18);e.button_index=1;e.pressed=down;e.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0
		var vp:Viewport=pop
		if pop.is_embedded():e.position+=Vector2(pop.position);vp=root
		var motion:=InputEventMouseMotion.new();motion.position=e.position;vp.push_input(motion,true);vp.push_input(e,true);await process_frame
	await wait_frames()
	# Remaining new-game flow runs in the same title scene through real controls.
	if current_scene==game:
		verify(false,"return title real popup input");game.save_enabled=false;game.queue_free();await process_frame
		title=load("res://scenes/title.tscn").instantiate();root.add_child(title);current_scene=title
	else:title=current_scene
	await wait_frames();verify(title.language=="en","language survives recreated title")
	await click(title.menu.get_node("new"));var dialogs:Array=title.get_children().filter(func(n):return n is ConfirmationDialog)
	verify(dialogs.size()==1,"overwrite confirmation")
	# DIRECTION: 新游戏直接开正式开局，不再问开局类型。
	var backup_service=title.backups
	await click(dialogs[0].get_ok_button());await wait_frames()
	verify(backup_service.archives().size()>0,"backup exists before direct standard entry")
	game=current_scene;verify(game.world.standard.active(),"new standard island");game.save_enabled=false
	print("TITLE_INPUT_CHECKS ",checks);quit()

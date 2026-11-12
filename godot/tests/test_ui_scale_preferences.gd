extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
const Scale=preload("res://scripts/ui_scale.gd")
var failed:=false
var checks:=0
func check(ok:bool,text:String)->void:
	checks+=1
	if not ok:failed=true;push_error(text)
func _initialize()->void:call_deferred("run")
func run()->void:
	var temp:String=OS.get_environment("HABITAT_DATA_DIR");assert(temp.contains("youqi-"))
	var game:Node=UI.init_game(self);await process_frame;await process_frame
	check(game.ui_scale.level==2 and is_equal_approx(Scale.factor(),1.3),"fresh local settings default genuinely 130 percent")
	var base:int=game.dialogue_button.get_meta("ui_scale_base_font_size")
	check(game.dialogue_button.get_theme_font_size("font_size")==roundi(base*1.3),"actual button font is baseline times130 percent")
	var zoom:float=game.view.zoom
	game._open_audio_settings();for i in range(4):await process_frame
	var slider:HSlider=null
	for node in UI.descendants(game.audio_dialog):
		if node is HSlider and node.max_value==3:slider=node
	check(slider!=null,"settings contains four step slider")
	if slider!=null:
		slider.grab_focus()
		for code in [KEY_HOME,KEY_RIGHT]:
			for pressed in [true,false]:
				var key:=InputEventKey.new();key.keycode=code;key.pressed=pressed
				var viewport:Viewport=slider.get_viewport()
				if viewport is Window and viewport.is_embedded():viewport=root
				viewport.push_input(key,true);await process_frame
		check(game.ui_scale.level==1 and is_equal_approx(Scale.factor(),1.1),"native keyboard slider changes level immediately")
		var cfg:=ConfigFile.new();cfg.load(temp.path_join("local-life.cfg"));check(cfg.get_value("interface","scale_index",-1)==1,"UI choice persists only in local cfg")
		game._save_local_settings();cfg.load(temp.path_join("local-life.cfg"))
		check(cfg.get_value("interface","scale_index",-1)==1,"routine preference save preserves freshly changed UI scale")
		check(game.view.zoom==zoom,"native UI preference leaves camera zoom unchanged")
	game.audio_dialog.hide();await process_frame
	game.island_hud.refresh()
	check(await UI.click(self,game.dialogue_button),"native dialogue entry remains clickable")
	check(game.chat.visible and not game.island_hud.context.visible and not game.island_hud.utility_actions.visible and not game.island_hud.residents_panel.visible,"opening chat synchronously clears input-covering overlays")
	check(await UI.click(self,game.dialogue_button),"bottom chat toggle remains clickable while chat is open")
	check(not game.chat.visible,"bottom toggle closes focused chat")
	game.game_audio.shutdown();game.queue_free();await process_frame;await create_timer(.1).timeout
	# Loading old three-level preference has no world/save involvement.
	for pair in [["hud.size_small",0],["hud.size_standard",1],["hud.size_large",2]]:
		var directory:String=temp.path_join(str(pair[1]));DirAccess.make_dir_recursive_absolute(directory)
		var cfg:=ConfigFile.new();cfg.set_value("interface","size",preload("res://scripts/localization.gd").source(pair[0]));cfg.save(directory.path_join("local-life.cfg"))
		var host:=Node.new();root.add_child(host);var ui:=Control.new();ui.size=Vector2(960,640);host.add_child(ui);var manager:=Scale.new();host.add_child(manager);manager.setup(host,ui,directory)
		check(manager.level==pair[1],"old preference migrates "+pair[0]);host.queue_free();await process_frame
	print("UI scale preferences: ",checks," checks; native keyboard and local cfg migration")
	quit(1 if failed else 0)

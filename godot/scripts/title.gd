extends Control
const Text=preload("res://scripts/localization.gd")
var memory_books=preload("res://scripts/memory_books.gd").new()
var connection_panel:Control
var book_panel:Control
var about_panel:Control
var version_label:Label
var data_dir:=""
var language:="zh"
var world:RefCounted
var view:Node
var island_hud:Node
var local_settings:=ConfigFile.new()
var game_audio:Node
var audio_dialog:AcceptDialog
var backups:=preload("res://scripts/save_backup.gd").new()
var ui_scale:Node
var menu:VBoxContainer
var heading:Label
var languages:HBoxContainer
var fade:ColorRect
var elapsed:=0.0
var entering:=false
func _ready()->void:
	ProjectSettings.set_setting("application/config/version",preload("res://scripts/game_version.gd").VERSION)
	get_window().content_scale_size=Vector2i.ZERO
	if OS.get_environment("HABITAT_SKIP_TITLE")=="1" or "--skip-title" in OS.get_cmdline_user_args() or DisplayServer.get_name()=="headless" or Array(OS.get_cmdline_user_args()).any(func(a):return a.begins_with("--snapshot=") or a.begins_with("--scenario=") or a.begins_with("--opening=") or a=="--fresh-world"):
		get_tree().change_scene_to_file.call_deferred("res://scenes/main_v3.tscn");return
	data_dir=OS.get_environment("HABITAT_DATA_DIR")
	if data_dir.is_empty():data_dir=ProjectSettings.globalize_path("user://")
	DirAccess.make_dir_recursive_absolute(data_dir)
	language=Text.configure(data_dir);backups.setup(data_dir)
	var theme_data:=Theme.new();theme_data.default_font=preload("res://assets/fonts/NotoSansSC.ttf");theme=theme_data
	if ResourceLoader.exists("res://assets/title/night.png"):
		var background:=TextureRect.new();background.texture=load("res://assets/title/night.png");background.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;background.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_COVERED;background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);background.show_behind_parent=true;background.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(background)
	var veil:=ColorRect.new();veil.color=Color(0.015,0.035,0.07,.32);veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);veil.show_behind_parent=true;veil.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(veil)
	heading=Label.new();heading.set_meta("ui_font_base",52);heading.add_theme_font_override("font",preload("res://assets/fonts/NotoSerifSC-Black.ttf"));heading.add_theme_color_override("font_color",Color("ffdfa0"));heading.add_theme_color_override("font_outline_color",Color("251d30"));heading.add_theme_constant_override("outline_size",8);add_child(heading)
	menu=VBoxContainer.new();menu.add_theme_constant_override("separation",14);add_child(menu)
	languages=HBoxContainer.new();languages.add_theme_constant_override("separation",12);add_child(languages)
	for locale in ["zh","en"]:
		var button:=Button.new();button.focus_mode=Control.FOCUS_NONE;button.name=locale;button.text=Text.text("title.zh") if locale=="zh" else "English";button.pressed.connect(func():Text.select(data_dir,locale));languages.add_child(button)
	ui_scale=preload("res://scripts/ui_scale.gd").new();add_child(ui_scale);ui_scale.setup(self,self,data_dir);ui_scale.changed.connect(func(_i):_layout())
	Text.events.changed.connect(_refresh)
	memory_books.setup(data_dir)
	book_panel=preload("res://scripts/memory_book_panel.gd").new();add_child(book_panel);book_panel.setup(memory_books)
	connection_panel=preload("res://scripts/connection_overview.gd").new();add_child(connection_panel);connection_panel.setup(data_dir)
	about_panel=preload("res://scripts/about_panel.gd").new();add_child(about_panel)
	version_label=Label.new();version_label.text=preload("res://scripts/game_version.gd").short_label();version_label.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(version_label)
	_refresh();resized.connect(_layout)
	# Reuse the exact game audio preference implementation without starting a world.
	var silent_world:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	view=preload("res://scripts/island_view.gd").new()
	game_audio=preload("res://scripts/game_audio.gd").new();add_child(game_audio);game_audio.setup(silent_world,view,data_dir);game_audio.set_process(false)
	_layout.call_deferred()
	fade=ColorRect.new();fade.color=Color.BLACK;fade.mouse_filter=Control.MOUSE_FILTER_IGNORE;fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(fade);create_tween().tween_property(fade,"color:a",0.0,.25)
func _refresh()->void:
	language="en" if Text.revision().begins_with("en") else "zh"
	heading.text=Text.text("title.name")
	for child in menu.get_children():menu.remove_child(child);child.queue_free()
	if FileAccess.file_exists(data_dir.path_join("island-v2.json")):_button("continue",func():_enter())
	_button("new",_new_game);_button("connections",func():connection_panel.open());_button("memory",func():book_panel.open());_button("about",func():about_panel.open());_button("settings",_open_audio_settings);_button("quit",func():get_tree().quit())
	for button in languages.get_children():button.modulate=Color("ffd482") if button.name==language else Color("8d9daa")
	_layout()
	menu.get_child(0).grab_focus()
func _button(key:String,action:Callable)->void:
	var button:=Button.new();button.focus_mode=Control.FOCUS_NONE;button.set_meta("ui_font_base",20);button.set_meta("ui_scale_min",Vector2(0,42));button.name=key;button.text=Text.text("title."+key);button.pressed.connect(action);menu.add_child(button)
func _layout()->void:
	if menu==null:return
	var factor:float=preload("res://scripts/ui_scale.gd").factor()
	heading.position=Vector2(size.x*.07,size.y*.12);heading.add_theme_font_size_override("font_size",int(52*factor))
	var count:int=maxi(1,menu.get_child_count())
	var available:float=size.y*.62-32
	var gap:float=minf(14,available*.03)
	menu.add_theme_constant_override("separation",int(gap))
	var height:float=minf(42*factor,(available-gap*(count-1))/count)
	menu.position=Vector2(size.x*.07,size.y*.32);menu.size=Vector2(minf(size.x*.3,320),0)
	for button in menu.get_children():button.custom_minimum_size=Vector2(0,height);button.add_theme_font_size_override("font_size",mini(int(20*factor),int(height*.55)))
	languages.position=Vector2(size.x-240,size.y-66)
	if version_label!=null:version_label.position=Vector2(24,size.y-40)
func _new_game()->void:
	if FileAccess.file_exists(data_dir.path_join("island-v2.json")):
		var dialog:=ConfirmationDialog.new();dialog.dialog_text=Text.text("title.overwrite");dialog.ok_button_text=Text.text("title.confirm");dialog.cancel_button_text=Text.text("title.cancel");add_child(dialog)
		dialog.confirmed.connect(func():
			var result:Dictionary=backups.backup()
			if not result.ok:dialog.dialog_text=backups.last_error;dialog.popup_centered();return
			_start_standard())
		dialog.popup_centered(Vector2i(560,180))
	else:_start_standard()
func _start_standard()->void:
	get_tree().set_meta("title_fresh",true);get_tree().set_meta("title_opening","standard");_enter()
func _pick_opening()->void:
	var dialog:=AcceptDialog.new();dialog.title=Text.text("title.choose");add_child(dialog)
	var box:=VBoxContainer.new();dialog.add_child(box)
	for id in ["standard","showcase"]:
		var button:=Button.new();button.focus_mode=Control.FOCUS_NONE;button.text=Text.text("title."+id);box.add_child(button);button.pressed.connect(func():dialog.hide();get_tree().set_meta("title_fresh",true);get_tree().set_meta("title_opening",id);_enter())
	dialog.popup_centered(Vector2i(680,200))
func _enter()->void:
	if entering:return
	entering=true
	fade.mouse_filter=Control.MOUSE_FILTER_STOP
	await create_tween().tween_property(fade,"color:a",1.0,.25).finished
	get_tree().set_meta("title_transition",true)
	get_tree().change_scene_to_file("res://scenes/main_v3.tscn")
func _open_audio_settings()->void:
	preload("res://scripts/audio_settings_panel.gd").open(self)
func _process(delta:float)->void:
	elapsed+=delta;queue_redraw()
func _draw()->void:
	var center:=Vector2(size.x*.64,size.y*.62)
	for i in range(9,0,-1):draw_circle(center,12+i*12,Color(1,.45,.12,(.006+.002*sin(elapsed*7))*float(10-i)))
	for i in range(10):
		var star:=Vector2(size.x*(.15+i*.079),size.y*(.04+fmod(i*.037,.17)))
		draw_rect(Rect2(star,Vector2(2,2)),Color(1,.95,.8,maxf(0,sin(elapsed*.6+i*3))*.75))
	for i in range(7):
		var p:=Vector2(size.x*(.45+i*.065)+sin(elapsed*.5+i)*18,size.y*.65+sin(elapsed*.8+i*2)*65)
		draw_rect(Rect2(p,Vector2(3,3)),Color(1,.9,.4,.5+.4*sin(elapsed+i)))
func _exit_tree()->void:
	if is_instance_valid(game_audio):game_audio.shutdown()
	if is_instance_valid(view):view.free()

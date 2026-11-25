extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
static func open(host:Node)->void:
	if host.audio_dialog!=null:host.audio_dialog.hide();host.audio_dialog.queue_free()
	host.audio_dialog=AcceptDialog.new();host.audio_dialog.title=LocalText.text("ui.audio.title");host.add_child(host.audio_dialog)
	var box:=VBoxContainer.new();host.audio_dialog.add_child(box);box.custom_minimum_size=Vector2(430,0)
	if host.ui_scale!=null:host.ui_scale.add_settings(box)
	if host.world!=null:
		var follow_toggle:=CheckButton.new();follow_toggle.focus_mode=Control.FOCUS_NONE;follow_toggle.text=LocalText.text("ui.main.follow");follow_toggle.button_pressed=not host.world.activities.following.is_empty();box.add_child(follow_toggle)
		follow_toggle.toggled.connect(func(value):
			host.local_settings.set_value("follow","enabled",value);host.local_settings.save(host.data_dir.path_join("local-life.cfg"))
			host.world.activities.set_followers(host.world.actors.keys().filter(func(id):return id!="human") if value else []))
	var language_row:=HBoxContainer.new();box.add_child(language_row)
	var language_label:=Label.new();language_label.text=LocalText.text("ui.language.label");language_row.add_child(language_label)
	var language_picker:=OptionButton.new();language_picker.focus_mode=Control.FOCUS_NONE;language_picker.add_item(LocalText.text("ui.language.zh"));language_picker.add_item("English")
	language_picker.select(1 if host.language=="en" else 0);language_row.add_child(language_picker)
	language_picker.item_selected.connect(func(index):
		host.language="en" if index==1 else "zh"
		LocalText.select(host.data_dir,host.language);host._open_audio_settings())
	var toggle:=CheckButton.new();toggle.focus_mode=Control.FOCUS_NONE;toggle.text=LocalText.text("ui.audio.sound_toggle");toggle.button_pressed=host.game_audio.enabled;box.add_child(toggle)
	toggle.toggled.connect(func(value):host.game_audio.enabled=value;host.game_audio.apply_mix();host.game_audio.persist())
	var speech_toggle:=CheckButton.new();speech_toggle.focus_mode=Control.FOCUS_NONE;speech_toggle.text=LocalText.text("ui.audio.speech_toggle");speech_toggle.button_pressed=host.game_audio.speech_enabled;box.add_child(speech_toggle)
	speech_toggle.toggled.connect(func(value):host.game_audio.speech_enabled=value;host.game_audio.apply_mix();host.game_audio.persist())
	for key in ["master","Music","Ambience","Effects","Voices"]:
		var row:=HBoxContainer.new();box.add_child(row);var caption:=Label.new();caption.text=LocalText.text({"master":"ui.audio.master","Music":"ui.audio.music","Ambience":"ui.audio.ambience","Effects":"ui.audio.effects","Voices":"ui.audio.voices"}[key]);caption.custom_minimum_size.x=90;row.add_child(caption)
		var slider:=HSlider.new();slider.min_value=0;slider.max_value=1;slider.step=.01;slider.value=host.game_audio.master if key=="master" else host.game_audio.levels[key];slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL;slider.custom_minimum_size.x=250;row.add_child(slider)
		slider.value_changed.connect(func(value):
			if key=="master":host.game_audio.master=value
			else:host.game_audio.levels[key]=value
			host.game_audio.apply_mix();host.game_audio.persist())
	var unfocused:=CheckButton.new();unfocused.focus_mode=Control.FOCUS_NONE;unfocused.text=LocalText.text("ui.audio.mute_unfocused");unfocused.button_pressed=host.game_audio.mute_unfocused;box.add_child(unfocused)
	unfocused.toggled.connect(func(value):host.game_audio.mute_unfocused=value;host.game_audio.apply_mix();host.game_audio.persist())
	var test_button:=Button.new();test_button.focus_mode=Control.FOCUS_NONE;test_button.text=LocalText.text("ui.audio.test");box.add_child(test_button)
	var music_note:=Label.new();music_note.text=host.game_audio.music_status();box.add_child(music_note)
	var test_note:=Label.new();box.add_child(test_note)
	host.game_audio.sound_test_finished.connect(test_note.set_text)
	test_button.pressed.connect(func():test_note.text=LocalText.text("ui.audio.playing");host.game_audio.test_sounds())
	var music_button:=Button.new();music_button.focus_mode=Control.FOCUS_NONE;music_button.text=LocalText.text("ui.music.preview");box.add_child(music_button)
	music_button.pressed.connect(func():preload("res://scripts/music_preview.gd").open(host.audio_dialog,host.game_audio))
	if not host.game_audio.error.is_empty():var note:=Label.new();note.text=host.game_audio.error;box.add_child(note)
	var backup_note:=Label.new();backup_note.text=host.backups.summary();backup_note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;backup_note.custom_minimum_size.x=400;box.add_child(backup_note)
	var backup_button:=Button.new();backup_button.focus_mode=Control.FOCUS_NONE;backup_button.text=LocalText.text("ui.backup.open");box.add_child(backup_button)
	backup_button.pressed.connect(func():
		var folder:String=host.backups.folder()
		if folder.is_empty():backup_note.text=LocalText.text("ui.backup.unavailable");return
		if not DirAccess.dir_exists_absolute(folder) and DirAccess.make_dir_recursive_absolute(folder)!=OK:backup_note.text=LocalText.text("ui.backup.open_failed");return
		if OS.shell_open(folder)!=OK:backup_note.text=LocalText.text("ui.backup.open_failed"))
	host.audio_dialog.popup_centered()

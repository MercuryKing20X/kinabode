extends RefCounted
const Text=preload("res://scripts/localization.gd")
static func finish(audio:Node)->void:
	if not is_instance_valid(audio) or not audio.music_preview_active:return
	audio.music_preview_active=false
	for i in range(audio.active.size()-1,-1,-1):
		if str(audio.active[i].key).begins_with("sound-test:music."):audio.recycle(audio.active[i].player);audio.active.remove_at(i)
	if audio.observer!=null and not audio.shutting_down:audio.observer.environment()
static func open(host:Node,audio:Node)->AcceptDialog:
	var existing:=host.get_node_or_null("MusicPreview")
	if existing!=null:return existing
	var dialog:=AcceptDialog.new();dialog.name="MusicPreview";dialog.title=Text.text("ui.music.preview")
	dialog.theme=Theme.new();dialog.theme.default_font=load("res://assets/fonts/NotoSansSC.ttf");dialog.theme.default_font_size=16
	host.add_child(dialog)
	audio.music_preview_active=true
	# Suspend only scene music immediately; all bus settings and ducking stay intact.
	for item in audio.active:
		if str(item.event).begins_with("music.") and not str(item.key).begins_with("sound-test:"):
			item.target=0.0;item.gain=0.0;item.player.volume_db=-80.0
	var scroll:=ScrollContainer.new();scroll.custom_minimum_size=Vector2(500,350);dialog.add_child(scroll)
	var box:=VBoxContainer.new();scroll.add_child(box);box.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	for scene in ["day","dusk","night","rain","fireside","moon","dark","their"]:
		var id:String="music."+scene
		var row:=HBoxContainer.new();box.add_child(row)
		var button:=Button.new();button.focus_mode=Control.FOCUS_NONE;button.text=Text.text("ui.music."+scene);row.add_child(button)
		if not audio.catalog.events.has(id):
			button.disabled=true
			var empty:=Label.new();empty.text=Text.text("ui.audio.music_empty");row.add_child(empty);continue
		var source:Dictionary=audio.catalog.sources[id]
		var label:=Label.new();label.text=str(source.parameters.title)+" · "+str(source.parameters.author)+" · "+str(source.license);box.add_child(label)
		var link:=LinkButton.new();link.text=source.url;box.add_child(link);link.pressed.connect(func():OS.shell_open(source.url))
		button.pressed.connect(func():
			for i in range(audio.active.size()-1,-1,-1):
				if str(audio.active[i].key).begins_with("sound-test:music."):audio.recycle(audio.active[i].player);audio.active.remove_at(i)
			audio.play_event(id,Vector2.ZERO,"","",1,1,"sound-test:"+id))
	dialog.visibility_changed.connect(func():
		if dialog.visible:return
		finish(audio);dialog.queue_free())
	dialog.tree_exiting.connect(func():finish(audio))
	dialog.popup_centered()
	return dialog

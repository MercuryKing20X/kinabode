extends PanelContainer
const Text=preload("res://scripts/localization.gd")
var books:RefCounted
var world:RefCounted
var reasoning_points:Control
var partner:OptionButton
var tabs:OptionButton
var rows:VBoxContainer
var note:Label
var quotes:CheckBox
var offset:=0
var residents:Array=[]
var locale_labels:Dictionary={}
func T(key:String)->String:
	var full_key:String="memory."+key
	var value:String=Text.text(full_key)
	locale_labels[value]=full_key
	# Static footer widgets survive locale switches in both directions.
	for translated in Text.entries.get(full_key,{}).values():locale_labels[str(translated)]=full_key
	return value
func refresh_locale()->void:
	for node in _descendants(self):
		if node is Button or node is Label:
			if locale_labels.has(node.text):node.text=Text.text(locale_labels[node.text])
	for i in 5:tabs.set_item_text(i,T(["days","about","mail","album","portrait"][i]))
	if visible:refresh()
func _descendants(node:Node)->Array:
	var result:Array=[]
	for child in node.get_children():result.append(child);result.append_array(_descendants(child))
	return result
func setup(store:RefCounted,source:RefCounted=null)->void:
	books=store;world=source;z_index=200
	Text.events.changed.connect(refresh_locale)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER);offset_left=-350;offset_right=350;offset_top=-270;offset_bottom=270
	var style:=StyleBoxFlat.new();style.bg_color=Color("243542");style.set_content_margin_all(18);add_theme_stylebox_override("panel",style)
	var column:=VBoxContainer.new();add_child(column)
	var head:=HBoxContainer.new();column.add_child(head)
	partner=OptionButton.new();head.add_child(partner);partner.item_selected.connect(func(_i):offset=0;refresh())
	tabs=OptionButton.new();head.add_child(tabs)
	for key in ["days","about","mail","album","portrait"]:tabs.add_item(T(key))
	tabs.item_selected.connect(func(_i):offset=0;refresh());button(head,T("close"),hide)
	reasoning_points=preload("res://scripts/reasoning_points.gd").new();column.add_child(reasoning_points)
	var scroll:=ScrollContainer.new();scroll.custom_minimum_size=Vector2(660,360);column.add_child(scroll)
	rows=VBoxContainer.new();rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(rows)
	var paging:=HBoxContainer.new();column.add_child(paging)
	button(paging,T("previous"),func():offset=maxi(0,offset-10);refresh());button(paging,T("next"),func():offset+=10;refresh())
	quotes=CheckBox.new();quotes.text=T("exclude");column.add_child(quotes)
	var footer:=HBoxContainer.new();column.add_child(footer)
	button(footer,T("export_html"),func():choose(false,"html"));button(footer,T("export_data"),func():choose(false,"json"));button(footer,T("import"),func():choose(true,"json"))
	note=Label.new();column.add_child(note);hide()
func button(parent:Node,text:String,callback:Callable)->Button:
	var b:=Button.new();b.focus_mode=Control.FOCUS_NONE;b.text=text;b.pressed.connect(callback);parent.add_child(b);return b
func open()->void:
	residents=[]
	if world!=null:
		for id in world.actors:
			if id!="human":residents.append(id)
	for entry in books.entries.values():
		if entry.resident_id not in residents:residents.append(entry.resident_id)
	partner.clear()
	for id in residents:partner.add_item(Text.resident(world,id) if world!=null and world.actors.has(id) else Text.text({"codex":"resident.snow","companion-2":"resident.skye","npc.mira":"resident.clem","npc.nora":"resident.raven"}.get(id,"resident.unknown")))
	offset=0;show();refresh()
func refresh()->void:
	for child in rows.get_children():rows.remove_child(child);child.queue_free()
	if residents.is_empty():note.text=T("empty");return
	var pool:Node=preload("res://scripts/connection_session_pool.gd").obtain(get_tree(),books.directory.get_base_dir())
	reasoning_points.setup(books.directory.get_base_dir(),world.world_id if world!=null else pool.ledger_world,residents[partner.selected])
	var layer:String=["facts","about_you","letters","","about_you"][tabs.selected]
	var entries:Array=books.list_for(residents[partner.selected],layer)
	if tabs.selected==4:
		var portraits:Array=entries.filter(func(e):return e.params.get("kind","")=="portrait")
		if not portraits.is_empty():entries=portraits.slice(-1)
		elif world==null or not world.director.model_controlled(residents[partner.selected]):
			var intro:=Label.new();intro.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;intro.text=T("portrait_local").replace("{notes}"," / ".join(entries.map(func(e):return books.render(e))));rows.add_child(intro)
	if offset>=entries.size():offset=maxi(0,entries.size()-10)
	note.text=str(entries.size())+" · "+str(offset+1)
	for entry in entries.slice(offset,offset+10):
		var row:=HBoxContainer.new();rows.add_child(row)
		var label:=Label.new();label.text=Time.get_date_string_from_unix_time(int(entry.at))+" · "+books.render(entry);label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(label)
		button(row,T("delete"),func():books.remove(entry.id);refresh())
		var photo:String=books.photo_path(str(entry.photo_id if not entry.photo_id.is_empty() else entry.params.get("attachment","")))
		if not photo.is_empty() and FileAccess.file_exists(photo):
			var image:=Image.load_from_file(photo)
			if image!=null:
				var picture:=TextureRect.new();picture.texture=ImageTexture.create_from_image(image);picture.custom_minimum_size=Vector2(320,200);picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;rows.add_child(picture)
		if entry.layer=="letters":
			if world!=null and world.library!=null and world.actors.has(entry.resident_id):
				var artwork:Dictionary=world.library.artworks.get(world.library.visual_appearance(world.actors[entry.resident_id]),{})
				if not artwork.is_empty():
					var portrait:=TextureRect.new();portrait.texture=ImageTexture.create_from_image(world.library.render(artwork,"idle_down" if artwork.frames.has("idle_down") else artwork.frames.keys()[0]));portrait.custom_minimum_size=Vector2(48,64);portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;rows.add_child(portrait)
			var signature:=Label.new();signature.text=T("signature").replace("{name}",books.display_name(entry.resident_id));rows.add_child(signature)
		if entry.params.get("goal_status","")=="offered":
			button(row,T("agree"),func():books.decide_goal(entry.id,true);refresh())
			button(row,T("decline"),func():books.decide_goal(entry.id,false);refresh())
func choose(importing:bool,extension:String)->void:
	var dialog:=FileDialog.new();dialog.access=FileDialog.ACCESS_FILESYSTEM;dialog.file_mode=FileDialog.FILE_MODE_OPEN_FILE if importing else FileDialog.FILE_MODE_SAVE_FILE;dialog.filters=PackedStringArray(["*."+extension]);add_child(dialog)
	dialog.file_selected.connect(func(path:String):
		if importing:
			var result:Dictionary=books.import_data(path);refresh();note.text=T("imported") if result.ok else T("invalid_data")
		elif extension=="html":note.text=T("done") if books.export_html(path,not quotes.button_pressed) else T("failed")
		else:note.text=T("done") if books.export_data(path) else T("failed")
		dialog.queue_free())
	dialog.popup_centered_ratio(.8)

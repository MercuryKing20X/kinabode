extends Control
## Read-only repository documents; no world or connection is created here.
const Text=preload("res://scripts/localization.gd")
var panel:PanelContainer
var body:RichTextLabel
var close_button:Button
func _ready()->void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter=Control.MOUSE_FILTER_STOP
	var shade:=ColorRect.new();shade.color=Color(0,0,0,.65);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(shade)
	shade.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:hide())
	panel=PanelContainer.new();add_child(panel)
	var background:=StyleBoxFlat.new();background.bg_color=Color("18212a");background.border_color=Color("b6a67c");background.set_border_width_all(1);background.set_corner_radius_all(6);panel.add_theme_stylebox_override("panel",background)
	var margin:=MarginContainer.new();panel.add_child(margin)
	for side in ["left","right","top","bottom"]:margin.add_theme_constant_override("margin_"+side,16)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",12);margin.add_child(column)
	body=RichTextLabel.new();body.name="document";body.bbcode_enabled=true;body.size_flags_vertical=Control.SIZE_EXPAND_FILL;body.selection_enabled=true;body.focus_mode=Control.FOCUS_ALL;body.meta_clicked.connect(_open_link);column.add_child(body)
	close_button=Button.new();close_button.pressed.connect(hide);column.add_child(close_button)
	resized.connect(_layout);Text.events.changed.connect(_refresh)
	_refresh();hide()
func open()->void:
	show();move_to_front();_refresh();body.grab_focus()
func _refresh()->void:
	close_button.text=Text.text("about.close")
	_layout();show_document()
func _layout()->void:
	if panel==null:return
	var bounds:=get_viewport_rect().size
	panel.position=Vector2(20,20);panel.size=bounds-Vector2(40,40)
	var factor:float=preload("res://scripts/ui_scale.gd").factor()
	var font_size:=mini(int(18*factor),int((bounds.x-100)/40))
	body.add_theme_font_size_override("normal_font_size",int(18*factor));body.add_theme_font_size_override("bold_font_size",int(18*factor));close_button.add_theme_font_size_override("font_size",font_size)
func document_path(english:bool)->String:
	var name:="about"+(".en" if english else "")+".md"
	if not OS.has_feature("editor"):return "res://content/about/"+name
	return ProjectSettings.globalize_path("res://").path_join("../docs/"+name).simplify_path()
func show_document()->void:
	if body==null:return
	var english:=Text.revision().begins_with("en")
	var path:=document_path(english)
	body.clear()
	if english and not FileAccess.file_exists(path):
		body.append_text(Text.text("about.missing")+"\n\n");path=document_path(false)
	if not FileAccess.file_exists(path):return
	var file:=FileAccess.open(path,FileAccess.READ)
	var comment:=false
	for line in file.get_as_text().split("\n"):
		if line.strip_edges().begins_with("<!--"):comment=true
		if comment:
			if "-->" in line:comment=false
			continue
		if line.begins_with("!["):
			var image_re:=RegEx.new();image_re.compile("^!\\[.*?\\]\\(([^)]+)\\)$")
			var match:=image_re.search(line)
			if match!=null:
				var image_path:=path.get_base_dir().path_join(match.get_string(1)).simplify_path()
				# Optional local images only, inside the about document directory.
				if image_path.begins_with(path.get_base_dir()+"/") and FileAccess.file_exists(image_path):
					var image:=preload("res://scripts/bundled_image.gd").read(image_path)
					if image!=null:
						var width:=mini(image.get_width(),int(panel.size.x-64));body.add_image(ImageTexture.create_from_image(image),width,int(float(width)*image.get_height()/image.get_width()));body.append_text("\n")
			continue
		var content:=_inline(line)
		if line.strip_edges()=="---":content="[color=#b6a67c]────────────────────────[/color]"
		if line.begins_with("# "):content="[font_size="+str(int(26*preload("res://scripts/ui_scale.gd").factor()))+"][b]"+_inline(line.substr(2))+"[/b][/font_size]"
		elif line.begins_with("## "):content="[font_size="+str(int(23*preload("res://scripts/ui_scale.gd").factor()))+"][b]"+_inline(line.substr(3))+"[/b][/font_size]"
		elif line.begins_with("### "):content="[font_size="+str(int(20*preload("res://scripts/ui_scale.gd").factor()))+"][b]"+_inline(line.substr(4))+"[/b][/font_size]"
		elif line.begins_with("- "):content="• "+_inline(line.substr(2))
		body.append_text(content+"\n")
	body.scroll_to_line(0)
func _inline(value:String)->String:
	var regex:=RegEx.new();regex.compile("\\[([^]\\n]+)\\]\\((https?://[^)]+)\\)")
	var result:="";var cursor:=0
	for match in regex.search_all(value):
		result+=value.substr(cursor,match.get_start()-cursor).replace("[","[lb]")
		result+="[url="+match.get_string(2).replace("]","%5D")+"]"+match.get_string(1).replace("[","[lb]")+"[/url]";cursor=match.get_end()
	result+=value.substr(cursor).replace("[","[lb]")
	var bold:=RegEx.new();bold.compile("\\*\\*(.+?)\\*\\*")
	return bold.sub(result,"[b]$1[/b]",true)
func _open_link(value:Variant)->void:
	var url:=str(value)
	if url.begins_with("https://") or url.begins_with("http://"):OS.shell_open(url)
func _unhandled_key_input(event:InputEvent)->void:
	if visible and event.is_action_pressed("ui_cancel"):hide();get_viewport().set_input_as_handled()

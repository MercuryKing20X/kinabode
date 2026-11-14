extends PanelContainer
const Text=preload("res://scripts/localization.gd")
var world:RefCounted
var library:RefCounted
var actor_id:=""
var body:RichTextLabel
var portrait:TextureRect
var heading:Label
var elapsed:=0.0
func setup(w:RefCounted,art:RefCounted)->void:
	world=w;library=art
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left=-300;offset_right=300;offset_top=-255;offset_bottom=255
	var style:=StyleBoxFlat.new();style.bg_color=Color("213e37");style.set_content_margin_all(20);style.set_corner_radius_all(14);add_theme_stylebox_override("panel",style)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",12);add_child(column)
	var row:=HBoxContainer.new();column.add_child(row)
	portrait=TextureRect.new();portrait.custom_minimum_size=Vector2(64,80);portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;portrait.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;row.add_child(portrait)
	heading=Label.new();heading.add_theme_font_size_override("font_size",24);heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(heading)
	var close:=Button.new();close.text="×";close.set_meta("ui_font_base",16);close.custom_minimum_size=Vector2(36,32);close.pressed.connect(hide);row.add_child(close)
	body=RichTextLabel.new();body.bbcode_enabled=false;body.size_flags_vertical=Control.SIZE_EXPAND_FILL;body.add_theme_font_size_override("normal_font_size",16);body.set_meta("ui_font_base",16);column.add_child(body)
	z_index=100;hide()
func open(id:String)->void:
	if not world.director.brains.has(id):return
	actor_id=id;refresh();show()
func refresh()->void:
	var brain:RefCounted=world.director.brains[actor_id]
	var summary:Dictionary=brain.summary()
	heading.text=Text.resident(world,actor_id)+" · "+brain.text("title")
	portrait.texture=library.texture(world.actors[actor_id].appearance_id,"down_0")
	var lines:Array=[summary.sentence,"",brain.text("needs")]
	lines.append(" · ".join(summary.needs.values()))
	lines.append("");lines.append(brain.text("recent"))
	for entry in summary.recent:
		var at:float=float(entry.at)
		lines.append("%02d:%02d  %s · %s"%[int(at)/60,int(at)%60,brain.action_name(entry.choice),brain.text(entry.outcome) if entry.outcome!="running" else "…"])
	body.text="\n".join(lines)
func _process(delta:float)->void:
	if not visible or actor_id.is_empty():return
	elapsed+=delta
	if elapsed>=1:elapsed=0;refresh()
func _unhandled_key_input(event:InputEvent)->void:
	if visible and event.is_action_pressed("ui_cancel"):hide();get_viewport().set_input_as_handled()

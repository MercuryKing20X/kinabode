extends Control
const LocalText=preload("res://scripts/localization.gd")
signal selected(entry: Dictionary)
var entry: Dictionary={}
var renderer: RefCounted
var rules: Dictionary
var font: Font
var chosen:=false
func _ready() -> void:
	custom_minimum_size=Vector2(154,96);mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND;focus_mode=Control.FOCUS_ALL
func _draw() -> void:
	if entry.is_empty() or font==null:return
	var caught: bool=entry.caught
	var box:=StyleBoxFlat.new();box.bg_color=Color("fff0ce") if caught else Color("d7d1b9");box.border_color=Color("b4824b") if chosen else Color("b9b29b");box.set_border_width_all(3 if chosen else 1);box.set_corner_radius_all(7);draw_style_box(box,Rect2(Vector2.ZERO,size))
	var tex: Texture2D=renderer.texture(entry.species_id,entry.color_id,rules)
	var factor:=minf(minf(size.x-32,96)/tex.get_width(),40.0/tex.get_height());var image_size:=Vector2(tex.get_size())*factor
	var at:=Vector2(size.x/2,53)
	draw_texture_rect(tex,Rect2(at-image_size/2,image_size),false,Color.WHITE if caught else Color(.27,.35,.32,.32))
	var heading: String=LocalText.content(entry.color_name)+" · "+LocalText.content(entry.size_name)
	draw_string(font,Vector2(9,22),heading,HORIZONTAL_ALIGNMENT_LEFT,size.x-18,12 if LocalText.revision().begins_with("en") else 16,Color("39544a"))
	if not caught:draw_string(font,Vector2(size.x/2-6,63),"?",HORIZONTAL_ALIGNMENT_LEFT,-1,24,Color("50675b"))
	var caption:=LocalText.text("ui.journal.caught") if caught else LocalText.text("ui.journal.not_seen")
	draw_string(font,Vector2(9,size.y-12),caption,HORIZONTAL_ALIGNMENT_LEFT,size.x-18,16,Color("726b52"))
func _gui_input(event: InputEvent) -> void:
	if (event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_LEFT) or (event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER,KEY_SPACE]):selected.emit(entry.duplicate(true));accept_event()

extends PanelContainer
const LocalText=preload("res://scripts/localization.gd")
var heading_label:Label
var close_button:Button
var world: RefCounted
var lines: VBoxContainer
var signature:=""
var dismissed: Dictionary={}
var shown_ids: Dictionary={}
var notifications_embedded:=false
var detail_requested:=false
func setup(source: RefCounted) -> void:
	world=source;set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT);offset_left=-335;offset_right=-20;offset_top=112;offset_bottom=330
	var style:=StyleBoxFlat.new();style.bg_color=Color("213e37e8");style.set_corner_radius_all(10);style.content_margin_left=12;style.content_margin_right=12;style.content_margin_top=10;style.content_margin_bottom=10;add_theme_stylebox_override("panel",style)
	var body:=VBoxContainer.new();add_child(body)
	var caption:=Label.new();heading_label=caption;caption.text=LocalText.text("content.remaining.daily_life_small_wishes");body.add_child(caption)
	var scroll:=ScrollContainer.new();scroll.custom_minimum_size.y=120;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;body.add_child(scroll)
	lines=VBoxContainer.new();lines.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(lines)
	var close:=Button.new();close.focus_mode=Control.FOCUS_NONE;close_button=close;close.text=LocalText.text("content.remaining.got_it");close.focus_mode=Control.FOCUS_NONE;body.add_child(close);close.pressed.connect(func():dismissed.merge(shown_ids,true);hide())
	hide()
	if not LocalText.events.changed.is_connected(refresh_locale):LocalText.events.changed.connect(refresh_locale)

func refresh(blocked: bool=false) -> void:
	var cards: Array=[]
	for id in world.director.routines:
		var wish: Dictionary=world.wishes.summary(id)
		if wish.active and wish.announced and dismissed.get(id,"")!=wish.id and world.relationships.available(id):cards.append({"actor_id":id,"name":LocalText.resident(world,id),"id":wish.id,"text":wish.text,"hint":world.wishes.hint(world.wishes.template(world.wishes.active(id).template_id),true)})
	shown_ids.clear()
	for card in cards:shown_ids[card.actor_id]=card.id
	if cards.is_empty():detail_requested=false
	visible=not blocked and not cards.is_empty() and (not notifications_embedded or detail_requested)
	var next: String=JSON.stringify(cards)
	if signature==next:return
	signature=next
	for child in lines.get_children():lines.remove_child(child);child.queue_free()
	for card in cards:
		var label:=Label.new();label.text=card.name+"："+LocalText.content(card.text)+"\n"+LocalText.content(card.hint);label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;lines.add_child(label)

func refresh_locale()->void:
	heading_label.text=LocalText.text("content.remaining.daily_life_small_wishes")
	close_button.text=LocalText.text("content.remaining.got_it")
	signature="";refresh()

extends PanelContainer
const LocalText=preload("res://scripts/localization.gd")
signal responded(proposal_id: String,accepted: bool)
var heading_label:Label
var world: RefCounted
var list: VBoxContainer
var note: Label
var signature:=""
var notifications_embedded:=false
var detail_requested:=false
func setup(source: RefCounted) -> void:
	world=source;set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT);offset_left=20;offset_top=140;offset_right=330;offset_bottom=430
	var body:=VBoxContainer.new();add_child(body)
	var title:=Label.new();heading_label=title;title.text=LocalText.text("content.remaining.companion_suggestions");body.add_child(title)
	var scroll:=ScrollContainer.new();scroll.custom_minimum_size.y=170;scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;body.add_child(scroll)
	list=VBoxContainer.new();list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(list)
	note=Label.new();note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;note.add_theme_font_size_override("font_size",13);body.add_child(note);hide()
	if not LocalText.events.changed.is_connected(refresh_locale):LocalText.events.changed.connect(refresh_locale)

func refresh() -> void:
	var cards: Array=world.proposals.snapshot();var next: String=JSON.stringify(cards)
	if cards.is_empty():detail_requested=false
	visible=not cards.is_empty() and (not notifications_embedded or detail_requested)
	if signature==next:return
	signature=next
	for child in list.get_children():list.remove_child(child);child.queue_free()
	for card in cards:
		var box:=VBoxContainer.new();list.add_child(box)
		var text:=Label.new();text.text=LocalText.resident(world,str(card.actor_id))+"："+(LocalText.content(card.text) if card.get("source","")=="local_rules" else str(card.text))+"\n"+LocalText.content(world.proposals.config.activities[card.activity].name);text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;box.add_child(text)
		var buttons:=HBoxContainer.new();box.add_child(buttons)
		for option in [{"text":LocalText.text("content.remaining.yes_let_s"),"yes":true},{"text":LocalText.text("content.remaining.another_time"),"yes":false}]:
			var button:=Button.new();button.focus_mode=Control.FOCUS_NONE;button.text=option.text;button.focus_mode=Control.FOCUS_NONE;buttons.add_child(button);button.pressed.connect(func():responded.emit(card.id,bool(option.yes)))

func refresh_locale()->void:
	heading_label.text=LocalText.text("content.remaining.companion_suggestions")
	signature="";refresh()

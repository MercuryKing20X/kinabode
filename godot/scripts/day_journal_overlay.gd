extends Node
const LocalText=preload("res://scripts/localization.gd")
var _locale_static:Dictionary={}
func T(key:String)->String:
	var value:String=LocalText.text(key);_locale_static[value]=key;return value
func _refresh_static(node:Node)->void:
	if node is Control and (node is Label or (node is Button and not node is OptionButton)):
		if not node.has_meta("locale_key") and _locale_static.has(node.text):node.set_meta("locale_key",_locale_static[node.text])
		if node.has_meta("locale_key"):node.text=T(str(node.get_meta("locale_key")))
	for child in node.get_children():_refresh_static(child)
## Presentation-only attachment: permanent journal facts, queries and cards stay unchanged.
var world: RefCounted
var panel: Control
var note: Label
func setup(source: RefCounted,book: Control) -> void:
	world=source;panel=book;note=Label.new();note.add_theme_font_size_override("font_size",16);note.add_theme_color_override("font_color",Color("506354"));note.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var row: Node=panel.actors.get_parent();row.add_child(note);row.move_child(note,panel.actors.get_index())
	if not LocalText.events.changed.is_connected(refresh_locale):LocalText.events.changed.connect(refresh_locale)

func refresh() -> void:
	note.add_theme_color_override("font_color",Color("fff4db") if LocalText.revision().begins_with("en") else Color("506354"))
	if not panel.visible or panel.actors.item_count==0:return
	var id: String=panel.actor_id();var day: Dictionary=world.days.summary(id)
	note.text=T("activities.today_count")%[day.day,day.today_first_count]
	for tile in panel.grid.get_children():
		var badge: Label=tile.get_node_or_null("TodayBadge")
		if badge==null:
			badge=Label.new();badge.name="TodayBadge";badge.text=T("activities.today");badge.add_theme_font_size_override("font_size",16);badge.add_theme_color_override("font_color",Color("875632"));badge.mouse_filter=Control.MOUSE_FILTER_IGNORE;tile.add_child(badge)
		badge.text=T("activities.today")
		badge.position=Vector2(tile.size.x-24,32);badge.visible=not world.days.today(id,tile.entry.id).is_empty();badge.tooltip_text=T("activities.today_tooltip")%day.day
func _process(_delta: float) -> void:
	if panel.visible:refresh()

func refresh_locale()->void:
	refresh()

class_name InteriorPanel
extends PanelContainer
const LocalText=preload("res://scripts/localization.gd")
signal recipe_selected(recipe: String)
signal action_requested(args: Dictionary)
signal invite_requested(target: String)
signal edit_requested(art: String)
var world: RefCounted
var library: RefCounted
var body: VBoxContainer
var recipes_grid: GridContainer
var detail: VBoxContainer
var note: Label
var selected := ""

func setup(source: RefCounted, art_library: RefCounted) -> void:
	world = source; library = art_library
	LocalText.events.changed.connect(refresh_locale)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -284; offset_right = -20; offset_top = 108
	var style := StyleBoxFlat.new(); style.bg_color = Color("243e35"); style.set_corner_radius_all(12)
	style.content_margin_left = 14; style.content_margin_right = 14; style.content_margin_top = 14; style.content_margin_bottom = 14
	add_theme_stylebox_override("panel", style)
	body = VBoxContainer.new(); body.add_theme_constant_override("separation", 8); add_child(body)
	var heading := HBoxContainer.new(); body.add_child(heading)
	var title := Label.new(); title.text = T("ui.interior_panel.title"); title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; heading.add_child(title)
	button(heading, "×", hide)
	var grid := GridContainer.new(); recipes_grid = grid; grid.columns = 2; body.add_child(grid)
	for key in world.interior.RECIPES:
		var recipe: Dictionary = world.interior.RECIPES[key]
		var b := button(grid, T("ui.interior_panel.recipe") % [LocalText.content(recipe.name), recipe.wood], func(): selected = ""; recipe_selected.emit(key); note.text = T("ui.interior_panel.place_hint"))
		b.set_meta("recipe_id",key)
		b.icon = library.texture("furniture-" + key, "down"); b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER; b.vertical_icon_alignment = VERTICAL_ALIGNMENT_TOP
		b.expand_icon = true; b.add_theme_constant_override("icon_max_width", 48); b.custom_minimum_size = Vector2(112, 102)
	note = Label.new(); note.text = T("ui.interior_panel.intro"); note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; note.custom_minimum_size.x = 230; note.add_theme_font_size_override("font_size", 13); body.add_child(note)
	detail = VBoxContainer.new(); body.add_child(detail)
	button(body, T("ui.interior_panel.exit"), func(): action_requested.emit({"intent": "exit"}))
	hide()
	refresh_locale()

func button(parent: Node, text: String, callback: Callable) -> Button:
	var b := Button.new();b.focus_mode=Control.FOCUS_NONE; b.text = text; b.focus_mode = Control.FOCUS_NONE; b.pressed.connect(callback); parent.add_child(b); return b

func select_item(id: String) -> void:
	selected = id
	for child in detail.get_children(): detail.remove_child(child); child.queue_free()
	if not world.interior.furniture.has(id): return
	recipes_grid.hide()
	button(detail, T("ui.interior_panel.catalog"), func():
		recipes_grid.show()
		for child in detail.get_children(): detail.remove_child(child); child.queue_free())
	var item: Dictionary = world.interior.furniture[id]
	var label := Label.new(); label.text = LocalText.content(item.name); detail.add_child(label)
	if item.recipe_id == "chair":
		button(detail, T("ui.interior_panel.sit"), func(): action_requested.emit({"intent": "sit", "target_id": id}))
		button(detail, T("ui.interior_panel.invite"), func(): invite_requested.emit(id))
	button(detail, T("ui.interior_panel.pickup"), func(): action_requested.emit({"intent": "pickup_furniture", "target_id": id}))
	if item.recipe_id == "chair": button(detail, T("ui.interior_panel.rotate"), func(): action_requested.emit({"intent": "rotate_furniture", "target_id": id, "facing": "up" if item.facing == "down" else "down"}))
	button(detail, T("ui.interior_panel.edit"), func(): edit_requested.emit("furniture-" + str(item.recipe_id)))
	show()

func refresh_locale()->void:
	offset_left=-440 if LocalText.revision().begins_with("en") else -284
	offset_right=-20
	_translate_static(self)
	for button_node in recipes_grid.get_children():
		if button_node.has_meta("recipe_id"):
			var recipe:Dictionary=world.interior.RECIPES[button_node.get_meta("recipe_id")];button_node.text=T("ui.interior_panel.recipe")%[LocalText.content(recipe.name),recipe.wood]
	if not selected.is_empty() and not recipes_grid.visible:select_item(selected)

var locale_labels:Dictionary={}
func T(key:String)->String:
	var result:=LocalText.text(key);locale_labels[LocalText.source(key)]=key;locale_labels[result]=key;locale_labels[str(LocalText.entries.get(key,{}).get("en",result))]=key;return result
func _translate_static(node:Node)->void:
	for property in ["text","tooltip_text"]:
		if not node.get_property_list().any(func(p):return p.name==property):continue
		var value:Variant=node.get(property)
		if value is String and locale_labels.has(value):node.set(property,LocalText.text(locale_labels[value]))
	for child in node.get_children():_translate_static(child)

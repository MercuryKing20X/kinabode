extends AcceptDialog
const LocalText=preload("res://scripts/localization.gd")
var _locale_static:Dictionary={}
func T(key:String)->String:
	var value:String=LocalText.text(key);_locale_static[value]=key;return value
func _mark_static(node:Node)->void:
	var fields:Array=[]
	if node is Label or (node is Button and not node is OptionButton):fields.append("text")
	if node is Window:fields.append("title")
	if node is AcceptDialog:fields.append_array(["dialog_text","ok_button_text"])
	if node is ConfirmationDialog:fields.append("cancel_button_text")
	if node is LineEdit:fields.append("placeholder_text")
	for field in fields:
		if _locale_static.has(str(node.get(field))):node.set_meta("workshop_locale_"+field,_locale_static[str(node.get(field))])
	for child in node.get_children():_mark_static(child)
func _refresh_static(node:Node)->void:
	for field in ["text","title","dialog_text","ok_button_text","cancel_button_text","placeholder_text"]:
		if node.has_meta("workshop_locale_"+field):node.set(field,T(str(node.get_meta("workshop_locale_"+field))))
	for child in node.get_children():_refresh_static(child)
var editor: Control
var name_field: LineEdit
var behavior: OptionButton
var width_field: SpinBox
var depth_field: SpinBox
var seconds_field: SpinBox
var geometry: TextEdit
var note: Label
func setup(source: Control) -> void:
	editor=source;title=T("content.workshop.facility_purpose_interaction");ok_button_text=T("content.workshop.apply_to_draft")
	var col:=VBoxContainer.new();add_child(col)
	name_field=LineEdit.new();name_field.placeholder_text=T("content.workshop.work_name");col.add_child(name_field)
	behavior=OptionButton.new();for label in [T("content.workshop.swing"),T("content.workshop.sit_together"),T("content.workshop.dance")]:behavior.add_item(label)
	col.add_child(behavior)
	for key in ["width","depth","seconds"]:
		var row:=HBoxContainer.new();col.add_child(row);var label:=Label.new();label.text={"width":T("content.workshop.footprint_width"),"depth":T("content.workshop.footprint_depth"),"seconds":T("content.workshop.activity_seconds")}[key];row.add_child(label)
		var value:=SpinBox.new();value.min_value=5 if key=="seconds" else 3;value.max_value=300 if key=="seconds" else 12 if key=="width" else 10;row.add_child(value)
		if key=="width":width_field=value
		elif key=="depth":depth_field=value
		else:seconds_field=value
	var help:=Label.new();help.text=T("content.workshop.coordinates_relative_to_the_facility_center_entrance_seats_and_ob");col.add_child(help)
	geometry=TextEdit.new();geometry.custom_minimum_size=Vector2(540,230);col.add_child(geometry)
	note=Label.new();note.custom_minimum_size.x=540;note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;col.add_child(note)
	confirmed.connect(_apply)
	_mark_static(self)
	if not LocalText.events.changed.is_connected(refresh_locale):LocalText.events.changed.connect(refresh_locale)

func open_config() -> void:
	var art: Dictionary=editor.canvas.art;var config: Dictionary=art.get("recreation",{})
	if config.is_empty():return
	name_field.text=art.get("name",art.id);behavior.select(["swing","sit","dance"].find(config.behavior))
	width_field.value=config.width;depth_field.value=config.depth;seconds_field.value=config.seconds
	var geometry_config: Dictionary={"entry":config.entry,"slots":config.slots,"obstacles":config.obstacles}
	if config.has("rigs"):geometry_config.rigs=config.rigs
	if config.has("game"):geometry_config.game=config.game
	if config.has("board_rect"):geometry_config.board_rect=config.board_rect
	geometry.text=JSON.stringify(geometry_config,"  ")
	note.text=T("content.workshop.construction_wood_s_newly_placed_instances_use_this_version_after")%preload("res://scripts/leisure_rules.gd").cost(config)
	popup_centered(Vector2i(590,530))
func _apply() -> void:
	var config: Variant=JSON.parse_string(geometry.text)
	if not config is Dictionary:editor.feedback.text=T("content.workshop.invalid_interaction_json_the_original_draft_is_safe");return
	config.merge({"width":int(width_field.value),"depth":int(depth_field.value),"seconds":int(seconds_field.value),"behavior":["swing","sit","dance"][behavior.selected]},true)
	if not preload("res://scripts/leisure_rules.gd").valid(config):editor.feedback.text=T("content.workshop.invalid_entrance_seats_or_collision_layout_the_original_draft_is");return
	editor.canvas.checkpoint();editor.canvas.art.recreation=config;editor.canvas.art.name=name_field.text.strip_edges().left(48);editor._mark_dirty();editor.feedback.text=T("content.workshop.configuration_added_to_draft_construction_requires_s_wood")%preload("res://scripts/leisure_rules.gd").cost(config)

func refresh_locale()->void:
	_refresh_static(self)
	for index in range(behavior.item_count):behavior.set_item_text(index,T(["content.workshop.swing","content.workshop.sit_together","content.workshop.dance"][index]))

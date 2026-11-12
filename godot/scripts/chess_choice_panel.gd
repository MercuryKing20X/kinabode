extends Control
const Text=preload("res://scripts/localization.gd")
signal chosen(kind:String,site_id:String)
signal continued(kind:String,site_id:String)
var world:RefCounted
var site_id:=""
var card:PanelContainer
var column:VBoxContainer
var message:Label
var stage:="kind"
func setup(source:RefCounted)->void:
	world=source;set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);z_index=125;mouse_filter=Control.MOUSE_FILTER_STOP
	card=PanelContainer.new();add_child(card)
	var style:=StyleBoxFlat.new();style.bg_color=Color("24454b");style.set_corner_radius_all(12)
	for edge in ["left","right","top","bottom"]:style.set("content_margin_"+edge,18)
	card.add_theme_stylebox_override("panel",style);column=VBoxContainer.new();column.add_theme_constant_override("separation",10);card.add_child(column)
	Text.events.changed.connect(func():if visible:rebuild())
	hide()
func open(id:String)->void:
	site_id=id;stage="kind";show();move_to_front();rebuild()
func add_label(key:String)->Label:
	var label:=Label.new();label.text=Text.text(key);label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(label);return label
func button(key:String,action:Callable)->Button:
	var b:=Button.new();b.focus_mode=Control.FOCUS_NONE;b.text=Text.text(key);b.set_meta("chess_key",key);b.custom_minimum_size.y=40;column.add_child(b);b.pressed.connect(action);return b
func previous()->Dictionary:
	if not world.jieqi.game.is_empty() and world.jieqi.phase in ["paused","arriving","playing"]:return {"kind":"jieqi","site":world.jieqi.site_id}
	for session in world.gomoku.sessions.values():
		if session.phase in ["paused","arriving","playing"] and "human" in world.gomoku.players(session):return {"kind":"gomoku","site":session.site_id}
	return {}
func reason()->String:
	var site:Dictionary=world.gomoku.table(site_id)
	if site.is_empty():return "chess.no_table"
	if not site.complete:
		var art:Dictionary=world.leisure.art(site)
		if not art.is_empty() and not world.leisure.chess_space_clear(site,art.recreation):return "chess.blocked"
		return "chess.unbuilt"
	if str(world.actors.human.region_id)!=str(site.region_id):return "chess.other_island"
	return ""
func select_kind(kind:String)->void:
	if kind=="gomoku":
		if world.gomoku.table(site_id).is_empty():message.text=Text.text("chess.no_table");return
		var old:=previous()
		if not old.is_empty() and old.kind!="gomoku":message.text=Text.text("chess.finish_previous");return
		hide();chosen.emit(kind,site_id);return
	var why:=reason()
	if not why.is_empty():message.text=Text.text(why);return
	var old:=previous()
	if not old.is_empty():message.text=Text.text("chess.finish_previous");return
	stage="mode";rebuild()
func rebuild()->void:
	for child in column.get_children():column.remove_child(child);child.queue_free()
	add_label("chess.choose" if stage=="kind" else "chess.choose_mode")
	message=add_label(reason() if not reason().is_empty() else "chess.choose_hint")
	if stage=="kind":
		var old:=previous()
		if not old.is_empty():button("chess.continue",func():hide();continued.emit(old.kind,old.site))
		button("ui.main.gomoku",func():select_kind("gomoku"))
		button("jieqi.title",func():select_kind("jieqi"))
	else:
		button("chess.standard",func():hide();chosen.emit("standard",site_id))
		add_label("chess.standard_hint")
		button("chess.chaos",func():hide();chosen.emit("chaos",site_id))
		add_label("chess.chaos_hint")
		button("chess.back",func():stage="kind";rebuild())
	button("jieqi.close",hide)
	_layout.call_deferred()
func _layout()->void:
	var f:float=preload("res://scripts/ui_scale.gd").factor()
	var extent:Vector2=get_viewport_rect().size
	var minimum:Vector2=column.get_combined_minimum_size()
	card.size=Vector2(minf(440*f,extent.x-32),minf(minimum.y+36,extent.y-80));card.position=(extent-card.size)/2
func _process(_delta:float)->void:
	if visible:_layout()
func _gui_input(event:InputEvent)->void:
	if event is InputEventMouseButton and event.pressed and not card.get_global_rect().has_point(event.global_position):hide()
func _unhandled_key_input(event:InputEvent)->void:
	if visible and event.is_action_pressed("ui_cancel"):hide();get_viewport().set_input_as_handled()

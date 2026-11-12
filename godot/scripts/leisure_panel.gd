extends PanelContainer
const Catalog=preload("res://scripts/workshop_catalog.gd")
const LocalText=preload("res://scripts/localization.gd")
var _locale_static:Dictionary={}
func T(key:String)->String:
	var value:String=LocalText.text(key);_locale_static[value]=key;return value
func _mark_static(node:Node)->void:
	if node is Label or (node is Button and not node is OptionButton):
		if _locale_static.has(node.text):node.set_meta("panels_locale",_locale_static[node.text])
	for child in node.get_children():_mark_static(child)
func _refresh_static(node:Node)->void:
	if node.has_meta("panels_locale"):node.text=T(str(node.get_meta("panels_locale")))
	for child in node.get_children():_refresh_static(child)
signal invite_requested(args: Dictionary)
signal edit_requested(id: String)
signal place_requested(id: String)
signal inspect_requested(id: String)
signal game_requested(id: String)
var world: RefCounted
var picker: OptionButton
var templates: OptionButton
var info: Label
var site_id:="play.swing"
var game_button: Button
var play_button: Button
var _time:=0.0
func setup(source: RefCounted) -> void:
	world=source;set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT);offset_left=-380;offset_right=-24;offset_top=116;offset_bottom=510
	var style:=StyleBoxFlat.new();style.bg_color=Color("243e35ef");style.set_corner_radius_all(12)
	for side in ["left","right","top","bottom"]:style.set("content_margin_"+side,16)
	add_theme_stylebox_override("panel",style)
	var col:=VBoxContainer.new();col.add_theme_constant_override("separation",10);add_child(col)
	var row:=HBoxContainer.new();col.add_child(row);picker=OptionButton.new();picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(picker)
	button(row,"×",hide);picker.item_selected.connect(func(index):site_id=picker.get_item_metadata(index);refresh();inspect_requested.emit(site_id))
	info=Label.new();info.custom_minimum_size=Vector2(308,90);info.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;col.add_child(info)
	play_button=button(col,T("panels.choose_participants_play_together"),func():invite_requested.emit({"intent":"use_facility","target_id":site_id}))
	game_button=Button.new();game_button.text=T("panels.open_gomoku_invite_a_companion");col.add_child(game_button);game_button.pressed.connect(func():game_requested.emit(site_id))
	button(col,T("panels.choose_builder_build"),func():invite_requested.emit({"intent":"build_facility","target_id":site_id}))
	button(col,T("panels.edit_this_facility_template"),func():edit_requested.emit(world.leisure.sites[site_id].template_id))
	templates=OptionButton.new();col.add_child(templates)
	button(col,T("panels.place_a_new_facility_foundation"),func():
		if templates.selected>=0:place_requested.emit(templates.get_item_metadata(templates.selected));hide())
	rebuild();hide()
	_mark_static(self)
	if not LocalText.events.changed.is_connected(refresh_locale):LocalText.events.changed.connect(refresh_locale)

func button(parent: Node,text: String,call: Callable) -> Button:
	var b:=Button.new();b.focus_mode=Control.FOCUS_NONE;b.text=text;
	if _locale_static.has(text):b.set_meta("panels_locale",_locale_static[text])
	b.pressed.connect(call);parent.add_child(b)
	return b
func rebuild() -> void:
	picker.clear();templates.clear()
	for site in world.leisure.sites.values():picker.add_item(LocalText.content(site.name));picker.set_item_metadata(picker.item_count-1,site.id)
	for art in world.library.artworks.values():
		if art.has("recreation"):templates.add_item(Catalog.work_name(art,art.id));templates.set_item_metadata(templates.item_count-1,art.id)
	open_site(site_id)
func open_site(id: String) -> void:
	if not world.leisure.sites.has(id):return
	site_id=id
	for i in range(picker.item_count):
		if picker.get_item_metadata(i)==id:picker.select(i)
	refresh();show()
func refresh() -> void:
	var site: Dictionary=world.leisure.sites[site_id];var art: Dictionary=world.leisure.art(site)
	if art.is_empty():return
	var config: Dictionary=art.recreation
	game_button.visible=config.get("game")=="gomoku"
	play_button.visible=not game_button.visible
	if world.standard.sites.has(site_id):
		game_button.hide();play_button.hide();info.text=LocalText.content(site.name)+" · "+(T("panels.complete_59") if site.complete else T("panels.unbuilt"))+T("panels.nwood_s_s_ndeliver_materials_in_person_missing_stock_stopping_and_reloading")%[site.invested,world.leisure.cost(site)];return
	var occupants: Array=[]
	for id in world.work.jobs:
		if world.work.jobs[id].get("target_id")==site_id:occupants.append(LocalText.resident(world,id))
	info.text=(T("panels.ready_to_enjoy") if site.complete else T("panels.construction_wood_s_s")%[site.invested,world.leisure.cost(site)])+T("panels.nseats_s_s_sec_each")%[config.slots.size(),config.seconds]+("\n"+"、".join(occupants) if not occupants.is_empty() else "")
	if game_button.visible:info.text=(T("panels.gomoku_table_ready") if site.complete else T("panels.construction_wood_s_s")%[site.invested,world.leisure.cost(site)])+T("panels.ntwo_player_gomoku_finish_the_game_or_explicitly_pause")
func _process(delta: float) -> void:
	_time+=delta
	if visible and _time>.3:_time=0;refresh()

func refresh_locale()->void:
	_refresh_static(self)
	for index in range(templates.item_count):
		var id:String=str(templates.get_item_metadata(index));templates.set_item_text(index,Catalog.work_name(world.library.artworks[id],id))
	for index in range(picker.item_count):picker.set_item_text(index,LocalText.content(world.leisure.sites[str(picker.get_item_metadata(index))].name))
	refresh()

class_name FishingPanel
extends PanelContainer
const LocalText=preload("res://scripts/localization.gd")
var _locale_static:Dictionary={}
func T(key:String)->String:
	var value:String=LocalText.text(key);_locale_static[value]=key;return value
func _refresh_static(node:Node)->void:
	if node is Control and (node is Label or (node is Button and not node is OptionButton)):
		if not node.has_meta("locale_key") and _locale_static.has(node.text):node.set_meta("locale_key",_locale_static[node.text])
		if node.has_meta("locale_key"):node.text=T(str(node.get_meta("locale_key")))
	for child in node.get_children():_refresh_static(child)
signal focus_requested(pen_id: String)
signal greet_requested(fish_id: String)
signal grill_requested(fish_id:String)
var world: RefCounted
var renderer: RefCounted
var actor_picker: OptionButton
var pen_picker: OptionButton
var note: Label
var state: Label
var fish_list: ItemList
var picture: TextureRect
var detail: Label
var controls: GridContainer
var stock_button: Button
var release_button: Button
var catch_button: Button
var grill_button: Button
var elapsed:=0.0
var last_pending_id:=""
var selected_fish:=""
var fish_ids: Array=[]
var revision:=-1
func setup(source: RefCounted,art: RefCounted) -> void:
	world=source;renderer=art
	set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	offset_left=-378;offset_right=-20;offset_top=-290;offset_bottom=290
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",8);add_child(column)
	var header:=HBoxContainer.new();column.add_child(header)
	var title:=Label.new();title.text=T("activities.fishery");title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(title)
	button(header,T("activities.close"),hide)
	actor_picker=OptionButton.new();column.add_child(actor_picker)
	actor_picker.item_selected.connect(func(_index):selected_fish="";refresh(true))
	pen_picker=OptionButton.new();column.add_child(pen_picker)
	pen_picker.item_selected.connect(func(_index):selected_fish="";refresh(true))
	var bar:=HBoxContainer.new();column.add_child(bar)
	button(bar,T("activities.view_fishery"),func():focus_requested.emit(pen_id()))
	
	state=Label.new();state.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;state.custom_minimum_size.y=48;column.add_child(state)
	fish_list=ItemList.new();fish_list.custom_minimum_size.y=110;fish_list.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(fish_list)
	fish_list.item_selected.connect(func(index):selected_fish=fish_ids[index];show_fish())
	picture=TextureRect.new();picture.custom_minimum_size.y=100;picture.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;picture.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;picture.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;column.add_child(picture)
	detail=Label.new();detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;detail.custom_minimum_size.y=48;column.add_child(detail)
	controls=GridContainer.new();controls.columns=2;column.add_child(controls)
	grill_button=button(controls,T("activities.grill"),func():grill_requested.emit(selected_fish))
	button(controls,T("activities.greet"),func():
		if not selected_fish.is_empty():greet_requested.emit(selected_fish))
	stock_button=button(controls,T("activities.stock_selected"),func():command({"intent":"stock_fish","fish_id":selected_fish,"pen_id":pen_id()}))
	release_button=button(controls,T("activities.release"),func():command({"intent":"release_fish","fish_id":selected_fish}))
	note=Label.new();note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;note.custom_minimum_size.y=44;column.add_child(note)
	hide()
	if not LocalText.events.changed.is_connected(refresh_locale):LocalText.events.changed.connect(refresh_locale)

func button(parent: Node,text: String,callback: Callable) -> Button:
	var control:=Button.new();control.focus_mode=Control.FOCUS_NONE;control.text=text;control.set_meta("audio_primary",_locale_static.get(text,"") in ["activities.grill","activities.release","activities.chat"]);control.focus_mode=Control.FOCUS_NONE;control.pressed.connect(callback);parent.add_child(control);return control
func actor_id() -> String:return str(actor_picker.get_item_metadata(actor_picker.selected))
func pen_id() -> String:return str(pen_picker.get_item_metadata(pen_picker.selected))
func open(target_id: String="",resident_id: String="human") -> void:
	_fit_language_layout()
	actor_picker.clear()
	for actor in world.actors.values():
		if actor.id!="human" and not world.residents.supports(actor,"move"):continue
		actor_picker.add_item(T("activities.view_resident")+str(LocalText.resident(world,actor.id)));actor_picker.set_item_metadata(actor_picker.item_count-1,actor.id)
		if actor.id==resident_id:actor_picker.select(actor_picker.item_count-1)
	pen_picker.clear()
	var chosen: String=target_id
	for pen in world.fishing.pens.values():
		pen_picker.add_item(LocalText.content(pen.name));pen_picker.set_item_metadata(pen_picker.item_count-1,pen.id)
		if pen.id==chosen:pen_picker.select(pen_picker.item_count-1)
	selected_fish="";note.text=T("activities.fishery_help");show();refresh(true)
func command(args: Dictionary) -> void:
	var entry:Dictionary=world.fishing.fish.get(str(args.get("fish_id","")),{})
	var result:Dictionary
	if entry.get("location")=="pending" and entry.get("owner_id")==actor_id():
		result=world.fishing.host_pending_action(str(entry.id),str(args.intent),str(args.get("pen_id","")))
	else:result=world.command(actor_id(),args)
	note.text=LocalText.content(str(result.get("message",result.get("error",""))))
	refresh(true)
func _process(delta: float) -> void:
	if not visible or world==null:return
	elapsed+=delta
	if elapsed<.3:return
	elapsed=0;refresh()
func refresh(force:=false) -> void:
	if actor_picker.item_count==0 or pen_picker.item_count==0:return
	if not force and revision==world.revision:return
	revision=world.revision
	var own_pending: Array=world.fishing.pending(actor_id())
	var pending_id: String=str(own_pending[0].id) if not own_pending.is_empty() else ""
	if pending_id!=last_pending_id and not pending_id.is_empty():
		selected_fish=pending_id;note.text=T("activities.new_fish")
	last_pending_id=pending_id
	var job: Dictionary=world.work.jobs.get(actor_id(),{})
	var phases: Dictionary={"fish_cast":T("activities.cast"),"fish_wait":T("activities.wait"),"fish_reel":T("activities.reel")}
	var label: String=T("activities.walk_shore") if world._routes.has(actor_id()) else str(phases.get(job.get("phase",""),""))
	var pen: Dictionary=world.fishing.pens[pen_id()]
	state.text=T("activities.pen_count")%[LocalText.content(pen.name),world.fishing.residents_fish(pen_id()).size(),int(pen.capacity)]
	fish_ids.clear();fish_list.clear()
	var stored:Array=world.fishing.fish.values().filter(func(entry):return entry.owner_id=="human" and entry.location=="storage")
	var entries: Array=own_pending+stored+world.fishing.residents_fish(pen_id())
	for entry in entries:
		var info: Dictionary=world.fishing.describe(entry)
		fish_ids.append(entry.id)
		fish_list.add_item(T("activities.fish_list") % [T("activities.pending_prefix") if entry.location=="pending" else "",LocalText.content(info.species_name),info.scale])
		if entry.id==selected_fish:fish_list.select(fish_list.item_count-1)
	if selected_fish not in fish_ids:selected_fish=str(fish_ids[0]) if not fish_ids.is_empty() else ""
	show_fish()
func show_fish() -> void:
	var entry: Dictionary=world.fishing.fish.get(selected_fish,{})
	picture.visible=not entry.is_empty() if LocalText.revision().begins_with("en") else true
	if entry.is_empty():
		picture.texture=null;detail.text=T("activities.empty_pen");stock_button.disabled=true;release_button.disabled=true;grill_button.disabled=true;return
	var info: Dictionary=world.fishing.describe(entry)
	picture.texture=renderer.texture(entry.species_id,entry.color_id,world.fishing.rules)
	var when:String=T("activities.day")%int(entry.caught_day) if entry.has("caught_day") else Time.get_date_string_from_unix_time(int(entry.caught_at))
	detail.text=T("activities.fish_detail")%[LocalText.content(info.species_name),LocalText.content(info.colors_name),LocalText.content(info.sizes_name),info.scale,LocalText.resident(world,entry.owner_id),when]
	stock_button.disabled=entry.owner_id!=actor_id() or entry.location not in ["pending","storage"]
	grill_button.disabled=not world.life.fireside.direct_fish_available(entry)
	release_button.disabled=entry.owner_id!=actor_id()

func refresh_locale()->void:
	_fit_language_layout()
	_refresh_static(self)
	for index in range(actor_picker.item_count):actor_picker.set_item_text(index,T("activities.view_resident")+LocalText.resident(world,str(actor_picker.get_item_metadata(index))))
	for index in range(pen_picker.item_count):pen_picker.set_item_text(index,LocalText.content(world.fishing.pens[str(pen_picker.get_item_metadata(index))].name))
	note.text=LocalText.content(note.text);revision=-1;refresh(true)

func _fit_language_layout()->void:
	var english:bool=LocalText.revision().begins_with("en");z_index=120 if english else 0
	fish_list.custom_minimum_size.y=70 if english else 110
	picture.custom_minimum_size.y=60 if english else 100
	state.custom_minimum_size.y=32 if english else 48
	detail.custom_minimum_size.y=0 if english else 48
	note.custom_minimum_size.y=0 if english else 44
	note.add_theme_font_size_override("font_size",14 if english else get_theme_default_font_size())
	detail.add_theme_font_size_override("font_size",14 if english else get_theme_default_font_size())

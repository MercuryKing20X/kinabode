class_name FarmPanel
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
signal focus_requested(farm_id: String)
signal discuss_requested(actor_id: String, text: String)
signal edit_requested(art_id: String)
signal helpers_requested(farm_id: String)
var world: RefCounted
var farm_id := "farm.home"
var target_id := ""
var farm_picker: OptionButton
var manager_picker: OptionButton
var crop_picker: OptionButton
var mode_picker: OptionButton
var item_picker: OptionButton
var note: Label
var summary: Label
var plot_button: Button
var fill_picker: OptionButton
var fill_button: Button
var harvest_button: Button
var helpers_button: Button
var more_toggle: Button
var more_box: VBoxContainer
var more_scroll: ScrollContainer
const ERRORS := {"busy":"activities.busy","farm_order_active":"activities.already_tending","hungry":"activities.hungry","hands_full":"activities.hands_full","different_region":"activities.other_island","no_seed":"activities.no_seeds","farm_permission":"activities.field_unavailable","unsupported_capability":"activities.no_farming","invalid_farm_plan":"activities.invalid_plan"}
var _time := 0.0
var syncing := false

func setup(source: RefCounted) -> void:
	world = source; z_index = 100
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -376; offset_right = -24; offset_top = 116; offset_bottom = 550
	var style := StyleBoxFlat.new(); style.bg_color = Color("243f37f2")
	style.content_margin_left = 18; style.content_margin_right = 18; style.content_margin_top = 15; style.content_margin_bottom = 15
	style.corner_radius_top_left=12; style.corner_radius_top_right=12; style.corner_radius_bottom_left=12; style.corner_radius_bottom_right=12
	add_theme_stylebox_override("panel",style)
	var col := VBoxContainer.new(); col.add_theme_constant_override("separation",10); add_child(col)
	var head := HBoxContainer.new(); col.add_child(head)
	farm_picker = OptionButton.new(); farm_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL; head.add_child(farm_picker)
	for farm in world.farms.farms.values(): farm_picker.add_item(LocalText.content(farm.name)); farm_picker.set_item_metadata(farm_picker.item_count-1,farm.id)
	farm_picker.item_selected.connect(func(index): open_farm(str(farm_picker.get_item_metadata(index))); focus_requested.emit(farm_id))
	_button(head,"×",hide)
	# One-line farming: the two big actions sit on top; everything else folds under T("activities.more").
	var quick := HBoxContainer.new(); quick.add_theme_constant_override("separation",8); col.add_child(quick)
	fill_picker = OptionButton.new(); fill_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL; quick.add_child(fill_picker)
	fill_button = _button(quick,T("activities.fill"),func(): run_order("plant",[]))
	harvest_button = _button(quick,T("activities.harvest"),func(): run_order("ready",[]))
	for big in [fill_button, harvest_button]: big.custom_minimum_size = Vector2(72,40); big.add_theme_font_size_override("font_size",18)
	helpers_button = _button(col,T("activities.helpers"),func(): helpers_requested.emit(farm_id))
	more_toggle = _button(col,T("activities.more_closed"),func(): set_more(not more_scroll.visible))
	more_scroll = ScrollContainer.new(); more_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED; more_scroll.hide()
	more_box = VBoxContainer.new(); more_box.add_theme_constant_override("separation",10); more_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL; more_scroll.add_child(more_box)
	var summary_holder := col
	col = more_box
	manager_picker = OptionButton.new(); col.add_child(manager_picker)
	manager_picker.item_selected.connect(func(index):
		if syncing: return
		_result(world.command("human",{"intent":"assign_farm","farm_id":farm_id,"manager_id":str(manager_picker.get_item_metadata(index))})))
	var options := HBoxContainer.new(); col.add_child(options)
	crop_picker = OptionButton.new(); crop_picker.size_flags_horizontal=Control.SIZE_EXPAND_FILL; options.add_child(crop_picker)
	mode_picker = OptionButton.new(); options.add_child(mode_picker)
	for label in [T("activities.once"),T("activities.repeat"),T("activities.harvest_only"),T("activities.plant_only")]: mode_picker.add_item(label)
	summary = Label.new(); summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; summary.custom_minimum_size=Vector2(304,52); summary_holder.add_child(summary)
	plot_button=_button(summary_holder,T("activities.pick_plot"),_plot_action)
	summary_holder.move_child(summary, more_toggle.get_index()); summary_holder.move_child(plot_button, more_toggle.get_index())
	var actions := HBoxContainer.new(); col.add_child(actions)
	_button(actions,T("activities.self_tend"),func(): _manage("human"))
	_button(actions,T("activities.manager_tend"),func(): _manage(str(world.farms.farms[farm_id].manager_id)))
	var chat_actions := HBoxContainer.new(); col.add_child(chat_actions)
	_button(chat_actions,T("activities.discuss"),func():
		var id: String=world.farms.farms[farm_id].manager_id
		if id.is_empty() or id=="human": note.text=T("activities.choose_companion"); return
		discuss_requested.emit(id,T("activities.farm_discussion") % [LocalText.content(world.farms.farms[farm_id].name),farm_id]))
	_button(chat_actions,T("activities.pause"),func():
		for id in world.farms.orders.keys():
			if world.farms.orders[id].farm_id==farm_id: world.command(id,{"intent":"stop"})
		for id in world.work.jobs.keys():
			if world.work.jobs[id].get("farm_id")==farm_id: world.command(id,{"intent":"stop"})
		refresh())
	item_picker=OptionButton.new();item_picker.hide();col.add_child(item_picker)
	var uses := HBoxContainer.new(); col.add_child(uses)
	_button(uses,T("activities.flowers"),func(): _result(world.command("human",{"intent":"decorate_farm","farm_id":farm_id})))
	_button(col,T("activities.edit_crops"),func(): edit_requested.emit(str(world.farms.crops[crop_id()].art)))
	col = summary_holder; col.add_child(more_scroll)
	note=Label.new(); note.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART; note.custom_minimum_size=Vector2(304,36); note.add_theme_font_size_override("font_size",13); col.add_child(note)
	col.move_child(note, helpers_button.get_index())
	open_farm(farm_id); hide()

	if not LocalText.events.changed.is_connected(refresh_locale):LocalText.events.changed.connect(refresh_locale)

func set_more(open: bool) -> void:
	more_scroll.visible = open; more_toggle.text = T("activities.more_open") if open else T("activities.more_closed")
	var room: float = get_viewport_rect().size.y - offset_top - 330 if is_inside_tree() else 240.0
	more_scroll.custom_minimum_size = Vector2(304, clampf(room, 120, 300))

func message(result: Dictionary) -> String:
	if result.get("ok", false): return LocalText.content(str(result.get("message", T("activities.assigned"))))
	var code := str(result.get("error", ""))
	if code == "farm_permission" and world.standard != null and not world.standard.ready(farm_id): return T("activities.field_unbuilt")
	var text := str(result.get("message", ""))
	return T(str(ERRORS[code])) if ERRORS.has(code) else LocalText.content(text) if not text.is_empty() and text != code else T("activities.unavailable")

## Host button: the human (and any chosen helpers) fill the field or bring in what is ripe.
func run_order(mode: String, helpers: Array) -> Dictionary:
	if mode == "ready" and not world.farms.farm_plots(farm_id).any(func(p): return world.farms.stage(p) == "mature"):
		note.text = T("activities.not_ripe"); return {"ok":false,"error":"not_ready"}
	var crop := str(fill_picker.get_item_metadata(fill_picker.selected)) if fill_picker.selected >= 0 else "mixed"
	var ids:Array=helpers if not helpers.is_empty() else ["human"]
	var plan:Dictionary=world.farms.preview_host_orders(ids,mode,farm_id,crop)
	var result:Dictionary
	if helpers.is_empty() and plan.rows.any(func(r):return r.eligible):result=world.farms.host_order("human",farm_id,crop,mode)
	else:result=world.farms.confirm_host_orders(plan)
	note.text=str(result.get("message",""));refresh()
	return result

func _button(parent: Node, text: String, action: Callable) -> Button:
	var button:=Button.new();button.focus_mode=Control.FOCUS_NONE; button.text=text; button.pressed.connect(action); parent.add_child(button); return button

func open_farm(id: String, target: String = "") -> void:
	if not world.farms.farms.has(id): return
	farm_id=id; target_id=target; syncing=true
	farm_picker.clear()
	for farm in world.farms.farms.values():
		farm_picker.add_item(LocalText.content(farm.name));farm_picker.set_item_metadata(farm_picker.item_count-1,farm.id)
	for index in range(farm_picker.item_count):
		if farm_picker.get_item_metadata(index)==id: farm_picker.select(index)
	manager_picker.clear(); manager_picker.add_item(T("activities.no_manager")); manager_picker.set_item_metadata(0,"")
	for actor in world.actors.values():
		if not world.residents.supports(actor,"manage_farm"):continue
		manager_picker.add_item(T("activities.manager_prefix")+LocalText.resident(world,actor.id)); manager_picker.set_item_metadata(manager_picker.item_count-1,actor.id)
		if actor.id==world.farms.farms[id].manager_id: manager_picker.select(manager_picker.item_count-1)
	fill_picker.clear(); fill_picker.add_item(T("activities.mixed")); fill_picker.set_item_metadata(0,"mixed")
	for crop in world.farms.farms[id].crop_ids:
		fill_picker.add_item(str(LocalText.content(world.farms.crops[crop].name))); fill_picker.set_item_metadata(fill_picker.item_count-1,crop)
	crop_picker.clear()
	for crop in world.farms.farms[id].crop_ids:
		crop_picker.add_item(LocalText.content(world.farms.crops[crop].name)); crop_picker.set_item_metadata(crop_picker.item_count-1,crop)
	syncing=false; refresh(); move_to_front(); show()
	# Opened over the resident list (top right): draw and take clicks above it.
	if get_parent()!=null: get_parent().move_child(self, -1)

func crop_id() -> String: return str(crop_picker.get_item_metadata(crop_picker.selected))
func _result(result: Dictionary) -> void:
	note.text=message(result); refresh()
func _manage(id: String) -> void:
	if id.is_empty(): note.text=T("activities.choose_manager"); return
	_result(world.command(id,{"intent":"manage_farm","farm_id":farm_id,"crop_id":crop_id(),"mode":["once","repeat","harvest","plant"][mode_picker.selected]}))
func _plot_action() -> void:
	if not world.farms.plots.has(target_id): return
	var stage: String=world.farms.stage(world.farms.plots[target_id])
	var intent: String={"empty":"plant","dry":"water","mature":"harvest"}.get(stage,"")
	if intent.is_empty(): return
	var args: Dictionary={"intent":intent,"target_id":target_id}
	if intent=="plant": args.crop_id=crop_id()
	_result(world.command("human",args))
func _process(delta: float) -> void:
	if not visible or world==null: return
	_time+=delta
	if _time>=.5: _time=0; refresh()
func refresh() -> void:
	z_index=120
	for i in range(manager_picker.item_count):
		var id: String=str(manager_picker.get_item_metadata(i))
		if world.actors.has(id):manager_picker.set_item_text(i,T("activities.manager_prefix")+LocalText.resident(world,id))
	var counts: Dictionary={"empty":0,"dry":0,"seedling":0,"growing":0,"mature":0}
	for plot in world.farms.farm_plots(farm_id): counts[world.farms.stage(plot)]+=1
	summary.text=T("activities.field_counts") % [counts.empty,counts.dry,counts.seedling+counts.growing,counts.mature]
	for actor_id in world.farms.orders:
		var order: Dictionary=world.farms.orders[actor_id]
		if order.farm_id==farm_id: summary.text+="\n"+LocalText.resident(world,actor_id)+" · "+LocalText.content(order.message)
	plot_button.disabled=true; plot_button.text=T("activities.plot_help")
	if world.farms.plots.has(target_id):
		var plot: Dictionary=world.farms.plots[target_id]; var stage: String=world.farms.stage(plot)
		plot_button.text={"empty":T("activities.plant_plot"),"dry":T("activities.water_plot"),"mature":T("activities.harvest_plot")}.get(stage,T("activities.remaining") % int(ceil(world.farms.remaining(plot)/60)))
		plot_button.disabled=stage not in ["empty","dry","mature"]

func refresh_locale()->void:
	_refresh_static(self)
	for index in range(farm_picker.item_count):
		var id:String=str(farm_picker.get_item_metadata(index));farm_picker.set_item_text(index,LocalText.content(world.farms.farms[id].name))
	for picker_node in [fill_picker,crop_picker]:
		for index in range(picker_node.item_count):
			var id:String=str(picker_node.get_item_metadata(index))
			picker_node.set_item_text(index,T("activities.mixed") if id=="mixed" else LocalText.content(world.farms.crops[id].name))
	manager_picker.set_item_text(0,T("activities.no_manager"))
	for index in range(mode_picker.item_count):mode_picker.set_item_text(index,T(["activities.once","activities.repeat","activities.harvest_only","activities.plant_only"][index]))
	note.text=LocalText.content(note.text);refresh();set_more(more_scroll.visible)

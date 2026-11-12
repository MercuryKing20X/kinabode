class_name HousePanel
extends PanelContainer
const LocalText=preload("res://scripts/localization.gd")

signal delivery_requested(site_id: String)
signal build_requested(site_id: String)
signal companion_requested(site_id: String)
signal enter_requested(site_id: String)
signal edit_requested(art_id: String)
var world: RefCounted
var library: RefCounted
var site_id := "home.house.01"
var title: Label
var preview: TextureRect
var plan: OptionButton
var progress: ProgressBar
var stage_label: Label
var materials: Label
var feedback: Label
var delivery_button: Button
var build_button: Button
var companion_button: Button
var elapsed := 0.0
var plans: Array=[]
var appearance:OptionButton
const STAGES := [("ui.house_panel.foundation"), ("ui.house_panel.frame"), ("ui.house_panel.walls"), ("ui.house_panel.roof"), ("ui.house_panel.finishing")]

func setup(source: RefCounted, art_library: RefCounted) -> void:
	world = source; library = art_library
	LocalText.events.changed.connect(refresh_locale)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -340; offset_right = -24; offset_top = 105
	var style := StyleBoxFlat.new(); style.bg_color = Color("243e35")
	style.set_corner_radius_all(12); style.content_margin_left = 18; style.content_margin_right = 18; style.content_margin_top = 14; style.content_margin_bottom = 14
	add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation", 9); add_child(column)
	var header := HBoxContainer.new(); column.add_child(header)
	title = Label.new(); title.size_flags_horizontal = Control.SIZE_EXPAND_FILL; header.add_child(title)
	button(header, "×", hide)
	preview = TextureRect.new(); preview.custom_minimum_size = Vector2(270, 180); preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE; preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED; preview.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST; column.add_child(preview)
	plan = OptionButton.new();column.add_child(plan);_plans()
	plan.item_selected.connect(func(index):
		var result: Dictionary = world.command("human", {"intent": "select_blueprint", "target_id": site_id, "blueprint_id": plans[index]})
		feedback.text = str(result.get("message", result.get("error", ""))); refresh())
	appearance=OptionButton.new();column.add_child(appearance)
	appearance.add_item(T("house.personal"));appearance.add_item(T("house.classic"));appearance.add_item(T("house.legacy"))
	appearance.item_selected.connect(func(index):
		world.objects[site_id]["house_appearance"]=["personal","classic","personal_legacy"][index]
		world.revision+=1;refresh())
	stage_label = Label.new(); column.add_child(stage_label)
	progress = ProgressBar.new(); progress.show_percentage = false; progress.custom_minimum_size.y = 8; column.add_child(progress)
	materials = Label.new(); column.add_child(materials)
	build_button = button(column, T("ui.house_panel.build"), func():
		if int(world.objects[site_id].get("stage_index", 0)) == 5: enter_requested.emit(site_id)
		else: build_requested.emit(site_id))
	delivery_button = button(column, T("ui.house_panel.deliver"), func(): delivery_requested.emit(site_id))
	companion_button = button(column, T("ui.house_panel.invite"), func(): companion_requested.emit(site_id))
	var edit_button := button(column, T("ui.house_panel.edit"), func(): edit_requested.emit(plans[plan.selected]))
	edit_button.tooltip_text = T("ui.house_panel.template_hint")
	feedback = Label.new(); feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; feedback.custom_minimum_size.x = 265; feedback.add_theme_font_size_override("font_size", 13); column.add_child(feedback)
	hide()

func button(parent: Node, text: String, callback: Callable) -> Button:
	var result := Button.new();result.focus_mode=Control.FOCUS_NONE; result.text = text; result.focus_mode = Control.FOCUS_NONE; result.pressed.connect(callback); parent.add_child(result); return result

func open_site(id: String) -> void:
	if not world.objects.has(id) or world.objects[id].kind != "construction_site": return
	site_id = id; feedback.text = "";_plans(); refresh(); show()

func refresh() -> void:
	preview.custom_minimum_size.y=100 if get_viewport_rect().size.y<=640 else 180
	var state: Dictionary = world.construction_state(site_id)
	if not state.ok: hide(); return
	var site: Dictionary = world.objects[site_id]
	appearance.select(["personal","classic","personal_legacy"].find(str(site.get("house_appearance","personal"))))
	title.text = LocalText.content(state.name)
	var selected := plans.find(state.plan_id)
	plan.select(maxi(0, selected)); plan.disabled = state.locked or world.projects.site_locked(site_id)
	var art: Dictionary = site.get("blueprint", {}).get("artwork", library.artworks.get(state.plan_id,library.artworks.cottage))
	preview.texture = library.frozen_texture(art, "stage_%s" % maxi(0, int(state.stage) - 1)) if state.stage > 0 else library.frozen_texture(art, "stage_4")
	if state.stage==5 and preload("res://scripts/house_appearance.gd").enabled(site):preview.texture=preload("res://scripts/house_appearance.gd").texture(site,library,world.days.phase().id=="night")
	stage_label.text = T("ui.house_panel.completed") if state.stage == 5 else T("ui.house_panel.stage") % [state.stage + 1, T(STAGES[state.stage])]
	progress.max_value = state.total; progress.value = state.invested + state.delivered
	materials.text = T("ui.house_panel.invested") % [state.invested + state.delivered, state.total]
	if state.stage < 5:
		materials.text += T("ui.house_panel.stage_delivered") % [state.delivered, state.costs[state.stage]]
		materials.text += T("ui.house_panel.remaining") % [state.needed, state.stored, world.actors.human.carry.get("wood", 0)]
	build_button.disabled = not str(state.claimed_by).is_empty()
	delivery_button.visible = state.stage < 5 and int(world.actors.human.carry.get("wood", 0)) > 0
	delivery_button.disabled = world.work.jobs.has("human")
	companion_button.disabled = world.projects.site_locked(site_id) if state.stage < 5 else false
	companion_button.text = T("ui.house_panel.invite_inside") if state.stage == 5 else T("ui.house_panel.builders")
	build_button.text = T("ui.house_panel.building") if not str(state.claimed_by).is_empty() else T("ui.house_panel.deliver_build") if state.stage < 5 else T("ui.house_panel.enter")

func _process(delta: float) -> void:
	if not visible: return
	elapsed += delta
	if elapsed > .25: elapsed = 0; refresh()

func _plans() -> void:
	plans.clear();plan.clear()
	for art in library.artworks.values():
		if art.get("kind")!="building":continue
		plans.append(art.id);plan.add_item(preload("res://scripts/workshop_catalog.gd").work_name(art,art.id))

func refresh_locale()->void:
	_translate_static(self)
	appearance.set_item_text(0,T("house.personal"));appearance.set_item_text(1,T("house.classic"));appearance.set_item_text(2,T("house.legacy"))
	for i in plans.size():plan.set_item_text(i,preload("res://scripts/workshop_catalog.gd").work_name(library.artworks[plans[i]],plans[i]))
	if visible:refresh()

var locale_labels:Dictionary={}
func T(key:String)->String:
	var result:=LocalText.text(key);locale_labels[LocalText.source(key)]=key;locale_labels[result]=key;locale_labels[str(LocalText.entries.get(key,{}).get("en",result))]=key;return result
func _translate_static(node:Node)->void:
	for property in ["text","tooltip_text"]:
		if not node.get_property_list().any(func(p):return p.name==property):continue
		var value:Variant=node.get(property)
		if value is String and locale_labels.has(value):node.set(property,LocalText.text(locale_labels[value]))
	for child in node.get_children():_translate_static(child)

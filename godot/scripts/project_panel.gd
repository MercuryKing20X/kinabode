class_name ConstructionProjectPanel
extends PanelContainer
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
signal control_requested(args: Dictionary)
signal discuss_requested(project_id: String)
signal enter_requested(site_id: String)
signal inspect_requested(site_id: String)
var world: RefCounted
var heading: Label
var detail: Label
var progress: ProgressBar
var pause_button: Button
var resume_button: Button
var cancel_button: Button
var discuss_button: Button
var enter_button: Button
var actor_id := "codex"
var timer := 0.0
var dismissed_id := ""
var dismiss_button: Button

func setup(source: RefCounted) -> void:
	world = source
	position = Vector2(28, 106)
	var style := StyleBoxFlat.new(); style.bg_color = Color("243e35e8"); style.set_corner_radius_all(10)
	style.content_margin_left = 14; style.content_margin_right = 14; style.content_margin_top = 10; style.content_margin_bottom = 10
	add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new(); column.add_theme_constant_override("separation", 7); add_child(column)
	heading = Label.new(); heading.add_theme_font_size_override("font_size", 15); column.add_child(heading)
	progress = ProgressBar.new(); progress.show_percentage = false; progress.custom_minimum_size = Vector2(340, 7); column.add_child(progress)
	detail = Label.new(); detail.custom_minimum_size.x = 340; detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; detail.add_theme_font_size_override("font_size", 13); column.add_child(detail)
	var row := HFlowContainer.new(); column.add_child(row)
	pause_button = button(row, T("panels.pause"), func(): request("pause_project"))
	resume_button = button(row, T("panels.resume_68"), func(): request("resume_project"))
	discuss_button = button(row, T("panels.discuss"), func(): discuss_requested.emit(world.projects.plans[actor_id].id))
	cancel_button = button(row, T("panels.cancel_plan"), func(): request("cancel_project"))
	enter_button = button(row, T("panels.come_inside"), func(): enter_requested.emit(world.projects.plans[actor_id].site_id))
	dismiss_button = button(row, T("panels.close"), func(): dismissed_id = world.projects.plans[actor_id].id; hide())
	button(row, T("panels.view_house"), func(): inspect_requested.emit(world.projects.plans[actor_id].site_id))
	hide()

	_mark_static(self)
	if not LocalText.events.changed.is_connected(refresh_locale):LocalText.events.changed.connect(refresh_locale)

func button(parent: Node, text: String, callback: Callable) -> Button:
	var result := Button.new();result.focus_mode=Control.FOCUS_NONE; result.text = text;
	if _locale_static.has(text):result.set_meta("panels_locale",_locale_static[text])
	result.focus_mode = Control.FOCUS_NONE; result.pressed.connect(callback); parent.add_child(result); return result

func request(intent: String) -> void:
	control_requested.emit({"intent": intent, "project_id": world.projects.plans[actor_id].id})
	refresh()

func refresh() -> void:
	var plan: Dictionary = world.projects.state(actor_id)
	visible = not plan.is_empty() and plan.status != "cancelled" and plan.id != dismissed_id
	if not visible: return
	var state: Dictionary = plan.construction
	heading.text = "%s · %s / 5" % [LocalText.content(state.name), state.stage]
	progress.max_value = state.total; progress.value = state.invested + state.delivered
	detail.text = T("panels.s_s_s_s_wood_delivered") % [LocalText.resident(world,actor_id),LocalText.content(plan.step_label), state.invested + state.delivered, state.total] if plan.status == "active" else LocalText.content(plan.reason)
	if plan.status == "completed": detail.text = T("panels.the_cottage_is_finished_come_inside")
	if plan.contributors.has("human"): detail.text += T("panels.nyou_delivered_s_wood_completed_s_stages") % [plan.contributors.human.wood, plan.contributors.human.stages]
	pause_button.visible = plan.status == "active"
	resume_button.visible = plan.status in ["paused", "blocked"]
	cancel_button.visible = plan.status in ["active", "paused", "blocked"]
	discuss_button.visible = plan.status in ["paused", "blocked"]
	enter_button.visible = plan.status == "completed"
	dismiss_button.visible = plan.status == "completed"

func _process(delta: float) -> void:
	timer += delta
	if timer >= .25: timer = 0; refresh()

func refresh_locale()->void:
	_refresh_static(self);refresh()

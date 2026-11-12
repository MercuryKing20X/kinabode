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
signal command_requested(actor_id: String,args: Dictionary)
signal focus_requested
signal recipe_requested
var world: RefCounted
var actors: OptionButton
var state: Label
var requirements: Label
var preview: Label
var feedback: Label
var progress: ProgressBar
var wood_limit: SpinBox
var crop_limit: SpinBox
var start_button: Button
var resume_button: Button
var pause_button: Button
var cancel_button: Button
var build_button: Button
var recipe_button: Button
var title_button:Button
var elapsed:=0.0
func label(parent: Node,text: String="") -> Label:
	var result:=Label.new();result.text=text;
	if _locale_static.has(text):result.set_meta("panels_locale",_locale_static[text])
	result.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;parent.add_child(result);return result
func button(parent: Node,text: String,callback: Callable) -> Button:
	var result:=Button.new();result.focus_mode=Control.FOCUS_NONE;result.text=text;
	if _locale_static.has(text):result.set_meta("panels_locale",_locale_static[text])
	result.focus_mode=Control.FOCUS_NONE;parent.add_child(result);result.pressed.connect(callback);return result
func setup(source: RefCounted) -> void:
	world=source;set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT);anchor_bottom=1.0;offset_left=-460;offset_right=-20;offset_top=100;offset_bottom=-88
	var style:=StyleBoxFlat.new();style.bg_color=Color("213e37");style.set_corner_radius_all(12);style.content_margin_left=16;style.content_margin_right=16;style.content_margin_top=14;style.content_margin_bottom=14;add_theme_stylebox_override("panel",style)
	var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;add_child(scroll)
	var column:=VBoxContainer.new();column.size_flags_horizontal=Control.SIZE_EXPAND_FILL;column.add_theme_constant_override("separation",9);scroll.add_child(column)
	var heading:=HBoxContainer.new();column.add_child(heading)
	title_button=button(heading,T("panels.homestead_project")+LocalText.content(world.homestead.config.site.name),func():focus_requested.emit());button(heading,T("panels.close"),hide)
	state=label(column);requirements=label(column)
	progress=ProgressBar.new();progress.show_percentage=false;progress.max_value=world.homestead.config.build_seconds;column.add_child(progress)
	preview=label(column)
	label(column,T("panels.choose_who_will_work_viewing_does_not_move_anyone"))
	actors=OptionButton.new();column.add_child(actors)
	for actor in world.actors.values():
		if not world.residents.supports(actor,"homestead_start"):continue
		actors.add_item(LocalText.resident(world,actor.id));actors.set_item_metadata(actors.item_count-1,actor.id)
	actors.item_selected.connect(func(_index):feedback.text="";refresh())
	label(column,T("panels.delivery_limits_crops_may_be_mixed_and_count_individually"))
	var row:=HBoxContainer.new();column.add_child(row)
	var wood_label:=label(row,T("panels.wood"));wood_label.autowrap_mode=TextServer.AUTOWRAP_OFF
	wood_limit=SpinBox.new();wood_limit.custom_minimum_size.x=96;wood_limit.min_value=0;wood_limit.max_value=world.homestead.site.requirements.wood;wood_limit.value=wood_limit.max_value;row.add_child(wood_limit)
	var crop_label:=label(row,T("panels.crops"));crop_label.autowrap_mode=TextServer.AUTOWRAP_OFF
	crop_limit=SpinBox.new();crop_limit.custom_minimum_size.x=96;crop_limit.min_value=0;crop_limit.max_value=world.homestead.site.requirements.crops;crop_limit.value=crop_limit.max_value;row.add_child(crop_limit)
	start_button=button(column,"",func():send("homestead_start"))
	resume_button=button(column,"",func():send("homestead_resume"))
	build_button=button(column,"",func():send("homestead_build"))
	var controls:=HFlowContainer.new();column.add_child(controls)
	pause_button=button(controls,T("panels.pause_selected_resident"),func():command_requested.emit(actor_id(),{"intent":"stop"}))
	cancel_button=button(controls,T("panels.cancel_own_plan_keep_contributions"),func():send("homestead_cancel"))
	recipe_button=button(column,T("panels.view_unlocked_recipe")+LocalText.content(world.homestead.config.unlock_recipe.name),func():recipe_requested.emit())
	feedback=label(column)
	label(column,T("panels.wood_comes_from_island_storage_crops_only_from_authorized_harvest_boxes_non"))
	hide();refresh()
	_mark_static(self)
	if not LocalText.events.changed.is_connected(refresh_locale):LocalText.events.changed.connect(refresh_locale)

func actor_id() -> String:return str(actors.get_item_metadata(actors.selected)) if actors.item_count>0 else ""
func open(id: String="") -> void:
	for index in range(actors.item_count):
		if actors.get_item_metadata(index)==id:actors.select(index)
	feedback.text="";show();refresh()
func send(intent: String) -> void:
	var id:=actor_id();var args: Dictionary={"intent":intent}
	if intent=="homestead_start":args["site_id"]=world.homestead.config.site.id
	else:args["plan_id"]=world.homestead.plans.get(id,{}).get("id","")
	if intent in ["homestead_start","homestead_resume"]:args["wood_limit"]=int(wood_limit.value);args["crop_limit"]=int(crop_limit.value)
	command_requested.emit(id,args)
func refresh() -> void:
	if actors==null or actors.item_count==0:return
	var data: Dictionary=world.homestead.summary(actor_id());var plan: Dictionary=data.plan
	state.text=T("panels.level_1")+{"unstarted":T("panels.not_started"),"funding":T("panels.delivering_in_batches"),"ready":T("panels.materials_ready_confirm_construction"),"building":T("panels.under_construction"),"completed":T("panels.flower_garden_complete")}[data.state]
	requirements.text=T("panels.wood_delivered_d_d_ncrops_delivered_d_d")%[data.delivered.get("wood",0),data.requirements.wood,world.homestead.crop_count(data.delivered),data.requirements.crops]
	for item in data.delivered:
		if item!="wood":requirements.text+="\n  %s ×%s"%[LocalText.content(world.farms.crops[item].name),data.delivered[item]]
	progress.value=data.progress
	preview.text=T("panels.s_s_d_blueberries_d_servings_using_the_existing_shared_meal_flow")%[T("panels.unlocked") if data.unlock_recipe.unlocked else T("panels.unlock_on_completion"),LocalText.content(data.unlock_recipe.name),world.homestead.config.unlock_recipe.ingredients.blueberry,world.homestead.config.unlock_recipe.portions]
	if not LocalText.content(data.blocked_reason).is_empty():state.text+="\n"+LocalText.content(data.blocked_reason)+T("panels.contributions_kept")
	if not plan.is_empty():state.text+=T("panels.nown_plan")+str({"active":T("panels.active"),"paused":T("panels.paused"),"blocked":T("panels.waiting_for_conditions"),"cancelled":T("panels.cancelled"),"completed":T("panels.complete")}.get(plan.status,plan.status))+" · "+str(LocalText.content(plan.reason))
	var own: String=T("panels.me") if actor_id()=="human" else T("panels.selected_resident")
	start_button.text=T("panels.collect_deliver_actor") % own;resume_button.text=T("panels.resume_deliver_actor") % own;build_button.text=T("panels.construct_actor") % own
	var busy: bool=world.work.jobs.has(actor_id()) or world._routes.has(actor_id())
	start_button.disabled=data.state=="completed" or plan.get("status") in world.homestead.LIVE or busy
	resume_button.disabled=plan.get("status") not in ["paused","blocked"] or busy or data.state=="completed" or world.homestead.funded()
	build_button.disabled=not world.homestead.funded() or plan.get("status") not in ["paused","blocked"] or busy or data.state=="completed"
	pause_button.disabled=not world.homestead.active(actor_id());cancel_button.disabled=plan.get("status") not in world.homestead.LIVE;recipe_button.visible=data.unlock_recipe.unlocked
func _process(delta: float) -> void:
	if not visible:return
	elapsed+=delta
	if elapsed>=.25:elapsed=0;refresh()

func refresh_locale()->void:
	_refresh_static(self)
	title_button.text=T("panels.homestead_project")+LocalText.content(world.homestead.config.site.name)
	recipe_button.text=T("panels.view_unlocked_recipe")+LocalText.content(world.homestead.config.unlock_recipe.name)
	for index in range(actors.item_count):actors.set_item_text(index,LocalText.resident(world,str(actors.get_item_metadata(index))))
	refresh()

extends PanelContainer
const LocalText=preload("res://scripts/localization.gd")
var _locale_static:Dictionary={}
var _display_locale:String=""
var _preserve_locale_draft:=false
func T(key:String)->String:
	var value:String=LocalText.text(key);_locale_static[value]=key;return value
func _mark_static(node:Node)->void:
	if node is Label or (node is Button and not node is OptionButton):
		if _locale_static.has(node.text):node.set_meta("panels_locale",_locale_static[node.text])
	for child in node.get_children():_mark_static(child)
func _refresh_static(node:Node)->void:
	if node.has_meta("panels_locale"):node.text=T(str(node.get_meta("panels_locale")))
	for child in node.get_children():_refresh_static(child)
signal connect_requested(actor_id:String)
var connect_button:Button
signal selected(actor_id: String)
signal chat_requested(actor_id: String)
signal stop_requested(actor_id: String)
signal external_requested(actor_id: String)
signal gift_requested(receiver_id: String)
signal promise_cancel_requested(actor_id: String,promise_id: String)
const Preferences = preload("res://scripts/resident_intelligence_preferences.gd")
var world: RefCounted
var library: RefCounted
var status_provider: Callable
var preferences := Preferences.new()
var selected_id := ""
var resident_ids: Array[String] = []
var residents: ItemList
var portrait: TextureRect
var heading: Label
var origin: Label
var activity: Label
var capability: Label
var controls_host: VBoxContainer
var promise_rows: VBoxContainer
var promise_signature:=""
var life_host: VBoxContainer
var connection_section: VBoxContainer
var heart_headers:Array[Control]=[]
var heart:VBoxContainer
var life_archive_provider:Callable
var tabs: TabBar
var actions_host: HFlowContainer
var personality_label: Label
var address_edit: LineEdit
var our_days: RichTextLabel
var relationship_actions: HFlowContainer
var wish_label: Label
var relationship_label: Label
var details_scroll: ScrollContainer
var intelligence: VBoxContainer
var autonomy_provider: Callable
var autonomy_toggle: CheckButton
var records_text: RichTextLabel
var records_host: VBoxContainer
var usage_label: Label
var pending_enable := false
var level_picker: OptionButton
var level_note: Label
var footer: Label
var notice: Label
var external_button: Button
var life_dialog: ConfirmationDialog
var life_warning:Label
var life_ack: CheckBox
var life_actor:=""
var life_world:=""
var downgrade:Button
var ultra_dialog: ConfirmationDialog
var pending_id := ""
var pending_world := ""
var elapsed := 0.0
func label(parent: Node, text: String, small: bool = false) -> Label:
	var result := Label.new(); result.text = text;
	if _locale_static.has(text):result.set_meta("panels_locale",_locale_static[text])
	result.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if small: result.add_theme_font_size_override("font_size",13)
	parent.add_child(result); return result
func button(parent: Node, text: String, callback: Callable) -> Button:
	var result := Button.new();result.focus_mode=Control.FOCUS_NONE; result.text=text;
	if _locale_static.has(text):result.set_meta("panels_locale",_locale_static[text])
	result.focus_mode=Control.FOCUS_NONE;parent.add_child(result);result.pressed.connect(callback);return result
func setup(source: RefCounted, art_library: RefCounted, directory: String, provider: Callable) -> void:
	world=source;library=art_library;status_provider=provider;preferences.setup(directory,world.world_id)
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT); anchor_bottom=1.0
	offset_left=-424;offset_right=-20;offset_top=86;offset_bottom=-88
	var style:=StyleBoxFlat.new();style.bg_color=Color("213e37");style.set_corner_radius_all(12)
	style.content_margin_left=16;style.content_margin_right=16;style.content_margin_top=14;style.content_margin_bottom=14
	add_theme_stylebox_override("panel",style)
	var body:=VBoxContainer.new();body.add_theme_constant_override("separation",9);add_child(body)
	var title:=HBoxContainer.new();body.add_child(title)
	var caption:=label(title,T("panels.resident_connections"));caption.add_theme_font_size_override("font_size",21);caption.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	button(title,T("panels.close"),close_panel)
	residents=ItemList.new();residents.custom_minimum_size.y=112;residents.add_theme_font_size_override("font_size",14);residents.item_selected.connect(func(index):select_resident(resident_ids[index]));body.add_child(residents)
	details_scroll=ScrollContainer.new();details_scroll.custom_minimum_size.y=240;details_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;details_scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;body.add_child(details_scroll)
	var details:=VBoxContainer.new();details.size_flags_horizontal=Control.SIZE_EXPAND_FILL;details.add_theme_constant_override("separation",9);details_scroll.add_child(details)
	var person:=HBoxContainer.new();details.add_child(person)
	portrait=TextureRect.new();portrait.custom_minimum_size=Vector2(48,64);portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;person.add_child(portrait)
	var identity:=VBoxContainer.new();identity.size_flags_horizontal=Control.SIZE_EXPAND_FILL;person.add_child(identity)
	heading=label(identity,"");heading.add_theme_font_size_override("font_size",19);origin=label(identity,"",true)
	connect_button=button(details,T("simple.connect"),func():connect_requested.emit(selected_id))
	connect_button.custom_minimum_size.y=44
	activity=label(details,"");capability=label(details,"",true)
	var quick:=HFlowContainer.new();details.add_child(quick)
	button(quick,T("panels.chat_with_her"),func():chat_requested.emit(selected_id))
	button(quick,T("panels.stop_this_resident"),func():stop_requested.emit(selected_id);refresh())
	heart_headers=[person,connect_button,activity,capability,quick]
	tabs=TabBar.new();tabs.add_tab(T("panels.connection"));tabs.add_tab(T("panels.life_plans"));tabs.add_tab(T("simple.more"));tabs.add_tab(T("gestation.heart"));tabs.tab_changed.connect(func(_index):_show_section());details.add_child(tabs)
	connection_section=VBoxContainer.new();connection_section.add_theme_constant_override("separation",9);details.add_child(connection_section)
	controls_host=VBoxContainer.new();controls_host.add_theme_constant_override("separation",7);connection_section.add_child(controls_host)
	external_button=button(connection_section,T("panels.external_ai_connection_settings"),func():external_requested.emit(selected_id))
	label(connection_section,T("panels.residents_use_local_personalities_models_are_optional_every_action_follows"),true)
	life_host=VBoxContainer.new();life_host.add_theme_constant_override("separation",9);details.add_child(life_host)
	intelligence=VBoxContainer.new();intelligence.add_theme_constant_override("separation",6);details.add_child(intelligence)
	label(intelligence,T("panels.reasoning_level"))
	level_picker=OptionButton.new()
	for title_text in [T("panels.low"),T("panels.medium"),T("panels.high"),T("panels.ultra_frequent_decisions"),T("life.level")]:level_picker.add_item(title_text)
	level_picker.item_selected.connect(_level_selected);intelligence.add_child(level_picker)
	level_note=label(intelligence,"",true)
	autonomy_toggle=CheckButton.new();autonomy_toggle.text=T("panels.allow_autonomous_reasoning_within_budget");intelligence.add_child(autonomy_toggle)
	autonomy_toggle.toggled.connect(_toggle_autonomy)
	usage_label=label(intelligence,"",true)
	var records_button:=button(intelligence,T("panels.autonomy_records_latest_20"),func():records_host.visible=not records_host.visible)
	records_button.toggle_mode=true;records_host=VBoxContainer.new();intelligence.add_child(records_host);records_host.hide()
	records_text=RichTextLabel.new();records_text.custom_minimum_size.y=150;records_text.add_theme_font_size_override("normal_font_size",13);records_host.add_child(records_text)
	label(intelligence,T("panels.autonomous_turns_require_your_input_within_the_last_120_seconds_an_idle_com"),true)
	heart=preload("res://scripts/life_panel.gd").new();details.add_child(heart);heart.setup()
	notice=label(details,"",true)
	relationship_label=label(life_host,"",true)
	wish_label=label(life_host,"",true)
	personality_label=label(life_host,"",true)
	label(life_host,T("panels.what_she_calls_you_once_familiar"))
	address_edit=LineEdit.new();address_edit.max_length=12;life_host.add_child(address_edit)
	address_edit.text_submitted.connect(func(value):world.relationships.set_address(str(address_edit.get_meta("actor_id",selected_id)),value);refresh())
	address_edit.focus_exited.connect(func():
		if address_edit.editable:world.relationships.set_address(str(address_edit.get_meta("actor_id",selected_id)),address_edit.text))
	relationship_actions=HFlowContainer.new();life_host.add_child(relationship_actions)
	button(relationship_actions,T("panels.sit_with_me"),func():world.relationships.reward(selected_id,"sit",true))
	button(relationship_actions,T("panels.watch_the_sea_together"),func():world.relationships.reward(selected_id,"sea",true))
	our_days=RichTextLabel.new();our_days.custom_minimum_size.y=160;life_host.add_child(our_days)
	label(life_host,T("panels.promises"))
	promise_rows=VBoxContainer.new();life_host.add_child(promise_rows)
	label(life_host,T("panels.resident_plans"))
	button(life_host,T("panels.give_her_what_i_m_holding"),func():gift_requested.emit(selected_id))
	actions_host=HFlowContainer.new();life_host.add_child(actions_host)
	footer=label(body,"",true);footer.add_theme_color_override("font_color",Color("ebd397"))
	life_dialog=ConfirmationDialog.new();life_dialog.title=T("life.level");add_child(life_dialog)
	var life_body:=VBoxContainer.new();life_body.custom_minimum_size=Vector2(480,160);life_dialog.add_child(life_body)
	life_warning=Label.new();life_warning.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;life_warning.custom_minimum_size=Vector2(480,110);life_warning.add_theme_color_override("font_color",Color(1,.65,.3));life_body.add_child(life_warning)
	life_ack=CheckBox.new();life_ack.text=T("life.ack");life_body.add_child(life_ack)
	life_ack.toggled.connect(func(on):life_dialog.get_ok_button().disabled=not on)
	life_dialog.confirmed.connect(func():
		if life_ack.button_pressed and visible and selected_id==life_actor and world.world_id==life_world and world.director.model_controlled(selected_id):_save_level("lifeblood");preferences.enable_autonomy(selected_id,true);refresh())
	downgrade=Button.new();downgrade.text=T("life.downgrade");level_picker.get_parent().add_child(downgrade);downgrade.pressed.connect(func():_save_level("ultra"))
	ultra_dialog=ConfirmationDialog.new();ultra_dialog.exclusive=true;life_dialog.title=T("life.level");life_dialog.ok_button_text=T("life.confirm");life_dialog.cancel_button_text=T("panels.cancel");life_ack.text=T("life.ack");downgrade.text=T("life.downgrade")
	ultra_dialog.title=T("panels.confirm_ultra");ultra_dialog.ok_button_text=T("panels.confirm_may_increase_usage");ultra_dialog.cancel_button_text=T("panels.cancel");ultra_dialog.min_size=Vector2i(380,180);add_child(ultra_dialog)
	ultra_dialog.confirmed.connect(_confirm_ultra);ultra_dialog.canceled.connect(_cancel_ultra)
	ultra_dialog.close_requested.connect(_cancel_ultra)
	hide();refresh()
	_mark_static(self)
	if not LocalText.events.changed.is_connected(refresh_locale):LocalText.events.changed.connect(refresh_locale)

func open(actor_id: String = "") -> void:
	_fit_language_layout()
	show()
	if not actor_id.is_empty():select_resident(actor_id)
	refresh()
func close_panel() -> void:
	_cancel_ultra();hide()
func select_resident(actor_id: String) -> void:
	if not world.actors.has(actor_id) or actor_id=="human":return
	if selected_id!=actor_id:_cancel_ultra();notice.text="";details_scroll.scroll_vertical=0
	selected_id=actor_id;refresh();selected.emit(actor_id)
func refresh() -> void:
	var locale_changed:bool=not _display_locale.is_empty() and _display_locale!=LocalText.revision()
	_display_locale=LocalText.revision()
	var ids: Array[String]=[]
	for id in world.actors:
		if id!="human":ids.append(id)
	if selected_id not in ids:selected_id=ids[0] if not ids.is_empty() else ""
	if ids!=resident_ids:
		resident_ids=ids;residents.clear()
		for id in ids:residents.add_item("")
	for index in range(ids.size()):
		var id: String=ids[index];var state: Dictionary=status_provider.call(id)
		var row_text:String=str(LocalText.resident(world,id))+"  ·  "+str(state.origin)
		if preferences.preference(id).level=="lifeblood":
			var today:Dictionary=autonomy_provider.call(id).get("usage",{}) if autonomy_provider.is_valid() else preferences.accounting(id)
			row_text+="  ⚠ "+str(today.get("tokens",0))+(" + ?" if int(today.get("reserved",0))>0 or int(today.get("unknown_turns",0))>0 else "")+" token"
		if residents.get_item_text(index)!=row_text:residents.set_item_text(index,row_text)
		residents.set_item_tooltip(index,str(LocalText.resident(world,id))+"\n"+state.origin+" · "+state.connection+"\n"+state.activity)
		if id==selected_id:residents.select(index)
	if selected_id.is_empty():return
	var actor: Dictionary=world.actors[selected_id];var state: Dictionary=status_provider.call(selected_id)
	heading.text=LocalText.resident(world,actor.id);portrait.texture=library.texture(actor.appearance_id,"down_0")
	origin.text=state.origin+"\n"+state.connection
	connect_button.text=T("simple.disconnect") if state.get("light_state","") in ["ready","connecting"] else T("simple.connect")
	activity.text=T("panels.current_activity")+state.activity
	capability.text=T("panels.can_work_and_socialize") if "work" in world.residents.capabilities(actor) else T("panels.can_socialize_an_optional_model_adds_no_work_permissions")
	var model: bool=world.director.model_controlled(selected_id)
	tabs.set_tab_disabled(2,not model)
	if not model and tabs.current_tab==2:tabs.current_tab=0
	_show_section()
	if tabs.current_tab==3 and life_archive_provider.is_valid():
		var archive:Variant=life_archive_provider.call()
		if is_instance_valid(archive):heart.bind(archive,selected_id)
	external_button.hide()
	external_button.disabled=not model
	external_button.tooltip_text=T("panels.select_a_model_connection_for_this_resident_before_configuring_external_acc") if external_button.disabled else T("panels.keep_the_existing_external_configuration_without_adding_reasoning_level_par")
	if not model and not pending_id.is_empty():_cancel_ultra()
	var relation: Dictionary=world.relationships.summary(selected_id)
	relationship_label.text=T("panels.relationship")+LocalText.content(relation.name)+T("panels.nrecently_shared")+("、".join(relation.recent.map(func(value):return LocalText.content(str(value)))) if not relation.recent.is_empty() else T("panels.no_records_yet_take_your_time"))
	var wish: Dictionary=world.wishes.summary(selected_id)
	wish_label.text=T("panels.a_small_wish")+(LocalText.content(str(wish.text))+"\n"+LocalText.content(str(wish.hint)) if wish.active else T("panels.nothing_particular_in_mind_right_now"))
	personality_label.text=T("panels.personality")+LocalText.content(str(world.personality.summary(selected_id).name))+T("panels.local")
	address_edit.editable=world.relationships.index(selected_id)>=1
	if not address_edit.has_focus() and not locale_changed and not _preserve_locale_draft and (str(address_edit.get_meta("actor_id",""))!=selected_id or address_edit.text.is_empty() or address_edit.text==world.relationships.address(selected_id)):address_edit.set_meta("actor_id",selected_id);address_edit.text=world.relationships.address(selected_id)
	relationship_actions.visible=world.relationships.index(selected_id)>=2
	our_days.visible=world.relationships.index(selected_id)>=4
	if our_days.visible:
		var entries: Array=world.relationships.book(selected_id)
		var days_text:String=T("panels.our_days_real_shared_memories_n")+"\n".join(entries.map(func(entry):return Time.get_datetime_string_from_unix_time(int(entry.occurred_at)).replace("T"," ")+"  "+str(entry.summary)))
		if our_days.text!=days_text:our_days.text=days_text
	var promised: Array=world.promises.own(selected_id)
	var next_promises: String=selected_id+LocalText.revision()+JSON.stringify(promised)
	if promise_signature!=next_promises:
		promise_signature=next_promises
		for child in promise_rows.get_children():promise_rows.remove_child(child);child.queue_free()
		if promised.is_empty():label(promise_rows,T("panels.no_pending_promises"),true)
		for entry in promised:
			label(promise_rows,T("panels.day_d_s_s_s")%[int(entry.day),LocalText.content(entry.phase),LocalText.content(world.promises.config.actions[entry.action_type].name),T("panels.running") if entry.status=="running" else T("panels.scheduled")],true)
			button(promise_rows,T("panels.cancel_this_promise"),func():promise_cancel_requested.emit(selected_id,entry.id))
	var chosen: Dictionary=preferences.preference(selected_id);level_picker.select(Preferences.LEVELS.find(chosen.level))
	downgrade.visible=chosen.level=="lifeblood"
	level_note.text=T("life.row") if chosen.level=="lifeblood" else [T("panels.light_reasoning_only_your_messages_trigger_model_calls"),T("panels.standard_reasoning_important_events_can_trigger_it_when_enabled"),T("panels.deeper_reasoning_responds_to_important_events_more_often_when_enabled"),T("panels.uses_the_model_s_highest_published_reasoning_level_with_occasional_idle_ref")][level_picker.selected]
	var runtime: Dictionary=autonomy_provider.call(selected_id) if autonomy_provider.is_valid() else {"supported":false,"reason":T("panels.scheduler_not_ready_yet"),"usage":{},"policy":{}}
	autonomy_toggle.disabled=not model or chosen.level=="low" or (not runtime.supported and not runtime.get("retryable",false))
	autonomy_toggle.set_pressed_no_signal(chosen.autonomy_enabled and chosen.level!="low")
	level_note.text+="\n"+T("gestation.reasoning_policy")
	if not runtime.supported:level_note.text+="\n"+LocalText.content(str(runtime.reason))
	var use: Dictionary=runtime.usage;var policy: Dictionary=runtime.policy
	usage_label.text=T("panels.actual_usage_today_d_tokens_input_d_output_d_nautonomous_turns_d_d_last_hou")%[int(use.get("tokens",0)),int(use.get("input_tokens",0)),int(use.get("output_tokens",0)),int(use.get("calls",0)),int(policy.get("daily",0)),use.get("times",[]).size(),int(policy.get("hourly",0)),int(use.get("reserved",0)),int(use.get("unknown_turns",0))]
	if records_text!=null:
		var lines: Array[String]=[];var history: Dictionary=runtime.get("records",{})
		for turn in history.get("turns",[]):
			var actions: Array=turn.actions.map(func(action):return str(action.intent)+"（"+str(action.status)+"）")
			lines.append(Time.get_datetime_string_from_unix_time(int(turn.at)).replace("T"," ")+" · "+",".join(turn.events)+"\n"+(T("panels.no_action_submitted") if actions.is_empty() else "、".join(actions))+" · "+(T("panels.actual_d_tokens")%int(turn.actual_tokens) if turn.usage_status=="complete" else T("panels.actual_usage_unconfirmed_d_reported")%int(turn.actual_tokens))+T("panels.estimated_d_s")%[int(turn.estimated_tokens),turn.status])
		for gate in history.get("gates",[]).slice(-4):lines.append(T("panels.not_woken")+LocalText.content(str(runtime.get("gate_labels",{}).get(gate.reason,gate.reason))))
		var records_value:String="\n\n".join(lines) if not lines.is_empty() else T("panels.no_autonomy_records_yet")
		if records_text.text!=records_value:records_text.text=records_value
	var reference: String=LocalText.content(str(runtime.get("usage_reference","")))
	if reference.is_empty():reference=T("panels.ultra_up_to_about_d_tokens_hour_full_prompt_tools_and_output_estimate_not_a")%int(runtime.get("estimated_tokens_per_hour",0))
	footer.text=reference+T("panels.may_increase_costs_autonomy_s_disable_it_or_choose_a_lower_level")%[T("panels.is_enabled_within_cooldowns_and_budgets") if chosen.runtime_active else T("panels.has_not_started_making_calls")]

func _show_section() -> void:
	if connection_section==null or life_host==null or intelligence==null:return
	connection_section.visible=tabs.current_tab==0;life_host.visible=tabs.current_tab==1;intelligence.visible=tabs.current_tab==2
	if heart!=null:heart.visible=tabs.current_tab==3
	for node in heart_headers:node.visible=tabs.current_tab!=3
	if footer!=null:footer.visible=tabs.current_tab!=3
func _level_selected(index: int) -> void:
	if not world.director.model_controlled(selected_id) or index<0 or index>=Preferences.LEVELS.size():return
	var level: String=Preferences.LEVELS[index]
	if level==preferences.preference(selected_id).level:return
	if level=="lifeblood":
		life_actor=selected_id;life_world=world.world_id;life_ack.set_pressed_no_signal(false);life_dialog.get_ok_button().disabled=true
		var estimate:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/autonomy.json")).lifeblood_estimate
		life_warning.text=T("life.warning")% (float(estimate.tokens_per_turn)*120.0/10000.0);life_dialog.popup_centered(Vector2i(560,260));return
	if level=="ultra":
		pending_enable=false;pending_id=selected_id;pending_world=world.world_id
		ultra_dialog.dialog_text=T("panels.choose_ultra_for_s_nthis_may_call_the_model_more_often_and_increase_costs_a")%LocalText.resident(world,selected_id)
		ultra_dialog.popup_centered(Vector2i(460,220));return
	_save_level(level)
func _save_level(level: String) -> void:
	var saved: bool=preferences.choose(selected_id,level)
	notice.text=T("panels.saved_autonomous_behavior_still_requires_the_explicit_switch") if saved else T("panels.couldn_t_save_previous_choice_kept")
	refresh()
func _confirm_ultra() -> void:
	var valid: bool=visible and pending_id==selected_id and pending_world==world.world_id and world.director.model_controlled(selected_id)
	var enable: bool=pending_enable
	pending_id="";pending_world="";pending_enable=false
	if valid:
		_save_level("ultra")
		if enable:preferences.enable_autonomy(selected_id,true);refresh()
	else:refresh()
func _cancel_ultra() -> void:
	pending_id="";pending_world="";pending_enable=false
	if ultra_dialog!=null:ultra_dialog.hide()
	if world!=null and not selected_id.is_empty() and level_picker!=null:level_picker.select(Preferences.LEVELS.find(preferences.preference(selected_id).level))
func _process(delta: float) -> void:
	if not visible:return
	elapsed+=delta
	if elapsed>=2.0:elapsed=0;refresh()

func _toggle_autonomy(enabled: bool) -> void:
	if not world.director.model_controlled(selected_id):refresh();return
	var runtime: Dictionary=autonomy_provider.call(selected_id) if autonomy_provider.is_valid() else {"supported":false}
	if enabled and (preferences.preference(selected_id).level=="low" or (not runtime.supported and not runtime.get("retryable",false))):refresh();return
	if enabled and preferences.preference(selected_id).level=="ultra":
		pending_enable=true;pending_id=selected_id;pending_world=world.world_id
		ultra_dialog.dialog_text=T("panels.enable_ultra_autonomy_for_s_nthis_may_call_the_model_frequently_use_many_to")%LocalText.resident(world,selected_id)
		ultra_dialog.popup_centered(Vector2i(460,240));autonomy_toggle.set_pressed_no_signal(false);return
	if not preferences.enable_autonomy(selected_id,enabled):notice.text=T("panels.couldn_t_save_previous_switch_state_kept")
	refresh()

func refresh_locale()->void:
	_fit_language_layout()
	_refresh_static(self)
	for index in range(tabs.tab_count):tabs.set_tab_title(index,T(["panels.connection","panels.life_plans","simple.more","gestation.heart"][index]))
	for index in range(level_picker.item_count):level_picker.set_item_text(index,T(["panels.low","panels.medium","panels.high","panels.ultra_frequent_decisions","life.level"][index]))
	life_dialog.title=T("life.level");life_dialog.ok_button_text=T("life.confirm");life_dialog.cancel_button_text=T("panels.cancel");life_ack.text=T("life.ack");downgrade.text=T("life.downgrade")
	ultra_dialog.title=T("panels.confirm_ultra");ultra_dialog.ok_button_text=T("panels.confirm_may_increase_usage");ultra_dialog.cancel_button_text=T("panels.cancel")
	if not pending_id.is_empty():
		ultra_dialog.dialog_text=T("panels.enable_ultra_autonomy_for_s_nthis_may_call_the_model_frequently_use_many_to" if pending_enable else "panels.choose_ultra_for_s_nthis_may_call_the_model_more_often_and_increase_costs_a") % LocalText.resident(world,pending_id)
	var draft:String=address_edit.text;var actor_meta:Variant=address_edit.get_meta("actor_id",selected_id);var scroll:int=details_scroll.scroll_vertical
	promise_signature="";_preserve_locale_draft=true;refresh();_preserve_locale_draft=false
	address_edit.text=draft;address_edit.set_meta("actor_id",actor_meta);details_scroll.scroll_vertical=scroll

func _fit_language_layout()->void:
	z_index=120 if LocalText.revision().begins_with("en") else 0

extends PanelContainer
const Text=preload("res://scripts/localization.gd")
var directory:=""
var provider:Callable
var probe:Callable
var rows:VBoxContainer
var signature:=""
var elapsed:=0.0
var previous_states:Dictionary={}
var banner_text:=""
var banner_until:=0
var banner:Label
var pool:Node
var buttons:Dictionary={}
var advanced:=false
var invitation:ConfirmationDialog
var art:=preload("res://scripts/character_library.gd").new()
func setup(base:String,current:Callable=Callable(),test:Callable=Callable())->void:
	directory=base;provider=current;probe=test;z_index=220
	art.configure(directory)
	pool=preload("res://scripts/connection_session_pool.gd").obtain(get_tree(),base)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER);offset_left=-390;offset_right=390;offset_top=-290;offset_bottom=290
	var style:=StyleBoxFlat.new();style.bg_color=Color("213e37");style.set_content_margin_all(20);add_theme_stylebox_override("panel",style)
	var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;add_child(scroll)
	rows=VBoxContainer.new();rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL;rows.add_theme_constant_override("separation",10);scroll.add_child(rows);hide()
	Text.events.changed.connect(refresh)
	pool.start_saved.call_deferred()
func current()->Dictionary:return provider.call() if provider.is_valid() else pool.rows()
func refresh()->void:
	if rows==null:return
	var records:=current();signature=JSON.stringify(records)+str(pool.api_tokens())+str(pool.api_cost());buttons.clear()
	for child in rows.get_children():rows.remove_child(child);child.queue_free()
	var records_changed:Array=[]
	for id in records:
		var now:String=str(records[id].state)
		if previous_states.get(id,"")=="connecting" and now in ["ready","error"]:
			records_changed.append(id)
			var who:String=Text.text({"codex":"resident.snow","companion-2":"resident.skye","npc.mira":"resident.clem","npc.nora":"resident.raven"}.get(id,"resident.unknown"))
			banner_text=who+Text.text("simple.connected_suffix") if now=="ready" else who+": "+str(records[id].get("error",""))
			banner_until=Time.get_ticks_msec()+3000
		previous_states[id]=now
	banner=Label.new();banner.text=banner_text if Time.get_ticks_msec()<banner_until else "";banner.add_theme_color_override("font_color",Color("ffdfa0"));rows.add_child(banner)
	if advanced:_api_controls()
	var title:=Label.new();title.text=Text.text("memory.connections");rows.add_child(title)
	for id in records:
		var state:Dictionary=records[id];var row:=HBoxContainer.new();rows.add_child(row)
		if not str(state.get("error","")).is_empty():state.state="error"
		var light:=Label.new();light.text="●";light.add_theme_color_override("font_color",Color("77ca91") if state.state=="ready" else Color("f3ce55") if state.state=="connecting" else Color("e97070") if state.state in ["error","disconnected"] else Color("858585"));row.add_child(light)
		var portrait:=TextureRect.new();portrait.custom_minimum_size=Vector2(32,40);portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.texture=art.texture({"codex":"white-haired-girl","companion-2":"blue-haired-girl","npc.mira":"orange-sunflower-girl","npc.nora":"black-scarf-girl"}[id],"down_0");row.add_child(portrait)
		if id in records_changed:
			var bounce:=create_tween()
			bounce.tween_property(portrait,"position:y",-10.0,.15).as_relative()
			bounce.tween_property(portrait,"position:y",10.0,.22).as_relative()
		var label:=Label.new();label.add_theme_font_size_override("font_size",15);label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		label.text=Text.text({"codex":"resident.snow","companion-2":"resident.skye","npc.mira":"resident.clem","npc.nora":"resident.raven"}.get(id,"resident.unknown"))+" · "+Text.text("memory.state."+str(state.state))+" · "+str(state.get("tokens","?"))+" token"
		label.tooltip_text=str(state.get("error",state.get("greeting","")));row.add_child(label)
		var api:=OptionButton.new();api.name="api_"+id;api.size_flags_vertical=Control.SIZE_SHRINK_CENTER
		for text in [Text.text("simple.local"),"Codex","GPT API"]:api.add_item(text)
		api.select(0 if pool.settings.get_value("selection",id,"local")=="local" and not pool.settings.get_value("enabled",id,false) else 2 if pool.settings.get_value("api",id,"codex")=="openai" else 1)
		api.item_selected.connect(func(index):
			if index==0:
				pool.disconnect_ai(id);pool.local_requested.emit(id)
			else:pool.set_api(id,"openai" if index==2 else "codex")
			refresh())
		row.add_child(api)
		var points:=preload("res://scripts/reasoning_points.gd").new();points.size_flags_vertical=Control.SIZE_SHRINK_CENTER;row.add_child(points);points.setup(directory,pool.ledger_world,id)
		var action:=VBoxContainer.new();action.size_flags_vertical=Control.SIZE_SHRINK_CENTER;row.add_child(action)
		var button:=Button.new();button.focus_mode=Control.FOCUS_NONE;button.name="connect_"+id;buttons[id]=button;button.text=Text.text("simple.disconnect" if state.state in ["ready","connecting"] else "simple.connect");action.add_child(button)
		button.pressed.connect(func():
			if state.state in ["ready","connecting"]:
				if probe.is_valid():probe.call(id,"disconnect")
				else:pool.disconnect_ai(id)
			else:test_connection(id))
		if advanced and state.state=="ready":
			var manager:=CheckButton.new();manager.focus_mode=Control.FOCUS_NONE;manager.text=Text.text("steward.authority");manager.set_pressed_no_signal(pool.management(id));manager.toggled.connect(func(on):pool.set_management(id,on));action.add_child(manager)
		if true:
			var cap_label:=Label.new();cap_label.name="daily_quota_label_"+id;cap_label.text=quota_caption(id);action.add_child(cap_label)
			var limit:=SpinBox.new();limit.name="daily_quota_"+id;limit.min_value=0;limit.max_value=100000000;limit.step=1;limit.value=pool.daily_limit(id);limit.tooltip_text=Text.text("steward.daily_limit");action.add_child(limit)
			var quota_progress:=ProgressBar.new();quota_progress.name="quota_progress_"+id;quota_progress.custom_minimum_size=Vector2(120,18);quota_progress.max_value=maxi(1,pool.daily_limit(id));quota_progress.value=int(pool.quota_usage(id).get("tokens",0))+int(pool.quota_usage(id).get("reserved",0));quota_progress.show_percentage=pool.daily_limit(id)>0;action.add_child(quota_progress)
			limit.value_changed.connect(func(value):
				pool.set_daily_limit(id,int(value))
				cap_label.text=quota_caption(id)
				quota_progress.max_value=maxi(1,int(value));quota_progress.show_percentage=int(value)>0)
		if advanced:
			var turn_caption:=Label.new();turn_caption.text=Text.text("play.turn_limit");action.add_child(turn_caption)
			var turn_cap:=SpinBox.new();turn_cap.min_value=0;turn_cap.max_value=100000000;turn_cap.step=10000;turn_cap.value=pool.turn_limit(id);turn_cap.tooltip_text=Text.text("play.unlimited_hint");turn_cap.value_changed.connect(func(value):pool.set_turn_limit(id,int(value)));action.add_child(turn_cap)

	var reset:=Button.new();reset.focus_mode=Control.FOCUS_NONE;reset.text=Text.text("repair.reset");reset.pressed.connect(func():pool.settings.erase_section("steward_prompt");pool.persist());rows.add_child(reset)
	var more:=Button.new();more.focus_mode=Control.FOCUS_NONE;more.text=Text.text("simple.advanced");more.pressed.connect(func():advanced=not advanced;refresh());rows.add_child(more)
	var usage:=Label.new();usage.name="GPTUsage";usage.text=Text.text("gpt.usage")+": %d · USD %.6f (%s)" % [pool.api_tokens(),pool.api_cost(),Text.text("gpt.estimate")];rows.add_child(usage)
	if pool.api_usage.get_value(Time.get_date_string_from_system(),"unknown_price",false):usage.text=Text.text("gpt.usage")+Text.text("gestation.unknown_cost") % pool.api_tokens()
	var progress:=ProgressBar.new();progress.max_value=maxi(1,int(pool.settings.get_value("openai","limit",10000000)));progress.value=pool.api_tokens();rows.add_child(progress)
	var stop:=Button.new();stop.text=Text.text("gpt.stop");stop.pressed.connect(func():pool.stop_all_ai();refresh());rows.add_child(stop)
	var close:=Button.new();close.focus_mode=Control.FOCUS_NONE;close.text=Text.text("memory.close");close.pressed.connect(hide);rows.add_child(close)
func quota_caption(id:String)->String:
	var caption:String=Text.text("quota.limit")
	var usage:Dictionary=pool.quota_usage(id)
	if int(usage.get("reserved",0))>0 or int(usage.get("unknown_turns",0))>0:caption+=" · "+Text.text("quota.unknown")
	if pool.daily_limit(id)==0:caption+=" · "+Text.text("quota.unlimited")
	return caption
func open()->void:show();refresh()
func test_connection(id:String)->void:
	if probe.is_valid():probe.call(id,"connect")
	else:pool.connect_ai(id)
	refresh()
func offer_steward()->void:
	if not visible or probe.is_valid() or is_instance_valid(invitation) and invitation.visible:return
	if not pool.steward_requested.is_empty():return
	for id in pool.IDS:
		if pool.states.get(id,{}).get("state","")!="ready" or pool.settings.get_value("steward_prompt",id,false):continue
		pool.settings.set_value("steward_prompt",id,true);pool.persist()
		invitation=ConfirmationDialog.new();add_child(invitation);invitation.dialog_text=Text.text("repair.offer");invitation.title=Text.text({"codex":"resident.snow","companion-2":"resident.skye","npc.mira":"resident.clem","npc.nora":"resident.raven"}[id]);invitation.get_ok_button().text=Text.text("repair.yes");invitation.get_cancel_button().text=Text.text("repair.later")
		invitation.confirmed.connect(func():pool.set_management(id,true);pool.steward_requested=id)
		invitation.popup_centered();return
func _process(delta:float)->void:
	# Management remains explicit in settings; no automatic modal over connection rows.
	if is_instance_valid(banner) and Time.get_ticks_msec()>=banner_until:banner.text=""
	elapsed+=delta
	if elapsed<.25:return
	elapsed=0
	if visible and signature!=JSON.stringify(current())+str(pool.api_tokens())+str(pool.api_cost()):refresh()

func show_persona(id:String)->void:
	var cards=preload("res://scripts/persona_cards.gd")
	var card:Dictionary=cards.card(id,"",directory)
	var dialog:=AcceptDialog.new();dialog.name="PersonaEditor";dialog.title=Text.text("reliable.persona");add_child(dialog)
	var body:=VBoxContainer.new();dialog.add_child(body)
	var editor:=TextEdit.new();editor.name="PersonaText";editor.custom_minimum_size=Vector2(600,340);editor.wrap_mode=TextEdit.LINE_WRAPPING_BOUNDARY;editor.text=card.text;body.add_child(editor)
	var note:=Label.new();note.text=Text.text("reliable.next_connection");body.add_child(note)
	var reset:=Button.new();reset.focus_mode=Control.FOCUS_NONE;reset.name="RestorePersona";reset.text=Text.text("reliable.default");reset.pressed.connect(func():editor.text=cards.card(id).text);body.add_child(reset)
	var reconnect:=Button.new();reconnect.focus_mode=Control.FOCUS_NONE;reconnect.text=Text.text("reliable.reconnect");reconnect.pressed.connect(func():save_persona(id,card.language,editor.text);pool.disconnect_ai(id,false);pool.connect_ai(id);dialog.queue_free());body.add_child(reconnect)
	dialog.get_ok_button().text=Text.text("reliable.save")
	dialog.confirmed.connect(func():save_persona(id,card.language,editor.text);dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free);dialog.popup_centered()
func save_persona(id:String,language:String,text:String)->void:
	var overrides:=ConfigFile.new();overrides.load(directory.path_join("persona-overrides.cfg"))
	overrides.set_value(language,id,text);overrides.save(directory.path_join("persona-overrides.cfg"))

func _api_controls()->void:
	if not pool.IDS.any(func(id):return pool.settings.get_value("api",id,"codex")=="openai"):return
	var caption:=Label.new();caption.text=Text.text("gpt.key");rows.add_child(caption)
	var key:=LineEdit.new();key.name="GPTKey";key.secret=true;key.placeholder_text=Text.text("gpt.key_hint")+(" ••••"+str(pool.settings.get_value("openai","key_suffix","")) if pool.settings.has_section_key("openai","key_suffix") else "");rows.add_child(key)
	var save:=Button.new();save.text=Text.text("gpt.save_key");rows.add_child(save)
	var status:=Label.new();rows.add_child(status)
	save.pressed.connect(func():
		if not OS.get_environment("HABITAT_DATA_DIR").is_empty():status.text=Text.text("gpt.test_key");key.clear();return
		var secret:=key.text.strip_edges();key.clear()
		if secret.is_empty():return
		var output:Array=[]
		var code:=OS.execute("/usr/bin/security",PackedStringArray(["add-generic-password","-U","-s","youqi.openai","-a","api","-w",secret]),output,false)
		if code==0:pool.settings.set_value("openai","key_suffix",secret.right(4));pool.persist()
		status.text=(Text.text("gpt.saved")+" ••••"+secret.right(4)) if code==0 else Text.text("gpt.key_failed")
	)
	var endpoint_label:=Label.new();endpoint_label.text=Text.text("gestation.api_domain");rows.add_child(endpoint_label)
	var endpoint:=LineEdit.new();endpoint.name="GPTEndpoint";endpoint.text=str(pool.settings.get_value("openai","base","https://api.openai.com/v1")).trim_prefix("https://").split("/")[0];rows.add_child(endpoint)
	var shown_domain:String=endpoint.text
	var save_endpoint:Callable=func(value):
		if str(value).strip_edges()==shown_domain:return
		var base:String=str(value).strip_edges()
		if not base.begins_with("https://"):base="https://"+base
		if base.trim_prefix("https://").find("/")==-1:base+="/v1"
		if base==str(pool.settings.get_value("openai","base","https://api.openai.com/v1")):return
		pool.settings.set_value("openai","base",base);pool.settings.erase_section_key("openai","models");pool.persist()
	endpoint.text_submitted.connect(save_endpoint)
	endpoint.focus_exited.connect(func():save_endpoint.call(endpoint.text))
	var fetch:=Button.new();fetch.text=Text.text("gestation.refresh_models");rows.add_child(fetch)
	fetch.pressed.connect(func():
		var output:Array=[]
		var python:=OS.get_environment("HABITAT_PYTHON")
		if python.is_empty():python="/usr/bin/python3"
		OS.execute(python,PackedStringArray([ProjectSettings.globalize_path("res://bridge/openai_companion.py"),"--models","--base",str(pool.settings.get_value("openai","base","https://api.openai.com/v1"))]),output,false)
		var result:Variant=JSON.parse_string("".join(output))
		if result is Dictionary and result.has("models"):pool.settings.set_value("openai","models",result.models);pool.persist();refresh()
		else:status.text=str(result.get("error",Text.text("gestation.list_failed"))) if result is Dictionary else Text.text("gestation.list_failed")
	)
	for field in ["chat","thinking"]:
		var row:=HBoxContainer.new();rows.add_child(row)
		var label:=Label.new();label.text=Text.text("gpt."+field);row.add_child(label)
		var models:Array=pool.settings.get_value("openai","models",[])
		if models.is_empty():
			var manual:=LineEdit.new();manual.name="GPTManual_"+field;manual.text=pool.settings.get_value("openai",field,"gpt-6.1-terra");manual.placeholder_text=Text.text("gestation.manual_model");manual.text_changed.connect(func(value):pool.settings.set_value("openai",field,value);pool.persist());row.add_child(manual)
		else:
			var picker:=OptionButton.new();picker.name="GPTModel_"+field
			for model in models:picker.add_item(str(model))
			var selected:int=models.find(pool.settings.get_value("openai",field,"gpt-6.1-terra"))
			if selected<0:selected=maxi(0,models.find("gpt-6.1-terra"));pool.settings.set_value("openai",field,models[selected]);pool.persist()
			picker.select(selected)
			picker.item_selected.connect(func(index):pool.settings.set_value("openai",field,picker.get_item_text(index));pool.persist());row.add_child(picker)
	var limit:=SpinBox.new();limit.name="GPTGlobalQuota";limit.min_value=0;limit.max_value=100000000;limit.step=1;limit.value=pool.settings.get_value("openai","limit",10000000);limit.tooltip_text=Text.text("gpt.limit");limit.value_changed.connect(func(value):pool.settings.set_value("openai","limit",int(value));pool.persist());rows.add_child(limit)

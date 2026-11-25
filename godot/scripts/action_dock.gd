class_name ActionDock
extends Control
const LocalText=preload("res://scripts/localization.gd")
var _locale_static:Dictionary={}
func T(key:String)->String:
	var value:String=LocalText.text(key);_locale_static[value]=key;return value
func _refresh_static(node:Node)->void:
	if node is Control and (node is Label or (node is Button and not node is OptionButton)):
		if not node.has_meta("locale_key") and _locale_static.has(node.text):node.set_meta("locale_key",_locale_static[node.text])
		if node.has_meta("locale_key"):node.text=T(str(node.get_meta("locale_key")))
	for child in node.get_children():_refresh_static(child)
signal chat_requested
signal invite_requested(ids: Array)
signal connection_requested
signal journal_requested
const InvitationCommon=preload("res://scripts/invitation_common.gd")
var action_tabs:TabContainer
var world: RefCounted
var host_node:Node
var menu: PanelContainer
var strip: PanelContainer
var picker: OptionButton
var status: Label
var controls: HBoxContainer
var targets: HBoxContainer
var stop_button: Button
var stock_button: Button
var release_button: Button
var popup: AcceptDialog
var choices: VBoxContainer
var summary: Label
var reopen_button: Button
var next_button: Button
var last_seen: Dictionary={}
var last_jobs: Dictionary={}
var dismissed:=false
var refresh_time:=0.0
var feedback:=""
var notifications_embedded:=false
var start_host_on_invite:=false
var all_fishers:CheckBox
func setup(source: RefCounted,host:Node=null) -> void:
	world=source;host_node=host;set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);mouse_filter=Control.MOUSE_FILTER_IGNORE
	menu=PanelContainer.new();menu.z_index=120;add_child(menu);menu.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM);menu.offset_left=-210;menu.offset_right=210;menu.offset_top=-370;menu.offset_bottom=-90
	menu.add_theme_stylebox_override("panel",style())
	var column:=VBoxContainer.new();menu.add_child(column)
	var tabs:=TabContainer.new();action_tabs=tabs;column.add_child(tabs)
	var functional:=VBoxContainer.new();functional.name=T("activities.functional_tab");tabs.add_child(functional)
	button(functional,T("activities.fish"),func():open_invite(true))
	button(functional,T("storage.ask_wood"),func():menu.hide();host_node.participant_picker.open_for({"intent":"gather_wood","tree_count":1},"companion-2"))
	button(functional,T("activities.stow"),func():
		var result:Dictionary=world.stow_loose();feedback=LocalText.content(str(result.get("message",result.get("error",""))));menu.hide()
		if host_node!=null:host_node.status.text=feedback)
	button(functional,T("activities.place_jar"),func():feedback=str(world.dark.discoveries.place_jar().get("message",T("activities.place_unavailable")));menu.hide())
	button(functional,T("activities.reclaim_jar"),func():feedback=str(world.dark.discoveries.reclaim_jar().get("message",T("activities.reclaim_unavailable")));menu.hide())
	button(functional,T("activities.fish_journal"),func():menu.hide();journal_requested.emit())
	var daily:=VBoxContainer.new();daily.name=T("activities.daily_tab");tabs.add_child(daily)
	button(daily,T("activities.wave"),func():perform({"intent":"gesture","gesture":"wave"}))
	button(daily,T("activities.stretch"),func():perform({"intent":"gesture","gesture":"stretch"}))
	button(column,T("activities.close"),menu.hide)
	strip=PanelContainer.new();add_child(strip);strip.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	strip.offset_left=-346;strip.offset_right=-20;strip.offset_top=-170;strip.offset_bottom=-76
	strip.add_theme_stylebox_override("panel",style())
	var body:=VBoxContainer.new();strip.add_child(body)
	summary=Label.new();summary.add_theme_font_size_override("font_size",13);body.add_child(summary)
	var heading:=HBoxContainer.new();body.add_child(heading)
	picker=OptionButton.new();picker.custom_minimum_size.x=88;picker.clip_text=true;heading.add_child(picker)
	picker.item_selected.connect(func(_index):feedback="";dismissed=false;refresh())
	status=Label.new();status.size_flags_horizontal=Control.SIZE_EXPAND_FILL;status.clip_text=true;heading.add_child(status)
	controls=HBoxContainer.new();body.add_child(controls)
	stop_button=button(controls,T("activities.stop_fishing"),func():perform({"intent":"stop"},actor_id()))
	stock_button=button(controls,T("activities.stock"),toggle_targets)
	release_button=button(controls,T("activities.release"),func():
		var entry: Dictionary=world.fishing.held(actor_id())
		if not entry.is_empty():perform({"intent":"release_fish","fish_id":entry.id},actor_id()))
	button(controls,T("activities.chat"),func():chat_requested.emit())
	next_button=button(controls,T("activities.switch"),next_active)
	button(controls,T("activities.close"),func():dismissed=true;refresh())
	reopen_button=button(self,"",func():dismissed=false;refresh())
	reopen_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	reopen_button.offset_left=-300;reopen_button.offset_right=-20;reopen_button.offset_top=-120;reopen_button.offset_bottom=-76;reopen_button.hide()
	targets=HBoxContainer.new();body.add_child(targets)
	for pen in world.fishing.pens.values():
		var id: String=pen.id
		var label: String=LocalText.content(pen.name) if TranslationServer.get_locale().begins_with("en") else LocalText.content(pen.name).substr(0,2)
		var target_button:=button(targets,label,func():
			var entry: Dictionary=world.fishing.held(actor_id())
			if not entry.is_empty():perform({"intent":"stock_fish","fish_id":entry.id,"pen_id":id},actor_id())
			targets.hide())
		target_button.set_meta("pen_id",id)
	targets.hide();menu.hide();strip.hide()
	popup=AcceptDialog.new();popup.title=T("activities.invite");popup.dialog_text="";popup.size=Vector2i(340,300);add_child(popup)
	var scroll:=ScrollContainer.new();popup.add_child(scroll);scroll.position=Vector2(14,14);scroll.size=Vector2(312,220);scroll.custom_minimum_size=Vector2(312,220)
	choices=VBoxContainer.new();choices.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(choices)
	popup.get_ok_button().set_meta("audio_primary",true)
	popup.confirmed.connect(func():
		var ids: Array=[]
		for choice in choices.get_children():
			if choice is CheckButton and not choice.disabled and choice.button_pressed:ids.append(choice.get_meta("actor_id"))
		invite_requested.emit(ids))
	if not LocalText.events.changed.is_connected(refresh_locale):LocalText.events.changed.connect(refresh_locale)

func style() -> StyleBoxFlat:
	var result:=StyleBoxFlat.new();result.bg_color=Color("24454b");result.content_margin_left=10;result.content_margin_right=10;result.content_margin_top=8;result.content_margin_bottom=8;result.corner_radius_top_left=8;result.corner_radius_top_right=8;result.corner_radius_bottom_left=8;result.corner_radius_bottom_right=8;return result
func button(parent: Node,text: String,callback: Callable) -> Button:
	var control:=Button.new();control.focus_mode=Control.FOCUS_NONE;control.text=text;control.set_meta("audio_primary",_locale_static.get(text,"") in ["activities.grill","activities.release","activities.chat"]);control.focus_mode=Control.FOCUS_NONE;control.pressed.connect(callback);control.add_theme_constant_override("outline_size",0)
	var box:=style();box.content_margin_left=7;box.content_margin_right=7;box.content_margin_top=5;box.content_margin_bottom=5
	control.add_theme_stylebox_override("normal",box);parent.add_child(control);return control
func actor_id() -> String:return str(picker.get_item_metadata(picker.selected)) if picker.item_count>0 else "human"
func choose(id: String) -> void:
	picker.clear()
	for actor in world.actors.values():
		if actor.id!="human" and not world.residents.supports(actor,"move"):continue
		picker.add_item(LocalText.resident(world,actor.id));picker.set_item_metadata(picker.item_count-1,actor.id)
		if actor.id==id:picker.select(picker.item_count-1)
func active_actors() -> Array:
	var pending: Array=[];var fishing: Array=[]
	for actor in world.actors.values():
		if not world.fishing.held(actor.id).is_empty():pending.append(actor.id)
		elif world.work.jobs.get(actor.id,{}).get("intent")=="fish":fishing.append(actor.id)
	return pending+fishing
func next_active() -> void:
	var active:=active_actors()
	if active.is_empty():return
	var index:=active.find(actor_id())
	choose(active[(index+1)%active.size()]);feedback="";dismissed=false;refresh()
func toggle_menu() -> void:
	menu.visible=not menu.visible
	if menu.visible:choose("human");dismissed=false;refresh()
func perform(args: Dictionary,id: String="human") -> Dictionary:
	var result: Dictionary=world.command(id,args)
	choose(id);feedback=LocalText.content(str(result.get("message",result.get("error",""))))
	if result.get("ok",false) and args.get("intent") in ["stock_fish","release_fish"] and not active_actors().is_empty():
		choose(active_actors()[0]);feedback=""
	dismissed=false;menu.hide();refresh();return result
func open_invite(start_host:=false) -> void:
	if world.fishing.shore("human").is_empty():feedback=T("activities.shore_first");choose("human");dismissed=false;menu.hide();refresh();return
	start_host_on_invite=start_host
	if host_node!=null and host_node.view!=null:
		var hud:Node=host_node.island_hud
		InvitationCommon.style_dialog(popup,host_node.view.font,hud.pixel_style() if hud!=null else null,hud!=null and hud.ui_size_mode==LocalText.source("activities.large"))
	for child in choices.get_children():choices.remove_child(child);child.queue_free()
	all_fishers=InvitationCommon.add_all(choices)
	var boxes:Array=[]
	for actor in world.actors.values():
		if actor.id=="human" or not world.residents.supports(actor,"move"):continue
		var choice:=CheckButton.new();choice.focus_mode=Control.FOCUS_NONE;choice.text=LocalText.resident(world,actor.id);choice.set_meta("actor_id",actor.id);choices.add_child(choice)
		var brain:RefCounted=world.director.brains.get(actor.id)
		if world.work.jobs.get(actor.id,{}).get("intent")=="fish" and (brain==null or not brain.owns_local_job()):
			choice.disabled=true;choice.text+=" · "+(T("activities.approaching") if world._routes.has(actor.id) else T("activities.fishing"))
		boxes.append(choice)
	InvitationCommon.bind_all(all_fishers,boxes)
	menu.hide();popup.popup_centered()
func invited(result: Dictionary) -> void:
	feedback=LocalText.content(str(result.get("message","")));dismissed=false
	if not result.get("accepted",[]).is_empty():choose(result.accepted[0])
	refresh()
func toggle_targets() -> void:
	targets.visible=not targets.visible
	strip.offset_top=-224 if targets.visible else -190
func refresh() -> void:
	if picker.item_count==0:choose("human")
	var active:=active_actors();var pending_count:=0
	for actor in world.actors.values():
		var fish_id: String=str(world.fishing.held(actor.id).get("id",""))
		var work: Dictionary=world.work.jobs.get(actor.id,{})
		var job_id: String=str(work.get("id","")) if work.get("intent")=="fish" else ""
		if not job_id.is_empty() and last_jobs.get(actor.id,"")!=job_id and actor_id() not in active:feedback=""
		last_jobs[actor.id]=job_id
		if not fish_id.is_empty():pending_count+=1
		if fish_id!=str(last_seen.get(actor.id,"")) and not fish_id.is_empty():
			dismissed=false
			if actor_id() not in active:feedback=""
		last_seen[actor.id]=fish_id
	if not active.is_empty() and actor_id() not in active and feedback.is_empty():
		choose(active[0]);feedback="";targets.hide()
	var id:=actor_id();var entry: Dictionary=world.fishing.held(id);var job: Dictionary=world.work.jobs.get(id,{})
	var phases: Dictionary={"fish_approach":T("activities.approach_shore"),"fish_cast":T("activities.casting"),"fish_wait":T("activities.waiting"),"fish_bite":T("activities.bite"),"fish_reel":T("activities.reeling")}
	summary.text=T("activities.active_counts")%[pending_count,active.size()-pending_count]
	next_button.visible=active.size()>1
	for index in range(picker.item_count):
		var key: String=str(picker.get_item_metadata(index))
		picker.set_item_text(index,str(LocalText.resident(world,key)))
	status.text=str(phases.get(job.get("phase",""),"")) if job.get("intent")=="fish" else LocalText.content(str(world.fishing.describe(entry).get("species_name","")))+T("activities.holding") if not entry.is_empty() else feedback
	status.tooltip_text=status.text
	stop_button.visible=job.get("intent")=="fish";stock_button.visible=not entry.is_empty();release_button.visible=not entry.is_empty()
	if entry.is_empty():targets.hide()
	strip.offset_top=-224 if targets.visible else -190
	strip.visible=not dismissed and (job.get("intent")=="fish" or not entry.is_empty() or not feedback.is_empty())
	reopen_button.visible=dismissed and not active.is_empty()
	reopen_button.text=T("activities.reopen")%[pending_count,active.size()-pending_count]
	if notifications_embedded:strip.hide();reopen_button.hide()
func _process(delta: float) -> void:
	if world==null:return
	refresh_time+=delta
	if refresh_time<.25:return
	refresh_time=0
	refresh()

func refresh_locale()->void:
	menu.z_index=120
	_refresh_static(self)
	if action_tabs.get_meta("watch_tabs",false):
		for index in range(4):action_tabs.set_tab_title(index,T(["watch.common","watch.everyone","watch.myself","watch.ask"][index]))
	else:action_tabs.set_tab_title(0,T("activities.functional_tab"));action_tabs.set_tab_title(1,T("activities.daily_tab"))
	popup.title=T("activities.invite")
	for control in targets.get_children():
		if control.has_meta("pen_id"):
			var name:String=LocalText.content(world.fishing.pens[str(control.get_meta("pen_id"))].name)
			control.text=name if TranslationServer.get_locale().begins_with("en") else name.substr(0,2)
	for choice in choices.get_children():
		if choice.has_meta("actor_id"):
			var id:String=str(choice.get_meta("actor_id"));choice.text=LocalText.resident(world,id)
			if choice.disabled:choice.text+=" · "+(T("activities.approaching") if world._routes.has(id) else T("activities.fishing"))
	feedback=LocalText.content(feedback);refresh()

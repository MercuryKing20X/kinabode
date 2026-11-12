extends AcceptDialog
const LocalText=preload("res://scripts/localization.gd")
## A host choice only. Selection never moves residents or consumes resources.
const Common=preload("res://scripts/invitation_common.gd")
var host:WeakRef
var life:RefCounted
var all_box:CheckBox
var checks:Dictionary={}
var feedback:Label
var body:VBoxContainer
func setup(game:Node,station_id:String)->void:
	LocalText.events.changed.connect(refresh_locale)
	host=weakref(game);life=game.world.barbecues[station_id];title=T("ui.bbq.invite_title");ok_button_text=T("ui.bbq.next");dialog_hide_on_ok=false
	Common.style_dialog(self,game.view.font,game.island_hud.pixel_style() if game.island_hud!=null else null,false)
	body=VBoxContainer.new();body.add_theme_constant_override("separation",10);add_child(body)
	var heading:=Label.new();heading.text=T("ui.bbq.invite_title");heading.add_theme_font_size_override("font_size",22);body.add_child(heading)
	all_box=Common.add_all(body);all_box.custom_minimum_size.x=390
	var scroll:=ScrollContainer.new();scroll.custom_minimum_size=Vector2(390,200);body.add_child(scroll)
	var list:=VBoxContainer.new();list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list.add_theme_constant_override("separation",6);scroll.add_child(list)
	for id in game.world.actors:
		if id=="human" or not game.world.residents.supports(game.world.actors[id],"sit"):continue
		var box:=CheckBox.new();box.focus_mode=Control.FOCUS_NONE;box.text=LocalText.resident(game.world,id);box.set_meta("resident_id",id);box.custom_minimum_size.y=38;list.add_child(box);checks[id]=box
		if id in life.fireside.state.get("invited",[]) or id in life.fireside.selected_guests:
			box.disabled=true;box.set_meta("guest_status", "ui.bbq.selected" if id not in life.fireside.state.get("invited",[]) else "ui.bbq.seated" if life.fireside.seats.has(id) and not game.world._routes.has(id) else "ui.bbq.coming");box.text+=" · "+(T("ui.bbq.selected") if id not in life.fireside.state.get("invited",[]) else T("ui.bbq.seated") if life.fireside.seats.has(id) and not game.world._routes.has(id) else T("ui.bbq.coming"))
		else:
			var eligibility:Dictionary=life.fireside.can_invite([id])
			if not eligibility.ok:
				box.tooltip_text=str(eligibility.get("message",T("ui.bbq.busy")))
				box.text+=" · "+box.tooltip_text
	for id in checks:
		if checks[id].disabled:continue
		var readiness:Dictionary=life.fireside.can_invite([id])
		if not readiness.ok:
			var reason:String=str(readiness.get("message",T("ui.bbq.busy")))
			var reason_label:=Label.new();reason_label.custom_minimum_size.x=340;reason_label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
			reason_label.text=LocalText.resident(game.world,id)+": "+reason;list.add_child(reason_label)
			checks[id].tooltip_text=reason_label.text
	Common.bind_all(all_box,checks.values())
	feedback=Label.new();feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;feedback.custom_minimum_size=Vector2(390,44);feedback.text=T("ui.bbq.invite_note");body.add_child(feedback)
	get_ok_button().set_meta("audio_primary",true)
	confirmed.connect(next);canceled.connect(queue_free);close_requested.connect(queue_free)
	about_to_popup.connect(fit)
func selected_ids()->Array:
	return checks.keys().filter(func(id):return not checks[id].disabled and checks[id].button_pressed)
func sync_all()->void:
	all_box.set_pressed_no_signal(not checks.is_empty() and checks.values().all(func(box):return box.button_pressed))
func fit()->void:
	var bounds:Vector2i=get_parent().get_viewport().get_visible_rect().size
	size=Vector2i(mini(470,bounds.x-40),mini(460,bounds.y-50));position=(bounds-size)/2
func next()->void:
	var game:Node=host.get_ref()
	if game==null:return
	var ids:Array=selected_ids();var available:Array=[];var skipped:Dictionary={}
	for id in ids:
		if game._resident_chat_busy(id):skipped[id]=T("ui.bbq.replying");continue
		if life.fireside.state.get("current",{}).get("direct_grill",false) and game.world.hunger.rank(id)>=3:skipped[id]=T("ui.bbq.hungry");continue
		var checked:Dictionary=life.fireside.can_invite([id])
		if not checked.get("ok",false):skipped[id]=str(checked.get("message",T("ui.bbq.busy")));continue
		available.append(id)
	var direct:bool=life.fireside.waiting_meal()
	var result:Dictionary=life.fireside.invite_direct(available) if direct else life.fireside.invite(available)
	if not result.get("ok",false):feedback.text=str(result.get("message",result.get("error",T("ui.bbq.invite_failed"))));return
	for id in skipped:
		game.world.director.say_local(id,str(skipped[id]),"barbecue_invitation",12,14)
	var skipped_lines:PackedStringArray=[]
	for id in skipped:skipped_lines.append(LocalText.resident(game.world,id)+": "+str(skipped[id]))
	var skipped_text:String=" · ".join(skipped_lines)
	if not skipped_text.is_empty():game.status.text=skipped_text
	if direct:queue_free();return
	hide()
	var menu:=preload("res://scripts/fireside_menu.gd").new();game.add_child(menu);menu.setup(life,game.view.font);menu.popup_centered();queue_free()

var locale_labels:Dictionary={}
func T(key:String)->String:
	var result:=LocalText.text(key);locale_labels[LocalText.source(key)]=key;locale_labels[result]=key;locale_labels[str(LocalText.entries.get(key,{}).get("en",result))]=key;return result
func refresh_locale()->void:
	_refresh_locale_nodes(self)
func _refresh_locale_nodes(node:Node)->void:
	for property in ["text","title","ok_button_text"]:
		if not node.get_property_list().any(func(p):return p.name==property):continue
		var value:Variant=node.get(property)
		if value is String and locale_labels.has(value):node.set(property,LocalText.text(locale_labels[value]))
	if node is CheckBox and node.has_meta("resident_id"):
		var game:Node=host.get_ref();node.text=LocalText.resident(game.world,str(node.get_meta("resident_id")))+(" · "+LocalText.text(str(node.get_meta("guest_status"))) if node.has_meta("guest_status") else "")
	for child in node.get_children():_refresh_locale_nodes(child)

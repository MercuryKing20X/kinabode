extends AcceptDialog
const LocalText=preload("res://scripts/localization.gd")
## Host choice of farm helpers. Choosing never moves anyone; only the confirm buttons
## issue the real FarmSystem orders through the farm panel.
const Common=preload("res://scripts/invitation_common.gd")
var host:WeakRef
var panel:Control
var all_box:CheckBox
var checks:Dictionary={}
var feedback:Label
var harvest_button:Button
func setup(game:Node,farm_panel:Control)->void:
	LocalText.events.changed.connect(refresh_locale)
	host=weakref(game);panel=farm_panel;var world:RefCounted=game.world
	title=T("system.farm_invitation.who_will_help_with_the_farm");ok_button_text=T("system.farm_invitation.plant_together");dialog_hide_on_ok=false
	Common.style_dialog(self,game.view.font,game.island_hud.pixel_style() if game.island_hud!=null else null,false)
	var body:=VBoxContainer.new();body.add_theme_constant_override("separation",10);add_child(body)
	var heading:=Label.new();heading.text=T("system.farm_invitation.who_is_coming_along")+LocalText.content(str(world.farms.farms[panel.farm_id].name));heading.add_theme_font_size_override("font_size",22);body.add_child(heading)
	all_box=Common.add_all(body);all_box.custom_minimum_size.x=390
	var scroll:=ScrollContainer.new();scroll.custom_minimum_size=Vector2(390,200);body.add_child(scroll)
	var list:=VBoxContainer.new();list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;list.add_theme_constant_override("separation",6);scroll.add_child(list)
	for id in world.actors:
		if id=="human":continue
		var box:=CheckBox.new();box.focus_mode=Control.FOCUS_NONE;box.text=LocalText.resident(world,id);box.custom_minimum_size.y=38;box.clip_text=true;box.text_overrun_behavior=TextServer.OVERRUN_TRIM_ELLIPSIS;list.add_child(box);checks[id]=box
		var reason:=busy_reason(game,id)
		if not reason.is_empty():box.disabled=true;box.text+=" · "+reason;box.tooltip_text=reason
	Common.bind_all(all_box,checks.values())
	feedback=Label.new();feedback.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;feedback.custom_minimum_size=Vector2(390,44);feedback.text=T("farm.help.choose_hint");body.add_child(feedback)
	harvest_button=add_button(T("system.farm_invitation.harvest_together"),true,"ready")
	confirmed.connect(func():go("plant"))
	custom_action.connect(func(action):if action=="ready":go("ready"))
	canceled.connect(queue_free);close_requested.connect(queue_free)
	about_to_popup.connect(fit)
static func busy_reason(game:Node,id:String)->String:
	var world:RefCounted=game.world
	if game._resident_chat_busy(id):return LocalText.text("system.farm_invitation.replying_to_you")
	var reason:String=preload("res://scripts/farm_host_plan.gd").reason(world.farms,id)
	return preload("res://scripts/farm_host_plan.gd").message(reason) if not reason.is_empty() else ""

func selected_ids()->Array:
	return checks.keys().filter(func(id):return not checks[id].disabled and checks[id].button_pressed)
func fit()->void:
	var bounds:Vector2i=get_parent().get_viewport().get_visible_rect().size
	size=Vector2i(mini(470,bounds.x-40),mini(460,bounds.y-50));position=(bounds-size)/2
func go(mode:String)->void:
	if selected_ids().is_empty():feedback.text=LocalText.text("farm.help.choose");return
	var result:Dictionary=panel.run_order(mode,selected_ids())
	if not result.get("ok",false):feedback.text=str(panel.note.text);return
	queue_free()

var locale_labels:Dictionary={}
func T(key:String)->String:
	var result:=LocalText.text(key);locale_labels[LocalText.source(key)]=key;locale_labels[result]=key;locale_labels[str(LocalText.entries.get(key,{}).get("en",result))]=key;return result
func refresh_locale()->void:
	_refresh_locale_nodes(self)
func _refresh_locale_nodes(node:Node)->void:
	for property in ["text","title","ok_button_text","cancel_button_text"]:
		if not node.get_property_list().any(func(p):return p.name==property):continue
		var value:Variant=node.get(property)
		if value is String and locale_labels.has(value):node.set(property,LocalText.text(locale_labels[value]))
	for child in node.get_children():_refresh_locale_nodes(child)

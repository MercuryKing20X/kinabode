extends ConfirmationDialog
const LocalText=preload("res://scripts/localization.gd")
signal chosen(ids: Array,command: Dictionary)
var world: RefCounted
var command: Dictionary={}
var list: VBoxContainer
var toggles: Dictionary={}
var all_box:CheckBox
const Common=preload("res://scripts/invitation_common.gd")
func setup(source: RefCounted) -> void:
	LocalText.events.changed.connect(refresh_locale)
	get_ok_button().set_meta("audio_primary",true)
	world=source;title=T("system.participant_picker.choose_participants");ok_button_text=T("system.participant_picker.start");cancel_button_text=T("system.participant_picker.cancel")
	list=VBoxContainer.new();add_child(list)
	confirmed.connect(func():
		var ids: Array=[]
		for id in toggles:
			if toggles[id].button_pressed and not toggles[id].disabled and unavailable(world.actors[id]).is_empty():ids.append(id)
		chosen.emit(ids,command.duplicate(true)))
func open_for(args: Dictionary,selected: String = "") -> void:
	command=args.duplicate(true);toggles.clear()
	title = T("system.participant_picker.barbecue_together_choose_companions") if args.get("activity_kind") == "barbecue" else T("system.participant_picker.choose_participants")
	if args.get("activity_kind")=="barbecue":title=T("system.participant_picker.barbecue_together")+(T("system.participant_picker.dark_island") if args.get("station_id")=="dark.barbecue" else T("system.participant_picker.crescent_island") if args.get("station_id","home.barbecue")!="home.barbecue" else T("system.participant_picker.main_island"))+T("system.participant_picker.choose_companions")
	for child in list.get_children():list.remove_child(child);child.queue_free()
	all_box=Common.add_all(list)
	for actor in world.actors.values():
		if actor.id=="human" and args.intent not in ["build","build_house","build_facility"]:continue
		var b:=CheckBox.new();b.focus_mode=Control.FOCUS_NONE;b.text=LocalText.resident(world,actor.id);b.disabled=not world.residents.supports(actor,args.intent);b.button_pressed=actor.id==selected and not b.disabled
		if args.get("activity_kind") == "barbecue" and actor.id == "human": b.button_pressed = true; b.disabled = true
		var reason:String=unavailable(actor)
		if not reason.is_empty():b.disabled=true;b.button_pressed=false;b.text+=" · "+reason
		b.tooltip_text=reason if not reason.is_empty() else T("system.participant_picker.this_resident_cannot_do_this_work") if b.disabled else "";list.add_child(b);toggles[actor.id]=b
		if args.get("activity_kind") == "barbecue" and actor.id == "human": b.tooltip_text = T("system.participant_picker.you_will_join_in_starting_pauses_participants_earlier_tasks")
	Common.bind_all(all_box,toggles.values())
	popup_centered(Vector2i(420,380))

var locale_labels:Dictionary={}
func T(key:String)->String:
	var result:=LocalText.text(key);locale_labels[LocalText.source(key)]=key;locale_labels[result]=key;locale_labels[str(LocalText.entries.get(key,{}).get("en",result))]=key;return result
func refresh_locale()->void:
	_refresh_locale_nodes(self)
	for id in toggles:toggles[id].text=LocalText.resident(world,id)
func _refresh_locale_nodes(node:Node)->void:
	for property in ["text","title","ok_button_text","cancel_button_text"]:
		if not node.get_property_list().any(func(p):return p.name==property):continue
		var value:Variant=node.get(property)
		if value is String and locale_labels.has(value):node.set(property,LocalText.text(locale_labels[value]))
	for child in node.get_children():_refresh_locale_nodes(child)

func unavailable(actor:Dictionary)->String:
	if not world.residents.supports(actor,command.intent):return T("system.participant_picker.this_resident_cannot_do_this_work")
	if world.hunger.rank(actor.id)>=3:return LocalText.text("ui.bbq.hungry")
	if actor.region_id!=world.actors.human.region_id:return preload("res://scripts/farm_host_plan.gd").message("different_region")
	if world.work.jobs.has(actor.id) or world.projects.active(actor.id) or world.farms.active(actor.id) or world.homestead.active(actor.id) or world.gomoku.active(actor.id):return preload("res://scripts/farm_host_plan.gd").message("busy")
	return ""

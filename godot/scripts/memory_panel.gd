extends PanelContainer
const LocalText=preload("res://scripts/localization.gd")
var world: RefCounted
var kinds: OptionButton
var partner: OptionButton
var rows: VBoxContainer
var details: RichTextLabel
var note: Label
var previous: Button
var next: Button
var offset := 0
var revision := ""
var page: Dictionary = {}
var chosen_id := ""
const TYPES := {"signature_taste":"content.signature.kind","home_island_arrival":"theirs.kind.first_visit","island_arrival":"theirs.kind.plan","island_build":"theirs.kind.built","dark_beacon":("ui.memory_panel.kind_beacon"),"first_shared_meal":("ui.memory_panel.kind_first"),"feeding":("ui.memory_panel.kind_feeding"),"meal_reaction":("ui.memory_panel.kind_full"),"moon_viewing":("ui.memory_panel.kind_moon"),"wish_completed":("ui.memory_panel.kind_wish"),"relationship_stage":("ui.memory_panel.kind_relationship"),"gift":("ui.memory_panel.kind_gift"),"promise_result":("ui.memory_panel.kind_promise"),"proposal_decision":("ui.memory_panel.kind_proposal"),"":("ui.memory_panel.kind_all"),"shared_barbecue":("ui.memory_panel.kind_bbq"),"fishing_catch":("ui.memory_panel.kind_fish"),"gomoku_match":("ui.memory_panel.kind_gomoku"),"meal":("ui.memory_panel.kind_meal"),"sat_together":("ui.memory_panel.kind_seat"),"house_completed":("ui.memory_panel.kind_house")}

func setup(source: RefCounted) -> void:
	world=source
	LocalText.events.changed.connect(refresh_locale)
	set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	offset_left=-340;offset_right=340;offset_top=-260;offset_bottom=260
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",8);add_child(column)
	var header:=HBoxContainer.new();column.add_child(header)
	var title:=Label.new();title.text=T("ui.memory_panel.title");title.size_flags_horizontal=Control.SIZE_EXPAND_FILL;header.add_child(title)
	button(header,T("ui.memory_panel.refresh"),func():refresh(true));button(header,T("ui.memory_panel.hide"),hide)
	var filters:=HBoxContainer.new();column.add_child(filters)
	kinds=OptionButton.new();filters.add_child(kinds)
	for kind in TYPES:kinds.add_item(T(TYPES[kind]));kinds.set_item_metadata(kinds.item_count-1,kind)
	kinds.select(TYPES.keys().find(""))
	kinds.item_selected.connect(func(_index):refresh(true))
	partner=OptionButton.new();partner.size_flags_horizontal=Control.SIZE_EXPAND_FILL;partner.clip_text=true;filters.add_child(partner)
	partner.item_selected.connect(func(_index):refresh(true))
	var scroll:=ScrollContainer.new();scroll.custom_minimum_size.y=150;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(scroll)
	rows=VBoxContainer.new();rows.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(rows)
	details=RichTextLabel.new();details.custom_minimum_size.y=150;details.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(details)
	var footer:=HBoxContainer.new();column.add_child(footer)
	previous=button(footer,T("ui.memory_panel.previous"),func():offset=maxi(0,offset-6);refresh())
	note=Label.new();note.size_flags_horizontal=Control.SIZE_EXPAND_FILL;note.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;footer.add_child(note)
	next=button(footer,T("ui.memory_panel.next"),func():offset=int(page.get("next_offset",-1));refresh())
	hide()

func button(parent: Node,text: String,callback: Callable) -> Button:
	var control:=Button.new();control.focus_mode=Control.FOCUS_NONE;control.text=text;control.focus_mode=Control.FOCUS_NONE;control.pressed.connect(callback);parent.add_child(control);return control

func open() -> void:
	_fit_language_layout()
	var selected: String=str(partner.get_item_metadata(partner.selected)) if partner.item_count>0 else ""
	partner.clear();partner.add_item(T("ui.memory_panel.everyone"));partner.set_item_metadata(0,"")
	for id in world.actors:
		if id=="human":continue
		partner.add_item(LocalText.resident(world,id));partner.set_item_metadata(partner.item_count-1,id)
		if id==selected:partner.select(partner.item_count-1)
	show();refresh(true)

func refresh(reset := false) -> void:
	if reset:offset=0;revision="";chosen_id=""
	var args: Dictionary={"offset":offset,"limit":6}
	var kind: String=str(kinds.get_item_metadata(kinds.selected))
	var with_id: String=str(partner.get_item_metadata(partner.selected))
	if not kind.is_empty():args["kind"]=kind
	if not with_id.is_empty():args["with_resident"]=with_id
	if not revision.is_empty():args["revision"]=revision
	page=world.read_memories("human",args)
	if page.get("error")=="stale_memories":offset=0;revision="";args.erase("revision");args.offset=0;page=world.read_memories("human",args)
	for child in rows.get_children():rows.remove_child(child);child.queue_free()
	details.clear()
	if not page.ok:note.text=T("ui.memory_panel.unavailable");previous.disabled=true;next.disabled=true;return
	revision=page.revision;previous.disabled=offset==0;next.disabled=int(page.next_offset)<0
	note.text=T("ui.memory_panel.count")%page.total
	for memory in page.memories:
		var row:=button(rows,T(TYPES.get(memory.kind,"theirs.kind.other"))+" · "+str(memory.summary),show_memory.bind(str(memory.id)))
		row.alignment=HORIZONTAL_ALIGNMENT_LEFT;row.clip_text=true;row.tooltip_text=memory.summary
	if page.memories.is_empty():details.add_text(T("ui.memory_panel.empty"))
	else:
		var selected_memory: Array=page.memories.filter(func(memory):return memory.id==chosen_id)
		show_memory(str(page.memories[0].id) if selected_memory.is_empty() else chosen_id)

func show_memory(id: String) -> void:
	var found: Dictionary=world.read_memories("human",{"memory_id":id})
	if not found.ok:refresh(true);return
	chosen_id=id;var memory: Dictionary=found.memories[0];details.clear()
	var date:=Time.get_datetime_dict_from_unix_time(int(memory.occurred_at)+int(Time.get_time_zone_from_system().bias)*60)
	details.add_text("%04d-%02d-%02d %02d:%02d\n"%[date.year,date.month,date.day,date.hour,date.minute])
	details.add_text(str(memory.summary)+T("ui.memory_panel.location")+str(memory.region_id)+"\n")
	var names: Array[String]=[]
	for actor in memory.participants:names.append(str(memory.participant_names[actor]))
	details.add_text(T("ui.memory_panel.participants")+T("ui.memory_panel.join").join(names)+"\n")
	match str(memory.kind):
		"meal":
			var overlap: Variant=memory.facts.get("overlapped_with",[])
			if overlap is Array and not overlap.is_empty():details.add_text(T("ui.memory_panel.meal_note"))
		"shared_barbecue":
			if memory.facts.get("version")==2:
				for who in memory.facts.foods:
					for food in memory.facts.foods[who]:details.add_text(memory.participant_names[who]+"："+(LocalText.content(food.name) if memory.get("text_version",0)==1 else str(food.name))+(T("ui.memory_panel.first_taste") if food.first_time else "")+"\n")
				return
			for role in ["prepare","turn","cleanup"]:details.add_text({"prepare":T("ui.memory_panel.prepare"),"turn":T("ui.memory_panel.turn"),"cleanup":T("ui.memory_panel.cleanup")}[role]+"："+memory.participant_names[memory.facts.roles[role]]+"\n")
		"house_completed":
			for actor in memory.facts.contributions:
				var count: Dictionary=memory.facts.contributions[actor]
				details.add_text(T("ui.memory_panel.contribution")%[memory.participant_names[actor],count.wood,count.stages])

func refresh_locale()->void:
	_fit_language_layout()
	_translate_static(self)
	for i in kinds.item_count:kinds.set_item_text(i,T(TYPES[kinds.get_item_metadata(i)]))
	for i in partner.item_count:
		var id:String=str(partner.get_item_metadata(i));partner.set_item_text(i,T("ui.memory_panel.everyone") if id.is_empty() else LocalText.resident(world,id))
	if partner.item_count>0:
		var selected:String=chosen_id;revision="";refresh();chosen_id=selected
		if not selected.is_empty():show_memory(selected)

var locale_labels:Dictionary={}
func T(key:String)->String:
	var result:=LocalText.text(key);locale_labels[LocalText.source(key)]=key;locale_labels[result]=key;locale_labels[str(LocalText.entries.get(key,{}).get("en",result))]=key;return result
func _translate_static(node:Node)->void:
	for property in ["text","tooltip_text"]:
		if not node.get_property_list().any(func(p):return p.name==property):continue
		var value:Variant=node.get(property)
		if value is String and locale_labels.has(value):node.set(property,LocalText.text(locale_labels[value]))
	for child in node.get_children():_translate_static(child)

func _fit_language_layout()->void:
	z_index=120 if LocalText.revision().begins_with("en") else 0

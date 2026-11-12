extends ConfirmationDialog
const Text=preload("res://scripts/localization.gd")
signal decision(card_id:String,accepted:bool,actors:Array)
var card_id:=""
var boxes:Dictionary={}
var body:VBoxContainer
func setup(plan:Dictionary,world:RefCounted,font:Font)->void:
	card_id=plan.id;title=Text.text("local.commands.farm_title" if plan.action in ["plant","ready"] else "local.commands.title");ok_button_text=Text.text("local.commands.ok");cancel_button_text=Text.text("local.commands.cancel");dialog_hide_on_ok=false
	theme=Theme.new();theme.default_font=font;theme.default_font_size=18
	dialog_text=str(plan.get("summary",Text.text("local.commands.review")));get_label().hide()
	var scroll:=ScrollContainer.new();scroll.custom_minimum_size=Vector2(620,240);add_child(scroll)
	body=VBoxContainer.new();body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;body.add_theme_constant_override("separation",12);scroll.add_child(body)
	var summary:=Label.new();summary.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;summary.text=dialog_text;body.add_child(summary)
	for row in plan.rows:
		var line:=VBoxContainer.new();body.add_child(line)
		var box:=CheckBox.new();box.focus_mode=Control.FOCUS_NONE;box.text=Text.resident(world,row.actor_id);box.button_pressed=bool(row.allowed);box.disabled=not row.allowed;line.add_child(box);boxes[row.actor_id]=box
		var detail:=Label.new();detail.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;detail.custom_minimum_size.x=540;line.add_child(detail)
		detail.text=Text.text("local.commands.action_"+plan.action)
		if plan.action in ["plant","ready"] and not str(row.get("farm_id","")).is_empty():
			detail.text+=" · "+Text.content(world.farms.farms[row.farm_id].name)
			if plan.action=="plant":detail.text+=" · "+(Text.text("local.commands.mixed") if row.get("crop_id")=="mixed" else Text.content(world.farms.crops.get(row.get("crop_id"),{}).get("name",str(row.get("crop_id","")))))
			var seed_keys:Array=row.get("seed_costs",{}).keys()
			for seed in row.get("missing",{}):
				if seed not in seed_keys:seed_keys.append(seed)
			for seed in seed_keys:detail.text+="\n"+Text.text("local.commands.seed_line")%[Text.content(world.farms.crops.get(str(seed).trim_prefix("seed."),{}).get("name",str(seed))),int(row.get("seed_costs",{}).get(seed,0))+int(row.get("missing",{}).get(seed,0)),int(row.get("missing",{}).get(seed,0))]
			detail.text+="\n"+Text.text("local.commands.executable_plots")%row.get("plot_ids",[]).size()
		if not row.allowed:
			var reason:String=str(row.get("reason","busy"));detail.text+="\n"+(Text.text("farm.help."+reason) if Text.entries.has("farm.help."+reason) else Text.content(reason));box.add_theme_color_override("font_disabled_color",Color("d7ddda"))
	confirmed.connect(func():decision.emit(card_id,true,boxes.keys().filter(func(id):return boxes[id].button_pressed and not boxes[id].disabled)))
	canceled.connect(func():decision.emit(card_id,false,[]));close_requested.connect(func():decision.emit(card_id,false,[]))
	about_to_popup.connect(func():
		get_label().hide()
		var bounds:Vector2i=get_parent().get_viewport().get_visible_rect().size
		scroll.custom_minimum_size=Vector2(mini(620,bounds.x-100),mini(300,maxi(120,bounds.y-280)));size=Vector2i(mini(740,bounds.x-48),mini(570,bounds.y-64));position=(bounds-size)/2)

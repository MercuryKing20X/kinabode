extends Node
const Text=preload("res://scripts/localization.gd")
var game:Node
var selected:Array=[]
var body:VBoxContainer
var grid:GridContainer
var tabs:HBoxContainer
var targets:HBoxContainer
var legacy:Array=[]
var commands_mode:=true
var category:=0
var counts:Dictionary={}
var sending:Label
var switch_talk:Button
var progress:VBoxContainer
var records:Label
var buttons:Dictionary={}
var tick:=0.0
var entries:Array=[]
var chat_header:Node
func en()->bool:return TranslationServer.get_locale().begins_with("en")
func label(zh:String,english:String)->String:return english if en() else zh
func setup(source:Node,column:VBoxContainer)->void:
	game=source
	chat_header=column.get_child(0)
	for child in column.get_children():
		if child!=column.get_child(0) and child!=column.get_child(column.get_child_count()-1):legacy.append(child)
	var cfg:=ConfigFile.new();cfg.load(game.data_dir.path_join("command-clicks.cfg"));counts=cfg.get_value("commands","counts",{})
	tabs=HBoxContainer.new();column.add_child(tabs);tabs.hide()
	targets=HBoxContainer.new();column.add_child(targets);column.move_child(targets,2)
	sending=Label.new();column.add_child(sending);column.move_child(sending,3)
	progress=VBoxContainer.new();column.add_child(progress);column.move_child(progress,4)
	body=VBoxContainer.new();column.add_child(body);column.move_child(body,5);body.size_flags_vertical=Control.SIZE_EXPAND_FILL
	var categories:=OptionButton.new();categories.focus_mode=Control.FOCUS_NONE;body.add_child(categories)
	for name in [[preload("res://scripts/localization.gd").source("content.health_20261107.4563c57b5143"),"Frequent"],[preload("res://scripts/localization.gd").source("content.health_20261107.19a7e929b39a"),"Together"],[preload("res://scripts/localization.gd").source("content.health_20261107.4bcae7930943"),"Work"],[preload("res://scripts/localization.gd").source("content.health_20261107.e1d2a9310891"),"Meals"],[preload("res://scripts/localization.gd").source("content.health_20261107.7d6739abb05e"),"Play"],[preload("res://scripts/localization.gd").source("content.health_20261107.daefa6caaf81"),"Ask"],[preload("res://scripts/localization.gd").source("content.health_20261107.16833aa2becf"),"Stop"]]:categories.add_item(label(name[0],name[1]))
	categories.item_selected.connect(func(index):category=index;rebuild())
	var scroll:=ScrollContainer.new();body.add_child(scroll);scroll.vertical_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;scroll.custom_minimum_size.y=42
	grid=GridContainer.new();grid.columns=64;grid.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(grid)
	records=Label.new();body.add_child(records);records.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	entries=JSON.parse_string(FileAccess.get_file_as_string("res://content/companions/command-presets.json"))
	game.chat.visibility_changed.connect(func():
		if game.chat.visible:
			if selected.is_empty():selected=actors()
			show_mode(true);rebuild_targets();rebuild())
	switch_talk=Button.new();body.add_child(switch_talk);switch_talk.hide();switch_talk.pressed.connect(func():show_mode(false);game.chat_input.grab_focus())
	show_mode(true)
func actors()->Array:return game.world.actors.keys().filter(func(id):return id!="human")
func show_mode(_mode:bool)->void:
	commands_mode=false
	var names:Array=[[Text.source("content.health_20261107.4563c57b5143"),"Frequent"],[Text.source("content.health_20261107.19a7e929b39a"),"Together"],[Text.source("content.health_20261107.4bcae7930943"),"Work"],[Text.source("content.health_20261107.e1d2a9310891"),"Meals"],[Text.source("content.health_20261107.7d6739abb05e"),"Play"],[Text.source("content.health_20261107.daefa6caaf81"),"Ask"],[Text.source("content.health_20261107.16833aa2becf"),"Stop"]]
	for index in names.size():body.get_child(0).set_item_text(index,label(names[index][0],names[index][1]))
	for child in legacy:child.show()
	# Connection and local-life settings already live on the resident card.
	for child in legacy:
		if child==game.daily_controls or child.get_children().has(game.controller_picker):child.hide()
	body.show();targets.show();sending.show();progress.show()
	tabs.hide()
	body.size_flags_vertical=0
	var column:Node=body.get_parent()
	column.move_child(body,column.get_child_count()-1)
	if game.chat_input.get_parent().get_parent()==column:column.move_child(game.chat_input.get_parent(),column.get_child_count()-1)
	game.chat.offset_top=-minf(590,game.get_viewport_rect().size.y-100)
	if not selected.is_empty():rebuild_targets()
func rebuild_targets()->void:
	for child in targets.get_children():targets.remove_child(child);child.queue_free()
	var all:=Button.new();all.focus_mode=Control.FOCUS_NONE;targets.add_child(all);all.text=label(preload("res://scripts/localization.gd").source("content.command_grammar.token_9"),"Everyone");all.toggle_mode=true;all.button_pressed=selected.size()==actors().size();all.pressed.connect(func():selected=actors();rebuild_targets();rebuild())
	for id in actors():
		var b:=Button.new();b.focus_mode=Control.FOCUS_NONE;targets.add_child(b);b.toggle_mode=true;b.button_pressed=id in selected;b.text=Text.resident(game.world,id)+(label(preload("res://scripts/localization.gd").source("content.health_20261107.5adfc8732da2"),"·Very hungry") if game.world.hunger.rank(id)>=3 else "")+(label(preload("res://scripts/localization.gd").source("content.health_20261107.aa0b7e25b6e6"),"·Away") if game.world.actors[id].region_id!=game.world.actors.human.region_id else "")
		b.modulate=Color.WHITE if id in selected else Color(.55,.55,.55)
		if game.island_hud!=null and game.island_hud.avatar_buttons.has(id):
			b.icon=game.island_hud.avatar_buttons[id].icon;b.tooltip_text=b.text;b.text="";b.expand_icon=true;b.add_theme_constant_override("icon_max_width",22);b.custom_minimum_size.x=30
		b.pressed.connect(func():
			if Input.is_key_pressed(KEY_SHIFT):toggle_target(id)
			else:selected=[id]
			rebuild_targets();rebuild())
		var check:=CheckBox.new();check.focus_mode=Control.FOCUS_NONE;targets.add_child(check);check.button_pressed=id in selected;check.tooltip_text=label(preload("res://scripts/localization.gd").source("content.health_20261107.461e085d5ca2"),"Multi-select");check.pressed.connect(func():toggle_target(id);rebuild_targets();rebuild())
	if selected.size()==1:game._select_chat(selected[0])
	elif not selected.is_empty():game._select_chat(game.Channels.ALL)
	sending.text=Text.text("ui.chat.sending_sentence")+", ".join(selected.map(func(id):return Text.resident(game.world,id)))
func toggle_target(id:String)->void:
	if id in selected:selected.erase(id)
	else:selected.append(id)
func preset_text(row:Dictionary)->String:
	var text:String=row.en if en() else row.zh
	text=text.trim_prefix(preload("res://scripts/localization.gd").source("content.command_grammar.token_17")).trim_prefix(preload("res://scripts/localization.gd").source("content.command_grammar.token_18"))
	var names:Array=selected.map(func(id):return Text.resident(game.world,id))
	return " ".join(names)+" "+text
func reason(row:Dictionary)->String:
	if row.id in ["flowers.arrange","flowers.gift"]:return "" if not selected.is_empty() else Text.text("local.commands.select")
	if row.has("resort_kind"):
		return "" if game.world.resort.vacation("human") else label(preload("res://scripts/localization.gd").source("content.health_20261107.53f977c720e6"),"Walk to the holiday island first")
	if selected.is_empty():return label(preload("res://scripts/localization.gd").source("content.health_20261107.9dd9dba71abf"),"Select companions")
	if row.has("blocked"):return label(row.blocked[0],row.blocked[1])
	var parser:RefCounted=game.local_host_commands.parser
	var parsed:Dictionary=parser.parse_command(game.world,preset_text(row),selected)
	if not parsed.get("ok",false):return label(preload("res://scripts/localization.gd").source("content.health_20261107.12c7cc425f11"),"No executable entry")
	if parsed.action=="query_state":return ""
	if selected.any(func(id):return game.world.director.model_controlled(id) or game.world.actors[id].has("world_door_client")):return ""
	var plan:Dictionary=game.local_host_commands.preview(parsed,selected.filter(func(id):return not game.world.director.model_controlled(id)))
	if plan.rows.any(func(r):return r.allowed):return ""
	if plan.rows.is_empty():return label(preload("res://scripts/localization.gd").source("content.health_20261107.c4d2c4453dd9"),"Use Talk for connected companions")
	var why:String=str(plan.rows[0].get("reason",""))
	return Text.text("farm.help."+why) if Text.entries.has("farm.help."+why) else (why if not why.is_empty() else label(preload("res://scripts/localization.gd").source("content.health_20261107.525066d3a619"),"No work available"))
func rebuild()->void:
	buttons.clear()
	for child in grid.get_children():grid.remove_child(child);child.queue_free()
	var rows:Array=entries.filter(func(row):return category==0 or row.category==category)
	rows.sort_custom(func(a,b):
		if game.world.resort.vacation("human") and a.has("resort_kind")!=b.has("resort_kind"):return a.has("resort_kind")
		var aa:bool=reason(a).is_empty();var bb:bool=reason(b).is_empty()
		if aa!=bb:return aa
		return int(counts.get(a.id,0))>int(counts.get(b.id,0)))
	if category==0:rows=rows.slice(0,6)
	for row in rows:
		var b:=Button.new();b.focus_mode=Control.FOCUS_NONE;grid.add_child(b);b.size_flags_horizontal=Control.SIZE_EXPAND_FILL;b.text=row.en if en() else row.zh;b.tooltip_text=reason(row);b.disabled=not b.tooltip_text.is_empty();buttons[row.id]=b
		b.pressed.connect(func():
			counts[row.id]=int(counts.get(row.id,0))+1
			var cfg:=ConfigFile.new();cfg.set_value("commands","counts",counts);cfg.save(game.data_dir.path_join("command-clicks.cfg"))
			if row.id=="flowers.arrange":game._open_flowers(selected);game.chat.hide()
			elif row.id=="flowers.gift":game._send(preset_text(row))
			else:game._send(preset_text(row))
			rebuild())
func dispatch(_text:String)->bool:
	return false
func _process(delta:float)->void:
	if game==null or not game.chat.visible:return
	tick+=delta
	if tick>=1:
		tick=0;rebuild()
		for child in progress.get_children():progress.remove_child(child);child.queue_free()
		for item in game.local_host_commands.tracked:
			for id in item.actors:
				if id in item.finished or id in item.canceled:continue
				var row:=HBoxContainer.new();progress.add_child(row)
				var info:=Label.new();row.add_child(info);info.text=label(preload("res://scripts/localization.gd").source("content.health_20261107.eda42c87835f"),"In progress: ")+Text.resident(game.world,id)+" · "+Text.text("local.commands.action_"+item.action)+game.local_host_commands.progress_text(id,item)
				var back:=Button.new();back.focus_mode=Control.FOCUS_NONE;row.add_child(back);back.text=label(preload("res://scripts/localization.gd").source("content.health_20261107.a6acd2a4549b"),"Come back");back.pressed.connect(func():game.local_host_commands.recall(id))

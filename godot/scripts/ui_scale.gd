extends Node
## Host presentation preference only. Never changes camera, world state or artwork.
const Text=preload("res://scripts/localization.gd")
const FACTORS=[0.9,1.1,1.3,1.5]
static var current_factor:=1.3
static func factor()->float:return current_factor
static func pixels(base:float)->int:return maxi(1,roundi(base*current_factor))
var level:=2
var game:Node
var interface:Control
var path:=""
var pending:Dictionary={}
var applying:=false
signal changed(index:int)
func setup(host:Node,ui_root:Control,directory:String)->void:
	game=host;interface=ui_root;interface.set_meta("ui_scale_manager",self);path=directory.path_join("local-life.cfg")
	var cfg:=ConfigFile.new();cfg.load(path)
	var stored:Variant=cfg.get_value("interface","scale_index",-1)
	if stored is int and stored>=0 and stored<4:level=stored
	elif cfg.has_section_key("interface","size"):
		var old:String=str(cfg.get_value("interface","size"))
		level=0 if old==Text.source("hud.size_small") else 2 if old==Text.source("hud.size_large") else 1
	current_factor=FACTORS[level]
	get_tree().node_added.connect(_added)
	get_viewport().size_changed.connect(refresh)
	refresh()
func set_level(index:int,persist:=true)->void:
	level=clampi(index,0,3);current_factor=FACTORS[level]
	if persist:
		var cfg:=ConfigFile.new();cfg.load(path);cfg.set_value("interface","scale_index",level);cfg.set_value("interface","size",[Text.source("hud.size_small"),Text.source("hud.size_standard"),Text.source("hud.size_large"),Text.source("ui.scale.extra")][level]);cfg.save(path)
	refresh();changed.emit(level)
func add_settings(parent:Node)->void:
	var row:=HBoxContainer.new();parent.add_child(row)
	var label:=Label.new();label.text=Text.text("ui.scale.title");row.add_child(label)
	var slider:=HSlider.new();slider.min_value=0;slider.max_value=3;slider.step=1;slider.value=level;slider.custom_minimum_size.x=170;slider.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(slider)
	var caption:=Label.new();row.add_child(caption)
	var slider_ref:WeakRef=weakref(slider);var caption_ref:WeakRef=weakref(caption)
	var update:=func(index:int):
		var current_slider:HSlider=slider_ref.get_ref();var current_caption:Label=caption_ref.get_ref()
		if current_slider==null or current_caption==null:return
		current_slider.set_value_no_signal(index);current_caption.text=Text.text(["ui.scale.small","ui.scale.medium","ui.scale.large","ui.scale.extra"][index])+" · "+str(roundi(FACTORS[index]*100))+"%"
	update.call(level);changed.connect(update);slider.value_changed.connect(func(value:float):set_level(int(value)))
	slider.tree_exiting.connect(func():
		if changed.is_connected(update):changed.disconnect(update))

func _added(node:Node)->void:
	if node==self or applying:return
	if node is Control or node is Window:call_deferred("_new",weakref(node))
func _new(reference:WeakRef)->void:
	var node:Node=reference.get_ref()
	if node==null or not node.is_inside_tree():return
	if not game.is_ancestor_of(node):return
	apply_branch(node)
func refresh()->void:
	if not is_instance_valid(game):return
	apply_branch(game)
	if game.get("island_hud")!=null:
		var hud:Node=game.island_hud;hud.ui_size_mode=[Text.source("hud.size_small"),Text.source("hud.size_standard"),Text.source("hud.size_large"),Text.source("ui.scale.extra")][level];hud.layout_residents();hud.layout_primary_actions()
		var popup:PopupMenu=hud.settings_menu.get_popup()
		for index in range(4):
			var item:int=popup.get_item_index([91,92,93,95][index])
			if item>=0:popup.set_item_checked(item,index==level)
	if game.get("view")!=null:game.view.queue_redraw()
func apply_branch(node:Node)->void:
	if node==self:return
	if node is Control:
		var c:Control=node
		if c is Label or c is BaseButton or c is LineEdit or c is TextEdit or c is RichTextLabel or c is ItemList or c is Tree:
			for key in (["normal_font_size","bold_font_size","italics_font_size","mono_font_size"] if c is RichTextLabel else ["font_size"]):
				var meta:String="ui_scale_base_"+key
				if not c.has_meta(meta):c.set_meta(meta,c.get_meta("ui_font_base",c.get_theme_font_size(key)))
				c.add_theme_font_size_override(key,pixels(float(c.get_meta(meta))))
		if not c.has_meta("ui_scale_min"):c.set_meta("ui_scale_min",c.custom_minimum_size)
		var base:Vector2=c.get_meta("ui_scale_min")
		c.custom_minimum_size=base*factor() if not c.has_meta("ui_scale_wrapper") else base
		if c is Button:c.custom_minimum_size.y=maxf(c.custom_minimum_size.y,pixels(30))
		if c is Label and c.get_minimum_size().x>interface.get_viewport_rect().size.x-48:c.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		if c is BoxContainer or c is FlowContainer or c is GridContainer:
			for key in (["h_separation","v_separation"] if c is FlowContainer or c is GridContainer else ["separation"]):
				var meta:String="ui_scale_base_"+key
				if not c.has_meta(meta):c.set_meta(meta,c.get_theme_constant(key))
				c.add_theme_constant_override(key,pixels(float(c.get_meta(meta))))
		if c is PanelContainer and not c.get_parent() is Container and not c.get_meta("chess_scene_surface",false):_watch_fit(c)
	if node is PopupMenu:
		if not node.has_meta("ui_scale_font"):node.set_meta("ui_scale_font",node.get_theme_font_size("font_size"))
		node.add_theme_font_size_override("font_size",pixels(node.get_meta("ui_scale_font")))
	if node is Window:
		node.add_theme_font_size_override("title_font_size",pixels(16));_watch_fit(node)
	for child in node.get_children(true):apply_branch(child)
	if (node is PanelContainer or node is Window) and not node.get_meta("chess_scene_surface",false):_queue_fit(node)
func _watch_fit(node:Node)->void:
	if node.has_meta("ui_scale_fit"):return
	node.set_meta("ui_scale_fit",true)
	if node is Control:node.resized.connect(func():_queue_fit(node));node.visibility_changed.connect(func():_queue_fit(node))
	elif node is Window:node.size_changed.connect(func():_queue_fit(node));node.visibility_changed.connect(func():_queue_fit(node))
func _queue_fit(node:Node)->void:
	var id:int=node.get_instance_id()
	if pending.has(id):return
	pending[id]=true;call_deferred("_fit",weakref(node),id)
func _fit(reference:WeakRef,id:int)->void:
	pending.erase(id)
	var node:Node=reference.get_ref()
	if node==null or not node.is_inside_tree() or node.get_meta("chess_scene_surface",false) or node.get_meta("watch_menu",false):return
	var available:Vector2=interface.get_viewport_rect().size-Vector2(24,56 if node is Window else 24)
	if node==game.get("chat"):
		var hud:Node=game.get("island_hud")
		available.y=minf(available.y,hud.primary_actions.global_position.y-24 if hud!=null else interface.get_viewport_rect().size.y-84)
	if node is Control and (not node is PanelContainer or node.get_parent() is Container):return
	# Keep the chat header and input reachable above the bottom action dock.
	if node==game.get("chat") and not node.has_meta("chat_scroll_body"):
		node.set_meta("chat_scroll_body",true)
		var column:VBoxContainer=node.get_child(0)
		var children:Array=column.get_children()
		var scroll:=ScrollContainer.new();scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
		var content:=VBoxContainer.new();content.size_flags_horizontal=Control.SIZE_EXPAND_FILL
		column.add_child(scroll);column.move_child(scroll,1);scroll.add_child(content)
		for index in range(1,children.size()-1):
			var child:Node=children[index]
			var page:Node=game.get("command_page")
			if page!=null and child in [page.body,page.targets,page.sending]:continue
			child.reparent(content,false)
		var page:Node=game.get("command_page")
		if page!=null and page.sending.get_parent()==column:column.move_child(scroll,column.get_children().find(page.sending))
	# Long free panels keep their real font size, with content in a scroll viewport.
	var bodies:Array=[]
	for child in node.get_children():
		if child is Control and not child is ScrollContainer and not child.has_meta("ui_scale_wrapper"):bodies.append(child)
	for child in node.get_children():
		if child is ScrollContainer and (child.has_meta("ui_scale_wrapper") or node is Window):
			child.custom_minimum_size=Vector2(minf(child.custom_minimum_size.x,available.x-24),minf(child.custom_minimum_size.y,available.y-90)) if node is Window else Vector2.ZERO
	var minimum:Vector2=node.get_combined_minimum_size() if node is Control else Vector2(node.get_contents_minimum_size())
	if minimum.x>available.x or minimum.y>available.y:
		for body in bodies:
			if body.get_parent()!=node:continue
			var scroll:=ScrollContainer.new();scroll.set_meta("ui_scale_wrapper",true);scroll.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL
			scroll.set_meta("ui_scale_min",Vector2.ZERO);node.add_child(scroll);body.reparent(scroll,false);body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;body.size_flags_vertical=Control.SIZE_EXPAND_FILL
			if node is Window:
				scroll.custom_minimum_size=Vector2(minf(minimum.x,available.x-24),minf(minimum.y,available.y-90));scroll.set_meta("ui_scale_min",scroll.custom_minimum_size)
	if node is Control:
		node.custom_minimum_size=node.custom_minimum_size.min(available)
		node.size=node.size.min(available)
		var parent:Control=node.get_parent() as Control
		if parent!=null:
			var bounds:Vector2=parent.size
			if node==game.get("chat") and game.get("island_hud")!=null:bounds.y=game.island_hud.primary_actions.global_position.y-12
			node.position=Vector2(clampf(node.position.x,12,maxf(12,bounds.x-node.size.x-12)),clampf(node.position.y,12,maxf(12,bounds.y-node.size.y-12)))
	elif node is Window:
		node.max_size=Vector2i(available)
		if not node is PopupMenu:
			node.min_size=Vector2i.ZERO;node.size=Vector2i(Vector2(node.size).min(available));node.position=Vector2i(Vector2(node.position).clamp(Vector2(12,32),(interface.get_viewport_rect().size-Vector2(node.size)-Vector2(12,12)).max(Vector2(12,32))))

func modal_open()->bool:
	return (is_instance_valid(game) and game.get("chat")!=null and game.chat.visible) or full_modal_open()
func full_modal_open()->bool:
	if not is_instance_valid(interface):return false
	for child in interface.get_children():
		if (child==game.get("action_dock") and game.get("watch_ui")!=null) or child==game.get("island_hud") or child==game.get("chat") or not child is Control or not child.visible:continue
		if child is PanelContainer and child.size.x>=interface.size.x*.25 and child.size.y>=100:return true
		if child.size.x>=interface.size.x*.9 and child.size.y>=interface.size.y*.9:
			for panel in child.find_children("*","PanelContainer",true,false):
				if panel.is_visible_in_tree() and panel.size.x>=interface.size.x*.35 and panel.size.y>=interface.size.y*.35:return true
	return false

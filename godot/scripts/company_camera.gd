extends CanvasLayer
const Text=preload("res://scripts/localization.gd")
var c:Node
var g:Node:
	get:return c.g
var w:RefCounted:
	get:return c.w
var active:=false
var was_paused:=false
var point:=Vector2.ZERO
var region:=""
var zoom:=1.0
var drag:=false
var overlay:Control
var preview:TextureRect
var finder:SubViewport
var camera_view:Node2D
var message:Label
var shooting:=false
var last_photo:=""
var people:Array=[]
func setup(owner:Node)->void:
	c=owner;layer=100;process_mode=Node.PROCESS_MODE_ALWAYS
func launch()->void:
	if active or DisplayServer.get_name()=="headless":return
	active=true;was_paused=get_tree().paused;get_tree().paused=true
	point=g.view.center;region=g.view.region_id;zoom=g.view.zoom
	overlay=Control.new();overlay.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(overlay);overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.theme=g.island_hud.ui_root.theme
	var background:=ColorRect.new();background.color=Color("172d2a");background.mouse_filter=Control.MOUSE_FILTER_IGNORE;overlay.add_child(background);background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	finder=SubViewport.new();finder.size=Vector2i(960,600);overlay.add_child(finder)
	camera_view=g.view.get_script().new();camera_view.world=w;camera_view.library=g.library;camera_view.font=g.view.font;camera_view.sound_enabled=false;camera_view.memory_photo=true
	finder.add_child(camera_view);camera_view.set_process(false);camera_view.set_process_unhandled_input(false)
	preview=TextureRect.new();preview.texture=finder.get_texture();preview.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;preview.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;preview.mouse_filter=Control.MOUSE_FILTER_IGNORE
	overlay.add_child(preview);preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);preview.offset_top=16;preview.offset_bottom=-74
	var center:=CenterContainer.new();overlay.add_child(center);center.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE);center.offset_top=-64;center.offset_bottom=-12
	var row:=HBoxContainer.new();center.add_child(row)
	var minus:Button=c.button(row,"ZoomOut","−",func():zoom_by(.85));minus.tooltip_text=c.tr_key("zoom_out")
	var plus:Button=c.button(row,"ZoomIn","+",func():zoom_by(1.18));plus.tooltip_text=c.tr_key("zoom_in")
	c.button(row,"Shutter",c.tr_key("shutter"),take)
	c.button(row,"Folder",c.tr_key("photo_folder"),open_folder)
	c.button(row,"Close",Text.text("hud.close"),close)
	message=Label.new();overlay.add_child(message);message.position=Vector2(21,12)
	refresh()
func refresh()->void:
	if not active:return
	camera_view.region_id=region;camera_view.center=point;camera_view.zoom=zoom;camera_view.clock=g.view.clock
	people=[]
	camera_view.photo_poses.clear()
	for id in w.actors:
		var actor:Dictionary=w.actors[id]
		var at:Vector2=w.point(actor)
		if actor.region_id!=region or not Rect2(0,0,960,600).has_point(camera_view.screen(at)):continue
		people.append(id)
		if id=="human" or at.distance_to(point)>float(c.settings.photo_radius) or w._routes.has(id) or c.busy(id) or w.hunger.rank(id)>=3:continue
		camera_view.photo_poses[id]={"activity":{"lively":"play_cute","quiet":"fire_sit","laborious":"gesture_wave","gentle":"gesture_wave"}[c.tag(id)],"facing":"down"}
	camera_view.queue_redraw()
	finder.render_target_update_mode=SubViewport.UPDATE_ONCE
func zoom_by(amount:float)->void:
	zoom=clampf(zoom*amount,.28,2.4);refresh()
func _input(event:InputEvent)->void:
	if not active:return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE:close()
		elif event.keycode==KEY_SPACE:take()
		elif event.keycode in [KEY_UP,KEY_DOWN,KEY_LEFT,KEY_RIGHT]:
			point+=Vector2(int(event.keycode==KEY_RIGHT)-int(event.keycode==KEY_LEFT),int(event.keycode==KEY_DOWN)-int(event.keycode==KEY_UP))*2
			refresh()
		else:return
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT:
		drag=event.pressed;get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and drag:
		point-=event.relative/(zoom*32);refresh();get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		zoom_by(1.12 if event.button_index==MOUSE_BUTTON_WHEEL_UP else .89);get_viewport().set_input_as_handled()
func open_folder()->void:
	var folder:String=g.data_dir.path_join("photos")
	if DirAccess.make_dir_recursive_absolute(folder)==OK:OS.shell_open(folder)
func take()->void:
	if not active or shooting:return
	shooting=true
	finder.render_target_update_mode=SubViewport.UPDATE_ONCE
	await RenderingServer.frame_post_draw
	if not active:return
	var image:Image=finder.get_texture().get_image()
	if image==null or image.is_empty():shooting=false;message.text=c.tr_key("photo_failed");return
	var key:String=Crypto.new().generate_random_bytes(12).hex_encode()
	var place:String=str(w.region_info(region).get("name",region))
	var phase:String=str(w.days.phase().name)
	var names:Array=people.map(func(id):return Text.resident(w,id))
	var metadata:Dictionary={"region_id":region,"place":place,"people":people.duplicate(),"names":names,"phase":w.days.phase().id,"phase_label":phase,"time":w.days.within_day()}
	for locale in ["zh","en"]:
		metadata["names_"+locale]=[]
		for index in people.size():
			var actor:Dictionary=w.actors[people[index]]
			var label:String=names[index]
			if not actor.get("custom_name",false):
				for name_key in ["resident.you","resident.snow","resident.skye","resident.clem","resident.raven","resident.mira","resident.nora"]:
					if not Text.entries.has(name_key) or str(actor.name)!=Text.source(name_key):continue
					label=str(Text.entries[name_key][locale]);break
			metadata["names_"+locale].append(label)
	var result_path:String=g.memory_books.player_photo(w.world_id,key,image,w.days.day(),w.forest.clock,metadata)
	last_photo=result_path
	message.text=c.tr_key("photo_failed" if result_path.is_empty() else "photo_saved")
	if not result_path.is_empty():c.note("photo",{"region":region,"people":people.duplicate()})
	shooting=false
func close()->void:
	if not active:return
	active=false;drag=false;shooting=false
	get_tree().paused=was_paused
	overlay.queue_free();overlay=null
	preview=null;finder=null;camera_view=null;message=null

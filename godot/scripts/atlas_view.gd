class_name IslandAtlas
extends Node2D
const LocalText=preload("res://scripts/localization.gd")
var _locale_static:Dictionary={}
func T(key:String)->String:
	var value:String=LocalText.text(key);_locale_static[value]=key;return value
func _mark_static(node:Node)->void:
	if node is Label or (node is Button and not node is OptionButton):
		if _locale_static.has(node.text):node.set_meta("panels_locale",_locale_static[node.text])
	for child in node.get_children():_mark_static(child)
func _refresh_static(node:Node)->void:
	if node.has_meta("panels_locale"):node.text=T(str(node.get_meta("panels_locale")))
	for child in node.get_children():_refresh_static(child)
## World planning view only. These cartographic symbols are not final game assets.
var navigation_mode:=false
var world: RefCounted
var font: Font
var center := Vector2.ZERO
var scale_factor := 1.0
var show_zones := true
var selected_region := "home"
var selected_point:=Vector2.ZERO
var initialized := false
var panel: PanelContainer
var island_list: VBoxContainer
var detail: RichTextLabel
var view_button: Button
var time := 0.0
var dragging := false
signal land_clicked(region_id: String, local: Vector2)
signal selected(region_id: String)

const ZONE_COLORS := {"storage": Color("a39167"), "housing": Color("cba877"), "farming": Color("9f744d"), "resources": Color("416453"), "orchard": Color("859257"), "shore": Color("c8bc93"), "scenery": Color("82977b")}

func _process(delta: float) -> void:
	time += delta
	queue_redraw()

func screen_position(point: Vector2) -> Vector2:
	return (point - center) * scale_factor + map_rect().get_center()

func world_position(point: Vector2) -> Vector2:
	return (point - map_rect().get_center()) / scale_factor + center

func map_rect() -> Rect2:
	return Rect2(Vector2(320,90),Vector2(maxf(200,get_viewport_rect().size.x-345),maxf(200,get_viewport_rect().size.y-190)))

func fit_regions(ids: Array) -> void:
	if ids.is_empty():return
	var bounds:=Rect2()
	var first:=true
	for id in ids:
		var region: Dictionary=world.catalog.regions[id]
		var area:=Rect2(Vector2(region.origin[0],region.origin[1])+world.catalog.local_origin(region),Vector2(region.size[0],region.size[1]))
		bounds=area if first else bounds.merge(area);first=false
		for pen in world.fishing.pens.values():
			if pen.region_id==id:bounds=bounds.merge(Rect2(world.catalog.rectangle(pen.rect).position+Vector2(region.origin[0],region.origin[1]),world.catalog.rectangle(pen.rect).size))
	bounds=bounds.grow(12)
	center=bounds.get_center()
	scale_factor=clampf(minf(map_rect().size.x/bounds.size.x,map_rect().size.y/bounds.size.y),.01,22)

func focus(region_id: String) -> void:
	if not world.catalog.regions.has(region_id):return
	select_region(region_id);fit_regions([region_id])

func overview() -> void: fit_regions(world.catalog.regions.keys())

func nearby() -> void:
	var home: Dictionary=world.catalog.regions.home
	var anchor:=Vector2(home.origin[0],home.origin[1])+Vector2(home.size[0],home.size[1])/2
	var ids: Array=["home"]
	if world.catalog.regions.has("dark"):
		fit_regions(["home","dark"]);return
	# Nearest neighbours, independent of their names or world location.
	var others: Array=world.catalog.regions.keys().filter(func(id):return id!="home")
	others.sort_custom(func(a,b):return _region_center(a).distance_squared_to(anchor)<_region_center(b).distance_squared_to(anchor))
	ids.append_array(others.slice(0,6));fit_regions(ids)

func _region_center(id: String) -> Vector2:
	var region: Dictionary=world.catalog.regions[id]
	return Vector2(region.origin[0],region.origin[1])+world.catalog.local_origin(region)+Vector2(region.size[0],region.size[1])/2

func clamp_center() -> void:
	var bounds: Rect2=world.catalog.rectangle(world.catalog.manifest.bounds)
	center=center.clamp(bounds.position,bounds.end)

func build_ui(root: Control) -> void:
	panel=PanelContainer.new();root.add_child(panel)
	panel.position=Vector2(20,82);panel.custom_minimum_size=Vector2(280,0)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	panel.offset_left=20;panel.offset_right=300;panel.offset_top=82
	panel.anchor_bottom=1;panel.offset_bottom=-100
	var style:=StyleBoxFlat.new();style.bg_color=Color("203e3c");style.content_margin_left=12;style.content_margin_right=12;style.content_margin_top=12;style.content_margin_bottom=12
	panel.add_theme_stylebox_override("panel",style)
	var column:=VBoxContainer.new();column.add_theme_constant_override("separation",8);panel.add_child(column)
	var title:=Label.new();title.text=T("panels.youqi_archipelago");column.add_child(title)
	var controls:=HBoxContainer.new();column.add_child(controls)
	_button(controls,T("panels.home"),func():focus("home"))
	_button(controls,T("panels.nearby"),nearby);_button(controls,T("panels.all"),overview)
	_button(column,T("panels.find_me"),func():
		var actor: Dictionary=world.actors.human
		var id: String=actor.region_id
		if world.interior.rooms().has(id):id="home"
		focus(id)
		center=Vector2(world.catalog.regions[id].origin[0],world.catalog.regions[id].origin[1])+(world.interior.outside(actor.region_id) if world.interior.rooms().has(actor.region_id) else world.point(actor)))
	var scroll:=ScrollContainer.new();scroll.custom_minimum_size.y=90;scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(scroll)
	island_list=VBoxContainer.new();island_list.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(island_list)
	detail=RichTextLabel.new();detail.custom_minimum_size.y=145;detail.size_flags_vertical=Control.SIZE_EXPAND_FILL;column.add_child(detail)
	view_button=_button(column,T("panels.view_home_locations"),func():land_clicked.emit("home",selected_point))
	var help:=Label.new();help.text=T("panels.wheel_to_zoom_right_drag_to_pan_nclick_an_island_for_details");column.add_child(help)
	panel.hide()

	_mark_static(panel)
	if not LocalText.events.changed.is_connected(refresh_locale):LocalText.events.changed.connect(refresh_locale)

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button:=Button.new();button.focus_mode=Control.FOCUS_NONE;button.text=text;
	if _locale_static.has(text):button.set_meta("panels_locale",_locale_static[text])
	button.focus_mode=Control.FOCUS_NONE;button.pressed.connect(callback);parent.add_child(button);return button

func open() -> void:
	for child in island_list.get_children():island_list.remove_child(child);child.queue_free()
	for id in world.catalog.regions:
		var row:=_button(island_list,LocalText.content(str(world.catalog.regions[id].name)),func():focus(id));row.set_meta("region_id",id)
		row.clip_text=true
	if not world.catalog.regions.home.get("layout",{}).get("moon",{}).is_empty():
		_button(island_list,T("panels.moon_island_walk_across_the_bridge"),func():
			focus("home");var at:Array=world.map_anchor("moon.lookout");selected_point=Vector2(at[0],at[1]);center=Vector2(world.catalog.regions.home.origin[0],world.catalog.regions.home.origin[1])+selected_point)
	if world.catalog.regions.home.get("layout",{}).has("homelands") and (world.opening_id!="standard" or world.their_island.introduced or world.home_island.landed):
		_button(island_list,T("homeisland.walking"),func():
			focus("home");selected_point=Vector2(81,190);center=Vector2(world.catalog.regions.home.origin[0],world.catalog.regions.home.origin[1])+selected_point)
	var reopening:=initialized
	if not initialized:nearby();initialized=true
	if navigation_mode:focus("home")
	var retained_point:=selected_point
	select_region(selected_region if world.catalog.regions.has(selected_region) else "home")
	if reopening:selected_point=retained_point
	panel.show()

func select_region(id: String) -> void:
	selected_region=id;selected.emit(id)
	selected_point=world.catalog.local_origin(world.catalog.regions[id])+Vector2(world.catalog.regions[id].size[0],world.catalog.regions[id].size[1])/2
	if detail==null:return
	var info: Dictionary=world.read_map("human",{"region_id":id}).region
	detail.clear();detail.add_text(str(LocalText.content(info.name))+"\n"+(T("panels.dark_island_north_shore_bridge") if id=="dark" else T("panels.home_a_place_to_live") if info.availability=="home" else T("panels.view_only_travel_not_open_yet"))+"\n")
	detail.add_text(T("panels.position_0f_0f_0f_0f_tiles_n")%[info.origin[0],info.origin[1],info.size[0],info.size[1]])
	var zones: Array[String]=[]
	for zone in info.zones:zones.append(str(LocalText.content(zone.name)))
	var version: Variant=info.pack.get("version",1)
	var version_label:=str(int(version)) if (version is int or version is float) and is_finite(version) else str(version)
	detail.add_text(T("panels.regions")+("、".join(zones) if not zones.is_empty() else T("panels.none_listed"))+T("panels.ncontent_pack_s_v_s")%[LocalText.content(str(info.pack.get("name",""))),version_label])
	if id=="home" and not info.get("walking_areas",{}).is_empty():detail.add_text(T("panels.nmoon_island_reachable_on_foot_same_region"))
	view_button.disabled=id!="home"

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_MIDDLE, MOUSE_BUTTON_RIGHT]: dragging = event.pressed
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var before := world_position(event.position)
			scale_factor = clampf(scale_factor * (1.16 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1 / 1.16), 0.01, 22)
			center += before - world_position(event.position)
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var point := world_position(event.position)
			for region in world.catalog.regions.values():
				var local := point - Vector2(region.origin[0], region.origin[1])
				if world.terrain_surface(region.id,local):
					select_region(region.id)
					selected_point=local
					if navigation_mode:land_clicked.emit(region.id,local)
					get_viewport().set_input_as_handled()
					break
	elif event is InputEventMouseMotion and dragging:
		center -= event.relative / scale_factor
		clamp_center()

func _draw() -> void:
	if world == null: return
	var viewport := get_viewport_rect()
	draw_rect(viewport, Color("173f48"))
	# Sparse nautical marks keep the overview legible without allocating ocean tiles.
	for row in range(15):
		for col in range(23):
			var p := Vector2(col * 80 + (row % 2) * 32, row * 72)
			draw_line(p, p + Vector2(12, 0), Color(0.35, 0.64, 0.65, 0.12), 1)
	# World-unit scale and north marker stay independent of island placement.
	var legend:=Vector2(viewport.size.x-150,98)
	draw_string(font,legend,T("panels.n"),HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("eee0bd"))
	var units: float=pow(10,floor(log(110.0/scale_factor)/log(10.0)))
	if units*scale_factor<45:units*=5
	var start:=Vector2(viewport.size.x-150,viewport.size.y-72)
	draw_line(start,start+Vector2(units*scale_factor,0),Color("eee0bd"),2)
	draw_line(start-Vector2(0,4),start+Vector2(0,4),Color("eee0bd"),2)
	draw_line(start+Vector2(units*scale_factor,-4),start+Vector2(units*scale_factor,4),Color("eee0bd"),2)
	draw_string(font,start+Vector2(0,-9),T("panels.0f_tiles")%units,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("eee0bd"))
	for region in world.catalog.regions.values():
		var origin := Vector2(region.origin[0], region.origin[1])
		var bounds := Rect2(screen_position(origin+world.catalog.local_origin(region)), Vector2(region.size[0], region.size[1]) * scale_factor).grow(60)
		if not viewport.intersects(bounds): continue
		if world.dark!=null and world.dark.enabled() and region.id in ["home","dark"]:
			var bridge:Array=world.dark.config.walking_connection.home_bridge if region.id=="home" else world.dark.config.walking_connection.dark_bridge
			draw_colored_polygon(PackedVector2Array(bridge.map(func(a):return screen_position(origin+Vector2(a[0],a[1])))),Color("b49a72"))
		if region.id=="dark":_dark_map(origin);continue
		var points := PackedVector2Array()
		for point in world.catalog.polygon(region): points.append(screen_position(origin + point))
		var closed := points.duplicate()
		closed.append(points[0])
		draw_polyline(closed, Color("29636a"), maxf(6, scale_factor * 3.8), true)
		draw_colored_polygon(points, Color("7f9d7e") if region.id==selected_region else Color("6c8b73"))
		draw_polyline(closed, Color("d1bd88"), maxf(2, scale_factor * 1.1), true)
		for extension in region.get("land_extensions",[]):
			var outline:=PackedVector2Array()
			for point in extension:outline.append(screen_position(origin+Vector2(point[0],point[1])))
			draw_colored_polygon(outline,Color("7f9d7e"));outline.append(outline[0]);draw_polyline(outline,Color("d1bd88"),2,true)
		var moon:Dictionary=region.get("layout",{}).get("moon",{})
		if not moon.is_empty():
			var bridge:=PackedVector2Array()
			for point in world.surface_polygon(moon.bridge.surface_id):bridge.append(screen_position(origin+point))
			draw_colored_polygon(bridge,Color("b49a72"))
			var p:Array=world.map_anchor("moon.camera");draw_string(font,screen_position(origin+Vector2(p[0],p[1])),T("panels.moon_island_reachable_on_foot"),HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("fff4da"))
		if region.get("layout",{}).has("homelands"):
			var southern_bridge:=PackedVector2Array()
			for point in world.surface_polygon("homelands.bridge"):southern_bridge.append(screen_position(origin+point))
			draw_colored_polygon(southern_bridge,Color("b49a72"))
			if world.opening_id!="standard" or world.their_island.introduced or world.home_island.landed:draw_string(font,screen_position(origin+Vector2(81,198)),T("homeisland.walking"),HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("fff4da"))
		if show_zones and scale_factor > 2:
			for zone in region.zones:
				var area := Rect2(screen_position(origin + Vector2(zone.rect[0], zone.rect[1])), Vector2(zone.rect[2], zone.rect[3]) * scale_factor)
				var color: Color = ZONE_COLORS.get(zone.purpose, Color.GRAY)
				draw_rect(area, Color(color, 0.8))
				draw_rect(area, Color("e1d3a7"), false, 1)
				if scale_factor > 5 and not world.farms.farms.values().any(func(farm): return farm.zone_id == zone.id): draw_string(font, area.position + Vector2(0, -8), LocalText.content(zone.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color("f6ecd7"))
		if scale_factor > 3:
			for object in world.objects.values():
				if object.region_id != region.id: continue
				var p := screen_position(origin + Vector2(object.position[0], object.position[1]))
				match object.kind:
					"tree":
						draw_circle(p, scale_factor * 0.65, Color("294b43") if object.status == "mature" else Color("ad8a5c"))
						draw_arc(p, scale_factor * 0.9, 0, TAU, 16, Color("b1bd82"), 1, true)
					"farm_plot": pass
					"construction_site":
						var area := Rect2(p - Vector2(4, 3.5) * scale_factor, Vector2(8, 7) * scale_factor)
						draw_rect(area, Color("eee0bd"), false, 2)
		var label := screen_position(origin + Vector2(region.size[0] / 2.0, region.size[1] + 4))
		draw_string(font, label - Vector2(40, 0), LocalText.content(region.name), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("e4e0cb"))
	if scale_factor > 3:
		var origin := Vector2(world.catalog.regions.home.origin[0],world.catalog.regions.home.origin[1])
		for farm in world.farms.farms.values():
			var rect: Rect2 = world.catalog.rectangle(farm.rect)
			var p := screen_position(origin+rect.get_center())
			draw_rect(Rect2(screen_position(origin+rect.position),rect.size*scale_factor),Color("dfb573"),false,2)
			for plot in world.farms.farm_plots(farm.id):
				var at := screen_position(origin+world.point(plot))
				draw_rect(Rect2(at-Vector2(3,2),Vector2(6,4)),Color("c2b97e") if plot.crop_id.is_empty() else Color("bcdb88"))
			draw_string_outline(font,p+Vector2(-32,5),LocalText.content(farm.name),HORIZONTAL_ALIGNMENT_LEFT,-1,13,3,Color("263e35"))
			draw_string(font,p+Vector2(-32,5),LocalText.content(farm.name),HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("ffedc0"))
	for pen in world.fishing.pens.values():
		var region: Dictionary=world.catalog.regions[pen.region_id]
		var rect: Rect2=world.catalog.rectangle(pen.rect)
		var origin:=Vector2(region.origin[0],region.origin[1])
		var area:=Rect2(screen_position(origin+rect.position),rect.size*scale_factor)
		draw_rect(area,Color(.4,.8,.85,.18));draw_rect(area,Color("e4c998"),false,1)
		if scale_factor>1.5:draw_string(font,area.get_center()+Vector2(-25,0),LocalText.content(str(pen.name)),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color("fff0ce"))

	if world.ingredients!=null:
		for item in world.ingredients.sources():
			if not item.id in world.ingredients.discovered:continue
			var region:Dictionary=world.catalog.regions.get(item.region,{})
			if region.is_empty():continue
			if item.has("icon_crop") and world.library!=null:
				var crop:Dictionary=world.farms.crops.get(str(item.icon_crop),{})
				if not crop.is_empty():
					var seed_at:Vector2=screen_position(Vector2(region.origin[0],region.origin[1])+Vector2(item.position[0],item.position[1]))
					draw_texture_rect(world.library.texture(str(crop.art),"seedling"),Rect2(seed_at-Vector2(9,9),Vector2(18,18)),false)
				continue
			var path:String="res://assets/island-food/"+str(item.id)+".png"
			if not ResourceLoader.exists(path):continue
			var at:Vector2=screen_position(Vector2(region.origin[0],region.origin[1])+Vector2(item.position[0],item.position[1]))
			draw_texture_rect(load(path),Rect2(at-Vector2(9,9),Vector2(18,18)),false)
	for life in world.barbecues.values():
		var origin:Vector2=Vector2(world.catalog.regions[life.station.region_id].origin[0],world.catalog.regions[life.station.region_id].origin[1])
		var p:Vector2=screen_position(origin+world.point(life.station))
		draw_circle(p,6,Color("ef9a55"));draw_string(font,p+Vector2(8,0),T("journey.fire"),HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color.WHITE)
	var cat_point:Vector2=screen_position(Vector2(world.catalog.regions[world.cat.region].origin[0],world.catalog.regions[world.cat.region].origin[1])+world.cat.position)
	draw_circle(cat_point,4,Color("edb1cb"))

	for actor in world.actors.values():
		if actor.region_id=="dark" and not world.dark.permanent(world.point(actor)):continue
		var region_id: String = actor.region_id
		var position: Vector2 = world.point(actor)
		if world.interior.rooms().has(region_id):
			position = world.interior.outside(region_id); region_id = "home"
		var region: Dictionary = world.catalog.regions[region_id]
		var p := screen_position(Vector2(region.origin[0], region.origin[1]) + position)
		var color := Color("fff5e8") if actor.id != "human" else Color("f4bc71")
		draw_circle(p, 5, color)
		draw_arc(p, 8 + sin(time * 3) * 0.8, 0, TAU, 24, Color(color, 0.55), 1, true)
		if true: draw_string(font, p + (Vector2(-22, 5) if actor.id == "human" else Vector2(11, 5)), LocalText.resident(world,actor.id), HORIZONTAL_ALIGNMENT_LEFT, -1, preload("res://scripts/ui_scale.gd").pixels(13), color)

func _dark_map(origin:Vector2)->void:
	var d:RefCounted=world.dark
	for light in d.light_sources():draw_circle(screen_position(origin+d.p(light.position)),float(light.radius)*scale_factor,Color("9aa875"))
	for area in d.config.areas:
		if area.id in d.beacons:
			var polygon:=PackedVector2Array(area.polygon.map(func(a):return screen_position(origin+d.p(a))))
			draw_colored_polygon(polygon,Color("9aa875"));draw_string(font,screen_position(origin+d.p(area.beacon)),LocalText.content(area.name),HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("fff3ca"))
	draw_string(font,screen_position(origin+d.p(d.config.camp)),T("panels.dock_camp"),HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("fff3ca"))
	draw_string(font,screen_position(origin+d.p(d.config.camp))+Vector2(10,-12),T("panels.dark_island_north_shore_bridge_20"),HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("ffe2a4"))

func refresh_locale()->void:
	if panel==null:return
	_refresh_static(panel)
	for child in island_list.get_children():
		if child.has_meta("region_id"):child.text=LocalText.content(world.catalog.regions[str(child.get_meta("region_id"))].name)
	var retained:Vector2=selected_point
	select_region(selected_region);selected_point=retained;queue_redraw()

extends "res://scripts/island_view.gd"
## Whole-island presentation only. World remains the only movement/collision authority.
var terrain:=preload("res://scripts/polygon_study_ground.gd").new()
var props:=preload("res://scripts/study_prop_atlas.gd").new()
var ground_config:Dictionary={}
var window_masks:Dictionary={}
var overview:=false
var overview_factor:=5
var boardwalk:Texture2D
var curbs:PackedVector2Array=[]
var atmosphere=preload("res://scripts/island_ambience.gd").new()
var ambience_enabled:=true
var emission:Node2D
var baking_world:=false
var static_west:SubViewport
var west_cache_rect:=Rect2()
var static_ground:SubViewport
var static_farms:SubViewport
var ground_ready:=false
var farms_ready:=false
var static_bakes:=0
var farm_bakes:=0
var farm_cache_rect:=Rect2()
var farm_cache_key:=""
var static_decor:SubViewport
var decor_ready:=false
var decor_bakes:=0
var decor_stamp:=""
var decor_check_at:=0.0
var location_highlight:=Vector2.ZERO
var location_highlight_until:=-1.0
func focus_location(point:Vector2)->void:
	show_region("home");follow_player=false;overview=false;center=point;zoom=default_zoom("home",point)
	location_highlight=point;location_highlight_until=clock+5;queue_redraw()
func _draw()->void:
	super._draw()
	if clock<location_highlight_until and region_id=="home":
		var p:Vector2=screen(location_highlight)
		draw_arc(p,48*zoom,0,TAU,32,Color("ffe8a4"),3)
		draw_string(font,p+Vector2(-36,-58)*zoom,LocalText.text("system.island_v3_view.here"),HORIZONTAL_ALIGNMENT_LEFT,-1,16,Color("fff4db"))
func _ready()->void:
	super._ready()
	props.build(JSON.parse_string(FileAccess.get_file_as_string("res://content/island-v3-style.json")))
	boardwalk=ImageTexture.create_from_image(Image.load_from_file("res://assets/home-v3/boardwalk.png"))
	# Reuse the existing authored stone/log ring, excluding its flame layers.
	var b=props.base
	b.image=Image.create(96,72,false,Image.FORMAT_RGBA8);b.image.fill(Color.TRANSPARENT)
	# Original crossed logs and flame pixels, without the old solid platform.
	b.line(Vector2i(25,49),Vector2i(69,60),34,7);b.line(Vector2i(24,59),Vector2i(68,47),36,7)
	props.commit("unlit_fire",Vector2i(48,68))
	b.polygon([[29,49],[32,28],[42,39],[47,6],[57,34],[66,22],[68,49],[53,57],[39,55]],44);b.polygon([[36,49],[45,27],[49,41],[58,32],[61,49],[50,54]],46);b.polygon([[43,49],[49,38],[54,49],[49,53]],47)
	props.commit("campfire",Vector2i(48,68))
	var layout:Dictionary=world.catalog.regions.home.layout
	var roads:Array=layout.roads.duplicate(true)
	for road in roads:road.width=float(road.width)/2 # authored width is the complete road width
	ground_config={"region":world.catalog.regions.home,"camera":world.map_anchor("plaza.center"),"plaza":Array(Layout.plaza_shape(layout)),"paving":layout.ground_art.paving,"roads":roads,"well":world.map_anchor("well"),"shortcut":[world.map_anchor("well"),world.map_anchor("camp.fire")],"variant_regions":layout.ground_art.variant_regions}
	ground_config["formal_plaza"]=layout.ground_art.formal_plaza
	ground_config["continuous_ocean"]=true
	terrain.prepare(ground_config)
	for road in layout.roads:
		if not road.get("curb",false):continue
		for i in range(road.points.size()-1):
			var a:=Vector2(road.points[i][0],road.points[i][1]);var end:=Vector2(road.points[i+1][0],road.points[i+1][1]);var dir:Vector2=(end-a).normalized();var normal:=Vector2(-dir.y,dir.x)
			var count:int=maxi(1,int(a.distance_to(end)*32/44))
			for n in range(count):
				for side in [-1,1]:
					var edge:Vector2=a.lerp(end,(n+.5)/count)+normal*float(road.width)*.57*side
					if not Rect2(Vector2(layout.plaza[0],layout.plaza[1]),Vector2(layout.plaza[2],layout.plaza[3])).has_point(edge):curbs.append(edge)
	atmosphere.prepare(self)
	emission=preload("res://scripts/island_ambience_lights.gd").new();emission.view_ref=weakref(self);add_child(emission)
	update_ambience()
	if DisplayServer.get_name()!="headless":initialize_static_cache()
func update_ambience()->void:
	if overview:zoom=1.0/overview_factor
	self_modulate=atmosphere.sample(world).tint if ambience_enabled and region_id=="home" else Color.WHITE
	if is_instance_valid(emission):emission.queue_redraw()
func _process(delta:float)->void:
	super._process(delta);update_ambience()
	if static_ground!=null:refresh_farm_cache();refresh_decor_cache()
func _prepare_scenery()->void:scenery.clear() # v3 uses authored clusters, not uniform random scattering
func screen(point:Vector2)->Vector2:return super.screen(point).round()
func hit(mouse:Vector2)->String:
	if region_id=="dark":
		var target:String=dark_renderer.hit(self,mouse)
		if not target.is_empty():return target
	if world.standard.active() and Rect2(screen(Vector2(world.map_anchor("notice")[0],world.map_anchor("notice")[1]))-Vector2(50,100)*zoom,Vector2(100,125)*zoom).has_point(mouse):return "opening.board"
	if world.standard.active():
		for id in world.standard.sites:
			var site:Dictionary=world.leisure.sites[id]
			if not site.complete and Rect2(screen(world.point(site))-Vector2(65,65)*zoom,Vector2(130,110)*zoom).has_point(mouse):return id
	if world.actors.human.region_id==region_id:
		var p:Vector2=screen(world.point(world.actors.human))
		if Rect2(p+Vector2(-22,-70)*zoom,Vector2(44,76)*zoom).has_point(mouse):return "human"
	return super.hit(mouse)
func _unhandled_input(event:InputEvent)->void:
	if event is InputEventMouseButton and event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN]:
		var before:=local_point(event.position);overview=false;follow_player=false
		zoom=2 if event.button_index==MOUSE_BUTTON_WHEEL_UP else 1
		center+=before-local_point(event.position);queue_redraw();return
	if event is InputEventMouseButton and event.pressed:overview=false;zoom=maxf(1,zoom)
	super._unhandled_input(event)
func _house_size(site:Dictionary)->Vector2:
	if site.has("blueprint"):return Vector2(site.blueprint.artwork.width,site.blueprint.artwork.height)
	var art:Dictionary=preload("res://scripts/building_visual.gd").art(site)
	return Vector2(art.width,art.height)
func _draw_courtyard(_site:Dictionary)->void:pass
func _add_house_fences(_entries:Array)->void:pass
func _draw_ground(_viewport:Rect2)->void:
	if overview:zoom=1.0/overview_factor
	if not baking_world:
		# One world-anchored ocean everywhere; cached land has a transparent exterior.
		var a:Vector2=local_point(Vector2.ZERO);var b:Vector2=local_point(_viewport.size)
		_surface(Layout.rectangle(Rect2(a,b-a)),textures.water,Color("80b3bd"))
	if not baking_world:preload("res://scripts/home_island_renderer.gd").draw(self)
	if ground_ready and not baking_world:
		if static_west!=null:draw_texture_rect(static_west.get_texture(),Rect2(screen(west_cache_rect.position),Vector2(static_west.size)*zoom),false)
		draw_texture_rect(static_ground.get_texture(),Rect2(screen(Vector2.ZERO),Vector2(static_ground.size)*zoom),false)
		if ambience_enabled:atmosphere.draw_water(self)
		return
	draw_set_transform(screen(Vector2.ZERO),0,Vector2.ONE*zoom);terrain.draw(self,ambient());draw_set_transform(Vector2.ZERO)
	for life in world.barbecues.values():
		if not world.standard.ready(life.station.id):continue
		var center_point:Vector2=world.point(life.station);var edge:PackedVector2Array=[];var inner:PackedVector2Array=[]
		for i in range(40):
			var angle:float=TAU*i/40;var direction:=Vector2(cos(angle),sin(angle))
			edge.append(center_point+direction*(1.25+sin(i*2.3)*.18));inner.append(center_point+direction*.65)
		_surface(edge,terrain.textures.slab2,Color("797970")*ambient());_surface(inner,textures.soil,Color("514d46")*ambient())
		for i in range(12):
			var angle:float=TAU*i/12
			_sprite("rock",center_point+Vector2(cos(angle),sin(angle))*.85,.23,ambient())
	for edge in curbs:
		var p:=screen(edge);draw_rect(Rect2(p-Vector2(7,2)*zoom,Vector2(14,5)*zoom),Color("777e71")*ambient());draw_rect(Rect2(p-Vector2(6,2)*zoom,Vector2(11,2)*zoom),Color("c0bba0")*ambient())
	for ditch in world.catalog.regions.home.layout.get("field_ditches",[]):
		var box:Rect2=world.catalog.rectangle(ditch.rect)
		_surface(Layout.rectangle(box.grow(.1)),textures.soil,ambient())
		_surface(Layout.rectangle(box),textures.water,Color("81a9a3")*ambient())
	for bed in world.catalog.regions.home.layout.get("plaza_planters",[]):
		var at:Array=world.map_anchor(bed.anchor);var box:=Rect2(Vector2(at[0]-bed.size[0]/2,at[1]-bed.size[1]/2),Vector2(bed.size[0],bed.size[1]))
		_surface(Layout.rectangle(box),terrain.textures.slab2,Color("777e71")*ambient())
		_surface(Layout.rectangle(box.grow(-.22)),textures.soil,Color("736a49")*ambient())
		for corner in [Vector2(-1,-1),Vector2(1,-1),Vector2(-1,1),Vector2(1,1)]:_sprite("flowers",Vector2(at[0],at[1])+corner,1,ambient())
	for cliff in world.catalog.regions.home.layout.cliffs:
		if not visible_cliff(cliff):
			# Keep the unchanged World obstacle readable, without orphan rectangular stairs.
			for stone in cliff_stones(cliff):_sprite("rock",stone,.32,ambient())
			continue
		_surface(Layout.points(cliff.polygon),textures.rock,Color("a5a38e")*ambient())
		var steps:Array=cliff.stairs
		_surface(Layout.rectangle(Rect2(Vector2(steps[0][0],steps[0][1]),Vector2(steps[1][0]-steps[0][0],steps[1][1]-steps[0][1]))),boardwalk,ambient())
	# Ponds/bridges are still driven by the same World layout used for walkability.
	for pond in world.catalog.regions.home.layout.ponds:
		var shape:PackedVector2Array=Layout.pond_shape(pond)
		for rim in Geometry2D.offset_polygon(shape,.4):_surface(rim,textures.sand,Color("c9bb91"))
		_surface(shape,textures.water,Color("77aeb2"))
	for dock in world.catalog.regions.home.layout.dock_surfaces:
		if dock.id=="moon.platform" and not world.standard.ready("moon.lookout"):continue
		# Whole native plank pixels, clipped by the authored boardwalk polygon.
		var shape:=Layout.points(dock.polygon);_surface(shape,boardwalk,ambient())
	var moon:Dictionary=world.catalog.regions.home.layout.get("moon",{})
	if not moon.is_empty():
		if moon.has("platform_surface") and world.standard.ready("moon.lookout"):_surface(Layout.points(moon.platform_surface),boardwalk,ambient())
		var bridge:PackedVector2Array=world.surface_polygon(moon.bridge.surface_id)
		for edge in [0,2]:
			var a:Vector2=bridge[edge];var b:Vector2=bridge[edge+1]
			draw_line(screen(a+Vector2(0,-.5)),screen(b+Vector2(0,-.5)),Color("80694f"),maxf(1,3*zoom))
			for i in range(int(a.distance_to(b)/4)+1):
				var p:Vector2=screen(a.lerp(b,float(i)/maxi(1,int(a.distance_to(b)/4))))
				draw_rect(Rect2(p-Vector2(2,20)*zoom,Vector2(4,24)*zoom),Color("70583f"))
	var at:Array=world.map_anchor("spring.bridge")
	_surface(Layout.rectangle(Rect2(Vector2(at[0]-2,at[1]-.6),Vector2(4,1.2))),boardwalk,ambient())
	_sprite("fence_h",Vector2(at[0],at[1]-.5),1,ambient())
	if ambience_enabled:atmosphere.draw_water(self)
func visible_cliff(cliff:Dictionary)->bool:
	return not world.standard.active() or cliff.id not in world.standard.config.hidden_scenery
func cliff_stones(cliff:Dictionary)->Array[Vector2]:
	var shape:PackedVector2Array=Layout.points(cliff.polygon)
	var bounds:=Rect2(shape[0],Vector2.ZERO)
	for point in shape:bounds=bounds.expand(point)
	var stairs:=Rect2(Vector2(cliff.stairs[0][0],cliff.stairs[0][1]),Vector2(cliff.stairs[1][0]-cliff.stairs[0][0],cliff.stairs[1][1]-cliff.stairs[0][1]))
	var stones:Array[Vector2]=[]
	for index in range(int(bounds.size.x/1.5)):
		var point:=Vector2(bounds.position.x+.65+index*1.5,bounds.get_center().y+sin(index*2.1)*.15)
		if not stairs.grow(.25).has_point(point):stones.append(point)
	return stones
func night()->bool:return world.days.phase().id=="night"
func ambient()->Color:return Color.WHITE # One scene tint; child lights remain warm.
func fire_visual(station_id:String)->Dictionary:
	var fire:RefCounted=world.barbecues[station_id].fireside
	return {"burning":fire.burning(),"frame":int(clock*8)%4,"ignition":clampf((world.director.time-fire.ignited_at)/.65,0,1)}
func _round_camp(station:Dictionary,point:Vector2,state:String)->bool:
	if not world.barbecues[station.id].fireside.active() and state!="cold":return false
	var key:String="unlit_fire" if state=="cold" else "campfire"
	var texture:Texture2D=props.textures[key];var anchor:Vector2=props.anchors[key]
	var visual:Dictionary=fire_visual(station.id)
	var stretch:Vector2=Vector2.ONE
	var tint:Color=ambient()
	if visual.burning:
		stretch=Vector2(1+[0.0,.025,0.0,-.02][visual.frame],(.55+.45*visual.ignition)*[1.0,1.04,.98,1.02][visual.frame])
		tint*=Color(1,1-.035*visual.frame,1-.07*visual.frame)
	draw_texture_rect(texture,Rect2(screen(point)-anchor*stretch*zoom,texture.get_size()*stretch*zoom),false,tint)
	return true
func prop_point(entry:Dictionary)->Vector2:
	var value:Array=world.map_anchor(str(entry.anchor)) if entry.has("anchor") else entry.position
	return Vector2(value[0],value[1])+Vector2(entry.get("offset",[0,0])[0],entry.get("offset",[0,0])[1])
func decor_dynamic(prop:Dictionary)->bool:return prop.kind in ["windchime","flowers","flower_arch","campfire","toolshed"]
func visible_prop(prop:Dictionary)->bool:
	if not world.standard.active():return true
	if str(prop.get("owner","")) not in ["","human"]:return false
	if prop.get("anchor","") in ["camp.fire","camp.crates","camp.wood","camp.bucket"]:return world.standard.ready("home.barbecue")
	return prop.kind in ["well","notice","toolshed","asset","plant","flowers","mailbox","placard","rock","crates","bucket","campfire"]
func decor_foreground(prop:Dictionary)->bool:
	var at:Vector2=prop_point(prop)
	return world.actors.values().any(func(actor):return actor.region_id=="home" and at.y>world.point(actor).y and at.y-world.point(actor).y<6 and absf(at.x-world.point(actor).x)<3)
func _extra_entries(entries:Array)->void:
	if overview and decor_ready:draw_texture_rect(static_decor.get_texture(),Rect2(screen(Vector2.ZERO),Vector2(static_decor.size)*zoom),false)
	for bed in world.catalog.regions.home.layout.get("plaza_planters",[]):
		var at:Array=world.map_anchor(bed.anchor)
		entries.append({"type":"v3_prop","value":{"kind":"asset","asset":bed.tree_asset,"position":at},"y":at[1]})
	for prop in world.catalog.regions.home.layout.art_props:
		if overview and decor_ready and prop_point(prop).x>=0 and not decor_dynamic(prop) and not decor_foreground(prop):continue
		var at:=prop_point(prop);entries.append({"type":"v3_prop","value":prop,"y":at.y})
func _draw_extra_entry(entry:Dictionary)->bool:
	if entry.type!="v3_prop":return false
	if not visible_prop(entry.value):return true
	var prop:Dictionary=entry.value;var at:=prop_point(prop);var p:=screen(at)
	if not get_viewport_rect().grow(280*zoom).has_point(p):return true
	var texture:Texture2D;var anchor:Vector2
	match str(prop.kind):
		"asset":texture=textures[prop.asset];anchor=Vector2(texture.get_width()/2,texture.get_height()-8)
		"plant":
			var art:Dictionary=library.artworks[prop.work];texture=library.texture(prop.work,prop.frame);anchor=Vector2(art.anchor[0],art.anchor[1])
		"toolshed":
			var art:Dictionary=library.artworks["play-gazebo"];texture=library.texture("play-gazebo","idle");anchor=Vector2(art.anchor[0],art.anchor[1])
		"fish_display":texture=props.textures.note_table;anchor=props.anchors.note_table # empty display stand, never decorative fake fish
		"campfire":
			var camp:RefCounted=null
			for candidate in world.barbecues.values():
				if world.point(candidate.station).distance_to(at)<3:camp=candidate;break
			var key:String="campfire" if camp!=null and camp.fireside.burning() else "unlit_fire"
			texture=props.textures[key];anchor=props.anchors[key]
		_:texture=props.textures[prop.kind];anchor=props.anchors[prop.kind]
	var tint:=ambient()*Color(prop.get("tint","#ffffff"))
	if prop.kind=="toolshed" and world.actors.values().any(func(a):return a.region_id=="home" and world.point(a).distance_to(at)<3):tint.a=.5
	if not (overview and decor_ready and not decor_dynamic(prop)):_shadow(p,texture.get_width()*.26)
	var sway:=Vector2.ZERO
	if ambience_enabled and prop.kind in ["windchime","flowers","flower_arch"]:sway.x=round(Ambience.wind(clock,at)*float(atmosphere.config.wind_pixels))
	draw_texture_rect(texture,Rect2(p+(sway-anchor)*zoom,texture.get_size()*zoom),false,tint)
	if prop.get("owner","")!="" and prop.kind=="placard":
		var label:String=world.actors.get(prop.owner,{}).get("name",prop.owner)
		draw_string(font,p+Vector2(-24,-18)*zoom,label.left(6),HORIZONTAL_ALIGNMENT_LEFT,-1,maxi(8,int(10*zoom)),Color("fff1cf"))
	if prop.has("label"):draw_string(font,p+Vector2(-15,-14)*zoom,prop.label,HORIZONTAL_ALIGNMENT_LEFT,-1,maxi(8,int(10*zoom)),Color("fff1cf"))
	return true
func _work_sprite(art:Dictionary,frame:String,point:Vector2,size:Vector2,tint:Color=Color.WHITE)->void:
	super._work_sprite(art,frame,point,size,tint*ambient())
func _shadow(p:Vector2,width:float)->void:
	draw_set_transform(p+Vector2(width*.23,4)*zoom,0,Vector2(1,.34))
	draw_circle(Vector2.ZERO,width*zoom,Color(.08,.13,.16,.20))
	draw_circle(Vector2(-width*.23,-6)*zoom,width*.56*zoom,Color(.05,.10,.10,.18))
	draw_set_transform(Vector2.ZERO)

func _draw_resident_labels()->void:
	if ambience_enabled:atmosphere.draw_foreground(self)
	fishing_renderer.overlay(self)
	for actor in world.actors.values():
		if actor.id=="human" or actor.region_id!=region_id:continue
		var p:Vector2=screen(world.point(actor))+Vector2(-12,15)
		draw_string_outline(font,p,LocalText.resident(world,str(actor.id)),HORIZONTAL_ALIGNMENT_LEFT,-1,preload("res://scripts/ui_scale.gd").pixels(12),3,Color("24392f"))
		draw_string(font,p,LocalText.resident(world,str(actor.id)),HORIZONTAL_ALIGNMENT_LEFT,-1,preload("res://scripts/ui_scale.gd").pixels(12),Color("fff4db"))
	for entry in speech_layout():
		draw_line(entry.anchor,entry.box.get_center(),Color(.95,.93,.8,.6),1,true)
		draw_style_box(_bubble(),entry.box)
		draw_multiline_string(font,entry.box.position+Vector2(10,25)*preload("res://scripts/ui_scale.gd").factor(),entry.text,HORIZONTAL_ALIGNMENT_LEFT,entry.box.size.x-20*preload("res://scripts/ui_scale.gd").factor(),preload("res://scripts/ui_scale.gd").pixels(14),-1,Color("3b483d"))

	_draw_thought_clouds()

func make_bake(kind:String,area:Rect2)->SubViewport:
	var viewport:=SubViewport.new();viewport.size=Vector2i((area.size*32).ceil());viewport.transparent_bg=true;viewport.disable_3d=true;viewport.canvas_item_default_texture_filter=Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST;viewport.render_target_update_mode=SubViewport.UPDATE_ONCE;add_child(viewport)
	var drawer=load("res://scripts/island_static_bake.gd").new()
	drawer.world=world;drawer.library=library;drawer.font=font;drawer.textures=textures;drawer.terrain=terrain;drawer.props=props;drawer.boardwalk=boardwalk;drawer.curbs=curbs;drawer.baking_world=true;drawer.zoom=1.0;drawer.texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;drawer.ambience_enabled=false;drawer.sound_enabled=false;drawer.mode=kind;drawer.bake_origin=area.position;drawer.texture_repeat=CanvasItem.TEXTURE_REPEAT_ENABLED
	viewport.add_child(drawer);return viewport
func initialize_static_cache()->void:
	texture_repeat=CanvasItem.TEXTURE_REPEAT_ENABLED
	var size:Array=world.catalog.regions.home.layout.get("mainland_size",world.catalog.regions.home.size)
	var moon:Dictionary=world.catalog.regions.home.layout.get("moon",{})
	if not moon.is_empty():
		west_cache_rect=world.catalog.rectangle(moon.bounds)
		static_west=make_bake("terrain",west_cache_rect)
	static_ground=make_bake("terrain",Rect2(Vector2.ZERO,Vector2(size[0],size[1])));static_bakes+=1
	for farm in world.farms.farms.values():
		var area:Rect2=world.catalog.rectangle(farm.rect).grow(1.5)
		farm_cache_rect=area if farm_cache_rect.size==Vector2.ZERO else farm_cache_rect.merge(area)
	static_farms=make_bake("farms",farm_cache_rect);refresh_farm_cache()
	static_decor=make_bake("decor",Rect2(Vector2.ZERO,Vector2(size[0],size[1])));decor_bakes+=1
	RenderingServer.frame_post_draw.connect(func():ground_ready=true;farms_ready=true;decor_ready=true;queue_redraw(),CONNECT_ONE_SHOT)
func refresh_farm_cache()->void:
	var state:Array=[]
	for farm in world.farms.farms.values():state.append([farm.id,farm.rect,farm.flowers,world.farms.ready(farm.id)])
	for plot in world.farms.plots.values():state.append(plot.watered)
	var signature:String=str(state)
	if signature==farm_cache_key:return
	farm_cache_key=signature;farm_bakes+=1
	if static_farms!=null:
		static_farms.render_target_update_mode=SubViewport.UPDATE_ONCE;static_farms.get_child(0).queue_redraw()
func use_cached_farm_ground()->bool:return farms_ready and not baking_world
func draw_cached_farm_ground()->void:
	draw_texture_rect(static_farms.get_texture(),Rect2(screen(farm_cache_rect.position),farm_cache_rect.size*32*zoom),false)
func map_label(text:String,at:Vector2,color:Color=Color("fff0cb"))->void:
	var size:int=maxi(9,int(14*zoom));var width:float=font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x
	var p:Vector2=screen(at)-Vector2(width/2,0)
	draw_rect(Rect2(p+Vector2(-4,-size),Vector2(width+8,size+5)),Color(.12,.19,.16,.58))
	draw_string_outline(font,p,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,2,Color("263e32"));draw_string(font,p,text,HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)

func refresh_decor_cache()->void:
	if clock<decor_check_at:return
	decor_check_at=clock+2
	var stamp:Array=[]
	if world.standard.active():
		for site in world.leisure.sites.values():stamp.append([site.id,site.complete])
	for actor in world.actors.values():stamp.append([actor.id,LocalText.resident(world,str(actor.id))])
	for prop in world.catalog.regions.home.layout.art_props:
		if prop.kind=="plant":stamp.append([prop.work,library.artworks.get(prop.work,{}).get("revision",0)])
	var value:String=str(stamp)
	if decor_stamp.is_empty():decor_stamp=value;return
	if value==decor_stamp:return
	decor_stamp=value
	if world.standard.active():invalidate_static_cache()
	if static_decor!=null:static_decor.render_target_update_mode=SubViewport.UPDATE_ONCE;static_decor.get_child(0).queue_redraw();decor_bakes+=1
func invalidate_static_cache()->void:
	if static_west!=null:static_west.render_target_update_mode=SubViewport.UPDATE_ONCE;static_west.get_child(0).queue_redraw()
	terrain.prepare(ground_config)
	if static_ground!=null:static_ground.render_target_update_mode=SubViewport.UPDATE_ONCE;static_ground.get_child(0).queue_redraw();static_bakes+=1
	if static_decor!=null:static_decor.render_target_update_mode=SubViewport.UPDATE_ONCE;static_decor.get_child(0).queue_redraw();decor_bakes+=1
	farm_cache_key="";refresh_farm_cache()

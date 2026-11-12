extends Node2D
## Draw order: world bodies -> opaque fog -> distant emissive pixels -> labels.
class AboveFog:
	extends Node2D
	var overlay:Node2D
	func _draw()->void:
		var v:Node=overlay.view_ref.get_ref()
		if v==null or not v.world.dark.here() or v.region_id!="dark":return
		v.draw_hunger_symbols(self)
		overlay.renderer.glows(v,self)
		overlay.renderer.discoveries_draw(v,self)
		for id in v.world.dark.companions.looking:
			if v.world.intelligence.tag(id)!="quiet":continue
			var at:Vector2=v.screen(v.world.point(v.world.actors[id]))+Vector2(0,-90)*v.zoom
			var target:Vector2=v.screen(v.world.dark.companions.looking[id].target)
			draw_line(at,at+(target-at).normalized()*16,Color("ffd98b"),2)
		for actor in v.world.actors.values():
			if actor.id=="human" or actor.region_id!="dark":continue
			var at:Vector2=v.screen(v.world.point(actor))+Vector2(-12,15)
			draw_string_outline(v.font,at,preload("res://scripts/localization.gd").resident(v.world,str(actor.id)),HORIZONTAL_ALIGNMENT_LEFT,-1,preload("res://scripts/ui_scale.gd").pixels(12),3,Color("24392f"))
			draw_string(v.font,at,preload("res://scripts/localization.gd").resident(v.world,str(actor.id)),HORIZONTAL_ALIGNMENT_LEFT,-1,preload("res://scripts/ui_scale.gd").pixels(12),Color("fff4db"))
		for entry in v.speech_layout():
			draw_line(entry.anchor,entry.box.get_center(),Color(.95,.93,.8,.6),1,true)
			draw_style_box(v._bubble(),entry.box)
			draw_multiline_string(v.font,entry.box.position+Vector2(10,25)*preload("res://scripts/ui_scale.gd").factor(),entry.text,HORIZONTAL_ALIGNMENT_LEFT,entry.box.size.x-20*preload("res://scripts/ui_scale.gd").factor(),preload("res://scripts/ui_scale.gd").pixels(14),-1,Color("3b483d"))
var view_ref:WeakRef
var renderer:RefCounted
var fog:ColorRect
var labels:AboveFog
var stamp:=""
var permanent:ImageTexture
var spread:ImageTexture
const RESOLUTION:=4
func configure(v:Node,source:RefCounted)->void:
	view_ref=weakref(v);renderer=source
	fog=ColorRect.new();fog.mouse_filter=Control.MOUSE_FILTER_IGNORE;fog.material=ShaderMaterial.new();fog.material.shader=load("res://scripts/dark_fog.gdshader");add_child(fog)
	labels=AboveFog.new();labels.overlay=self;add_child(labels)
	set_process(false);update()
func point(a:Array)->Vector2:return Vector2(a[0],a[1])
func polygon(image:Image,poly:Array)->void:
	var origin:Vector2=point(view_ref.get_ref().world.dark.config.get("local_origin",[0,0]))
	var values:=PackedVector2Array(poly.map(func(a):return point(a)-origin))
	var low:=values[0];var high:=values[0]
	for p in values:low=low.min(p);high=high.max(p)
	for y in range(maxi(0,int(low.y*RESOLUTION)),mini(image.get_height(),ceili(high.y*RESOLUTION))):
		for x in range(maxi(0,int(low.x*RESOLUTION)),mini(image.get_width(),ceili(high.x*RESOLUTION))):
			if Geometry2D.is_point_in_polygon(Vector2(x+.5,y+.5)/RESOLUTION,values):image.set_pixel(x,y,Color.WHITE)
func rebuild(v:Node,d:RefCounted,excluded:String)->void:
	var dimensions:=Vector2i(int(d.config.size[0]*RESOLUTION),int(d.config.size[1]*RESOLUTION))
	var mask:=Image.create(dimensions.x,dimensions.y,false,Image.FORMAT_RGBA8);mask.fill(Color.BLACK)
	var wave:=Image.create(dimensions.x,dimensions.y,false,Image.FORMAT_RGBA8);wave.fill(Color.BLACK)
	for light in d.light_sources():
		var center:Vector2=point(light.position)-point(d.config.get("local_origin",[0,0]));var radius:float=light.radius;var edge:float=d.config.soft_edge
		for y in range(maxi(0,int((center.y-radius-edge)*RESOLUTION)),mini(dimensions.y,ceili((center.y+radius+edge)*RESOLUTION))):
			for x in range(maxi(0,int((center.x-radius-edge)*RESOLUTION)),mini(dimensions.x,ceili((center.x+radius+edge)*RESOLUTION))):
				var amount:float=1.0-smoothstep(radius,radius+edge,(Vector2(x+.5,y+.5)/RESOLUTION).distance_to(center))
				if amount>mask.get_pixel(x,y).r:mask.set_pixel(x,y,Color(amount,amount,amount,1))
	for area in d.config.areas:
		if area.id not in d.beacons:continue
		polygon(wave if area.id==excluded else mask,area.polygon)
	permanent=ImageTexture.create_from_image(mask);spread=ImageTexture.create_from_image(wave)
	fog.material.set_shader_parameter("permanent_mask",permanent);fog.material.set_shader_parameter("spread_mask",spread)
func update()->void:
	var v:Node=view_ref.get_ref()
	if v==null:return
	visible=v.world.dark!=null and v.world.dark.here() and v.region_id=="dark"
	if not visible:return
	var d:RefCounted=v.world.dark
	var spreading:bool=not d.spread.is_empty() and float(d.spread.elapsed)<float(d.config.beacon_spread_seconds)
	var excluded:String=str(d.spread.area_id) if spreading else ""
	var key:String=JSON.stringify([d.fires,d.beacons,excluded])
	if key!=stamp:stamp=key;rebuild(v,d,excluded)
	fog.size=v.get_viewport_rect().size
	var material:ShaderMaterial=fog.material
	material.set_shader_parameter("viewport_size",fog.size)
	material.set_shader_parameter("camera_center",v.center)
	material.set_shader_parameter("map_origin",point(d.config.get("local_origin",[0,0])))
	material.set_shader_parameter("map_size",point(d.config.size))
	material.set_shader_parameter("pixel_scale",32.0*v.zoom)
	# Offset to the displayed torso so a four-tile-tall character's head remains
	# inside the same personal circle as her feet; position still comes from World.
	material.set_shader_parameter("personal_center",v.world.point(v.world.actors.human)+Vector2(0,-1.4))
	material.set_shader_parameter("personal_radius",d.visible_radius())
	material.set_shader_parameter("soft_edge",float(d.config.soft_edge))
	material.set_shader_parameter("planted_center",point(d.torch.position))
	material.set_shader_parameter("planted_radius",float(d.config.torch_radius) if d.torch.planted and d.torch.remaining>0 else 0.0)
	var warning:bool=d.torch.remaining>0 and d.torch.remaining<=d.config.torch_warning_seconds
	material.set_shader_parameter("flicker",1.0+sin(v.clock*(17 if warning else 7))*(.035 if warning else .009) if d.torch.remaining>0 else 1.0)
	var center:=Vector2.ZERO;var radius:=0.0
	if spreading:
		for area in d.config.areas:
			if area.id!=excluded:continue
			center=point(area.beacon)
			var farthest:=0.0
			for vertex in area.polygon:farthest=maxf(farthest,center.distance_to(point(vertex)))
			radius=farthest*float(d.spread.elapsed)/float(d.config.beacon_spread_seconds)
	material.set_shader_parameter("spread_center",center);material.set_shader_parameter("spread_radius",radius)
	labels.queue_redraw()

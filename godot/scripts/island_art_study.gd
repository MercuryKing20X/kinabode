extends Node2D
## Two snapshot-only compositions. No World, links, clock, input or save path.
@export_enum("A","B") var study_id:="A"
var period:="afternoon"
var detail:=false
var pixel_scale:=1
var config:Dictionary={}
var style:Dictionary={}
var ground:RefCounted=preload("res://scripts/polygon_study_ground.gd").new()
var layout=preload("res://scripts/art_study_layout.gd")
var props:RefCounted=preload("res://scripts/study_prop_atlas.gd").new()
var library:RefCounted=preload("res://scripts/character_library.gd").new()
var entries:Array=[]
var light_masks:Dictionary={}
var ready_for_capture:=false
func _ready()->void:
	get_window().content_scale_size=Vector2i.ZERO;texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;texture_repeat=CanvasItem.TEXTURE_REPEAT_ENABLED
	config=JSON.parse_string(FileAccess.get_file_as_string("res://content/art-studies/scenes.json"))[study_id].duplicate(true)
	style=JSON.parse_string(FileAccess.get_file_as_string("res://content/island-v3-style.json"));ground.prepare(config);props.build(style)
	for prop in config.props:
		var texture:Texture2D;var anchor:Vector2
		if prop.kind=="work":
			var art:=load_art(prop.artwork_id,"works");texture=library.texture(prop.artwork_id,prop.frame);anchor=Vector2(art.anchor[0],art.anchor[1])
		elif prop.kind=="scenery":texture=load("res://assets/island/"+prop.asset+".png");anchor=Vector2(texture.get_width()/2,texture.get_height()-8)
		else:texture=props.textures[prop.kind];anchor=props.anchors[prop.kind]
		entries.append({"type":"prop","value":prop,"point":layout.point(config,prop)*32,"texture":texture,"anchor":anchor,"scale":int(prop.scale)})
	for house in config.get("houses",[]):
		var art:=load_art(house.source_id,"study")
		entries.append({"type":"house","value":house,"point":Vector2(house.position[0],house.position[1])*32,"texture":library.texture(art.id,"stage_4"),"anchor":Vector2(art.anchor[0],art.anchor[1]),"scale":int(art.art_scale),"art":art})
	for actor in config.actors:
		var art:=load_art(actor.artwork_id,"characters")
		entries.append({"type":"actor","value":actor,"point":Vector2(actor.position[0],actor.position[1])*32,"texture":library.texture(actor.artwork_id,actor.frame),"anchor":Vector2(art.anchor[0],art.anchor[1]),"scale":1})
	for plant in config.foliage:
		var texture:Texture2D=load("res://assets/island/"+plant.asset+".png")
		entries.append({"type":"foliage","value":plant,"point":layout.point(config,plant)*32,"texture":texture,"anchor":Vector2(texture.get_width()/2,texture.get_height()-8),"scale":1})
	entries.sort_custom(func(a,b):return a.point.y<b.point.y);ready_for_capture=true;queue_redraw()
	var output:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snapshot="):output=arg.trim_prefix("--snapshot=")
		if arg.begins_with("--period="):period=arg.trim_prefix("--period=")
		if arg=="--detail":detail=true;pixel_scale=2
	if not output.is_empty():
		await get_tree().process_frame;await get_tree().process_frame;await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output);get_tree().quit()
func load_art(id:String,folder:String)->Dictionary:
	var key:String="study-house-"+id if folder=="study" else id
	if not library.artworks.has(key):
		var path:String="res://content/art-studies/houses/"+id+".json" if folder=="study" else "res://content/"+folder+"/"+id+".json"
		var art:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path));assert(library.valid(art));library.artworks[key]=art
	return library.artworks[key]
func origin()->Vector2:
	var camera:Array=config.detail if detail else config.camera
	return (get_viewport_rect().size/2-Vector2(camera[0],camera[1])*32*pixel_scale).round()
func lamp_positions()->Array:
	var result:Array=[]
	for entry in entries:
		if entry.type=="prop" and entry.value.kind in ["lamp","campfire"]:result.append(entry.point)
	return result
func shadow(entry:Dictionary)->void:
	var width:float=entry.texture.get_width()*entry.scale*.55;var length:int=24 if entry.type=="house" else 12
	var at:Vector2=entry.point;var points:=PackedVector2Array()
	for i in range(32):
		var a:float=i*TAU/32;points.append((at+Vector2(cos(a)*width/2,0)+Vector2(length,length*2.0/3)*(sin(a)*.5+.5)).round())
	var color:=Color("203c2c");color.a=.13 if period=="night" else .21;draw_colored_polygon(points,color)
func emission(entry:Dictionary)->Texture2D:
	var art:Dictionary=entry.art
	if not light_masks.has(art.id):
		var image:Image=library.render(art,"stage_4")
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				var pixel:=image.get_pixel(x,y)
				var in_window:=false
				for box in art.openings.windows:
					if Rect2(box[0],box[1],box[2],box[3]).has_point(Vector2(x,y)):in_window=true;break
				var glass:bool=pixel.a>.9 and (pixel.b>pixel.r*1.2 and pixel.g>pixel.r*.9)
				var glow:=Color("ffda8b")*clampf(pixel.g,.45,.9);glow.a=.55
				image.set_pixel(x,y,glow if in_window and glass else Color.TRANSPARENT)
		light_masks[art.id]=ImageTexture.create_from_image(image)
	return light_masks[art.id]
func _draw()->void:
	if not ready_for_capture:return
	var night:bool=period=="night";var tint:=Color("718aa4") if night else Color.WHITE
	draw_set_transform(origin(),0,Vector2(pixel_scale,pixel_scale));ground.draw(self,tint)
	var lamps:=lamp_positions()
	if night:
		for point in lamps:draw_texture(props.textures.light,point-Vector2(props.anchors.light))
	for entry in entries:shadow(entry)
	for entry in entries:
		var local:Color=tint
		if night:
			for light in lamps:local=local.lerp(Color("ffe6b6"),clampf(1-entry.point.distance_to(light)/240,0,1)*.5)
		var lit:bool=night and entry.type=="prop" and entry.value.kind in ["lamp","campfire"]
		draw_set_transform(origin()+entry.point*pixel_scale,0,Vector2.ONE*pixel_scale*entry.scale)
		draw_texture(entry.texture,-entry.anchor,Color.WHITE if lit else local)
		if night and entry.type=="house":draw_texture(emission(entry),-entry.anchor)
	draw_set_transform(Vector2.ZERO)

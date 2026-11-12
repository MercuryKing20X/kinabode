extends Node2D
## Screenshot-only art composition. No World instance, save/load, jobs, links or controls.
const Terrain=preload("res://scripts/tile_terrain_data.gd")
const Renderer=preload("res://scripts/tile_terrain_renderer.gd")
const Library=preload("res://scripts/character_library.gd")
var data:Dictionary={}
var style:Dictionary={}
var terrain:=Terrain.new()
var renderer:=Renderer.new()
var props:=preload("res://scripts/island_sample_props.gd").new()
var library:=Library.new()
var font:Font=preload("res://assets/fonts/NotoSansSC.ttf")
var time_of_day:="afternoon"
var pixel_scale:=1
var detail:=false
var entries:Array=[]
var emissions:Dictionary={}
var foliage_textures:Dictionary={}
var ready_for_capture:=false
func _ready()->void:
	get_window().content_scale_size=Vector2i.ZERO
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST
	data=JSON.parse_string(FileAccess.get_file_as_string("res://content/island-v3-sample.json"));style=JSON.parse_string(FileAccess.get_file_as_string("res://content/island-v3-style.json"))
	assert(data.snapshot_only and terrain.load_data(data))
	add_child(renderer);renderer.hide()
	props.build(style);renderer.configure(terrain,style);renderer.ensure_baked()
	for house in data.houses:_load_art(house.template_id,"works");entries.append({"type":"house","value":house,"position":foot(house.position)})
	for actor in data.actors:_load_art(actor.artwork_id,"characters");entries.append({"type":"actor","value":actor,"position":foot(actor.position)})
	for decor in data.get("foliage",[]):entries.append({"type":"foliage","value":decor,"position":foot(decor.position)})
	for prop in data.props:entries.append({"type":"prop","value":prop,"position":foot(prop.position)})
	entries.sort_custom(func(a,b):return a.position.y<b.position.y)
	ready_for_capture=true;queue_redraw()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--time="):time_of_day=arg.trim_prefix("--time=")
		if arg=="--detail":detail=true;pixel_scale=int(style.integer_scales[1])
	var output:=""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--snapshot="):output=arg.trim_prefix("--snapshot=")
	if not output.is_empty():
		await get_tree().process_frame;await get_tree().process_frame;await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(output);get_tree().quit()
func _load_art(id:String,folder:String)->void:
	if library.artworks.has(id):return
	var art:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/"+folder+"/"+id+".json"));assert(library.valid(art));library.artworks[id]=art
func foot(position:Array)->Vector2:
	var at:=Vector2(position[0],position[1])*32;var cell:Dictionary=terrain.cell(Vector2i(floor(position[0]),floor(position[1])))
	return (at-Vector2(0,int(cell.get("height",0))*16)).round()
func origin()->Vector2:
	var center:Array=data.camera.detail if detail else data.camera.center
	return (get_viewport_rect().size/2-Vector2(center[0],center[1])*32*pixel_scale).round()
func _shape(at:Vector2,width:int,height:int)->PackedVector2Array:
	var points:=PackedVector2Array()
	for i in range(24):points.append((at+Vector2(cos(i*TAU/24)*width/2,sin(i*TAU/24)*height/2)).round())
	return points
func _shadow(entry:Dictionary)->void:
	var at:Vector2=entry.position;var width:=54;var length:int=int(style.shadow.prop_length)
	if entry.type=="house":width=148;length=int(style.shadow.house_length)
	elif entry.type=="actor":width=40;length=int(style.shadow.actor_length)
	elif entry.type=="foliage":width=84;length=int(style.shadow.house_length)
	else:width=int(props.textures[entry.value.kind].get_width()*.6)
	var end:=Vector2(length,round(float(length)*style.shadow.direction[1]/style.shadow.direction[0]))
	var alpha:float=style.shadow.night_opacity if time_of_day=="night" else style.shadow.opacity
	var shadow:=Color(style.palette[8].hex);shadow.a=alpha
	var cast:=PackedVector2Array()
	for i in range(32):
		var angle:=i*TAU/32
		cast.append((at+Vector2(cos(angle)*width/2,0)+end*(sin(angle)*.5+.5)).round())
	draw_colored_polygon(cast,shadow)
	shadow.a=style.shadow.contact_opacity;draw_colored_polygon(_shape(at,width,2),shadow)
func _art(entry:Dictionary,tint:Color)->void:
	var value:Dictionary=entry.value;var id:String=value.template_id if entry.type=="house" else value.artwork_id
	var art:Dictionary=library.artworks[id];var frame:String="stage_4" if entry.type=="house" else value.frame
	var at:Vector2=entry.position-Vector2(art.anchor[0],art.anchor[1]);draw_texture(library.texture(id,frame),at,tint)
	if entry.type=="house" and time_of_day=="night":
		if not emissions.has(id):
			var image:Image=library.render(art,frame)
			for y in range(image.get_height()):
				for x in range(image.get_width()):
					var c:=image.get_pixel(x,y)
					if not(c.a>.5 and c.r>.8 and c.g>.65 and c.b<.65):image.set_pixel(x,y,Color.TRANSPARENT)
			emissions[id]=ImageTexture.create_from_image(image)
		draw_texture(emissions[id],at)
func _draw()->void:
	if not ready_for_capture:return
	var tint:=Color(style.day_tints.get(time_of_day,"#FFFFFF"))
	draw_set_transform(origin(),0,Vector2(pixel_scale,pixel_scale));draw_texture(renderer.texture,Vector2.ZERO,tint)
	if time_of_day=="night":
		for entry in entries:
			if entry.type=="prop" and entry.value.kind in ["lamp","campfire"]:
				var at:Vector2=entry.position-Vector2(props.anchors.light);draw_texture(props.textures.light,at)
	for entry in entries:_shadow(entry)
	for entry in entries:
		var local_tint:Color=tint
		if time_of_day=="night":
			for source in entries:
				if source.type=="prop" and source.value.kind in ["lamp","campfire"]:
					var warmth:=clampf(1-entry.position.distance_to(source.position)/220,0,1)*.55
					local_tint=local_tint.lerp(Color(style.palette[47].hex),warmth)
		if entry.type=="foliage":
			var id:String=entry.value.asset
			if not foliage_textures.has(id):foliage_textures[id]=load("res://assets/island/"+id+".png")
			var texture:Texture2D=foliage_textures[id]
			draw_texture(texture,entry.position-Vector2(texture.get_width()/2,texture.get_height()-8),local_tint);continue
		if entry.type!="prop":_art(entry,local_tint);continue
		var prop:Dictionary=entry.value;var at:Vector2=entry.position-Vector2(props.anchors[prop.kind])
		var lit:bool=time_of_day=="night" and prop.kind in ["lamp","campfire"]
		draw_texture(props.textures[prop.kind],at,Color.WHITE if lit else local_tint)
		if prop.has("text"):draw_string(font,at+Vector2(11,20),prop.text,HORIZONTAL_ALIGNMENT_LEFT,-1,12,Color(style.palette[32].hex))
	draw_set_transform(Vector2.ZERO)

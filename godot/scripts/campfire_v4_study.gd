extends Node2D
const LocalText=preload("res://scripts/localization.gd")
## Snapshot-only research composition. No World, Work, input, save path or live catalog.
@export_enum("mainland","moon") var biome:="mainland"
var period:="day"
var animation_time:=0.0
var frozen:=false
var assets:Dictionary={}
var characters:Array=[]
var font:Font
var library:RefCounted=preload("res://scripts/character_library.gd").new()
var ready_for_capture:=false
const NAMES=["human-starter","white-haired-girl","blue-haired-girl","orange-haired-girl","black-scarf-girl"]
const ACTOR_POINTS=[Vector2(0,175),Vector2(-123,-91),Vector2(128,-90),Vector2(205,66),Vector2(-202,69)]
func _ready()->void:
	get_window().content_scale_size=Vector2i.ZERO
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;texture_repeat=CanvasItem.TEXTURE_REPEAT_ENABLED
	font=load("res://assets/fonts/NotoSansSC.ttf")
	for id in ["grass","sand","water","soil"]:assets[id]=load("res://assets/island/"+id+".png")
	assets["stone"]=load("res://content/home-v3/textures/stone-1.png")
	for variant in ["mainland","moon"]:
		for id in ["fire-0","fire-1","fire-2","fire-3","rock","logs","stool","mushrooms","grass_clump","flowers","bench","bench-left","bench-up","sign"]:
			assets[variant+"-"+id]=load("res://assets/studies/campfire-v4/"+variant+"-"+id+".png")
	for id in ["string-lights","shell","smoke"]:assets[id]=load("res://assets/studies/campfire-v4/"+id+".png")
	for i in range(NAMES.size()):
		var art:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/characters/"+NAMES[i]+".json"))
		assert(library.valid(art));library.artworks[art.id]=art
		# Existing authored fire sitting action, no source edits or player artwork reads.
		characters.append({"id":art.id,"point":ACTOR_POINTS[i],"anchor":Vector2(art.anchor[0],art.anchor[1]),"frame":"fire_sit_down_0"})
	ready_for_capture=true;queue_redraw()
func _process(delta:float)->void:
	if not frozen:animation_time+=delta;queue_redraw()
func local_origin()->Vector2:return (get_viewport_rect().size/2+Vector2(0,35)).round()
func surface(shape:PackedVector2Array,key:String,color:Color)->void:
	var uv:PackedVector2Array=[];var texture:Texture2D=assets[key]
	for point in shape:uv.append(point/Vector2(texture.get_size()))
	draw_polygon(shape,PackedColorArray([color]),uv,texture)
func oval(center:Vector2,radius:Vector2,phase:float=0.0)->PackedVector2Array:
	var points:PackedVector2Array=[]
	for i in range(48):
		var angle:float=TAU*i/48
		var ragged:float=1+sin(i*2.7+phase)*.045+sin(i*.67)*.035
		points.append((center+Vector2(cos(angle),sin(angle))*radius*ragged).round())
	return points
func ground(tint:Color)->void:
	var size:=get_viewport_rect().size;var origin:=local_origin()
	var rectangle:=PackedVector2Array([Vector2.ZERO,Vector2(size.x,0),size,Vector2(0,size.y)])
	if biome=="mainland":
		surface(rectangle,"grass",Color("a1b493")*tint)
		# The old plaza stays at the edge; this fire clearing is entirely in grass.
		var paving:=PackedVector2Array([Vector2(0,100),Vector2(size.x*.18,125),Vector2(size.x*.22,size.y),Vector2(0,size.y)])
		surface(paving,"stone",Color("c9c3ad")*tint)
		for i in range(4):surface(oval(origin+Vector2(-8,52),Vector2(238-i*13,142-i*8),i*.3),"grass",Color(.75,.72,.54,.12)*tint)
		for i in range(18):
			var a:float=i*TAU/18;var p:=origin+Vector2(cos(a)*225,sin(a)*138+48)
			sprite("mainland-grass_clump",p+Vector2(0,16),Color(1,1,1,.6)*tint,Vector2(24,29))
	else:
		surface(rectangle,"water",Color("86b5bd")*tint)
		var beach:PackedVector2Array=[Vector2(0,size.y*.38),Vector2(size.x*.18,size.y*.35),Vector2(size.x*.34,size.y*.40),Vector2(size.x*.55,size.y*.36),Vector2(size.x*.77,size.y*.40),Vector2(size.x,size.y*.34),size,Vector2(0,size.y)]
		surface(beach,"sand",Color("f6dcae")*tint)
		for i in range(5):
			var y:float=size.y*.34-i*12
			for x in range(0,int(size.x),48):draw_line(Vector2(x,y+sin(x*.02+i)*5),Vector2(x+25,y+sin(x*.02+i)*5),Color(.83,.93,.89,.13),1,false)
		if period=="night":moon_and_reflection(size)
func moon_and_reflection(size:Vector2)->void:
	var at:=Vector2(size.x*.79,93)
	for y in range(-31,32):
		for x in range(-31,32):
			if x*x+y*y<31*31 and (x-11)*(x-11)+(y+6)*(y+6)>28*28:draw_rect(Rect2(at+Vector2(x,y),Vector2.ONE),Color("f9edc2"))
	for i in range(13):
		var width:float=20+i*3+sin(i*2.4)*12
		draw_rect(Rect2(Vector2(at.x-width/2+sin(i*1.7)*10,140+i*7),Vector2(width,2)),Color(1,.91,.61,.16))
func sprite(id:String,foot:Vector2,tint:Color=Color.WHITE,render_size:Vector2=Vector2.ZERO)->void:
	var texture:Texture2D=assets[id];var pixels:Vector2=texture.get_size() if render_size==Vector2.ZERO else render_size
	draw_texture_rect(texture,Rect2((foot-Vector2(pixels.x/2,pixels.y-4)).round(),pixels),false,tint)
func actor(entry:Dictionary,origin:Vector2,tint:Color)->void:
	var texture:Texture2D=library.texture(entry.id,entry.frame)
	draw_texture(texture,(origin+entry.point-entry.anchor).round(),tint)
func _draw()->void:
	if not ready_for_capture:return
	var night:bool=period=="night";var tint:Color=Color("72879e") if night else Color.WHITE;var origin:=local_origin()
	ground(tint)
	var title:String=LocalText.text("ui.campfire_v4_study.main_island_campfire_clearing") if biome=="mainland" else LocalText.text("ui.campfire_v4_study.crescent_island_moonlit_beach_campfire")
	draw_string_outline(font,Vector2(28,40),title,HORIZONTAL_ALIGNMENT_LEFT,-1,22,4,Color("31423b"))
	draw_string(font,Vector2(28,40),title,HORIZONTAL_ALIGNMENT_LEFT,-1,22,Color("fff1cc"))
	if night:
		draw_set_transform(origin+Vector2(0,15),0,Vector2(1,.70))
		for radius in range(300,0,-10):draw_circle(Vector2.ZERO,radius,Color(1,.66,.29,.009))
		draw_set_transform(Vector2.ZERO)
	# Native pixel props; assembly changes only the independent picture composition.
	for i in range(8):
		var angle:float=TAU*i/8
		var foot:Vector2=origin+Vector2(cos(angle)*204,sin(angle)*127+35)
		var id:String=biome+("-stool" if i%2==0 else "-bench" if i in [1,3,5,7] else "-stool")
		if id.ends_with("-bench"):
			# Original bench art is a scale reference; empty peripheral seats stay clear.
			continue
		sprite(id,foot,tint)
	sprite(biome+"-bench-up",origin+Vector2(-122,-88),tint)
	sprite(biome+"-bench-up",origin+Vector2(128,-87),tint)
	sprite(biome+"-logs",origin+Vector2(-285,-25),tint)
	sprite(biome+"-logs",origin+Vector2(-255,0),tint)
	sprite(biome+"-sign",origin+Vector2(285,-31),tint)
	sprite(biome+"-mushrooms",origin+Vector2(280,65),tint)
	for p in [Vector2(-310,145),Vector2(305,149),Vector2(-270,-130)]:sprite(biome+"-grass_clump",origin+p,tint)
	if biome=="mainland":
		for p in [Vector2(-300,150),Vector2(305,147)]:sprite(biome+"-flowers",origin+p,tint)
	else:
		for p in [Vector2(-290,120),Vector2(268,155),Vector2(338,112)]:sprite("shell",origin+p,tint)
	# Sort existing sitting character frames around the same physical firepit scale.
	for entry in characters:
		if entry.point.y<35:actor(entry,origin,tint.lerp(Color("ffe2b1"),.28 if night else 0))
	var frame:int=int(animation_time*6)%4
	sprite(biome+"-fire-"+str(frame),origin+Vector2(0,48),Color.WHITE if night else tint)
	# Quiet smoke and embers are bounded pure presentation, never world events.
	for i in range(3):
		var rise:float=fposmod(animation_time*.22+i*.31,1)
		var smoke:Texture2D=assets.smoke
		var width:float=24+rise*28;var at:Vector2=origin+Vector2(sin(rise*4+i)*15,-60-rise*110)
		draw_texture_rect(smoke,Rect2(at-Vector2(width/2,width/2),Vector2.ONE*width),false,Color(.86,.84,.77,sin(rise*PI)*.38))
	for i in range(10):
		var rise:float=fposmod(animation_time*.31+i*.117,1);var at:Vector2=origin+Vector2(sin(i*4+rise*3)*20,-20-rise*75)
		draw_rect(Rect2(at.round(),Vector2(2,2)),Color(1,.69,.21,(1-rise)*.75))
	for entry in characters:
		if entry.point.y>=35:actor(entry,origin,tint.lerp(Color("ffe2b1"),.35 if night else 0))
	sprite("string-lights",origin+Vector2(0,-220),tint)
	if night:
		for i in range(8):
			var x:float=-205+i*59;var y:float=-294+sin((i*59.0+25.0)/460.0*PI)*26
			for radius in [11,7,3]:draw_circle(origin+Vector2(x,y),radius,Color(1,.79,.38,.12))
	var note:String=LocalText.text("ui.campfire_v4_study.reused_study_artwork_image_endpoint_returned_401_separate_sample")
	draw_string_outline(font,Vector2(24,get_viewport_rect().size.y-22),note,HORIZONTAL_ALIGNMENT_LEFT,-1,13,3,Color("33443d"))
	draw_string(font,Vector2(24,get_viewport_rect().size.y-22),note,HORIZONTAL_ALIGNMENT_LEFT,-1,13,Color("f7e7c4"))

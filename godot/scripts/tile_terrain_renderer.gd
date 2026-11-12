class_name TileTerrainRenderer
extends Node2D
## Static tile bake only; never routes or mutates terrain/world.
var terrain:RefCounted
var style:Dictionary={}
var cache_builds:=0
var cached_revision:=-1
var _style_key:=""
var _cached_style_key:=""
var ground:Image
var texture:ImageTexture
var tint:=Color.WHITE
const RANK={"deep_water":0,"shallow_water":1,"sand":2,"grass":3,"soil":4,"stone":5}
const BASE={"deep_water":1,"shallow_water":4,"sand":22,"grass":12,"soil":19,"stone":28}
func configure(layer:RefCounted,grammar:Dictionary)->void:
	terrain=layer;style=grammar.duplicate(true);_style_key=JSON.stringify(style).sha256_text();cached_revision=-1
	texture_filter=CanvasItem.TEXTURE_FILTER_NEAREST;queue_redraw()
func color(index:int)->Color:return Color(style.palette[clampi(index,0,47)].hex)
func grain(material:String,x:int,y:int)->Color:
	var hash_value: int=(x*374761393+y*668265263)&0x7fffffff
	hash_value=((hash_value^(hash_value>>13))*1274126177)&0x7fffffff
	hash_value=(hash_value^(hash_value>>16))%4096
	var base:int=BASE[material]
	if material=="stone":
		var sx:int=(x+((y/12)%2)*12)%24;var sy:int=y%12
		if sy==0 or sx==0:return color(26)
		if sy==1 or sx==1:return color(29)
		if sy==11 or sx==23:return color(27)
		return color(29 if hash_value<10 else 27 if hash_value>4084 else 28)
	if material=="soil":
		if hash_value<12:return color(base-1)
		if hash_value>4084:return color(base+1)
	if material=="grass":
		if hash_value<5:return color(base-1)
		if hash_value>4091:return color(base+1)
	if material in ["shallow_water","deep_water"]:
		if (x+(y/8)*7)%43<9 and y%16==0:return color(base+1)
	elif material=="sand" and hash_value>4084:return color(base-1)
	return color(base)

func tile_image(at:Vector2i)->Image:
	var cell:Dictionary=terrain.cell(at);var image:=Image.create(32,32,false,Image.FORMAT_RGBA8)
	var neighbors:Array=[]
	for offset in [Vector2i.UP,Vector2i.RIGHT,Vector2i.DOWN,Vector2i.LEFT]:neighbors.append(terrain.cell(at+offset))
	for y in range(32):
		for x in range(32):
			var material:String=cell.material
			var distances:=[y,31-x,31-y,x]
			for i in range(4):
				var neighbor:Dictionary=neighbors[i]
				var lip:=3+absi((at.x*11+at.y*17+(x if i%2==0 else y)/4)*7)%3
				if not neighbor.is_empty() and RANK[neighbor.material]>RANK[material] and distances[i]<lip:material=neighbor.material
			image.set_pixel(x,y,grain(material,at.x*32+x,at.y*32+y))
	return image
func ensure_baked()->void:
	if terrain==null or cached_revision==terrain.revision and _cached_style_key==_style_key:return
	ground=Image.create(terrain.width*32,terrain.height*32,false,Image.FORMAT_RGBA8);ground.fill(Color.TRANSPARENT)
	for y in range(terrain.height):
		for x in range(terrain.width):
			var at:=Vector2i(x,y);var cell:Dictionary=terrain.cell(at);var point:=Vector2i(x*32,y*32-int(cell.height)*16)
			ground.blit_rect(tile_image(at),Rect2i(0,0,32,32),point)
			var below:Dictionary=terrain.cell(at+Vector2i.DOWN)
			if not below.is_empty() and int(below.height)<int(cell.height) :
				var face_height: int=(int(cell.height)-int(below.height))*16
				for py in range(face_height):
					for px in range(32):
						var joint:bool=py%8>=6 if cell.stairs else py%8==7 or (px+(py/8)*13)%24==0
						var dest:=point+Vector2i(px,32+py)
						if Rect2i(0,0,ground.get_width(),ground.get_height()).has_point(dest):ground.set_pixelv(dest,color(26 if joint else 29 if cell.stairs else 27 if py<3 else 26))
			if cell.stairs:
				for step in range(4):
					ground.fill_rect(Rect2i(point+Vector2i(0,step*8+5),Vector2i(32,2)),color(26))
	texture=ImageTexture.create_from_image(ground);cached_revision=terrain.revision;_cached_style_key=_style_key;cache_builds+=1
func _draw()->void:
	ensure_baked()
	if texture!=null:draw_texture(texture,Vector2.ZERO,tint)

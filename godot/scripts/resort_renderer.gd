extends RefCounted
## Flower Isle scenery: cached native pixel fields; no jobs or inventory here.
static var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/resort-villas.json"))
static var textures:Dictionary={}
const BEDS=[Rect2(58,192,20,12),Rect2(96,192,28,12),Rect2(27,215,24,14),Rect2(57,218,24,14),Rect2(93,216,28,12),Rect2(43,236,24,8),Rect2(95,236,24,8)]
const COLORS=["red","white","yellow","pink"]
static func asset(name:String)->Texture2D:
	if not textures.has(name):
		var path:String="res://assets/flower-isle/"+name+".png"
		if not preload("res://scripts/bundled_image.gd").exists(path):return null
		textures[name]=ImageTexture.create_from_image(preload("res://scripts/bundled_image.gd").read(path))
	return textures[name]
static func texture(_style:String,_night:bool)->Texture2D:return asset("greenhouse")
static func rect(v:Node,at:Vector2,size:Vector2,color:Color)->void:v.draw_rect(Rect2(v.screen(at-size/2),size*32*v.zoom),color)
static func patch(color:String,closed:bool)->Texture2D:
	var key:String="field-"+color+str(closed)
	if textures.has(key):return textures[key]
	var bush:Texture2D=asset("bush-"+color+("-closed" if closed else "-open"))
	var im:=Image.create(256,128,false,Image.FORMAT_RGBA8);im.fill(Color.TRANSPARENT)
	if bush!=null:
		var src:Image=bush.get_image()
		for y in range(0,128,23):
			for x in range(0,256,26):im.blend_rect(src,Rect2i(0,0,32,32),Vector2i(x+(12 if y%2 else 0),y))
	textures[key]=ImageTexture.create_from_image(im)
	return textures[key]
static func visible(v:Node,area:Rect2)->bool:
	return v.get_viewport_rect().grow(80).intersects(Rect2(v.screen(area.position),area.size*32*v.zoom))
static func ground(v:Node)->void:
	if v.region_id!="home" or not visible(v,Rect2(14,162,134,92)):return
	var camp:=Vector2(81,185)
	v._surface(preload("res://scripts/home_layout.gd").rectangle(Rect2(66,177,30,20),3),v.textures.sand,Color("e7d0a7"))
	rect(v,camp+Vector2(0,-3),Vector2(11,2),Color("9d7652"));rect(v,camp+Vector2(0,-3),Vector2(10.7,1.7),Color("c5a779"));rect(v,camp,Vector2(5,2),Color("495453"))
	for i in range(8):v.draw_line(v.screen(camp+Vector2(-2+i*.57,-.8)),v.screen(camp+Vector2(-2+i*.57,.8)),Color("c5b8a0"),2*v.zoom)
	var night:bool=v.world.days.phase().id=="night"
	for i in BEDS.size():
		var bed:Rect2=BEDS[i]
		if not visible(v,bed):continue
		# One cached field sprite per bed. Terrain remains a continuous polygon.
		v.draw_rect(Rect2(v.screen(bed.position),bed.size*32*v.zoom),Color("627b48"))
		v.draw_texture_rect(patch(COLORS[i%4],night),Rect2(v.screen(bed.position),bed.size*32*v.zoom),false)
		for n in range(4):
			var at:Vector2=bed.position+Vector2(fposmod(v.clock*.3+n*5,bed.size.x),fposmod(n*3+sin(v.clock+n)*.4,bed.size.y))
			if not night:
				var p:Vector2=v.screen(at)+Vector2(0,sin(v.clock*3+n)*5)*v.zoom
				v.draw_rect(Rect2(p,Vector2(3,2)*v.zoom),Color("f6c6bb"))
				if n==0:
					v.draw_line(p-Vector2(2,2)*v.zoom,p+Vector2(2,2)*v.zoom,Color("fff0bd"),3*v.zoom)
	for at in [Vector2(53,210),Vector2(88,211),Vector2(88,235)]:
		if not visible(v,Rect2(at-Vector2.ONE,Vector2(4,3))):continue
		rect(v,at+Vector2(0,.5),Vector2(3,.2),Color("514333"));rect(v,at,Vector2(3,1),Color("b88958"));rect(v,at-Vector2(0,.5),Vector2(3,.2),Color("ead29b"))
	var stall:Texture2D=asset("stall")
	if stall!=null and visible(v,Rect2(41,205,4,4)):v.draw_texture_rect(stall,Rect2(v.screen(Vector2(43,208))-Vector2(48,64)*v.zoom,Vector2(96,80)*v.zoom),false)
static func draw_entry(v:Node,entry:Dictionary)->bool:
	if entry.get("type")!="resort_villa":return false
	var row:Dictionary=entry.value
	if row.is_empty():return true
	var at:=Vector2(row.position[0],row.position[1]);var size:Vector2=Vector2(640,512)*v.zoom
	var box:=Rect2(v.screen(at)-size/2,size)
	if not v.get_viewport_rect().grow(100).intersects(box):return true
	var art:Texture2D=asset("greenhouse")
	if art!=null:v.draw_texture_rect(art,box,false)
	return true
static func hit(v:Node,mouse:Vector2)->String:
	if v.region_id!="home":return ""
	if Rect2(v.screen(Vector2(43,208))-Vector2(48,64)*v.zoom,Vector2(96,80)*v.zoom).has_point(mouse):return "flower.stall"
	for villa in data.villas:
		if v.screen(Vector2(villa.door[0],villa.door[1])).distance_to(mouse)<48*v.zoom:return villa.id
	return ""

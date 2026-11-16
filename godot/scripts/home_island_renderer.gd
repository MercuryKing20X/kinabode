extends RefCounted
## Authored pixel decorations only. Neither has an object/inventory/collision entry.
static var decor_textures:Dictionary={}
static func decoration(name:String)->Texture2D:
	if decor_textures.has(name):return decor_textures[name]
	var image:=Image.create(64,56,false,Image.FORMAT_RGBA8);image.fill(Color.TRANSPARENT)
	var outline:=Color("604735");var wood:=Color("ae7d4d");var light:=Color("d6b071")
	if name=="cat_home":
		image.fill_rect(Rect2i(7,46,50,5),Color("486447"))
		image.fill_rect(Rect2i(5,9,54,37),outline)
		image.fill_rect(Rect2i(8,12,48,31),wood)
		for y in [13,23,33]:
			image.fill_rect(Rect2i(8,y,48,2),light)
			image.fill_rect(Rect2i(8,y+8,48,1),outline)
		image.fill_rect(Rect2i(8,5,48,8),outline);image.fill_rect(Rect2i(8,5,45,3),light)
		image.fill_rect(Rect2i(7,12,4,31),light);image.fill_rect(Rect2i(52,12,4,31),Color("8b603d"))
		# Low, warm opening, linen cushion, and white-tipped tail emblem.
		image.fill_rect(Rect2i(19,25,27,20),outline)
		image.fill_rect(Rect2i(23,20,19,5),outline)
		image.fill_rect(Rect2i(23,18,5,4),outline);image.fill_rect(Rect2i(37,18,5,4),outline)
		image.fill_rect(Rect2i(22,39,21,4),Color("dfcfa8"))
		image.fill_rect(Rect2i(47,17,4,8),Color("de9950"));image.fill_rect(Rect2i(47,15,4,3),Color("f7eacb"))
	else:
		image.fill_rect(Rect2i(28,28,7,23),outline);image.fill_rect(Rect2i(28,28,3,21),wood)
		image.fill_rect(Rect2i(8,4,48,29),outline);image.fill_rect(Rect2i(10,6,44,24),wood)
		image.fill_rect(Rect2i(10,6,44,3),light);image.fill_rect(Rect2i(10,10,3,20),light)
		image.fill_rect(Rect2i(12,28,40,2),Color("8b603d"))
		for at in [Vector2i(14,12),Vector2i(49,12)]:image.fill_rect(Rect2i(at,Vector2i(2,2)),outline)
	decor_textures[name]=ImageTexture.create_from_image(image)
	return decor_textures[name]
static func draw_decoration(v:Node,name:String,at:Vector2)->void:
	var texture:Texture2D=decoration(name)
	v.draw_texture_rect(texture,Rect2(v.screen(at)-Vector2(64,56)*v.zoom,Vector2(128,112)*v.zoom),false)
static var draw_counts:Dictionary={"land":0,"decor":0}
static func visible(v:Node,box:Rect2)->bool:
	var screen_box:=Rect2(v.screen(box.position),box.size*32*v.zoom)
	return v.get_viewport_rect().grow(180).intersects(screen_box)
static func draw(v:Node)->void:
	if v.world.home_island==null or v.world.home_island.legacy:return
	var cfg:Dictionary=v.world.catalog.regions.home.layout.get("homelands",{})
	if cfg.is_empty():return
	var bridge:PackedVector2Array=v.world.surface_polygon("homelands.bridge")
	if visible(v,Rect2(79,108,4,76)):
		v._surface(bridge,v.boardwalk,Color.WHITE)
		for x in [79.5,82.5]:
			var a:Vector2=v.screen(Vector2(x,108));var b:Vector2=v.screen(Vector2(x,183))
			v.draw_line(a+Vector2(0,-8)*v.zoom,b+Vector2(0,-8)*v.zoom,Color("805b3c"),3*v.zoom)
			v.draw_line(a+Vector2(0,-11)*v.zoom,b+Vector2(0,-11)*v.zoom,Color("dbb778"),2*v.zoom)
			for y in range(109,183,4):
				if visible(v,Rect2(x,y,1,1)):v.draw_rect(Rect2(v.screen(Vector2(x,y))-Vector2(2,12)*v.zoom,Vector2(4,14)*v.zoom),Color("987044"))
	var land:PackedVector2Array=v.world.home_island.land_shape
	if not visible(v,Rect2(14,162,134,92)):return
	v._surface(land,v.textures.grass,Color("a3bb76"));draw_counts.land+=1
	for road in v.world.home_island.config.get("roads",[]):
		var points:=PackedVector2Array()
		for p in road.points:points.append(Vector2(p[0],p[1]))
		v._path(points,.85)
	var cat_at:Array=v.world.home_island.config.cat_home
	draw_decoration(v,"cat_home",Vector2(cat_at[0],cat_at[1]))
static func hit(_v:Node,_mouse:Vector2)->String:return ""

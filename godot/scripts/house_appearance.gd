extends RefCounted
## Cosmetic only: never changes blueprints, paid costs, footprints or doors.
const OWNERS=["human","codex","companion-2","npc.mira","npc.nora"]
const SOURCES=["human","gentle","curious","lively","quiet"]
static var cache:Dictionary={}
static func owner(site:Dictionary)->String:
	if site.get("owner_id","") in OWNERS:return site.owner_id
	var index:int=["home.house.01","home.house.02","home.house.03","home.house.04","home.house.05"].find(str(site.get("id","")))
	return OWNERS[index] if index>=0 else "human"
static func enabled(site:Dictionary)->bool:
	var authored:bool=site.get("owner_id","") in OWNERS or str(site.get("id","")) in ["home.house.01","home.house.02","home.house.03","home.house.04","home.house.05"]
	return site.get("house_appearance","personal" if authored else "classic") in ["personal","personal_legacy"]
static func texture(site:Dictionary,library:RefCounted,night:bool=false)->Texture2D:
	var id:=owner(site)
	if site.get("house_appearance","personal")!="personal_legacy":
		var names:Array=["human","white","blue","orange","black"]
		var path:String="res://assets/houses-redraw/"+str(names[OWNERS.find(id)])+("-night.png" if night else "-day.png")
		if not cache.has(path):cache[path]=ImageTexture.create_from_image(preload("res://scripts/bundled_image.gd").read(path))
		return cache[path]
	var key:String=id+str(night)
	if cache.has(key):return cache[key]
	var art:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/home-v3/works/houses/"+SOURCES[OWNERS.find(id)]+".json"))
	var image:Image=library.frozen_texture(art,"stage_4").get_image()
	var w:int=image.get_width();var h:int=image.get_height()
	var ink:=Color("523c35");var wood:=Color("ae7952");var light:=Color("f4d49a");var leaf:=Color("537657")
	if id=="human":
		for x in range(52,w-45,12):
			box(image,Rect2i(x,h-26,8,3),wood);box(image,Rect2i(x,h-23,3,15),ink)
		box(image,Rect2i(23,h-40,3,28),wood);box(image,Rect2i(16,h-46,18,14),ink);box(image,Rect2i(18,h-44,14,9),Color("b36e54"))
	elif id=="codex":
		for x in [35,w-48]:
			box(image,Rect2i(x,h-75,27,31),ink);box(image,Rect2i(x+2,h-73,23,27),Color("8eb3af"))
			box(image,Rect2i(x+12,h-73,2,27),light)
		for x in range(28,w-24,23):flower(image,Vector2i(x,h-30),leaf,Color("c99ca9"))
	elif id=="companion-2":
		box(image,Rect2i(24,h-73,w-48,2),ink)
		for x in range(38,w-30,28):
			box(image,Rect2i(x,h-72,1,9),ink);box(image,Rect2i(x-3,h-63,7,12),Color("bd9663"));box(image,Rect2i(x-1,h-62,2,8),light)
		box(image,Rect2i(w-38,h-43,2,23),wood);box(image,Rect2i(w-57,h-43,2,23),wood);box(image,Rect2i(w-58,h-21,23,4),Color("ab999f"))
	elif id=="npc.mira":
		for row in range(3):
			for col in range(4):
				box(image,Rect2i(20+col*9,h-17-row*7,8,6),ink);box(image,Rect2i(21+col*9,h-16-row*7,6,3),wood)
		for x in range(w-65,w-25,10):
			box(image,Rect2i(x,h-66,2,17),wood);box(image,Rect2i(x-3,h-68,8,4),Color("86928a"))
		box(image,Rect2i(65,h-39,30,19),Color("d3c7ad"));box(image,Rect2i(65,h-39,30,2),light)
	else:
		for x in range(23,w-22,19):
			var y:int=85+int(sin(float(x)*.025)*6)
			box(image,Rect2i(x,y,2,7),ink);box(image,Rect2i(x-2,y+5,6,3),light)
		for x in range(27,64,7):box(image,Rect2i(x,h-41,5,19),Color("77737e"));box(image,Rect2i(x,h-41,5,2),light)
	if night:
		for window in art.get("openings",{}).get("windows",[]):
			box(image,Rect2i(int(window[0])+5,int(window[1])+6,maxi(1,int(window[2])-10),maxi(1,int(window[3])-12)),Color("edc57f"))
		for y in range(image.get_height()):
			for x in range(image.get_width()):
				var c:=image.get_pixel(x,y)
				if c.a>0 and c!=Color("edc57f"):image.set_pixel(x,y,c*Color(.73,.76,.87,1))
	cache[key]=ImageTexture.create_from_image(image);return cache[key]
static func box(image:Image,rect:Rect2i,color:Color)->void:
	image.fill_rect(rect.intersection(Rect2i(0,0,image.get_width(),image.get_height())),color)
static func flower(image:Image,at:Vector2i,leaf:Color,petal:Color)->void:
	box(image,Rect2i(at.x,at.y,11,7),Color("9c7154"));box(image,Rect2i(at.x+2,at.y-8,7,9),leaf);box(image,Rect2i(at.x,at.y-12,5,5),petal);box(image,Rect2i(at.x+6,at.y-10,5,5),petal)

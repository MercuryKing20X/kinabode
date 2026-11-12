extends RefCounted
var manifest:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/play-animations/manifest.json"))
var textures:Dictionary={}
var valid:Dictionary={}
func texture(library:RefCounted,actor:Dictionary,column:int)->Texture2D:
	var id:String=library.visual_appearance(actor)
	if not manifest.works.has(id):return null
	var work:Dictionary=library.artworks[id]
	var key:String=id+":"+str(work.get("revision",0))
	if not valid.has(key):
		var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/characters/"+id+".json"))
		valid[key]=work.frames==source.frames and work.palette==source.palette and work.anchor==source.anchor and work.width==96 and work.height==128
	if not valid[key]:return null
	if not textures.has(id):textures[id]=ImageTexture.create_from_image(Image.load_from_file("res://content/play-animations/"+manifest.works[id].asset))
	var result:=AtlasTexture.new();result.atlas=textures[id];result.region=Rect2(clampi(column,0,34)*96,0,96,128);return result
static func turn_column(phase:float)->int:return [15,14,13,14][int(fposmod(phase,1)*4)]
static var hand_manifest:Dictionary={}
static func hand(phase:float,right:bool,appearance:String="",facing:String="down")->Vector2:
	if not appearance.is_empty():
		if hand_manifest.is_empty():hand_manifest=JSON.parse_string(FileAccess.get_file_as_string("res://content/play-animations/manifest.json"))
		var data:Dictionary=hand_manifest
		var points:Array=data.get("works",{}).get(appearance,{}).get("rope_hands",{}).get(facing,[])
		if points.size()==3:
			var point:Array=points[turn_column(phase)-13][1 if right else 0]
			return Vector2(point[0],point[1])-Vector2(48,120)
	return Vector2(70 if right else 26,[86,78,69][turn_column(phase)-13])-Vector2(48,120)

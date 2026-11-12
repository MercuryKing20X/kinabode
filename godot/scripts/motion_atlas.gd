extends RefCounted
## Optional imported action textures. Missing art and edited works use the original pose.
var manifests:Dictionary={}
var verified:Dictionary={}
var sheets:Dictionary={}
var frames:Dictionary={}
func _init()->void:
	for action in ["run","eat","walk","chop","gather","farm","gesture"]:
		var path:String="res://content/"+action+"-animations/manifest.json"
		if FileAccess.file_exists(path):
			var data:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
			if data is Dictionary:manifests[action]=data
func spec(action:String,library:RefCounted,actor:Dictionary)->Dictionary:
	var id:String=library.visual_appearance(actor)
	var data:Dictionary=manifests.get(action,{})
	var item:Dictionary=data.get("works",{}).get(id,{})
	if item.get("status")!="independent":return {}
	var work:Dictionary=library.artworks.get(id,{})
	var key:String=action+":"+id+":"+str(work.get("revision",0))
	if not verified.has(key):
		var values:PackedStringArray=[]
		var layers:Array=work.get("frames",{}).get("down_0",[])
		if layers.size()==1 and layers[0].get("visible",false):
			for value in layers[0].get("pixels",[]):values.append(str(int(value)))
		verified[key]=not values.is_empty() and ",".join(values).sha256_text()==item.get("base_frame_sha256","") and "|".join(PackedStringArray(work.get("palette",[]))).sha256_text()==item.get("base_palette_sha256","")
		if action in ["walk","chop","gather","farm","gesture"] and verified[key]:
			var original:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/characters/"+id+".json"))
			verified[key]=original is Dictionary and work.get("frames",{})==original.get("frames",{})
	return item if verified[key] else {}
func texture(action:String,library:RefCounted,actor:Dictionary,col:int)->Texture2D:
	var item:=spec(action,library,actor)
	if item.is_empty():return null
	if action=="eat" and food_hand(library,actor,col).is_empty():return null
	var row:int=["down","left","right","up"].find(str(actor.facing))
	if row<0:return null
	var asset:String=str(item.asset)
	if action in ["walk","run"] and not str(item.get("hands_busy_asset","")).is_empty() and actor.get("carry",{}).values().any(func(value):return float(value)>0):asset=str(item.hands_busy_asset)
	var id:String=library.visual_appearance(actor);var key:String=action+":"+id+":"+asset
	var columns:int=int(manifests[action].columns)
	col=posmod(col,columns)
	var frame_key:String=key+":"+str(row)+":"+str(col)
	if frames.has(frame_key):return frames[frame_key]
	if not sheets.has(key):
		var imported:Texture2D=load("res://content/"+action+"-animations/"+asset)
		if imported==null or imported.get_size()!=Vector2(96*columns,512):return null
		sheets[key]=imported
	var frame:=AtlasTexture.new();frame.atlas=sheets[key];frame.region=Rect2(col*96,row*128,96,128);frames[frame_key]=frame
	return frame
func food_hand(library:RefCounted,actor:Dictionary,col:int)->Dictionary:
	var item:=spec("eat",library,actor)
	var row:int=["down","left","right","up"].find(str(actor.facing))
	var hands:Variant=item.get("hands",[])
	if row<0 or not hands is Array or hands.size()!=4 or not hands[row] is Array or hands[row].size()!=10:return {}
	var hand:Variant=hands[row][posmod(col,10)]
	if not hand is Dictionary or not hand.get("pixel") is Array or hand.pixel.size()!=2 or not hand.get("front") is bool:return {}
	return hand

func run_contact(library:RefCounted,actor:Dictionary,col:int)->Dictionary:
	return contact("run",library,actor,col)

func contact(action:String,library:RefCounted,actor:Dictionary,col:int)->Dictionary:
	var item:Dictionary=spec(action,library,actor)
	var row:int=["down","left","right","up"].find(str(actor.facing))
	var feet:Variant=item.get("feet",[])
	if row<0 or not feet is Array or feet.size()!=4 or not feet[row] is Array or feet[row].size()!=6:return {}
	var foot:Variant=feet[row][posmod(col,6)]
	if not foot is Dictionary or not foot.get("pixel") is Array or foot.pixel.size()!=2 or not foot.get("airborne") is bool:return {}
	return foot

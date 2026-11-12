extends RefCounted
## Original detailed cottage masters, native pixel density. No collision/blueprint edits.
static var cache:Dictionary={}
static func art(site:Dictionary)->Dictionary:
	var variants:={"home.future.plaza.west":"gentle","home.future.plaza.east":"curious","home.future.dock":"quiet","home.future.forest":"lively"}
	var key:String=variants.get(str(site.get("id","")),"human")
	if not cache.has(key):cache[key]=JSON.parse_string(FileAccess.get_file_as_string("res://content/home-v3/works/houses/"+key+".json"))
	return cache[key]
static func texture(site:Dictionary,library:RefCounted,stage:int)->Texture2D:
	return library.frozen_texture(art(site),"stage_"+str(clampi(stage-1,0,4)))

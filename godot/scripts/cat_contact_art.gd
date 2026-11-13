extends RefCounted
## New composite poses from each current editable appearance's idle frame.
## Does not read pickup/putdown frames or mutate original artwork.
var cache:Dictionary={}
func redrawn(library:RefCounted,actor:Dictionary)->bool:
	var visual:String=library.visual_appearance(actor)
	return int(library.artworks[visual].get("revision",1))==1 and preload("res://scripts/bundled_image.gd").exists("res://assets/cat-contact-redraw/"+visual+"-hold-down-0.png")
func texture(library:RefCounted,actor:Dictionary,action:String,column:int)->Texture2D:
	var visual:String=library.visual_appearance(actor)
	var facing:String=str(actor.get("facing","down"))
	var redraw:String="res://assets/cat-contact-redraw/%s-%s-%s-%d.png"%[visual,action,facing,column]
	if int(library.artworks[visual].get("revision",1))==1 and preload("res://scripts/bundled_image.gd").exists(redraw):
		if not cache.has(redraw):cache[redraw]=ImageTexture.create_from_image(preload("res://scripts/bundled_image.gd").read(redraw))
		return cache[redraw]
	column=column%2
	var asset_path:String="res://assets/cat-contact/%s-%s-%s-%d.png"%[visual,action,facing,column]
	if int(library.artworks[visual].get("revision",1))==1 and preload("res://scripts/bundled_image.gd").exists(asset_path):
		if not cache.has(asset_path):cache[asset_path]=ImageTexture.create_from_image(preload("res://scripts/bundled_image.gd").read(asset_path))
		return cache[asset_path]
	var base:Texture2D=library.texture(visual,facing+"_0")
	if base==null:return null
	var key:String=visual+":"+str(base.get_rid())+":"+action+":"+facing+":"+str(column)
	if cache.has(key):return cache[key]
	var image:Image=base.get_image().duplicate()
	var width:int=image.get_width();var height:int=image.get_height()
	var cx:int=width/2;var cy:int=height*.58
	var skin:=Color("f3c9a1");var outline:=Color("634b43")
	# Authored contact silhouette: arms cradle across the torso, or reach down
	# from a lowered shoulder. Each direction has a distinct contact placement.
	var offset:int=-width/7 if facing=="left" else width/7 if facing=="right" else 0
	if action=="pet":cy+=height/8
	for side in [-1,1]:
		var start:=Vector2i(clampi(cx+side*width/7+offset,0,width-1),clampi(cy,0,height-1))
		var end:=Vector2i(clampi(cx+side*width/14+offset,0,width-1),clampi(cy+height/12+column,0,height-1))
		var steps:int=maxi(1,start.distance_to(end))
		for n in range(steps+1):
			var p:=Vector2i(Vector2(start).lerp(Vector2(end),float(n)/steps))
			image.fill_rect(Rect2i(p-Vector2i(2,2),Vector2i(5,5)).intersection(Rect2i(0,0,width,height)),outline)
			image.fill_rect(Rect2i(p-Vector2i(1,1),Vector2i(3,3)).intersection(Rect2i(0,0,width,height)),skin)
	if cache.size()>192:cache.clear()
	cache[key]=ImageTexture.create_from_image(image)
	return cache[key]

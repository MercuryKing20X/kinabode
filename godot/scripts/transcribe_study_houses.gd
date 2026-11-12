extends SceneTree
## Hand-authored structural collage using approved original cottage pixel pieces only.
var source:Dictionary
var plan:Dictionary
var masters:Dictionary={}
var image:Image
var parent:Image
var colors:Array[Color]=[]
var dark_cache:Dictionary={}
func solid_sample(rect:Array,x:int,y:int)->Color:
	var c:=parent.get_pixel(int(rect[0])+posmod(x,int(rect[2])),int(rect[1])+posmod(y,int(rect[3])))
	return c if c.a>.9 else parent.get_pixel(40,150)
func darken_to_original(c:Color)->Color:
	var key:=c.to_html(true)
	if dark_cache.has(key):return dark_cache[key]
	var target:=c.darkened(.28);var best:Color=c;var distance:=100.0
	for color in colors:
		if color.a<.9:continue
		var next:float=pow(color.r-target.r,2)+pow(color.g-target.g,2)+pow(color.b-target.b,2)
		if next<distance:distance=next;best=color
	dark_cache[key]=best;return best
func put(x:int,y:int,c:Color)->void:
	if x>=0 and y>=0 and x<image.get_width() and y<image.get_height() and c.a>.01:image.set_pixel(x,y,c)
func polygon(points:Array,material:String,dark:bool=false)->void:
	var shape:=PackedVector2Array()
	for point in points:shape.append(Vector2(point[0],point[1]))
	var rect:Array=source.swatches[material]
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if Geometry2D.is_point_in_polygon(Vector2(x,y),shape):
				var shift:int=int(pow((x-image.get_width()/2)/24.0,2)) if plan.roof=="soft_arch_tiled_cottage" and material=="roof" else 0
				var c:=solid_sample(rect,x,y+shift)
				put(x,y,darken_to_original(c) if dark else c)
func beam(a:Array,b:Array,width:int=2)->void:
	var from:=Vector2(a[0],a[1]);var to:=Vector2(b[0],b[1]);var count:=int(maxf(absf(to.x-from.x),absf(to.y-from.y)))
	for i in range(count+1):
		var at:=from.lerp(to,float(i)/maxi(1,count)).round()
		for dx in range(width):
			for dy in range(width):put(int(at.x)+dx,int(at.y)+dy,solid_sample(source.swatches.wood,int(at.x)+dx,int(at.y)+dy))
func piece(box:Array,name:String)->void:
	var rect:Array=source.pieces[name];var border:=3
	for y in range(int(box[3])):
		for x in range(int(box[2])):
			var sx:int=x if x<border else int(rect[2])-int(box[2])+x if x>=box[2]-border else border+posmod(x-border,int(rect[2])-border*2)
			var sy:int=y if y<border else int(rect[3])-int(box[3])+y if y>=box[3]-border else border+posmod(y-border,int(rect[3])-border*2)
			put(int(box[0])+x,int(box[1])+y,parent.get_pixel(int(rect[0])+sx,int(rect[1])+sy))
func paint(stage:int)->Image:
	image=Image.create(int(plan.canvas[0]),int(plan.canvas[1]),false,Image.FORMAT_RGBA8);image.fill(Color.TRANSPARENT)
	polygon(plan.base,"stone")
	if stage==1:
		for wall in plan.walls:
			beam(wall[0],wall[-1]);beam(wall[1],wall[-2])
	if stage>=2:
		for index in range(plan.walls.size()):
			var material:String="wood" if plan.get("dark",false) or plan.roof=="classic_tiled_gable" else "plaster" if index==0 else "wood"
			polygon(plan.walls[index],material,plan.get("dark",false))
			beam(plan.walls[index][0],plan.walls[index][-1],3);beam(plan.walls[index][1],plan.walls[index][-2],3)
	if stage>=3:
		for roof in plan.roof_polygons:polygon(roof,"roof",plan.get("dark",false))
		for i in range(plan.roof_trim.size()-1):beam(plan.roof_trim[i],plan.roof_trim[i+1],2)
		if plan.has("chimney"):piece([plan.chimney[0],plan.chimney[1],23,35],"chimney")
	if stage==4:
		for index in range(plan.windows.size()):piece(plan.windows[index],"dormer" if index==0 and plan.get("dormer",false) else "small_window" if plan.windows[index][2]<30 else "window")
		for door in plan.doors:piece(door,"door")
		if not plan.porch.is_empty():
			polygon(plan.porch,"wood",plan.get("dark",false))
			if plan.structure.porch>=2:
				var y:int=plan.doors[0][1]-6
				for point in [plan.porch[0],plan.porch[1]]:beam([point[0],y],point,3)
				beam([plan.porch[0][0],y],[plan.porch[1][0],y],3)
		if plan.has("balcony"):
			var b:Array=plan.balcony;polygon([[b[0],b[1]],[b[0]+b[2],b[1]],[b[0]+b[2],b[1]+b[3]],[b[0],b[1]+b[3]]],"wood")
			beam([b[0],b[1]-14],[b[0]+b[2],b[1]-14],2)
			for x in range(int(b[0]),int(b[0]+b[2]),7):beam([x,b[1]-14],[x,b[1]],2)
	return image.duplicate()
func _initialize()->void:
	source=JSON.parse_string(FileAccess.get_file_as_string("res://content/art-studies/house-source.json"))
	var lib:RefCounted=load("res://scripts/character_library.gd").new()
	for id in source.parents:
		var art:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/works/"+id+".json"));masters[id]=lib.render(art,"stage_4")
		for hex in art.palette:
			var c:=Color(hex)
			if not colors.has(c):colors.append(c)
	for id in source.profiles:
		plan=source.profiles[id];parent=masters[plan.parent];var frames:Array=[];var palette:Array=["#00000000"];var indices:Dictionary={"00000000":0}
		for stage in range(5):frames.append(paint(stage))
		var art:Dictionary={"schema_version":1,"id":"study-house-"+id,"name":plan.name,"kind":"building","revision":2,"width":int(plan.canvas[0]),"height":int(plan.canvas[1]),"anchor":plan.anchor,"structure":plan.structure,"frames":{},"roof_profile":plan.roof,"orientation":plan.orientation,"openings":{"doors":plan.doors,"windows":plan.windows},"yard":plan.yard,"art_scale":2,"style_parent":source.parents,"source":"Hand-authored structural collage using original approved cottage pixel materials, not flat geometry colors."}
		for stage in range(5):
			var pixels:Array=[];var frame:Image=frames[stage]
			for y in range(frame.get_height()):
				for x in range(frame.get_width()):
					var hex:String=frame.get_pixel(x,y).to_html(true)
					if not indices.has(hex):indices[hex]=palette.size();palette.append("#"+hex)
					pixels.append(indices[hex])
			art.frames["stage_"+str(stage)]=[{"name":"approved-style pixel pieces","visible":true,"pixels":pixels}]
		art.palette=palette;assert(lib.valid(art));var f:=FileAccess.open("res://content/art-studies/houses/"+id+".json",FileAccess.WRITE);f.store_string(JSON.stringify(art));f.close()
		var preview:Image=lib.render(art,"stage_4");preview.resize(preview.get_width()*2,preview.get_height()*2,Image.INTERPOLATE_NEAREST);preview.save_png("res://../production/art/island-v3-stage1b/house-previews/"+id+"-asset-2x.png")
	print("Approved cottage-style pieces transcribed into five distinct editable works.");quit()

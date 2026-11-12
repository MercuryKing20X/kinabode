extends RefCounted
## Cached polygon/UV commands over existing continuous material textures. No tile/world rules.
const Layout=preload("res://scripts/home_layout.gd")
var commands:Array=[]
var textures:Dictionary={}
var cache_builds:=0
var key:=""
var visual_plaza:=PackedVector2Array()
func load_textures()->void:
	if not textures.is_empty():return
	for material in ["grass","sand","soil"]:
		for i in range(3):textures[material+str(i)]=ImageTexture.create_from_image(Image.load_from_file("res://content/art-studies/textures/"+material+"-"+str(i)+".png"))
	for family in ["transition","coast"]:
		for i in range(3):textures[family+str(i)]=ImageTexture.create_from_image(Image.load_from_file("res://content/art-studies/textures/"+family+"-"+str(i)+".png"))
	textures.stone=ImageTexture.create_from_image(Image.load_from_file("res://content/art-studies/textures/stone.png"))
	for i in range(3):textures["slab"+str(i)]=ImageTexture.create_from_image(Image.load_from_file("res://content/home-v3/textures/stone-"+str(i)+".png"))
	textures.water=ImageTexture.create_from_image(Image.load_from_file("res://assets/island/water.png"))
func surface(shape:PackedVector2Array,material:String,color:Color)->void:
	var pixels:=PackedVector2Array();var uv:=PackedVector2Array();var size:Vector2=textures[material].get_size()
	for point in shape:pixels.append((point*32).round());uv.append(point*32/size)
	commands.append({"kind":"surface","shape":pixels,"uv":uv,"material":material,"color":color})
func ragged(shape:PackedVector2Array)->PackedVector2Array:
	var result:=PackedVector2Array();var profile:=[0.0,.8,-1.4,.4,1.1,-.7,.2,-.4,1.4,-.9,.5];var serial:=0
	for i in range(shape.size()):
		var a:Vector2=shape[i];var b:Vector2=shape[(i+1)%shape.size()];var direction:Vector2=(b-a).normalized();var normal:=Vector2(-direction.y,direction.x)
		var count:=maxi(1,int(a.distance_to(b)*32/12))
		for n in range(count):result.append(a.lerp(b,float(n)/count)+normal*profile[serial%profile.size()]/32);serial+=1
	return result
func soft_surface(shape:PackedVector2Array,material:String,color:Color)->void:
	var contour:=ragged(shape)
	for layer in [[.16,.18],[.08,.27],[0.0,.55],[-.10,1.0]]:
		for part in Geometry2D.offset_polygon(contour,layer[0],Geometry2D.JOIN_MITER):
			var ink:=color;ink.a*=layer[1];surface(part,material,ink)
func strokes(path:PackedVector2Array,width:float,material:String,color:Color)->void:
	var pixels:=PackedVector2Array()
	for p in path:pixels.append(p*32)
	for shape in Geometry2D.offset_polyline(pixels,width*32,Geometry2D.JOIN_ROUND,Geometry2D.END_ROUND):
		var units:=PackedVector2Array()
		for point in shape:units.append(point/32)
		soft_surface(units,material,color)
func brushes(path:PackedVector2Array,closed:bool=true,family:String="transition")->void:
	var points:=path.duplicate()
	if closed:points.append(points[0])
	var serial:=0
	for i in range(points.size()-1):
		var count:=maxi(1,int(points[i].distance_to(points[i+1])*32/43))
		for j in range(count):
			var position:Vector2=points[i].lerp(points[i+1],float(j+.25)/count)*32
			commands.append({"kind":"brush","position":position.round()-Vector2(32,24),"material":family+str(serial%3),"color":Color.WHITE});serial+=1
func irregular_ring(center:Array,radius:Vector2)->PackedVector2Array:
	var result:=PackedVector2Array();var offsets:=[1.0,.94,1.07,.98,.91,1.05,.96,1.08,.95,1.01,.93,1.04]
	for i in range(offsets.size()):result.append(Vector2(center[0],center[1])+Vector2(cos(i*TAU/12),sin(i*TAU/12))*radius*offsets[i])
	return result
func path_points(config:Dictionary,values:Array)->PackedVector2Array:
	var result:=PackedVector2Array()
	for value in values:
		if value is String:
			for house in config.get("houses",[]):
				if house.id==value:result.append(Vector2(house.position[0],house.position[1]))
		else:result.append(Vector2(value[0],value[1]))
	return result
func prepare(config:Dictionary)->void:
	var next:=JSON.stringify(config).sha256_text()
	if key==next:return
	load_textures();commands.clear()
	var region:Dictionary=config.get("region",JSON.parse_string(FileAccess.get_file_as_string("res://content/packs/core.json")).regions[0])
	var land:PackedVector2Array=Layout.points(region.land)
	if not config.get("continuous_ocean",false):surface(Layout.points([[0,0],[region.size[0],0],region.size,[0,region.size[1]]]),"water",Color("80b3bd"))
	for sand in Geometry2D.offset_polygon(land,-.3,Geometry2D.JOIN_ROUND):surface(sand,"sand0",Color("f0d8a5"))
	var grass_shapes:=Geometry2D.offset_polygon(land,-1.9,Geometry2D.JOIN_ROUND)
	for grass in grass_shapes:surface(grass,"grass0",Color("a9ba9e"));brushes(grass)
	brushes(land,true,"coast")
	# Different irregular regions/UV material variants, never a per-tile gameplay grid.
	var camera:Array=config.camera
	var marks:Array=config.get("variant_regions",[])
	if marks.is_empty():
		for i in range(5):marks.append([camera[0]-14+i*6,camera[1]+[-6,5,-2,7,-6][i]])
	for i in range(marks.size()):
		var center:Array=marks[i]
		var region_shape:=irregular_ring(center,Vector2(4.7,3.4))
		for grass in grass_shapes:
			for intersection in Geometry2D.intersect_polygons(region_shape,grass):surface(intersection,"grass"+str(1+i%2),Color("a9ba9e"))
	for extra in region.get("land_extensions",[]):
		var contour:PackedVector2Array=Layout.points(extra)
		for sand in Geometry2D.offset_polygon(contour,-.3,Geometry2D.JOIN_ROUND):surface(sand,"sand1",Color("f0d8a5"))
		for grass in Geometry2D.offset_polygon(contour,-2.5,Geometry2D.JOIN_ROUND):surface(grass,"grass1",Color("a9ba9e"));brushes(grass)
		brushes(contour,true,"coast")
	var plaza:PackedVector2Array=Layout.points(config.plaza)
	var formal:bool=config.has("formal_plaza")
	if not formal:
		for worn in Geometry2D.offset_polygon(plaza,.4,Geometry2D.JOIN_ROUND):surface(worn,"soil2",Color(.70,.69,.58,.40))
		soft_surface(plaza,"sand1",Color("d3c398"));brushes(plaza)
		soft_surface(Layout.points(config.paving),"stone",Color("d8d0b9"));brushes(Layout.points(config.paving))
	for road in config.roads:
		var path:PackedVector2Array=path_points(config,road.points)
		if road.get("smooth",false):path=smooth_path(path)
		if road.get("material","")=="stone":
			strokes(path,road.width,"slab1",Color.WHITE);continue
		strokes(path,road.width+.28,"soil1",Color(.65,.65,.54,.40))
		strokes(path,road.width,"sand2",Color("d9cbaa"))
		# A hand-marked edge band follows the path, not a collision or speed modifier.
		var path_pixels:=PackedVector2Array()
		for point in path:path_pixels.append(point*32)
		for edge in Geometry2D.offset_polyline(path_pixels,road.width*32,Geometry2D.JOIN_ROUND,Geometry2D.END_ROUND):
			var units:=PackedVector2Array()
			for point in edge:units.append(point/32)
			brushes(units)
	if not formal and not config.well.is_empty():
		var ring:=irregular_ring(config.well,Vector2(2.3,1.4));soft_surface(ring,"soil0",Color(.9,.85,.7,.32));brushes(ring)
	if not formal and not config.shortcut.is_empty():strokes(Layout.points(config.shortcut),.27,"soil2",Color(.85,.8,.7,.45))
	if formal:
		visual_plaza=rounded_plaza(plaza,float(config.formal_plaza.get("corner_radius",0)))
		# Short stone aprons connect all four entrances to the external dirt roads.
		for i in range(4):
			var edge:Vector2=plaza[(i+1)%4]-plaza[i];var midpoint:Vector2=(plaza[i]+plaza[(i+1)%4])/2
			var outward:=Vector2(edge.normalized().y,-edge.normalized().x)
			strokes(PackedVector2Array([midpoint,midpoint+outward*float(config.formal_plaza.entrance_extension)]),float(config.formal_plaza.entrance_width)/2,"slab1",Color.WHITE)
		# Last opaque continuous surface masks every dirt road/wear command inside plaza.
		surface(visual_plaza,"slab0",Color.WHITE)
		for i in range(8):
			var center:Vector2=plaza[0].lerp(plaza[2],float(i+1)/9)
			for patch in Geometry2D.intersect_polygons(irregular_ring([center.x,center.y],Vector2(7,5)),visual_plaza):surface(patch,"slab"+str(1+i%2),Color.WHITE)
		var center:=Vector2(config.well[0],config.well[1]);var count:int=int(config.formal_plaza.get("ring_segments",24));var radius:float=config.formal_plaza.ring_radius;var width:float=config.formal_plaza.get("ring_width",.7)
		for i in range(count):
			var angle:float=(i+.5)*TAU/count;var normal:=Vector2(cos(angle),sin(angle));var tangent:=Vector2(-normal.y,normal.x)
			var at:Vector2=center+normal*(radius-width/2+[.02,-.04,.05,-.03][i%4]);var stone:=PackedVector2Array()
			for side in range(8):
				var turn:float=side*TAU/8;stone.append(at+tangent*cos(turn)*(.47+[.01,-.02,.02][i%3])+normal*sin(turn)*width*.48)
			var shadow:=PackedVector2Array()
			for point in stone:shadow.append(point+Vector2(.035,.07))
			surface(shadow,"slab0",Color(.4,.37,.31,.65))
			var ink:=Color(config.formal_plaza.get("ring_tint","#797466"));ink=ink.lightened(.10 if i%3==0 else .025)
			surface(stone,"slab"+str(i%3),ink)
			var top:Array=Array(stone);top.sort_custom(func(a,b):return a.y<b.y)
			surface(PackedVector2Array([top[0],top[1],at+Vector2(-.05,-.05)]),"slab1",ink.lightened(.18))
		# Separate edge stones follow rounded corners, with entrance gaps.
		var entries:=[(plaza[0]+plaza[1])/2,(plaza[1]+plaza[2])/2,(plaza[2]+plaza[3])/2,(plaza[3]+plaza[0])/2]
		for i in range(visual_plaza.size()):
			var a:Vector2=visual_plaza[i];var b:Vector2=visual_plaza[(i+1)%visual_plaza.size()];var steps:int=maxi(1,int(a.distance_to(b)))
			for j in range(steps):
				var mid:Vector2=a.lerp(b,(j+.5)/steps)
				if entries.any(func(entry):return mid.distance_to(entry)<float(config.formal_plaza.entrance_width)/2):continue
				surface(Layout.rectangle(Rect2(mid-Vector2(.32,.12),Vector2(.64,.24))),"slab2",Color("c4bca5"))
	key=next;cache_builds+=1
func draw(view:Node2D,tint:Color=Color.WHITE)->void:
	for command in commands:
		if command.kind=="surface":view.draw_polygon(command.shape,PackedColorArray([command.color*tint]),command.uv,textures[command.material])
		else:view.draw_texture(textures[command.material],command.position,command.color*tint)

func smooth_path(path:PackedVector2Array)->PackedVector2Array:
	var result:=PackedVector2Array([path[0]])
	for i in range(1,path.size()-1):
		var corner:Vector2=path[i];var radius:float=minf(2,minf(corner.distance_to(path[i-1]),corner.distance_to(path[i+1]))*.4)
		var a:Vector2=corner.move_toward(path[i-1],radius);var b:Vector2=corner.move_toward(path[i+1],radius)
		for step in range(9):
			var t:float=step/8.0;result.append(a*(1-t)*(1-t)+corner*2*(1-t)*t+b*t*t)
	result.append(path[-1]);return result
func rounded_plaza(shape:PackedVector2Array,radius:float)->PackedVector2Array:
	if radius<=0:return shape
	var result:=PackedVector2Array();var a:Vector2=shape[0];var b:Vector2=shape[2]
	var centers:=[a+Vector2(radius,radius),Vector2(b.x-radius,a.y+radius),b-Vector2(radius,radius),Vector2(a.x+radius,b.y-radius)]
	for i in range(4):
		for step in range(7):
			var angle:float=PI+i*PI/2+step*PI/12;result.append(centers[i]+Vector2(cos(angle),sin(angle))*radius)
	return result

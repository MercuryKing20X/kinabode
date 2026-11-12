extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
## Southern land shares home's coordinates and its one authoritative World route.
var _owner:WeakRef
var world:RefCounted:
	get:return _owner.get_ref()
var config:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/home-island.json"))
var legacy:=false
var landed:=false
var was_here:=false
var land_shape:PackedVector2Array=[]
var vacation_shape:PackedVector2Array=[]
func _init(source:RefCounted)->void:
	_owner=weakref(source)
	legacy=world.catalog.regions.has("homelands")
	if legacy:config=JSON.parse_string(FileAccess.get_file_as_string("res://content/migrations/home-island-v1/home-island.json"))
	if not legacy and not world.catalog.regions.home.get("layout",{}).has("homelands"):return
	if not legacy:
		var layout:Dictionary=world.catalog.regions.home.layout.homelands
		land_shape=PackedVector2Array(world.catalog.regions.home.land_extensions[int(layout.land_index)].map(func(p):return Vector2(p[0],p[1])))
		vacation_shape=PackedVector2Array(preload("res://scripts/resort_system.gd").EXTENSION.map(func(p):return Vector2(p[0],p[1])))
	var life=preload("res://scripts/shared_life.gd").new(world,{"id":"homelands.barbecue","name":LocalText.source("content.homeisland.camp"),"region_id":"homelands" if legacy else "home","position":config.camp,"place_id":"homelands.camp","seat_offsets":world.life.activity_rules.seat_offsets.duplicate(true),"mushrooms":config.mushrooms})
	if not legacy and world.locations.v3():life.fireside.config.seat_offsets=[[-4,-3],[-2,-3],[0,-3],[2,-3],[4,-3]]
	world.barbecues[life.station.id]=life
func contains(at:Vector2)->bool:
	if legacy or at.y<150 or land_shape.is_empty():return false
	return Geometry2D.is_point_in_polygon(at,land_shape)
func here()->bool:return world.actors.human.region_id=="home" and contains(world.point(world.actors.human))
func restore_visited(value:bool=false)->void:
	landed=value or world.memories.records.any(func(entry):return entry.get("kind")=="home_island_arrival" and entry.get("source",{}).get("id")=="first-landing" and entry.get("participants",[])==["human"])
	# Loading an old resident already on this land is a baseline, not a new arrival.
	was_here=here()
func advance(delta:float)->void:
	if delta<=0:return
	var current:bool=here()
	if not landed and current and not was_here:
		landed=true;world.revision+=1
		world.memories.record_event("home_island_arrival","first-landing",["human"],{"region_id":"homelands"})
	was_here=current

# Ownership is derived from coordinates; old construction instances stay untouched.
func territory_at(at:Vector2)->String:
	if not contains(at):return ""
	var nearest:="";var distance:=INF
	for territory in config.get("their_island",{}).get("territories",[]):
		var candidate:float=absf(at.x-float(territory.anchor[0]))
		if candidate<distance:nearest=territory.owner_id;distance=candidate
	return nearest
func territory_sites(owner_id:String)->Array:
	var result:Array=[]
	for object in world.objects.values():
		if object.kind=="construction_site" and object.region_id=="home" and territory_at(world.point(object))==owner_id:result.append(object.id)
	return result
func island_name()->String:
	return LocalText.text("content.homeisland.name")

# Road preference supplies validated waypoints to World's original movement only.
func road_route(start:Vector2,finish:Vector2)->Array[Vector2]:
	var empty:Array[Vector2]=[]
	if legacy or start.distance_to(finish)<8 or not contains(start) or not contains(finish):return empty
	_prepare_road_topology()
	var segments:Array=road_segments
	var nodes:Array[Vector2]=road_nodes.duplicate()
	var fixed_count:int=nodes.size()
	for at in [start,finish]:
		var nearest:=Vector2.ZERO;var distance:=INF
		for segment in segments:
			var p:=Geometry2D.get_closest_point_to_segment(at,segment[0],segment[1])
			if at.distance_to(p)<=12 and at.distance_to(p)<distance and world.segment_clear("home",at,p):nearest=p;distance=at.distance_to(p)
		if distance>12:return empty
		if not nearest in nodes:nodes.append(nearest)
	var start_id:int=nodes.size();nodes.append(start)
	var finish_id:int=nodes.size();nodes.append(finish)
	var graph:=AStar2D.new()
	for i in range(nodes.size()):graph.add_point(i,nodes[i])
	for edge in road_edges:graph.connect_points(edge[0],edge[1])
	# Only the two query projections are new; immutable road edges are cached.
	for i in range(fixed_count,start_id):
		for j in range(i):
			for segment in segments:
				if nodes[i].distance_to(Geometry2D.get_closest_point_to_segment(nodes[i],segment[0],segment[1]))<.01 and nodes[j].distance_to(Geometry2D.get_closest_point_to_segment(nodes[j],segment[0],segment[1]))<.01:
					graph.connect_points(i,j);break
	for end_id in [start_id,finish_id]:
		var nearest_id:=-1;var distance:=INF
		for i in range(start_id):
			if nodes[end_id].distance_to(nodes[i])<distance and world.segment_clear("home",nodes[end_id],nodes[i]):nearest_id=i;distance=nodes[end_id].distance_to(nodes[i])
		if nearest_id<0:return empty
		graph.connect_points(end_id,nearest_id)
	var path:PackedVector2Array=graph.get_point_path(start_id,finish_id)
	var result:Array[Vector2]=[]
	for i in range(1,path.size()):
		# Validate only the chosen route; a blocked road uses World's original fallback.
		if not world.segment_clear("home",path[i-1],path[i]):return empty
		result.append(path[i])
	return result

# Only immutable topology is cached. Every returned edge still checks current World
# geometry; a blocked road falls back to World's original grid search.
var road_stamp:=""
var road_segments:Array=[]
var road_nodes:Array[Vector2]=[]
var road_edges:Array=[]
func _prepare_road_topology()->void:
	var stamp:String=JSON.stringify(config.get("roads",[]))
	if stamp==road_stamp:return
	road_stamp=stamp;road_segments.clear();road_nodes.clear();road_edges.clear()
	for road in config.get("roads",[]):
		for i in range(road.points.size()-1):
			var a:=Vector2(road.points[i][0],road.points[i][1]);var b:=Vector2(road.points[i+1][0],road.points[i+1][1])
			road_segments.append([a,b])
			if a not in road_nodes:road_nodes.append(a)
			if b not in road_nodes:road_nodes.append(b)
	for first in road_segments:
		for second in road_segments:
			var cross:Variant=Geometry2D.segment_intersects_segment(first[0],first[1],second[0],second[1])
			if cross is Vector2 and cross not in road_nodes:road_nodes.append(cross)
	for i in road_nodes.size():
		for j in range(i):
			for segment in road_segments:
				if road_nodes[i].distance_to(Geometry2D.get_closest_point_to_segment(road_nodes[i],segment[0],segment[1]))<.01 and road_nodes[j].distance_to(Geometry2D.get_closest_point_to_segment(road_nodes[j],segment[0],segment[1]))<.01:
					road_edges.append([i,j]);break

extends SceneTree
class ProbeWorld extends "res://scripts/world_state.gd":
	var barriers:Array[Rect2]=[]
	func walkable(_region:String,p:Vector2)->bool:
		return Rect2(1,1,60,60).has_point(p) and not barriers.any(func(b):return b.has_point(p))
	func _terrain_walkable(region:String,p:Vector2)->bool:return walkable(region,p)
var checks:=0
var failed:=false
func check(ok:bool,msg:String)->void:
	checks+=1
	if not ok:failed=true;push_error(msg)
func _initialize()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"))
	var w:=ProbeWorld.new();w.actors.human.position=[10.5,10.5];w.actors.human.facing="down";w.director.set_all_enabled(false)
	var finish:=Vector2(20.5,19.5);var route:Array[Vector2]=w.find_route("human",finish)
	check(route.size()==1 and route.back()==finish,"open diagonal uses one exact straight segment")
	check(w.route_to("human",finish),"World owns actual diagonal movement")
	var switches:=0;var last:String=w.actors.human.facing
	for frame in range(1000):
		w.advance(.02)
		if w.actors.human.facing!=last:switches+=1;last=w.actors.human.facing
		if not w._routes.has("human"):break
	check(w.point(w.actors.human).distance_to(finish)<.0001 and switches<=2,"real advance arrives without axis flicker")
	w._walk_facings.clear();w.actors.human.facing="down"
	var exact_axes:=true
	for frame in range(100):
		var movement:=Vector2(1.01 if frame%2 else .99,1);w.walk_facing("human",movement,.01)
		exact_axes=exact_axes and w.actors.human.facing==w.walking_direction(movement)
	check(exact_axes,"every moving frame uses its exact major axis under the v4 hard rule")
	for frame in range(16):w.walk_facing("human",Vector2(1.01,1),.01)
	check(w.actors.human.facing=="right","new moving axis has no presentation delay")
	w.walk_facing("human",Vector2.LEFT,.001);check(w.actors.human.facing=="left","large turn takes effect immediately")
	w.actors.human.position=[10.5,10.5];w.barriers=[Rect2(11,10,1,1),Rect2(10,11,1,1)];w._grids.clear();w._terrain_solids.clear()
	check(not w.segment_clear("home",Vector2(10.5,10.5),Vector2(11.5,11.5)),"diagonal never clips between blocked corners")
	for barrier in [Rect2(14,5,1,20),Rect2(14,5,.75,20),Rect2(14,5,5,20)]:
		w.barriers=[barrier];w._grids.clear();w._terrain_solids.clear()
		check(not w.segment_clear("home",Vector2(10.5,10.5),Vector2(25.5,15.5)),"line check rejects wall fence and water")
		route=w.find_route("human",Vector2(25.5,15.5));var origin:=w.point(w.actors.human)
		check(not route.is_empty() and route.back()==Vector2(25.5,15.5),"detour retains exact target")
		for at in route:check(w.segment_clear("home",origin,at),"every pulled segment validated through walkable");origin=at
	print("Walk v2: ",checks," checks, failed=",failed);quit(1 if failed else 0)

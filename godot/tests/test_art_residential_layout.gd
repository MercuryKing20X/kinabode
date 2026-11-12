extends SceneTree
const Layout=preload("res://scripts/art_study_layout.gd")
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:
	var config:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/art-studies/scenes.json")).B
	check(config.houses.size()==2,"only two houses in residential study")
	var houses:Array=config.houses;var first:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/art-studies/houses/"+houses[0].source_id+".json"));var second:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/art-studies/houses/"+houses[1].source_id+".json"))
	check(first.roof_profile!=second.roof_profile and first.orientation!=second.orientation,"different actual roof work and facing")
	check(absf(houses[0].position[1]-houses[1].position[1])>=1.5,"front/back setbacks differ")
	var gap:float=(houses[1].position[0]-houses[0].position[0])*32-(first.width*first.art_scale+second.width*second.art_scale)/2
	check(gap>=32,"at least one tile visible gap between artwork bounds")
	check(first.yard.bounds[2]*first.yard.bounds[3]!=second.yard.bounds[2]*second.yard.bounds[3],"yard areas differ")
	check(config.roads.size()>=3 and config.roads[0].points.size()>3,"non-straight street and individual connecting paths")
	var prop:Dictionary=config.props[0];var point:=Layout.point(config,prop)
	check(is_equal_approx(point.x,houses[0].position[0]+prop.offset[0]),"yard props derive from their only house anchor")
	for size in [Vector2(1280,800),Vector2(960,640)]:
		var origin:Vector2=size/2-Vector2(config.camera[0],config.camera[1])*32
		for house in houses:
			var art:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/art-studies/houses/"+house.source_id+".json"))
			var foot:=Vector2(house.position[0],house.position[1])*32
			var box:=Rect2(origin+foot-Vector2(art.anchor[0],art.anchor[1])*art.art_scale,Vector2(art.width,art.height)*art.art_scale)
			check(Rect2(Vector2.ZERO,size).encloses(box),"full house visible "+house.id+" "+str(size))
	var ground:RefCounted=load("res://scripts/polygon_study_ground.gd").new();ground.prepare(config)
	check(ground.path_points(config,config.roads[1].points)[0]==Vector2(houses[0].position[0],houses[0].position[1]),"path starts at shared house anchor")
	print("Residential composition: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)

extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Library=preload("res://scripts/character_library.gd")
const Opening=preload("res://scripts/world_opening.gd")
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	var w:=World.new("res://content/home-v3/world.json");w.library=Library.new();w.library.configure(directory);w.residents.provision(w);w.director.set_all_enabled(false);assert(Opening.apply(w,w.library).ok)
	var at:Array=w.map_anchor("moon.camp");var inland:=Vector2(at[0],at[1])
	check(not w.fishing._ocean("home",inland),"moon grass is land, never ocean")
	check(w.fishing.probe_position("home",inland).is_empty(),"inland camp does not advertise sea fishing")
	check(w.fishing.coast_points.any(func(p):return p.position[0]<0),"moon real coast is included in read-only coast candidates")
	at=w.map_anchor("moon.lookout")
	check(w.moon.contains(Vector2(at[0],at[1])) and w.moon.contains(Vector2(w.map_anchor("moon.reflection")[0],w.map_anchor("moon.reflection")[1])),"tidal ambience includes moon deck and bay, not only grass")
	check(not w.moon.contains(Vector2(w.map_anchor("plaza.center")[0],w.map_anchor("plaza.center")[1])),"tidal layer stays out of main plaza")
	var fish_before:int=w.fishing.fish.size()
	for frame in range(600):w.advance(.1)
	check(w.fishing.fish.size()==fish_before,"coast detection never generates fish")
	print("Moon coast: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)

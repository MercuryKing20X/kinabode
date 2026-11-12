extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Library=preload("res://scripts/character_library.gd")
const Opening=preload("res://scripts/world_opening.gd")
const F=preload("res://tests/cooking_fixture.gd")
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	var w:=World.new("res://content/home-v3/world.json")
	check(w.error.is_empty(),"expanded catalog valid "+w.error)
	if not w.error.is_empty():quit(1);return
	w.library=Library.new();w.library.configure(OS.get_environment("HABITAT_DATA_DIR"));w.residents.provision(w);w.director.set_all_enabled(false);assert(Opening.apply(w,w.library).ok)
	var at:Array=w.map_anchor("moon.bridge.east")
	check(F.job(w,"human",{"intent":"move","x":at[0],"y":at[1]}),"explicit walk to bridge east")
	at=w.map_anchor("moon.bridge.west")
	var start:int=Time.get_ticks_usec()
	var route:Array=w.find_route("human",Vector2(at[0],at[1]))
	check(not route.is_empty(),"bridge connected in authoritative World path grid")
	check(F.job(w,"human",{"intent":"move","x":at[0],"y":at[1]}),"actual bridge crossing")
	at=w.map_anchor("moon.lookout")
	check(F.job(w,"human",{"intent":"move","x":at[0],"y":at[1]}),"actual walk from bridge to crescent platform")
	check(w._grids.home.region.position.x==-190 and w._grids.home.region.size==Vector2i(360,330) and w.catalog.regions.home.layout.mainland_size[0]==160 and w.catalog.regions.home.layout.mainland_size[1]==128,"single grid covers west expansion without shifting mainland")
	var distances:Array=[]
	for pair in [["plaza.center","moon.lookout"],["moon.bridge.east","moon.bridge.west"]]:
		var source:Array=w.map_anchor(pair[0]);at=w.map_anchor(pair[1])
		check(F.job(w,"human",{"intent":"move","x":source[0],"y":source[1]}),"measurement starts at real anchor "+pair[0])
		check(w.command("human",{"intent":"move","x":at[0],"y":at[1]}).ok,"measurement route accepted")
		var seconds:=0.0
		while w._routes.has("human") and seconds<120:w.advance(.05);seconds+=.05
		check(seconds<120 and w.point(w.actors.human).distance_to(Vector2(at[0],at[1]))<.7,"measurement arrives by actual walking")
		distances.append({"from":pair[0],"to":pair[1],"seconds":snappedf(seconds,.05)})
	var file:=FileAccess.open(OS.get_environment("HABITAT_DATA_DIR").path_join("B-distances.json"),FileAccess.WRITE);file.store_string(JSON.stringify(distances,"  "))
	print("Moon map: %s checks, failed=%s; probe_us=%s"%[checks,failed,Time.get_ticks_usec()-start]);quit(1 if failed else 0)

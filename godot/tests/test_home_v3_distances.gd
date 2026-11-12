extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Opening=preload("res://scripts/world_opening.gd")
const F=preload("res://tests/cooking_fixture.gd")
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:
	var directory:String=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	var lib=preload("res://scripts/character_library.gd").new();lib.configure(directory)
	var w=World.new("res://content/home-v3/world.json");w.library=lib;w.residents.provision(w);w.director.set_all_enabled(false);assert(Opening.apply(w,lib).ok)
	var raw:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/home-v3/pack.json"))
	for farm in raw.regions[0].layout.farms:
		var zone:Dictionary=w.catalog.regions.home.zones.filter(func(z):return z.id==farm.zone_id)[0]
		check(not farm.has("rect") and not farm.has("first") and not farm.has("entrance") and w.farms.farms[farm.id].rect==zone.rect,"one zone authority derives farm geometry "+farm.id)
	var destinations:Array=[]
	for farm in w.catalog.regions.home.layout.farms:destinations.append({"id":farm.id,"at":farm.entrance,"limit":null})
	for id in ["dock.south.entry","dock.west.entry","logging.entry"]:destinations.append({"id":id,"at":w.map_anchor(id),"limit":8 if id=="logging.entry" else 10})
	var results:Array=[]
	for destination in destinations:
		var center:Array=w.map_anchor("plaza.center")
		check(F.job(w,"human",{"intent":"move","x":center[0],"y":center[1]}),"explicit player walk back to actual plaza center")
		var at:Array=destination.at;var accepted:Dictionary=w.command("human",{"intent":"move","x":at[0],"y":at[1]});var seconds:=0.0
		while accepted.ok and w._routes.has("human") and seconds<100:w.advance(.05);seconds+=.05
		seconds=snappedf(seconds,.05)
		check(accepted.ok and w.point(w.actors.human).distance_to(Vector2(at[0],at[1]))<.7 and is_finite(seconds) and (destination.limit==null or seconds<=destination.limit),"CENTER walk to "+destination.id+" = "+str(seconds)+" seconds")
		results.append({"target":destination.id,"start":"plaza.center","destination":at,"seconds":seconds,"limit":destination.limit,"speed_pixels_per_second":150,"actual_advance_delta":.05})
	var output:String=OS.get_environment("HABITAT_STAGE2_EVIDENCE")
	if not output.is_empty():
		var f:=FileAccess.open(output.path_join("2F-center-distances.json"),FileAccess.WRITE);f.store_string(JSON.stringify(results,"  "))
	print("Home v3 center distances: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)

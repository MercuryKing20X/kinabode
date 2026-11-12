extends SceneTree
const Places=preload("res://scripts/map_locations.gd")
const World=preload("res://scripts/world_state.gd")
const Save=preload("res://scripts/save_store.gd")
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var world:=World.new();var directory:=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	check(world.error.is_empty(),"legacy world configuration loads")
	var recipes:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/recipes.json"))
	check(world.life.station.position==recipes.station.position,"one authoritative camp and cooking position")
	for entry in Places.section("leisure"):check(world.leisure.sites[entry.id].position==entry.position,"authored facility "+entry.id)
	for entry in Places.section("mushrooms"):check(world.life.patches[entry.id].position==entry.position,"authored forage anchor "+entry.id)
	var legacy:RefCounted=load("res://scripts/farm_system.gd").new(world,"res://content/farms-v1.json")
	check(legacy.bed(legacy.plots.values()[0]).size==Vector2(world.farms.farms["farm.home"].bed_size[0],world.farms.farms["farm.home"].bed_size[1]),"legacy farm fixture without bed_size retains original bed geometry")
	var before:Dictionary=Places.data();var changed:Dictionary=Places.data();changed.camera.initial[0]=-99
	check(Places.data()==before,"content reads are independent copies")
	for key in before.points:check(Places.pair(key).size()==2 and is_finite(Places.point(key).x),"valid map point "+key)
	for farm in world.farms.farms.values():
		var plot:Dictionary=world.farms.farm_plots(farm.id)[0]
		check(world.farms.bed(plot).size==Vector2(farm.bed_size[0],farm.bed_size[1]),"bed uses farm source "+farm.id)
	check(Save.save_world(world,directory),"legacy world saves without migration")
	var restored:=World.new();check(Save.load_world(restored,directory).ok,"schema7 reload remains valid")
	check(restored.life.station.position==world.life.station.position,"reload keeps existing station position")
	for id in world.leisure.sites:
		var a:Dictionary=world.leisure.sites[id];var b:Dictionary=restored.leisure.sites[id]
		check(a.position==b.position and a.invested==b.invested and a.complete==b.complete,"reload keeps facility position and progression "+id)
	var captures:=OS.get_environment("HABITAT_ISLAND_COMPARE")
	if not captures.is_empty():
		var evidence:Dictionary={}
		for id in ["camp","garden","pond"]:
			var a:=Image.load_from_file(captures.path_join("before/"+id+".png"));var b:=Image.load_from_file(captures.path_join("after/"+id+".png"))
			var differing:=0;var world_differing:=0
			# Initial UI weather label was painted before the fixed screenshot seed in both captures.
			# Compare every world pixel, excluding only that bounded non-map text rectangle.
			for y in range(a.get_height()):
				for x in range(a.get_width()):
					if a.get_pixel(x,y)!=b.get_pixel(x,y):
						differing+=1
						if not Rect2i(20,740,250,30).has_point(Vector2i(x,y)):world_differing+=1
			var equal:=a.get_size()==b.get_size() and world_differing==0
			evidence[id]={"size":[a.get_width(),a.get_height()],"world_pixels_identical":equal,"changed_pixels":differing,"world_changed_pixels":world_differing,"excluded_ui_weather_label":[20,740,250,30]};check(equal,"old actual viewport pixel identical "+id)
		var file:=FileAccess.open(captures.path_join("legacy-comparison.json"),FileAccess.WRITE);file.store_string(JSON.stringify(evidence,"  "))
	print("Map coordinate data: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)

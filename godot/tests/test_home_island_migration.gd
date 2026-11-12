extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Library=preload("res://scripts/character_library.gd")
const Opening=preload("res://scripts/world_opening.gd")
const Save=preload("res://scripts/save_store.gd")
const Migration=preload("res://scripts/home_island_migration.gd")
var failed:=false
func check(ok:bool,label:String)->void:
	if not ok:failed=true;push_error(label)
func _initialize()->void:
	var directory:String=OS.get_environment("HABITAT_DATA_DIR")
	var library:=Library.new();library.configure(directory)
	var old:=World.new(Migration.LEGACY);old.library=library;old.residents.provision(old)
	check(old.error.is_empty() and Opening.apply(old,library,"showcase").ok,"frozen original world valid")
	old.director.set_all_enabled(false)
	# Exact user-specified legacy fixture, never a player save.
	old.actors.human.region_id="homelands";old.actors.human.position=[100,28]
	old.actors["companion-2"].region_id="homelands";old.actors["companion-2"].position=[103,28];old.actors["companion-2"].carry={"wood":3}
	old.objects["homelands.house.01"].stage_index=5;old.objects["homelands.house.01"].invested=60
	old.objects["homelands.house.01"]["contributions"]={"human":{"wood":60,"stages":5}}
	old.objects["homelands.house.02"].stage_index=3;old.objects["homelands.house.02"].invested=36;old.objects["homelands.house.02"].delivered={"wood":3}
	old.objects["homelands.house.02"]["contributions"]={"companion-2":{"wood":39,"stages":3}}
	old.objects["homelands.house.03"].stage_index=5;old.objects["homelands.house.03"].invested=0;old.objects["homelands.house.03"]["host_completed"]=true
	check(old.command("human",{"intent":"move","x":110,"y":40}).ok,"fixture walks to old exact camp before real lighting")
	for tick in range(1000):
		old.advance(.1)
		if not old._routes.has("human"):break
	var wood_before:int=old.storage.count("wood")
	check(old.barbecues["homelands.barbecue"].fireside.light_host().ok and old.storage.count("wood")==wood_before-2,"legacy active fire actually paid2 original stock wood")
	check(old.barbecues["homelands.barbecue"].fireside.burning(),"legacy camp burning original fuel timer")
	old.actors.human.position=[100,28]
	old.barbecues["homelands.barbecue"].patches["homelands.mushrooms.1"].amount=0;old.barbecues["homelands.barbecue"].patches["homelands.mushrooms.1"].ready_at=Time.get_unix_time_from_system()+1000
	old.cat.discover()
	check(Save.save_world(old,directory),"legacy exact schema7 fixture saves")
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("island-v2.json")))
	check(Save._valid(old,data),"frozen original validator accepts fixture before migration")
	var world:=World.new("res://content/home-v3/world.json");world.library=library;world.residents.provision(world)
	var original:Dictionary=data.duplicate(true)
	check(Migration.migrate(world,data),"old map translates only after original validation")
	check(data.actors.human.region_id=="home" and data.actors.human.position[0]==81 and data.actors.human.position[1]==178,"actor exact offset")
	var expected_cat:Dictionary=original.cat.duplicate(true)
	if expected_cat.get("region_id")=="homelands":Migration.shift(expected_cat)
	check(data.actors["companion-2"].carry==original.actors["companion-2"].carry and data.storage==original.storage and data.cat==expected_cat,"carry storage discovered memories unchanged and optional cat exact offset")
	var missing_cat:Dictionary=original.duplicate(true);missing_cat.cat.erase("region_id");missing_cat.cat.erase("position")
	var three_keys:Dictionary=missing_cat.cat.duplicate(true)
	check(Migration.migrate(world,missing_cat) and missing_cat.cat==three_keys,"actual old three-key cat keeps facts without inventing missing location")
	world.cat.restore(missing_cat.cat)
	check(world.cat.position==world.point(world.actors.human)+Vector2(2,0),"missing old location uses original load fallback only")
	for id in original.objects:
		var expected:Dictionary=original.objects[id].duplicate(true)
		if expected.region_id=="homelands":Migration.shift(expected)
		check(data.objects[id]==expected,"every old object exact position-only migration "+id)
	var old_camp:Dictionary=original.extra_barbecues["homelands.barbecue"].duplicate(true)
	Migration.shift(old_camp.station)
	for patch in old_camp.patches.values():Migration.shift(patch)
	check(data.extra_barbecues["homelands.barbecue"]==old_camp,"station and harvested mushroom state preserved position-only")
	var current:Dictionary=data.duplicate(true)
	check(preload("res://scripts/resort_revision_migration.gd").migrate(world,current) and Save._valid(world,current),"translated schema7 plus authorized vacation migration validates current catalog without relaxed receipts")
	var marker:Dictionary=data.duplicate(true);marker.home_map_version=true
	check(not Migration.migrate(world,marker),"boolean map version rejected")
	marker.home_map_version="2";check(not Migration.migrate(world,marker),"string map version rejected")
	marker.home_map_version=2.0;check(Migration.migrate(world,marker),"JSON numeric float2 equivalent accepted")
	var again:Dictionary=data.duplicate(true);check(Migration.migrate(world,data) and data==again,"idempotent translation")
	var bad:Dictionary=original.duplicate(true);bad.objects["homelands.house.01"].position[0]+=1
	check(not Migration.migrate(world,bad),"invalid old location rejected before translation")
	bad=original.duplicate(true);bad.cat.position=[40000,40000]
	check(not Migration.migrate(world,bad),"out-of-terrain old cat position rejected before shift")
	bad=original.duplicate(true);bad.cat.erase("position")
	check(not Migration.migrate(world,bad),"unpaired optional cat coordinates rejected")
	bad=original.duplicate(true);bad.actors["companion-2"].carry={"wood":21}
	check(not Migration.migrate(world,bad),"carry20 frozen bottom line rejected")
	check(Save.load_world(world,directory).ok and world.actors.human.region_id=="home" and world.actors.human.position[1]==178,"actual load automatically migrates no user operation")
	check(world.cat.region=="home" and world.cat.position==Vector2(expected_cat.position[0],expected_cat.position[1]),"automatic load preserves independently saved cat location after offset")
	check(Save.save_world(world,directory),"normal save retains optional map version")
	var reloaded:=World.new("res://content/home-v3/world.json");reloaded.library=library;reloaded.residents.provision(reloaded)
	check(Save.load_world(reloaded,directory).ok,"new map save reloads")
	check(reloaded.cat.position==world.cat.position and reloaded.cat.region==world.cat.region,"new optional cat location survives save/reload independently of human")
	var old_three:Dictionary=original.duplicate(true);old_three.cat.erase("region_id");old_three.cat.erase("position")
	var three_dir:String=directory.path_join("actual-old-three-keys");DirAccess.make_dir_recursive_absolute(three_dir)
	var three_file:=FileAccess.open(three_dir.path_join("island-v2.json"),FileAccess.WRITE);three_file.store_string(JSON.stringify(old_three));three_file.close()
	var three_world:=World.new("res://content/home-v3/world.json");three_world.library=library;three_world.residents.provision(three_world)
	check(Save.load_world(three_world,three_dir).ok and three_world.cat.position==three_world.point(three_world.actors.human)+Vector2(2,0) and three_world.cat.discovered,"actual old three-key file loads by original fallback, keeps discovery but cannot reconstruct missing independent position")
	var a:Dictionary=world.catalog.regions.home.duplicate(true);var b:Dictionary=world.catalog.regions.moon.duplicate(true)
	check(not world.catalog.land_overlaps(a,b),"empty bounding sea overlap is not occupied land")
	b.origin=a.origin.duplicate();b.land=a.land.duplicate(true)
	check(world.catalog.land_overlaps(a,b),"actual terrain overlap remains rejected")
	var collision:Dictionary={"id":"collision_probe","name":"collision_probe","origin":a.origin.duplicate(),"local_origin":a.local_origin.duplicate(),"size":a.size.duplicate(),"land":a.land.duplicate(true),"zones":[],"objects":[]}
	var issues:Array=world.catalog.validate_pack({"schema_version":1,"id":"collision_probe","regions":[collision]})
	check(issues.has(preload("res://scripts/localization.gd").text("system.world_catalog.region_footprints_overlap")),"catalog import validation itself rejects physically overlapping land")
	print("home island strict migration failed=",failed);quit(1 if failed else 0)

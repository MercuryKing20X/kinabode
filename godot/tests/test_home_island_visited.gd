extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Save=preload("res://scripts/save_store.gd")
var failed:=false
func check(value:bool,label:String)->void:
	if not value:failed=true;push_error(label)
func fresh()->RefCounted:
	var world:=World.new("res://content/home-v3/world.json");world.residents.provision(world);world.director.set_all_enabled(false);return world
func count(world:RefCounted)->int:return world.memories.records.filter(func(e):return e.kind=="home_island_arrival").size()
func _initialize()->void:
	var w:=fresh()
	# Explicit event fixtures, not player acceptance evidence; time advances normally.
	w.actors.human.position=[81,178];w.advance(.1)
	check(w.home_island.landed and count(w)==1,"one real new observation records first landing")
	for i in range(20):w.advance(.1)
	check(count(w)==1,"no per-frame duplicate or repeated retained-record scan")
	w.memories.records.clear()
	w.advance(1)
	check(count(w)==0 and w.home_island.landed,"evicted diary first landing never replays")
	var path:String=OS.get_environment("HABITAT_DATA_DIR").path_join("visited")
	check(Save.save_world(w,path),"save visited with evicted diary")
	var loaded:=fresh();check(Save.load_world(loaded,path).ok,"load visited optional flag")
	loaded.advance(1);check(loaded.home_island.landed and count(loaded)==0,"reloaded visited suppresses evicted record replay")
	var old:=fresh();old.actors.human.position=[81,178];old.home_island.restore_visited()
	old.advance(1);check(count(old)==0 and not old.home_island.landed,"old present location without proof is baseline, no history backfill")
	old.actors.human.position=[81,108];old.advance(.1);old.actors.human.position=[81,178];old.advance(.1)
	check(old.home_island.landed and count(old)==1,"only a subsequent genuinely observed arrival creates new proof")
	old.home_island.landed=false;old.home_island.restore_visited()
	check(old.home_island.landed,"retained canonical old first landing supplies baseline flag without new memory")
	print("home island visited failed=",failed);quit(1 if failed else 0)

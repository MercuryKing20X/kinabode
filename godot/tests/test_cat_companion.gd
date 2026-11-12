extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
const CatUI=preload("res://scripts/cat_companion_ui.gd")
var failures:=0
func check(value:bool,label:String)->void:
	if not value:failures+=1;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var w:=F.fresh();w.opening_id="showcase";w.cat.initialize()
	check(w.cat.discovered,"showcase pet available")
	var before:Dictionary=w.storage.saved().duplicate(true)
	var carry:Dictionary=w.actors.human.carry.duplicate(true)
	w.cat.position=w.point(w.actors.human)+Vector2(1,0)
	check(w.cat.interact("human","hold"),"near idle host may hold")
	check(w.cat.carrier=="human","exact holder")
	check(w.cat.interact("human","release"),"holder releases")
	check(w.cat.interact("human","pet"),"pet exact cat")
	check(w.memories.records.any(func(e):return e.kind=="cat_contact" and e.facts.action=="pet"),"true first pet canonical diary")
	var n:int=w.memories.records.size();w.cat.interact("human","pet")
	check(w.memories.records.size()==n,"first contact not replayed")
	check(w.cat.saved().memories.has("pet:human"),"actual first contact retained")
	check(w.cat.valid(w.cat.saved()) and not w.cat.valid({"version":1,"discovered":true,"memories":{"fake":123}}),"strict optional state")
	check(w.storage.saved()==before and w.actors.human.carry==carry,"pet consumes no resources")
	var saved:Dictionary=w.cat.saved();w.cat.restore(saved)
	check(w.cat.carrier.is_empty() and w.cat.route.is_empty(),"reload never resumes held pose or route")
	w.cat.position=w.point(w.actors.human)+Vector2(50,0)
	check(not w.cat.interact("human","hold"),"no remote pickup")
	check(not w.actors.has("__pet_path_query__"),"no pet query actor leaks into residents")
	var formal:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");formal.opening_id="standard";formal.cat.initialize()
	check(formal.cat.discovered and formal.cat.region=="home","formal pet available on main island from opening")
	var fish_world:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	fish_world.residents.provision(fish_world);fish_world.library=preload("res://scripts/character_library.gd").new();fish_world.library.configure(OS.get_environment("HABITAT_DATA_DIR").path_join("fish-cat"))
	check(preload("res://scripts/world_opening.gd").apply(fish_world,fish_world.library,"showcase").ok,"fish-cat showcase")
	fish_world.cat.initialize();fish_world.director.set_all_enabled(true)
	var Fish=preload("res://tests/fishing_fixture.gd")
	var BBQ=preload("res://tests/barbecue_fixture.gd")
	check(Fish.coast(fish_world,"human"),"real route to fish coast")
	var caught:Dictionary=Fish.catch_one(fish_world,"human")
	check(not caught.is_empty() and BBQ.approach(fish_world),"real fish and camp arrival")
	if not caught.is_empty():
		var result:Dictionary=fish_world.life.fireside.direct_grill(caught.id)
		check(result.ok,"real fish meal committed "+str(result))
		if not result.ok:quit(1);return
		var amounts:Dictionary=fish_world.life.fireside.state.current.duplicate(true)
		for tick in range(1600):
			fish_world.advance(.1)
			if fish_world.cat.fish_rub_serial>0:break
		check(fish_world.cat.fish_rub_serial==1,"cat reaches actual fish fire and emits one rub/meow event")
		check(fish_world.life.fireside.state.current.total==amounts.total,"cat never changes real fish portions")
	fish_world=null
	w=null;formal=null
	print("cat companion: failures=",failures)
	quit(1 if failures else 0)

extends SceneTree
const Fish=preload("res://tests/fishing_fixture.gd")
const BBQ=preload("res://tests/barbecue_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
const World=preload("res://scripts/world_state.gd")
var failed:=false
var count:=0
func check(value:bool,label:String)->void:
	count+=1
	if not value:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func catch_stored(w:RefCounted)->Dictionary:
	var existing:Array=w.fishing.fish.keys()
	if not w.command("human",{"intent":"fish"}).ok:return {}
	for i in range(1200):
		w.advance(.1)
		if not w.work.jobs.has("human"):
			for id in w.fishing.fish:
				if id not in existing:return w.fishing.fish[id].duplicate(true)
			break
	return {}
func run()->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR")
	assert(dir.contains("youqi-test-"))
	var w:=World.new("res://content/home-v3/world.json");w.residents.provision(w);w.library=preload("res://scripts/character_library.gd").new();w.library.configure(dir);assert(preload("res://scripts/world_opening.gd").apply(w,w.library,"showcase").ok);w.hunger.start();w.director.set_all_enabled(false)
	check(Fish.coast(w,"human"),"real route to shore")
	var fish:Dictionary=catch_stored(w)
	check(not fish.is_empty(),"real unique catch")
	if fish.is_empty():quit(1);return
	check(fish.location=="storage" and w.fishing.held("human").is_empty(),"human catch stored without held fish")
	check(w.work.visual_events.any(func(e):return e.kind=="fish_caught_shadow" and e.get("fish",{}).get("id")==fish.id),"caught shadow comes from committed exact fish")
	var journal:Dictionary=w.journal.saved().duplicate(true)
	check(w.journal.summary("human").discovered>0,"stored first catch is actually recorded in journal")
	var pen_id:String=str(w.fishing.pens.keys()[0])
	check(w.fishing.host_pending_action(fish.id,"stock_fish",pen_id).ok and w.fishing.fish[fish.id].location==pen_id,"exact caught fish stored in existing pen")
	check(BBQ.approach(w),"real route to camp")
	var f:RefCounted=w.life.fireside;var stock:int=int(f.available().get("wood",0))
	var result:Dictionary=f.direct_grill(fish.id)
	if not result.get("ok",false):print("direct grill rejected: ",result)
	check(result.get("ok",false) and int(f.available().get("wood",0))==stock-2,"cold fire consumes two real wood")
	if not result.get("ok",false):quit(1);return
	check(not w.fishing.fish.has(fish.id) and f.state.current.fish.id==fish.id and f.state.current.total==4,"unique fish transferred once into four meals")
	check(w.journal.saved()==journal,"discovery survives grilling")
	check(Save.save_world(w,dir.path_join("direct")),"direct fish saves")
	var restored:=World.new("res://content/home-v3/world.json");var loaded:Dictionary=Save.load_world(restored,dir.path_join("direct"));check(loaded.get("ok",false),"direct fish loads "+str(loaded))
	if not loaded.get("ok",false):quit(1);return
	check(restored.life.fireside.state.current.get("fish",{}).get("id")==fish.id and not restored.fishing.fish.has(fish.id),"reload keeps exact fire fish without duplicate")
	for frame in range(960):w.advance(.1)
	check(f.state.current.wasted==4 and f.state.current.eaten==0,"unclaimed cooked fish expires as waste")
	check(Fish.coast(w,"human"),"return to coast")
	var next:Dictionary=catch_stored(w)
	check(not next.is_empty() and BBQ.approach(w),"second real fish and route")
	# The real second coast trip may outlast the first fire. Establish the
	# stated burning-fire precondition with the original paid host action.
	check(f.burning() or f.light_host().get("ok",false),"host establishes a real burning fire for the second grill")
	stock=int(f.available().get("wood",0));result=f.direct_grill(next.id)
	check(result.get("ok",false) and int(f.available().get("wood",0))==stock-1,"burning fire consumes one wood")
	w.director.routines.codex.set_enabled(true)
	check(f.invite_direct(["codex"]).ok,"host explicitly invites companion")
	for frame in range(900):
		w.advance(.1)
		if f.state.current.eaters.has("codex"):break
	if not f.state.current.eaters.has("codex"):print("invite diagnostic: ",f.state," jobs=",f.jobs," actor=",w.actors.codex)
	check(f.state.current.eaters.has("codex") and "human" not in f.state.current.eaters,"only invited companion actually eats")
	print("Direct grill: ",count," checks failed=",failed,"; engine fixture, not player input")
	quit(1 if failed else 0)

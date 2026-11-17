extends SceneTree
## The 2026-11-06 vacation decision retires southern construction proposals.
## Engine rejection must preserve every physical item and retained memory.
const World=preload("res://scripts/world_state.gd")
const Library=preload("res://scripts/character_library.gd")
var failed:=false
var checks:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func facts(w:RefCounted)->Dictionary:
	var carry:Dictionary={}
	for id in w.actors:carry[id]=w.actors[id].carry.duplicate(true)
	return {"storage":w.storage.saved(),"carry":carry,"drops":w.drops.duplicate(true),"objects":w.objects.keys(),"sites":w.leisure.sites.keys(),"memories":w.memories.saved()}
func verify(model:bool)->void:
	var w:=World.new("res://content/home-v3/world.json");w.residents.provision(w)
	w.library=Library.new();w.library.configure(OS.get_environment("HABITAT_DATA_DIR").path_join("works"))
	check(preload("res://scripts/world_opening.gd").apply(w,w.library,"showcase").ok,"real current opening")
	w.director.set_all_enabled(false)
	check(w.resort.config.villas.size()==1 and w.objects.keys().filter(func(id):return str(id).begins_with("resort.villa.")).size()==1,"DIRECTION Flower Isle: exactly one real preset greenhouse")
	check(w.resort.activities.values().filter(func(a):return a.kind=="pool").size()==0,"DIRECTION Flower Isle: no retired pool")
	check(w.objects.keys().filter(func(id):return str(id).begins_with("homelands.house.") or str(id).begins_with("homelands.free.")).is_empty(),"no retired construction sites")
	check(w.farms.farms.keys().filter(func(id):return str(id).begins_with("farm.theirs") and w.farms.ready(id)).is_empty(),"no productive south farm")
	var before:Dictionary=facts(w)
	for id in ["codex","companion-2","npc.mira","npc.nora"]:
		w.director.set_held(id,model)
		for change in [{},{"template_id":"missing-template"},{"x":129.0},{"name":"x".repeat(41)},{"reason":"Imaginary meal"}]:
			var args:Dictionary={"template_id":"outdoor-chair","x":33.5,"y":226.5,"name":"Old chair","reason":"Host-requested test"};args.merge(change,true)
			var result:Dictionary=w.command(id,dict_intent(args)) if model else w.their_island.propose(id,args,true)
			check(not result.ok and result.get("error")=="vacation_activity_only","retired construction rejected for exact actor "+id)
			check(w.their_island.pending.is_empty() and w.their_island.grants.is_empty() and w.their_island.running.is_empty(),"rejection creates no card grant or job")
			check(facts(w)==before and w.work.jobs.is_empty(),"rejection preserves resources world objects and genuine history")
		check(not w.their_island.decide(id,"stale-construction-card","accept").ok,"stale host acceptance cannot restore retired construction")
		w.director.set_held(id,false)
	check(not w.their_island.propose("human",{}).ok,"human cannot manufacture a proposal")
	w.advance(1)
	check(facts(w)==before and w.work.jobs.is_empty(),"idle tick does not construct or invent completion memory")
func dict_intent(args:Dictionary)->Dictionary:
	var request:Dictionary=args.duplicate();request.intent="island_propose";return request
func run()->void:
	verify(false)
	print("Vacation construction rejection ",checks," failed=",failed);quit(1 if failed else 0)

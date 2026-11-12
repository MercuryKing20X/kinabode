# DIRECTION 2026-11-11: 12 existing + 11 new species; only content-derived total changes.
extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
const Fish=preload("res://tests/fishing_fixture.gd")
const BBQ=preload("res://tests/barbecue_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
var checks:=0
var failed:=false
var directory: String
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failed=true;push_error(label)
func load_copy(world: RefCounted,name: String) -> RefCounted:
	check(Save.save_world(world,directory.path_join(name)),"save "+name)
	var next:=F.fresh();var result: Dictionary=Save.load_world(next,directory.path_join(name));check(result.ok,"load "+name+str(result));next.director.set_all_enabled(false);return next
func run() -> void:
	directory=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	var world:=F.fresh();world.fishing.rng.seed=101
	check(world.error.is_empty(),"journal content and real catalogs valid "+world.error)
	if not world.error.is_empty():quit(1);return
	check(world.journal.entries.size()==368 and world.journal.summary("human").discovered==0,"data driven twenty-three by four by four, no free discoveries")
	var empty: Dictionary=world.command("human",{"intent":"journal_read"})
	check(empty.ok and empty.entries.size()==16 and empty.total==368 and empty.entries.all(func(entry):return not entry.caught and entry.first_catch.is_empty()),"on demand bounded unread catalog states")
	check(Fish.coast(world,"human"),"real coastal travel")
	check(world.command("human",{"intent":"fish"}).ok,"start real fishing")
	world.advance(3)
	var accepted: Dictionary=world.work.jobs.human.duplicate(true);var actor: Dictionary=world.actors.human.duplicate(true)
	check(world.command("human",{"intent":"journal_read","status":"caught"}).total==0 and world.work.jobs.human==accepted and world.actors.human==actor,"read during fishing never moves or interrupts accepted work")
	world=load_copy(world,"before-catch")
	check(world.work.jobs.is_empty() and world.journal.summary("human").discovered==0,"reload before actual catch starts no work and invents no discovery")
	world.command("human",{"intent":"stop"});world.advance(20)
	check(world.journal.summary("human").discovered==0,"cancel before actual catch never adds discovery")
	var stock: int=world.fishing.waters[world.fishing.shore("human").water_id].available
	var fish: Dictionary=Fish.catch_one(world,"human")
	check(not fish.is_empty(),"actual fish committed")
	if fish.is_empty():quit(1);return
	var key: String=world.journal.key(fish.species_id,fish.color_id,fish.size_id)
	var first: Dictionary=world.journal.discoveries.human[key].duplicate(true)
	check(world.journal.summary("human").discovered==1 and first.fish_id==fish.id and first.caught_at==fish.caught_at and first.scale==fish.scale,"first discovery is actual owned instance and capture time")
	check(world.fishing.waters[fish.source_id].available==stock-1 and world.fishing.fish.size()==1,"journal creates no resources and catch debits once")
	check(world.journal.summary("codex").discovered==0 and world.journal.summary("companion-2").discovered==0,"others never inherit catch or nearby presence")
	check(not world.journal.record_catch(fish.id) and world.journal.discoveries.human[key]==first,"replaying catch after its job ended cannot mutate journal")
	var page: Dictionary=world.journal.query("human",{"limit":7})
	var seen: Dictionary={};var next: Dictionary=page
	while true:
		for entry in next.entries:seen[entry.id]=true
		if next.next_offset<0:break
		next=world.journal.query("human",{"limit":7,"offset":next.next_offset,"revision":page.revision})
		if not next.ok:check(false,"stable pagination");break
	check(seen.size()==368,"bounded pagination covers whole catalog without drift")
	check(world.journal.query("human",{"offset":7,"limit":7}).get("error")=="stale_journal","subsequent pages require exact revision")
	var page_revision: String=page.revision
	check(Fish.walk(world,"human",[world.actors.human.position[0]+.1,world.actors.human.position[1]]),"real movement between journal pages")
	world.advance(1)
	check(world.journal.query("human",{"limit":7,"offset":7,"revision":page_revision}).ok,"world time and routes do not invalidate independent journal pages")
	var returned: Dictionary=world.journal.query("human",{"status":"caught"});returned.entries[0].first_catch.scale=99;returned.entries[0].caught=false
	check(world.journal.discoveries.human[key]==first,"returned pages are deep copies")
	check(world.command("human",{"intent":"stock_fish","fish_id":fish.id,"pen_id":"home.fishery.east"}).ok,"stock original fish")
	check(world.journal.discoveries.human[key]==first,"stocking does not erase or duplicate discovery")
	world=load_copy(world,"stocked")
	check(world.journal.query("human",{"limit":7,"offset":7,"revision":page_revision}).ok,"JSON numeric round trip preserves independent revision")
	check(world.command("human",{"intent":"release_fish","fish_id":fish.id}).ok and not world.fishing.fish.has(fish.id),"release actual original fish")
	check(world.memories._canonical(world.journal.discoveries.human[key])==world.memories._canonical(first),"released fish remains discovered")
	world=load_copy(world,"released")
	var initial: Dictionary=world.journal.discoveries.human.duplicate(true)
	# Genuine repeated catches overflow the old bounded32 memories, not this discovery set.
	for i in range(36):
		if not Fish.coast(world,"human"):check(false,"repeat real coast");break
		var caught: Dictionary=Fish.catch_one(world,"human")
		if caught.is_empty():world.advance(301);caught=Fish.catch_one(world,"human")
		if caught.is_empty():check(false,"repeat actual catch");break
		check(world.command("human",{"intent":"release_fish","fish_id":caught.id}).ok,"release exact repeated fish")
	check(world.fishing.memories.size()==32 and not world.fishing.memories.any(func(event):return event.id==first.fish_id),"old catch sources really rolled off bounded memories")
	check(world.journal.discoveries.human[key]==initial[key] and world.journal.summary("human").discovered<=37,"first facts remain after repeats and source rollover")
	check(world.journal.query("human",{"limit":7,"offset":7,"revision":page_revision}).get("error")=="stale_journal","new discovery invalidates same resident pagination")
	var stable: String=world.journal.revision("human")
	world.advance(301)
	check(Fish.coast(world,"codex") and not Fish.catch_one(world,"codex").is_empty(),"independent partner catches own real fish")
	check(world.journal.summary("codex").discovered==1 and world.journal.revision("human")==stable,"other resident discovery does not invalidate or credit host journal")
	var ledger: Dictionary=world.journal.saved();world=load_copy(world,"rollover")
	check(world.memories._canonical(world.journal.saved())==world.memories._canonical(ledger),"complete journal survives reload independent of physical fish and source32")
	var invalid_args: Array=[{"actor_id":"codex"},{"species_id":"missing"},{"status":"seen"},{"limit":true},{"offset":.5},{"limit":33},{"revision":"bad"},{"size_id":false}]
	for args in invalid_args:check(not world.journal.query("human",args).ok,"reject bad journal query "+str(args))
	var malformed: Dictionary=world.journal.saved();malformed.discoveries.human[key].scale=99
	check(not world.journal.valid_saved(malformed,world.actors),"invalid discovery size rejected")
	malformed=world.journal.saved();malformed.discoveries["fake"]=malformed.discoveries.human.duplicate(true)
	check(not world.journal.valid_saved(malformed,world.actors),"unknown saved resident rejected")
	old_save(world);cook_preserves()
	print("Fish journal: %s checks, %s"%[checks,"FAIL" if failed else "PASS"]);quit(1 if failed else 0)
func old_save(world: RefCounted) -> void:
	check(Save.save_world(world,directory.path_join("old")),"old fixture preserves actual fish and memories")
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("old/island-v2.json")));data.erase("journal")
	Fish.write_json(directory.path_join("old/island-v2.json"),data)
	var loaded:=F.fresh();check(Save.load_world(loaded,directory.path_join("old")).ok,"schema7 without optional journal loads")
	check(loaded.journal.discoveries.is_empty() and loaded.fishing.fish.size()==world.fishing.fish.size() and loaded.fishing.memories.size()==32,"legacy fish and memories cannot fabricate retroactive discoveries")
	data["journal"]={"version":1,"discoveries":{"human":{"fake":{"scale":1}}}}
	Fish.write_json(directory.path_join("invalid/island-v2.json"),data)
	var rejected: Dictionary=Save.load_world(F.fresh(),directory.path_join("invalid"))
	check(not rejected.ok and FileAccess.file_exists(rejected.get("backup","")),"invalid optional journal keeps recoverable save copy")
func cook_preserves() -> void:
	var world:=F.fresh();world.fishing.rng.seed=101
	check(F.mushroom(world) and BBQ.light(world) and Fish.coast(world,"human"),"real mushroom fuel and own fish meal sources")
	var fish: Dictionary=Fish.catch_one(world,"human")
	check(not fish.is_empty(),"real own catch before cooking")
	if fish.is_empty():return
	var discovery: Dictionary=world.journal.saved()
	check(F.serve(world,"grilled-fish",fish.id) and not world.fishing.fish.has(fish.id),"M1 cooking consumes unique fish")
	check(world.journal.saved()==discovery and world.journal.summary("codex").discovered==0,"cooked fish discovery persists for original catcher only")
	load_copy(world,"cooked")

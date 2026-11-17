extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Library=preload("res://scripts/character_library.gd")
const Save=preload("res://scripts/save_store.gd")
const Opening=preload("res://scripts/world_opening.gd")
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	var library:=Library.new();library.configure(directory)
	var world:=World.new("res://content/home-v3/world.json")
	check(world.error.is_empty(),"new profile constructs: "+world.error)
	if not world.error.is_empty():quit(1);return
	world.library=library;world.residents.provision(world)
	var result:=Opening.apply(world,library);check(result.ok and result.applied,"explicit showcase applies once")
	check(not Opening.apply(world,library).applied,"opening cannot duplicate stock/furniture")
	world.resort.furnish() # Complete the normal post-library preset initialization.
	var houses:Array=world.objects.values().filter(func(o):return o.kind=="construction_site" and o.stage_index==5)
	# DIRECTION 2026-11-11：“五座别墅只留一座”。Five main homes plus the single greenhouse.
	check(houses.size()==6 and world.interior.rooms().size()==6,"five main homes plus one greenhouse/room")
	check(houses.all(func(h):return h.invested==0 and h.delivered.is_empty() and h.get("contributions",{}).is_empty()),"no invented building investment or contributors")
	check(world.interior.furniture.size()==20 and world.interior.furniture.values().all(func(f):return f.invested==0),"fifteen main-home furnishings plus five greenhouse presets, all with zero invented investment")
	check(world.leisure.sites.size()==world.catalog.regions.home.layout.facilities.size() and world.leisure.sites.values().all(func(f):return f.complete and f.invested==0),"initial facilities include second chess table, no investment")
	check(world.memories.records.is_empty() and world.projects.memories.is_empty() and world.interior.memories.is_empty(),"no memories from initial state")
	check(world.relationships.states.is_empty() and world.wishes.states.is_empty(),"no relationship or wish history")
	check(world.homestead.completed() and world.homestead.site.completion.is_empty(),"preset flowerbed no historical completion")
	check(world.days.day()==1 and world.journal.saved().get("discoveries",{}).is_empty(),"day one and empty discovery history")
	check(world.work.jobs.is_empty() and world.work.claims.is_empty() and world._routes.is_empty(),"no work/claims/routes invented")
	check({"id":"storage","items":world.storage._items,"capacity":9007199254740991,"kind":"storage","region_id":"home","position":world.actors.human.position}.items.wood==24,"actual opening stock in chest")
	check(Save.save_world(world,directory),"showcase saves schema7")
	var restored:=World.new("res://content/home-v3/world.json");restored.library=library
	var loaded:=Save.load_world(restored,directory);check(loaded.ok and loaded.loaded,"preset save reloads: "+str(loaded))
	check(restored.work.jobs.is_empty() and restored.memories.records.is_empty(),"reload does not generate work/history")
	var legacy:=World.new();var rejected:=Save.load_world(legacy,directory)
	check(not rejected.ok and rejected.error=="world_template_mismatch" and not rejected.safe_to_save and FileAccess.file_exists(rejected.backup),"different template refused with preserved copy")
	var identity:=Save.read_identity(directory)
	check(identity.has("human") and not identity.human.has("carry") and not identity.human.has("position"),"reset extracts only identity")
	check(Save.archive_progress(directory) and not FileAccess.file_exists(directory.path_join("island-v2.json")),"explicit reset archives progress")
	var fresh:=World.new("res://content/home-v3/world.json");fresh.actors.human.name="暂名";Save.apply_identity(fresh,identity)
	check(fresh.actors.human.name==world.actors.human.name and fresh.actors.human.carry.is_empty(),"identity preserved without old items")
	print("Showcase opening: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)

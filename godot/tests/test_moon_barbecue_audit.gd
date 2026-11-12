# DIRECTION 2026-11-07: 烤蘑菇永久无限供应，不扣任何食材；其它食材守恒断言保留。
extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Library=preload("res://scripts/character_library.gd")
const Opening=preload("res://scripts/world_opening.gd")
const Save=preload("res://scripts/save_store.gd")
const F=preload("res://tests/cooking_fixture.gd")
const BBQ=preload("res://tests/barbecue_fixture.gd")
var checks:=0
var failed:=false
var library:RefCounted
var directory:String
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func fresh()->RefCounted:
	var w:=World.new("res://content/home-v3/world.json");w.library=library;w.residents.provision(w);w.director.set_all_enabled(false)
	assert(Opening.apply(w,library).ok);return w
func total(w:RefCounted,item:String)->int:
	var value:int=F.amount(w,item)+int(w.life.station.supplies.get(item,0))
	return value+int(w.life.station.fuel_used) if item=="wood" else value+int(w.life.station.portions)+int(w.life.station.meals_eaten)
func phase(w:RefCounted,wanted:String)->bool:
	for tick in range(9000):
		w.advance(.1)
		if w.shared_activity.session.get("phase")==wanted:return true
		if w.shared_activity.session.get("status")=="paused":return false
	return false
func _initialize()->void:
	directory=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	library=Library.new();library.configure(directory)
	var w:=fresh()
	for patch in w.life.patches.values():
		var before:int=F.amount(w,"mushroom")
		check(F.job(w,"human",{"intent":"forage","target_id":patch.id}),"real reachable mushroom collection "+patch.id)
		check(F.amount(w,"mushroom")==before+4 and patch.amount==0 and patch.ready_at>Time.get_unix_time_from_system(),"four real mushrooms stored; regeneration scheduled")
		# Boundary injection only changes a disposable clock deadline, never inventory.
		patch.ready_at=Time.get_unix_time_from_system()-.1;w.advance(.1)
		check(patch.amount==4,"elapsed regeneration restores patch, not inventory")
	var tree:Dictionary=w.objects.values().filter(func(o):return o.kind=="tree" and o.zone_id=="home.forest")[0]
	var wood:int=F.amount(w,"wood")
	check(F.job(w,"human",{"intent":"chop","target_id":tree.id}) and F.amount(w,"wood")==wood+3,"solo real chopping and storage")
	for station_id in ["home.barbecue","moon.barbecue"]:
		var life:RefCounted=w.barbecues[station_id]
		var wood_before:int=F.amount(w,"wood");var mushroom_before:int=F.amount(w,"mushroom")
		check(BBQ.meal(w,"single:mushroom",["human","codex","companion-2","npc.mira","npc.nora"],station_id),"actual five-person meal on chosen fire "+station_id)
		check(F.amount(w,"wood")==wood_before-2 and F.amount(w,"mushroom")==mushroom_before,"exact selected camp source material debit "+station_id)
		check(life.fireside.state.current.eaten==5 and life.fireside.state.current.wasted==0 and life.station.portions==0,"all actual food consumed once without leftovers "+station_id)
		var memories:Array=w.memories.records.filter(func(m):return m.kind=="shared_barbecue" and m.facts.station_id==station_id)
		check(memories.size()==1 and memories[0].participants.size()==5,"one canonical fact credits actual five diners "+station_id)
		var count:int=w.memories.records.size();for tick in range(50):w.advance(.1)
		w.memories.sync();check(w.memories.records.size()==count,"completion never replays "+station_id)
		check(Save.save_world(w,directory.path_join(station_id)),"save actual camp completion "+station_id)
		var restored:RefCounted=fresh();check(Save.load_world(restored,directory.path_join(station_id)).ok,"reload exact completion "+station_id)
		check(F.amount(restored,"wood")==F.amount(w,"wood") and F.amount(restored,"mushroom")==F.amount(w,"mushroom") and restored.work.claims.is_empty() and restored.work.jobs.is_empty(),"reload source amounts and no running claims "+station_id)
	print("Moon barbecue audit v4: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)

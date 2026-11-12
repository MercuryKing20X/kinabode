extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
const S=preload("res://scripts/save_store.gd")
const W=preload("res://scripts/world_state.gd")
const R=preload("res://scripts/carry_retention.gd")
var failed:=false
var checks:=0
func _initialize()->void:call_deferred("run")
func check(value:bool,text:String)->void:
	checks+=1
	if not value:failed=true;push_error(text)
func advance(w:RefCounted,seconds:float)->void:
	for frame in range(ceili(seconds/.1)):w.advance(.1)
func near(w:RefCounted,id:String,other:String)->bool:
	var p:Vector2=w.point(w.actors[other])
	for offset in [Vector2(1,0),Vector2(-1,0),Vector2(0,1),Vector2(0,-1)]:
		if w.walkable(w.actors[other].region_id,p+offset) and w.host_command(id,{"intent":"move","x":p.x+offset.x,"y":p.y+offset.y}).ok and F.wait(w,id):return true
	return false
func wait_work(w:RefCounted,id:String)->void:
	for tick in range(4000):
		w.advance(.1)
		if not w.work.jobs.has(id) and not w.deliveries.active(id):return
func write_variant(directory:String,data:Dictionary)->void:
	DirAccess.make_dir_recursive_absolute(directory)
	var f:=FileAccess.open(directory.path_join("island-v2.json"),FileAccess.WRITE);f.store_string(JSON.stringify(data));f.close()
func run()->void:
	var root_dir:String=OS.get_environment("HABITAT_DATA_DIR");assert(root_dir.contains("youqi-test-"))
	var w:RefCounted=F.fresh()
	check(F.harvest(w,"turnip") and F.withdraw(w,"human","turnip"),"real grown crop and actual player withdrawal")
	check(near(w,"human","npc.mira") and w.command("human",{"intent":"give","receiver_id":"npc.mira","item_id":"turnip","quantity":1}).ok,"explicit atomic gift")
	check(F.job(w,"human",{"intent":"store"}),"host explicitly stores genuine leftover crop before isolation baseline")
	var total:int=F.amount(w,"turnip");var warehouse:int=w.storage.count("turnip");var memories:Dictionary=w.memories.saved().duplicate(true)
	var human:Dictionary=w.actors.human.duplicate(true)
	w.director.set_all_enabled(true);w.hunger.start();check(w.activities.set_followers(["npc.mira"]).ok,"actual default follow selected")
	advance(w,120)
	check(w.actors["npc.mira"].carry.get("turnip")==1 and w.actors["npc.mira"].retained_carry.get("turnip")==1,"following leaves exactly one physical protected gift")
	check(w.storage.count("turnip")==warehouse and F.amount(w,"turnip")==total,"no automatic gift transfer or duplication")
	check(not w.deliveries.active("npc.mira") and w.actors.human==human,"kept gift creates no handoff or human operation")
	check(S.save_world(w,root_dir.path_join("gift")),"save optional protection with true carry")
	var clone:=W.new();check(S.load_world(clone,root_dir.path_join("gift")).ok,"reload valid protected gift")
	advance(clone,30)
	check(clone.actors["npc.mira"].carry.get("turnip")==1 and F.amount(clone,"turnip")==total,"reload does not queue a gift handoff")
	var saved:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(root_dir.path_join("gift/island-v2.json")))
	var legacy:Dictionary=saved.duplicate(true);legacy.actors["npc.mira"].erase("retained_carry")
	write_variant(root_dir.path_join("legacy"),legacy)
	var old:=W.new();check(S.load_world(old,root_dir.path_join("legacy")).ok,"legacy carry remains a valid schema7 optional absence")
	check(old.actors["npc.mira"].carry==legacy.actors["npc.mira"].carry and old.actors["npc.mira"].get("pocketed",false)==legacy.actors["npc.mira"].get("pocketed",false),"legacy physical carry and pocketed preserved")
	if old.memories._canonical(old.memories.saved())!=old.memories._canonical(saved.shared_memories):print("RETENTION_LEGACY_MEMORY_DIAG old=",old.memories.saved()," expected=",saved.shared_memories)
	check(old.actors["npc.mira"].retained_carry.get("turnip")==1 and old.memories._canonical(old.memories.saved())==old.memories._canonical(saved.shared_memories),"unknown provenance retained without fabricated gift history")
	for variant in [{"turnip":2},{"turnip":1.5},{"mushroom":1}]:
		var malformed:Dictionary=saved.duplicate(true);malformed.actors["npc.mira"].retained_carry=variant
		write_variant(root_dir.path_join("invalid"),malformed)
		check(not S.load_world(W.new(),root_dir.path_join("invalid")).ok,"reject malformed protection "+str(variant))
	var numeric:Dictionary=saved.duplicate(true);numeric.actors["npc.mira"].retained_carry={"turnip":1.0}
	write_variant(root_dir.path_join("numeric"),numeric)
	check(S.load_world(W.new(),root_dir.path_join("numeric")).ok,"integer and float counts remain equivalent")
	# A real normal harvest still follows its original paid route/commit/handoff.
	check(w.command("npc.mira",{"intent":"forage","target_id":"home.mushrooms.1"}).ok,"real work with existing kept gift accepted")
	var mushrooms:int=w.storage.count("mushroom");wait_work(w,"npc.mira")
	check(w.storage.count("mushroom")>mushrooms and w.actors["npc.mira"].carry.get("turnip")==1,"real new production delivers while kept gift stays physical")
	check(F.amount(w,"turnip")==total,"mixed work/gift preserves exact crop total")
	# Explicit store is an actual command, and may include kept goods.
	check(clone.command("npc.mira",{"intent":"store"}).ok,"explicit owner store accepted")
	wait_work(clone,"npc.mira")
	check(clone.actors["npc.mira"].carry.is_empty() and clone.actors["npc.mira"].retained_carry.is_empty() and clone.storage.count("turnip")==warehouse+1,"explicit store debits both physical and protected count once")
	check(near(w,"npc.mira","human") and w.command("npc.mira",{"intent":"give","receiver_id":"human","item_id":"turnip","quantity":1}).ok,"explicit re-gift transfers the real item")
	check(not w.actors["npc.mira"].carry.has("turnip") and not w.actors["npc.mira"].retained_carry.has("turnip") and F.amount(w,"turnip")==total,"re-gift clamps protection and conserves physical total")
	print("CARRY_RETENTION ",checks," failed=",failed);quit(1 if failed else 0)

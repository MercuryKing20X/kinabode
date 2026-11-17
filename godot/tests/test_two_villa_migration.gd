extends SceneTree
# DIRECTION 2026-11-11：“五座别墅只留一座”“泳池、躺椅、吊床等拿掉”“旧‘度假状态’取消”。
const Save=preload("res://scripts/save_store.gd")
var failed:=false
func check(ok:bool,message:String)->void:
	if not ok:failed=true;push_error(message)
func _initialize()->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR")
	var lib=preload("res://scripts/character_library.gd").new();lib.configure(dir)
	var old=load("res://content/migrations/resort-v2/world-state.gd").new("res://content/migrations/resort-v2/world.json");old.library=lib;old.residents.provision(old)
	check(preload("res://scripts/world_opening.gd").apply(old,lib,"standard").ok,"previous formal world opens")
	old.resort.ready()
	var memory:Dictionary=old.memories.saved().duplicate(true)
	check(Save.save_world(old,dir),"previous five-villa world saved")
	# Snapshot uses the previous marker, independent of today's save writer.
	var raw:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("island-v2.json")));raw.vacation_version=2
	FileAccess.open(dir.path_join("island-v2.json"),FileAccess.WRITE).store_string(JSON.stringify(raw))
	var before:Dictionary=raw.storage.duplicate(true)
	var w=load("res://scripts/world_state.gd").new("res://content/home-v3/world.json");w.library=lib;w.residents.provision(w)
	var result:Dictionary=Save.load_world(w,dir)
	check(result.get("ok",false) and result.get("loaded",false),"old five-villa save loads through actual entry")
	check(w.objects.keys().filter(func(id):return str(id).begins_with("resort.villa.")).size()==1,"DIRECTION Flower Isle: four removed villas absent")
	check(w.storage.saved().items.keys().size()==before.items.size() and before.items.keys().all(func(k):return w.storage.count(k)==int(before.items[k])),"free preset buildings and furniture grant no resources")
	check(w.memories.saved()==memory,"actual retained memories preserved")
	check(w.interior.furniture.values().all(func(f):return not str(f.region_id).begins_with("room.resort.villa.") or str(f.region_id) in ["room.resort.villa.human"]),"removed villa furniture not duplicated")
	check(Save.save_world(w,dir),"single-greenhouse save succeeds")
	var again=load("res://scripts/world_state.gd").new("res://content/home-v3/world.json");again.library=lib;again.residents.provision(again)
	result=Save.load_world(again,dir)
	check(result.get("ok",false) and again.storage.saved().items.keys().size()==before.items.size() and before.items.keys().all(func(k):return again.storage.count(k)==int(before.items[k])),"reload is idempotent")
	print("TWO_VILLA_MIGRATION failed=",failed);quit(1 if failed else 0)

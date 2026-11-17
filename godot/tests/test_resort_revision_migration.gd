extends SceneTree
# DIRECTION 2026-11-11：“五座别墅只留一座”“泳池、躺椅、吊床等拿掉”“旧‘度假状态’取消”。
const Migration=preload("res://scripts/resort_revision_migration.gd")
const Save=preload("res://scripts/save_store.gd")
var failed:=false
var count:=0
func check(ok:bool,label:String)->void:
	count+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR")
	var library=preload("res://scripts/character_library.gd").new();library.configure(dir)
	var old:RefCounted=Migration.old_world();old.library=library
	check(old.error.is_empty(),"frozen old geometry loads")
	check(preload("res://scripts/world_opening.gd").apply(old,library,"standard").ok,"old formal opening")
	var partial:Dictionary=old.objects["homelands.house.01"];partial.stage_index=1;partial.invested=4;partial.delivered={"wood":3}
	var complete:Dictionary=old.objects["homelands.house.02"];complete.stage_index=5;complete.status="complete";complete.stage="complete";complete.invested=20
	old.interior.serial=2
	old.interior.furniture["furniture.2"]={"id":"furniture.2","kind":"furniture","recipe_id":"chair","name":"旧椅","region_id":"room."+complete.id,"position":[9,4.5],"facing":"down","holder_id":"","invested":3,"items":{},"capacity":0,"artwork":library.artworks["furniture-chair"].duplicate(true)}
	check(Save.save_world(old,dir),"old-shaped fixture writes")
	var raw:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("island-v2.json")))
	raw.vacation_version=1
	raw.actors.codex.region_id="room."+complete.id
	raw.actors.codex.position=[13,7]
	var memories_before:Dictionary=raw.shared_memories.duplicate(true)
	check(Save._valid(old,raw),"strict frozen validation accepts original fixture")
	var before:int=int(raw.storage.items.wood)
	var world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");world.library=library;world.residents.provision(world)
	var corrupt:Dictionary=raw.duplicate(true);corrupt.objects[complete.id].position[0]+=1
	check(not Migration.migrate(world,corrupt),"invalid old position rejected before refunds")
	check(Migration.migrate(world,raw),"valid previous save migrates")
	check(int(raw.storage.items.wood)==before+30,"4 invested+3 delivered+20 completed+3 chair returned exactly")
	check(not raw.objects.keys().any(func(id):return Migration.removed(id)),"old small houses removed from saved objects")
	check(not raw.interior.furniture.has("furniture.2"),"refunded chair removed without duplication")
	# DIRECTION Flower Isle (2026-11-11) replaces the vacation map.
	check(raw.vacation_version==4,"Flower Isle revision marker written")
	check(raw.actors.codex.region_id=="home" and world.walkable("home",world.point(raw.actors.codex)),"old room resident relocated to actual walkable plaza")
	check(raw.shared_memories==memories_before,"all retained shared memory facts unchanged")
	check(not Migration.valid_archive({"plans":{},"memories":[],"interior":[{"kind":"made_up"}]}),"forged archived interior memory rejected")
	var forged:Dictionary=raw.duplicate(true);forged.interior.furniture["furniture.1"].position=[999,999]
	world.standard.install_geometry()
	check(not Save._valid(world,forged),"forged v2 furniture outside room remains rejected")
	var again:Dictionary=raw.duplicate(true)
	check(Migration.migrate(world,raw) and raw==again,"repeat migration is idempotent")
	var file:=FileAccess.open(dir.path_join("island-v2.json"),FileAccess.WRITE);file.store_string(JSON.stringify(raw));file.close()
	world.standard.install_geometry()
	var loaded:Dictionary=Save.load_world(world,dir)
	check(loaded.get("ok",false) and loaded.get("loaded",false),"migrated current world loads via real Save entry")
	check(world.storage.count("wood")==before+30,"loaded warehouse retains exact refund")
	check(Save.save_world(world,dir),"current revised world saves")
	var reload=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");reload.library=library;reload.residents.provision(reload)
	loaded=Save.load_world(reload,dir)
	check(loaded.get("ok",false) and reload.storage.count("wood")==before+30,"real reload does not refund twice")
	print("RESORT_REVISION_MIGRATION ",count," failed=",failed," before_wood=",before," after_wood=",raw.storage.items.wood," ledger=",world.resort.get_meta("revision_refunds",{}))
	quit(1 if failed else 0)

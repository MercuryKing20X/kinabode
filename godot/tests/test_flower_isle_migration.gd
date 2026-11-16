extends SceneTree
const Save=preload("res://scripts/save_store.gd")
var failed:=false
var checks:=0
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failed=true;push_error(label)
func _initialize()->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR")
	var library=preload("res://scripts/character_library.gd").new();library.configure(dir)
	var old:RefCounted=load("res://content/migrations/flower-predecessor/world-state.gd").new("res://content/home-v3/world.json")
	old.library=library;old.residents.provision(old)
	check(preload("res://scripts/world_opening.gd").apply(old,library,"showcase").ok,"previous showcase installed")
	old.resort.ready()
	old.actors.codex.region_id="room.resort.villa.companion-2";old.actors.codex.position=[13,7]
	old.actors["companion-2"].position=[75,196]
	check(old.storage.take({"wood":13}).ok,"fixture moves real warehouse wood into villa, chair and drop")
	old.objects["resort.villa.companion-2"].invested=4;old.objects["resort.villa.companion-2"].delivered={"wood":3}
	old.interior.furniture["furniture.100"]={"id":"furniture.100","kind":"furniture","recipe_id":"chair","name":"旧椅","region_id":"room.resort.villa.companion-2","position":[20,7],"facing":"down","holder_id":"","invested":3,"items":{},"capacity":0,"artwork":library.artworks["furniture-chair"].duplicate(true)}
	old.cat.initialize();old.cat.region="room.resort.villa.companion-2";old.cat.position=Vector2(18,8)
	old.drops["drop.old-villa"]={"id":"drop.old-villa","region_id":"home","position":[75,196],"wood":3}
	var wood:int=old.storage.count("wood")+10
	check(load("res://content/migrations/flower-predecessor/save-store.gd").save_world(old,dir),"real old world fixture written")
	var raw:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("island-v2.json")))
	raw.vacation_version=3
	check(Save._valid(old,raw),"frozen predecessor validates old two villas")
	FileAccess.open(dir.path_join("island-v2.json"),FileAccess.WRITE).store_string(JSON.stringify(raw))
	var world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");world.library=library;world.residents.provision(world)
	var result:Dictionary=Save.load_world(world,dir)
	check(result.get("loaded",false),"real save entry migrates old holiday fixture")
	check(world.resort.config.villas.size()==1 and world.objects.has("resort.villa.human") and not world.objects.has("resort.villa.companion-2"),"one greenhouse remains")
	check(world.storage.count("wood")==wood,"four invested + three delivered + three crafted chair returned exactly once")
	check(world.actors.codex.region_id=="home" and world.walkable("home",world.point(world.actors.codex)),"resident leaves removed room into walkable island")
	check(world.walkable("home",world.point(world.actors["companion-2"])),"removed villa footprint becomes walkable")
	check(world.cat.region=="home" and world.walkable("home",world.cat.position),"old cat at removed villa remains walkable")
	check(world.drops.has("drop.old-villa") and world.drops["drop.old-villa"].wood==3 and world.walkable("home",world.point(world.drops["drop.old-villa"])),"old drop keeps exact three wood on walkable ground")
	check(not world.interior.furniture.has("furniture.100"),"refunded crafted chair removed")
	check(not world.resort.vacation("codex"),"holiday status retired")
	check(world.resort.activities.values().all(func(a):return a.kind not in ["pool","lounge","swing","hammock"]),"old recreation fixtures absent")
	for who in ["codex","companion-2"]:
		world.director.routines[who].enabled=false
		var before:Vector2=world.point(world.actors[who])
		world.command(who,{"intent":"move","x":84,"y":208})
		for i in 300:world.advance(.1)
		check(world.point(world.actors[who]).distance_to(before)>1,"migrated resident moves through original World route "+who)
	check(Save.save_world(world,dir),"new island state writes")
	var again:RefCounted=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");again.library=library;again.residents.provision(again)
	check(Save.load_world(again,dir).get("loaded",false) and again.storage.count("wood")==wood,"second real load remains conserved")
	print("FLOWER_ISLE_MIGRATION ",checks," failed=",failed)
	quit(1 if failed else 0)

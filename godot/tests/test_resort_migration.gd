extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Library=preload("res://scripts/character_library.gd")
const Opening=preload("res://scripts/world_opening.gd")
const Save=preload("res://scripts/save_store.gd")
var failed:=false
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR")
	var library:=Library.new();library.configure(dir)
	var w:=World.new("res://content/home-v3/world.json");w.library=library;w.residents.provision(w)
	check(Opening.apply(w,library,"standard").ok,"formal fixture opens")
	# Previous-version fixture: actual canonical save shape, no vacation marker.
	var partial:Dictionary=w.objects["homelands.house.01"]
	partial.stage_index=1;partial.invested=4;partial.delivered={"wood":3}
	var complete:Dictionary=w.objects["homelands.house.02"]
	complete.stage_index=5;complete.status="complete";complete.stage="complete";complete["host_completed"]=true
	var saved_complete:Dictionary=complete.duplicate(true)
	var template:String="play-swing";var art:Dictionary=library.artworks[template].duplicate(true)
	w.leisure.serial+=1
	var site_id:String="play.custom."+str(w.leisure.serial)
	w.leisure.sites[site_id]={"id":site_id,"name":"旧岛秋千施工","kind":"play_site","region_id":"home","position":[57,250],"template_id":template,"invested":5,"complete":false,"artwork":art}
	var mature:Dictionary=w.farms.plots["farm.theirs.plot.01"]
	mature.crop_id="turnip";mature.watered=true;mature.planted_at=w.farms.clock-1300
	var young:Dictionary=w.farms.plots["farm.theirs.plot.02"]
	young.crop_id="turnip";young.watered=true;young.planted_at=w.farms.clock
	var before:Dictionary=w.storage.saved().items.duplicate(true)
	check(Save.save_world(w,dir),"old-shaped fixture saved")
	var raw:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("island-v2.json")))
	saved_complete=raw.objects[complete.id].duplicate(true) # canonical JSON numeric equivalence
	check(not raw.has("vacation_version"),"old fixture has no migration marker")
	check(Save._valid(w,raw),"fixture passes original strict save checks before migration")
	var loaded:=World.new("res://content/home-v3/world.json");loaded.library=library;loaded.residents.provision(loaded)
	var result:Dictionary=Save.load_world(loaded,dir)
	check(result.get("ok",false) and result.get("loaded",false),"load validates then migrates")
	check(loaded.storage.count("wood")==int(before.get("wood",0))+12,"7 house +5 leisure wood returned exactly")
	check(loaded.storage.count("turnip")==int(before.get("turnip",0))+3,"mature actual crop yield retained")
	check(loaded.storage.count("seed.turnip")==int(before.get("seed.turnip",0))+2,"two planted seeds retained; immature crop not credited full yield")
	if loaded.objects[complete.id]!=saved_complete:print("COMPLETE_DIFF expected=",saved_complete," actual=",loaded.objects[complete.id])
	check(loaded.objects[complete.id]==saved_complete,"completed old house preserved with JSON numeric equivalence")
	check(loaded.objects[partial.id].invested==0 and loaded.objects[partial.id].delivered.is_empty(),"refunded house retains no duplicate investment")
	check(loaded.leisure.sites[site_id].invested==0,"refunded leisure retains no duplicate investment")
	check(not loaded.farms.ready("farm.theirs"),"south farming retired")
	check(Save.save_world(loaded,dir),"migrated save written")
	var once:Dictionary=loaded.storage.saved()
	var twice:=World.new("res://content/home-v3/world.json");twice.library=library;twice.residents.provision(twice)
	result=Save.load_world(twice,dir)
	check(result.get("ok",false) and twice.storage.saved()==once,"reload cannot refund or rescue twice")
	print("RESORT_MIGRATION ",checks," failed=",failed," before=",before," after=",once," ledger=",loaded.resort.migration)
	quit(1 if failed else 0)

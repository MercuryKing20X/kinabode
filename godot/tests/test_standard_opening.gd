extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Library=preload("res://scripts/character_library.gd")
const Opening=preload("res://scripts/world_opening.gd")
const Save=preload("res://scripts/save_store.gd")
const F=preload("res://tests/cooking_fixture.gd")
const B=preload("res://tests/backpack_fixture.gd")
var checks:=0
var failed:=false
func check(ok:bool,msg:String)->void:
	checks+=1
	if not ok:failed=true;push_error(msg)
func _initialize()->void:call_deferred("run")
func fresh(dir:String)->RefCounted:
	var w:=World.new("res://content/home-v3/world.json");w.residents.provision(w);w.library=Library.new();w.library.configure(dir);return w
func run()->void:
	var dir:=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-test-"))
	var w:=fresh(dir);check(w.error.is_empty(),"world content valid")
	check(Opening.apply(w,w.library,"standard").ok,"independent standard opening applies")
	check(w.actors.size()==5 and w.standard.config.companions.all(func(id):return w.actors[id].controller=="local" and w.actors[id].carry.is_empty()),"four local companions, empty inventories")
	check(w.actors.human.carry.is_empty() and B.wood_total(w)==5,"only configured five real wood; human empty")
	check(w.memories.records.is_empty() and w.relationships.states.is_empty(),"no invented history or relation grants")
	check(w.objects[w.standard.config.house.site_id].stage_index==5 and w.interior.furniture.size()==1,"only player cottage and one chair complete")
	check(w.catalog.regions.home.layout.residential.filter(func(p):return p.owner_id!="human").all(func(p):return w.objects[p.site_id].stage_index==0),"other plots remain empty")
	check(not w.standard.ready("home.barbecue") and not w.command("human",{"intent":"barbecue","target_id":"home.barbecue"}).ok,"unbuilt camp cannot cook")
	check(not w.command("human",{"intent":"cook","recipe_id":"turnip-soup"}).ok and not w.life.fireside.invite(w.standard.config.companions).ok,"direct cooking and invitation cannot bypass unbuilt camp")
	check(w.farms.plots.values().all(func(p):return p.crop_id.is_empty()) and w.farms.crops.keys().all(func(item):return w.storage.count(item)==0),"empty uncropped fields and harvest chest")
	check(w.standard.ready("farm.home") and not w.standard.ready("farm.hill"),"only first farm cultivated")
	var bad:Dictionary=w.standard.config.duplicate(true);bad.construction[0].wood=-1;check(not w.standard.valid_config(bad),"invalid whole opening rejected")
	w.hunger.start();check(w.standard.config.companions.all(func(id):return w.hunger.rank(id)==1) and w.hunger.rank("human")==-1,"peckish companions; human never hungry")
	w.director.set_all_enabled(false)
	check(Save.save_world(w,dir.path_join("initial")),"initial standard saves")
	var loaded:=fresh(dir.path_join("reload"));var r:Dictionary=Save.load_world(loaded,dir.path_join("initial"));check(r.ok and loaded.opening_id=="standard" and B.wood_total(loaded)==5,"standard reload preserves stock and origin")
	check_fishery_migration(w,dir)
	if not r.ok:print(r)
	check(not Opening.apply(w,w.library,"showcase").ok,"cannot transform standard progress into showcase")
	check(F.job(w,"human",{"intent":"build_facility","target_id":"play.standard.camp"}) and not w.standard.ready("home.barbecue") and w.leisure.sites["play.standard.camp"].invested==5,"partial real material preserved when missing wood")
	check(Save.save_world(w,dir.path_join("partial")),"partial material investment saves")
	var partial:=fresh(dir.path_join("partial-read"));check(Save.load_world(partial,dir.path_join("partial")).ok and partial.leisure.sites["play.standard.camp"].invested==5 and partial.work.jobs.is_empty(),"partial reload retains deposits and no job or claim")
	check(B.wood(w,1,"human"),"human actually cuts and stores one configured-yield tree")
	check(F.job(w,"human",{"intent":"build_facility","target_id":"play.standard.camp"}) and w.standard.ready("home.barbecue"),"remaining one wood completes actual six-wood camp")
	check(B.wood_total(w)==8 and w.leisure.sites["play.standard.camp"].invested==6 and w.storage.count("wood")==2,"eight starting-plus-cut wood conserved; both fuel logs remain")
	check(Save.save_world(w,dir.path_join("built")),"built camp saves exact investment")
	var reloaded:=fresh(dir.path_join("reload-built"));check(Save.load_world(reloaded,dir.path_join("built")).ok and reloaded.standard.ready("home.barbecue") and reloaded.work.jobs.is_empty(),"reload camp completed, no restored work")
	check(not w.command("human",{"intent":"build_facility","target_id":"play.standard.camp"}).ok and B.wood_total(w)==8,"duplicate completion never spends again")
	check(B.wood(w,2,"human"),"real additional trees fund the separate field")
	check(F.job(w,"human",{"intent":"build_facility","target_id":"play.standard.hill-field"}) and w.standard.ready("farm.hill"),"another field unlocks by existing real construction")
	check(Save.save_world(w,dir.path_join("field")),"unlocked field persists")
	print("Standard opening: ",checks," checks, failed=",failed);quit(1 if failed else 0)

func check_fishery_migration(w:RefCounted,dir:String)->void:
	var south:="home.fishery.south";var west:="home.fishery.west"
	var retired:="play.standard.south-pen"
	check(w.fishing.pens.has(south) and w.fishing.pens.has(west) and w.standard.ready(south) and w.standard.ready(west),"both island fisheries are ready on a fresh standard world")
	check(not w.leisure.sites.has(retired) and w.flower_creation.creations.structure_check(south).error=="protected_structure","fisheries offer no construction or demolition")
	# Explicit migration fixture, including one historic paid site and two exact fish instances.
	var data:Dictionary=Save.encode_world(w).duplicate(true)
	var old:Dictionary=data.leisure.sites["play.standard.camp"].duplicate(true)
	old.id=retired;old.name="南码头围网";old.position=w.map_anchor("dock.south.end")
	old.complete=true;old.invested=12
	data.leisure.sites[retired]=old
	var fish:Dictionary={"id":"fish-%024x"%1,"owner_id":"human","source_id":"home.sea.south","spot_id":"shore-"+"0".repeat(24),"species_id":"bean","color_id":"cream","size_id":"person","scale":1,"location":south,"caught_at":100}
	data.fishing.fish[fish.id]=fish
	var held:Dictionary=fish.duplicate(true)
	held.id="fish-%024x"%2;held.owner_id="codex";held.location="pending"
	data.fishing.fish[held.id]=held
	var fixture=preload("res://tests/fishing_fixture.gd")
	var old_dir:=dir.path_join("paid-fishery")
	fixture.write_json(old_dir.path_join("island-v2.json"),data)
	var loaded:=fresh(dir.path_join("paid-fishery-read"))
	var result:Dictionary=Save.load_world(loaded,old_dir)
	check(result.ok and not loaded.leisure.sites.has(retired) and loaded.standard.ready(south) and loaded.standard.ready(west),"paid old construction stops appearing as a site after load "+str(result))
	var on_disk:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(old_dir.path_join("island-v2.json")))
	check(result.ok and loaded.fishing.fish==on_disk.fishing.fish and loaded.fishing.held("codex").get("id")==held.id and loaded.fishing.pen_count(south)==1,"old stocked fish and pending fish survive exactly")
	check(result.ok and loaded.storage.count("wood")==w.storage.count("wood"),"retired paid construction never refunds wood")
	if not result.ok:return
	loaded.intelligence.activate_presets()
	loaded.director.routines.codex.set_enabled(true)
	var door:Node=preload("res://scripts/world_door.gd").new()
	door.setup(loaded,old_dir)
	var claim:Dictionary=door.command("claim",{"resident":"codex","client":"Fishery fixture"},0)
	check(claim.ok,"external client can claim the resident who holds the exact fish")
	if claim.ok:
		var act:Dictionary=door.command("act",{"lease":claim.lease,"steps":[{"action":"stock_fish","fish_id":held.id,"pen_id":west},{"action":"stock_fish","fish_id":fish.id,"pen_id":west}]},0)
		for i in 10:loaded.advance(.1)
		var receipt:Dictionary=loaded.director.brains.codex.intention.basic.result
		var feedback:Array=loaded.director.brains.codex.intention.feedback_rows
		check(act.ok and receipt.get("error")=="fish_not_owned" and loaded.fishing.pen_count(west)==1 and loaded.fishing.held("codex").is_empty() and loaded.fishing.fish[held.id].owner_id=="codex" and loaded.fishing.fish[fish.id].location==south,"leased basic step transfers only its resident's exact catch: "+str(act.get("error",receipt.get("error","")))+" "+str(feedback.map(func(row):return row.reason)))
		door.command("release",{"lease":claim.lease},0)
	door.free()

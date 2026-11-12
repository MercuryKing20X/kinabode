extends SceneTree
const Helper=preload("res://tests/test_barbecue_v2.gd")
const F=preload("res://tests/cooking_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var helper:=Helper.new();var dir:=OS.get_environment("HABITAT_DATA_DIR");var w:RefCounted=helper.fresh(dir)
	check(helper.pickup(w,"wood",2) and helper.pickup(w,"mushroom",1),"real recipe ingredients, no grants")
	var actor:Vector2=w.point(w.actors.human)
	check(F.job(w,"npc.mira",{"intent":"move","x":actor.x+1,"y":actor.y}) and w.command("human",{"intent":"give","receiver_id":"npc.mira","item_id":"mushroom","quantity":1}).ok,"explicit real gift retains ingredient while human fishes empty-handed")
	check(F.job(w,"npc.mira",{"intent":"enter","target_id":"home.house.01"}),"gift owner genuinely stays indoors while host fishes")
	check(helper.approach(w,w.life) and w.life.fireside.light_host().ok,"real wood lights fire")
	var shore:Array=w.fishing.nearby_shores("human")[0].position
	check(F.job(w,"human",{"intent":"move","x":shore[0],"y":shore[1]}),"human explicitly reaches real coast")
	check(w.command("human",{"intent":"fish"}).ok,"actual fishing starts")
	for i in range(1200):
		w.advance(.1)
		if not w.work.jobs.has("human"):break
	var stored:Array=w.fishing.fish.values().filter(func(f):return f.owner_id=="human" and f.location=="storage")
	var fish:Dictionary=stored[0].duplicate(true) if not stored.is_empty() else {}
	check(not fish.is_empty(),"real fish instance caught")
	actor=w.point(w.actors.human)
	check(F.job(w,"human",{"intent":"enter","target_id":"home.house.01"}) and w.command("npc.mira",{"intent":"give","receiver_id":"human","item_id":"mushroom","quantity":1}).ok,"explicit existing give returns same mushroom, no automatic taking")
	check(F.job(w,"human",{"intent":"exit"}) and helper.approach(w,w.life) and w.life.fireside.menu().any(func(m):return m.id=="recipe:grilled-fish" and m.maximum>0),"fish recipe available with actual stored fish and carried side ingredient")
	check(w.life.fireside.roast_host("recipe:grilled-fish").ok and not w.fishing.fish.has(fish.id) and not w.actors.human.carry.has("mushroom"),"one original fish plus one original mushroom debited atomically")
	helper.advance(w,8.2);w.life.fireside.end_circle("cancel after cooking")
	check(w.life.fireside.state.current.total==w.recipes.config.fish_portions[fish.size_id] and w.life.station.portions==0 and w.life.fireside.state.current.eaten+w.life.fireside.state.current.wasted==w.life.fireside.state.current.total,"cancel accounts every not-yet-eaten true output as waste without leftovers")
	check(Save.save_world(w,dir.path_join("fish-recipe")),"fish recipe receipt saved")
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("fish-recipe/island-v2.json")))
	check(Save._valid(w,data),"strict original receipt accepted")
	data.fishing.fish[fish.id]=fish
	check(not Save._valid(w,data),"same original fish cannot be both consumed receipt and living instance")
	var loaded:RefCounted=helper.fresh(dir.path_join("read"));check(Save.load_world(loaded,dir.path_join("fish-recipe")).ok and loaded.work.jobs.is_empty() and not loaded.life.fireside.state.consent,"reload keeps fish food and no claims or running task")
	var old:RefCounted=helper.fresh(dir.path_join("legacy"));check(Save.save_world(old,dir.path_join("old-save")),"optional-field compatibility fixture")
	data=JSON.parse_string(FileAccess.get_file_as_string(dir.path_join("old-save/island-v2.json")));data.erase("barbecue_tastes");data.erase("extra_barbecues")
	check(Save._valid(old,data),"old save without any new optional state remains valid")
	var file:=FileAccess.open(dir.path_join("old-save/island-v2.json"),FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close()
	check(Save.load_world(helper.fresh(dir.path_join("old-read")),dir.path_join("old-save")).ok,"missing fields never issue free food")
	helper.free();print("Fireside receipts: ",checks," checks, failed=",failed);quit(1 if failed else 0)

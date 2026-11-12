extends SceneTree
## Integration — barbecue-v4 — BLOCKING resource authority, invitation, conservation.
const F=preload("res://tests/cooking_fixture.gd")
const BBQ=preload("res://tests/barbecue_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var w:=F.fresh()
	check(w.error.is_empty(),"world and pure recipes valid")
	var free_menu:Array=w.life.fireside.menu().filter(func(row):return row.id=="single:mushroom")
	check(free_menu.size()==1 and free_menu[0].maximum>=w.actors.size() and free_menu[0].ingredients.is_empty(),"mushroom menu truthfully declares no required ingredients and enough for every resident")
	check(not w.get_property_list().any(func(p):return p.name=="cooking"),"no independent cooking component")
	check(not w.hunger.has_method("pack") and not w.hunger.has_method("feed") and not w.life.fireside.has_method("pack_host") and not w.life.fireside.has_method("resume_host"),"removed food APIs absent")
	var empty_world:=F.fresh()
	check(BBQ.light(empty_world),"empty-food regression lights with real wood")
	var before_free:Dictionary=empty_world.storage.saved().duplicate(true)
	var free_fire:RefCounted=empty_world.life.fireside
	var guests:Array=empty_world.actors.keys().filter(func(id):return id!="human")
	check(F.amount(empty_world,"mushroom")==0,"regression has zero mushrooms before roasting")
	check(free_fire.invite(guests).ok and free_fire.roast_host("single:mushroom").ok,"zero mushrooms still serves every invited resident")
	for tick in 1200:
		empty_world.advance(.1)
		if int(free_fire.state.current.eaten)==guests.size()+1:break
	check(int(free_fire.state.current.eaten)==guests.size()+1 and free_fire.state.current.receipt.is_empty() and empty_world.storage.saved()==before_free,"all invited diners really eat without any ingredient debit")
	check(F.mushroom(w) and BBQ.light(w),"real forage, host walks and lights")
	var fire:RefCounted=w.life.fireside
	var before:Dictionary=w.actors.duplicate(true);var jobs:Dictionary=w.work.jobs.duplicate(true)
	check(fire.invite(["codex"]).ok and w.actors==before and w.work.jobs==jobs,"invitation only records selected actor, never moves human or guests")
	check(fire.roast_host("single:mushroom").ok,"chosen real source starts automatic allocation")
	check(fire.state.current.total==2 and fire.state.current.receipt.is_empty(),"unlimited mushroom serves host plus exact invite without ingredients")
	var ongoing:Dictionary=fire.state.current.duplicate(true);var stock:Dictionary=fire.available().duplicate(true)
	check(not fire.roast_host("single:mushroom").ok and fire.available()==stock and fire.state.current==ongoing,"in-flight replacement rejected atomically")
	for tick in range(1200):
		w.advance(.1)
		if fire.state.current.eaten==fire.state.current.total:break
	check(fire.state.current.eaters.has("human") and fire.state.current.eaters.has("codex"),"near host and selected guest actually eat")
	check(fire.state.current.eaters.all(func(id):return id in ["human","codex"]),"unselected bystanders never eat")
	check(fire.state.current.eaten+fire.state.current.wasted+w.life.station.portions==fire.state.current.total,"all real output accounted")
	var retained:Dictionary=fire.state.current.duplicate(true);var circle_jobs:Dictionary=w.work.jobs.duplicate(true);stock=fire.available().duplicate(true)
	for intent in ["cook","cook_read","eat","turn_food","cleanup","farm_meal"]:
		check(not w.command("human",{"intent":intent}).ok and w.work.jobs==circle_jobs and fire.state.current==retained and fire.available()==stock,"retired input has zero circle/job/inventory side effects "+intent)
	fire.end_circle("explicit test end")
	var eaten:int=fire.state.current.eaten
	w.hunger.start();w.hunger.ensure("codex");var hunger:Dictionary=w.hunger.states.codex.duplicate(true)
	w.hunger.ate("codex","fake-cooked","cooked","home.barbecue")
	w.hunger.ate("codex","fake-farm","farm","farm.home")
	check(w.hunger.states.codex==hunger,"only barbecue can restore hunger")
	var path:String=OS.get_environment("HABITAT_DATA_DIR").path_join("core-v4")
	check(Save.save_world(w,path),"schema7 real state saves")
	var serialized:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path.path_join("island-v2.json")))
	check(serialized.schema_version==7 and not serialized.has("cooking") and not serialized.has("shared_activity") and not serialized.hunger.has("consumed"),"removed optional food flow fields no longer written")
	var reloaded:=F.fresh();check(Save.load_world(reloaded,path).ok,"v4 state safely reloads")
	check(reloaded.life.station.portions==0 and reloaded.work.jobs.is_empty() and reloaded.life.fireside.state.current.eaten==eaten,"reload never restores leftover food human motion or jobs")
	var invalid:Dictionary=fire.state.duplicate(true)
	invalid.current.eaten=invalid.current.total+1
	check(not fire.valid(invalid,w.actors,w.life.station),"invalid output conservation remains rejected")
	var meal_records:int=w.memories.records.size()
	stock=fire.available().duplicate(true)
	check(fire.light_host().ok,"host can refuel after an actually completed circle")
	check(fire.valid(fire.state,w.actors,w.life.station),"refueling a completed circle keeps a valid schema7 state")
	check(Save.save_world(w,path) and Save.load_world(F.fresh(),path).ok,"refueled completed circle actually reloads from schema7")
	check(w.memories.records.size()==meal_records and fire.available().get("mushroom",0)==stock.get("mushroom",0),"refuel preserves committed meal history and remaining raw food")
	var local:=F.fresh()
	check(F.mushroom(local) and BBQ.light(local),"fresh real forage and fuel for local-to-invited ownership regression")
	var local_fire:RefCounted=local.life.fireside
	local.director.set_all_enabled(true)
	check(local_fire.invite(["codex","companion-2"]).ok and local_fire.roast_host("single:mushroom").ok,"explicit invitation takes over only idle local behavior")
	for tick in range(1200):
		local.advance(.1)
		if local_fire.state.current.eaten==3:break
	check(local_fire.state.current.eaters.size()==3,"idle local commands cannot suppress confirmed guests")
	var owned:Array=[]
	for id in local_fire.jobs:owned.append(local_fire.jobs[id])
	local_fire.end_circle("explicit completed ownership end")
	check(owned.all(func(job_id):return local.work.events.filter(func(e):return e.get("job_id")==job_id and e.status=="completed").size()==1),"each exact finished fire job receives one real completion receipt")
	shortage()
	print("Barbecue v4 core: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
func shortage()->void:
	var w:=F.fresh();check(F.mushroom(w) and BBQ.light(w),"real shortage world food and fuel")
	var fire:RefCounted=w.life.fireside
	var stock:int=int(fire.available().get("mushroom",0))
	if stock>0:check(w.pay_costs("human",{"mushroom":stock}).ok,"test clears actual mushroom stock")
	check(int(fire.available().get("mushroom",0))==0,"no mushrooms available")
	check(fire.invite(w.standard.config.companions).ok,"all four exact guests selected")
	check(fire.roast_host("single:mushroom").ok and fire.state.current.total==5 and fire.state.current.receipt.is_empty(),"zero stock serves all five without receipt")
	for tick in range(1800):
		w.advance(.1)
		if fire.state.current.eaten==5:break
	for tick in range(50):w.advance(.1)
	check(fire.state.current.eaten==5 and fire.state.current.eaters.size()==5 and w.life.station.portions==0,"all five actually eat")
	fire.end_circle("explicit shortage end")
	check(fire.state.current.eaten+fire.state.current.wasted==5 and fire.available().get("mushroom",0)==0,"zero source stock and output accounted")

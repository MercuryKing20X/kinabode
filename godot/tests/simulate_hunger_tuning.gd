extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Library=preload("res://scripts/character_library.gd")
const Opening=preload("res://scripts/world_opening.gd")
const Save=preload("res://scripts/save_store.gd")
const B=preload("res://tests/backpack_fixture.gd")
const BBQ=preload("res://tests/barbecue_fixture.gd")
var w:RefCounted
var elapsed:=0.0
var duration:=10500.0
var speech:Array=[]
var last_serial:=0
var behavior:Dictionary={}
var old_trees:Dictionary={}
var wood_generated:=0
var initial_wood:=0
var initial_food:=0
var used_food:=0
var served:Dictionary={}
var unexpected_interruptions:Array=[]
var actions:Array=[]
var checks:=0
var failed:=false
func check(ok:bool,msg:String)->void:
	checks+=1
	if not ok:failed=true;push_error(msg)
func _initialize()->void:call_deferred("run")
func food_total()->int:
	var count:=0
	for chest in [{"id":"storage","items":w.storage.saved().items,"capacity":9007199254740991}]:
		for crop in w.farms.crops:
			if crop!="daisy":count+=int(chest.items.get(crop,0))
	for actor in w.actors.values():
		for crop in w.farms.crops:
			if crop!="daisy":count+=int(actor.carry.get(crop,0))
	return count
func frame()->void:
	if elapsed>=duration:return
	var jobs:Dictionary=w.work.jobs.duplicate(true)
	w.advance(minf(.5,duration-elapsed));elapsed+=.5
	for object in w.objects.values():
		if object.kind=="tree":
			if old_trees.get(object.id)=="mature" and object.status=="stump":wood_generated+=int(object.wood_yield)
			old_trees[object.id]=object.status
	for camp in w.barbecues.values():
		var current:Dictionary=camp.fireside.state.get("current",{})
		if not current.is_empty() and not served.has(current.id):
			served[current.id]=true
			for crop in current.receipt:
				if crop in w.farms.crops:used_food+=int(current.receipt[crop])
	for id in jobs:
		if jobs[id].get("source")=="local_rules" or w.work.jobs.get(id,{}).get("id")==jobs[id].get("id"):continue
		var expected:bool=w.hunger.statistics.abandoned.any(func(e):return e.job_id==jobs[id].id)
		var completed:bool=w.work.events.any(func(e):return e.get("job_id")==jobs[id].id)
		if not expected and not completed:unexpected_interruptions.append({"actor":id,"intent":jobs[id].intent,"at":elapsed})
	for id in w.director.routines:
		var r:RefCounted=w.director.routines[id];var key:String=r.kind if not r.kind.is_empty() else "following" if w.hunger.follow_targets.has(id) else "idle"
		var counts:Dictionary=behavior.get(id,{});counts[key]=float(counts.get(key,0))+.5;behavior[id]=counts
	for e in w.director.events:
		if e.serial>last_serial:speech.append(e.duplicate(true));last_serial=e.serial
func wait(id:String,limit:float=600)->bool:
	var end:float=minf(duration,elapsed+limit)
	while elapsed<end:
		if not w.work.jobs.has(id) and not w._routes.has(id):return true
		frame()
	return not w.work.jobs.has(id) and not w._routes.has(id)
func job(id:String,args:Dictionary,limit:float=600)->bool:
	w.director.moods.player_input();w.relationships.player_input()
	var result:Dictionary=w.command(id,args);actions.append({"at":elapsed,"actor":id,"intent":args.intent,"ok":result.ok,"reason":result.get("error","")})
	return result.ok and wait(id,limit)
func replenish()->void:
	var plots:Array=w.farms.plots.values().filter(func(p):return p.crop_id in ["tomato","turnip","pumpkin","blueberry","apple"] and w.farms.stage(p)=="mature")
	for plot in plots.slice(0,4):
		if elapsed>duration-120:return
		job("human",{"intent":"harvest","target_id":plot.id})
		if not w.actors.human.carry.is_empty():w.deposit_all("human")
		if plot.crop_id.is_empty():
			job("human",{"intent":"plant","target_id":plot.id,"crop_id":"tomato" if "tomato" in w.farms.farms[plot.farm_id].crop_ids else "turnip"})
			job("human",{"intent":"water","target_id":plot.id})
func free_hands(id:String)->void:
	if not w.actors[id].carry.is_empty():job(id,{"intent":"store"})
func barbecue()->void:
	var result:bool=BBQ.meal(w,"single:mushroom",["human","companion-2","npc.mira"],"home.barbecue",frame)
	actions.append({"at":elapsed,"actor":"human","intent":"barbecue_host","ok":result})
func serve_pair(pair:Array)->void:
	if elapsed>duration-180:return
	for id in pair:free_hands(id)
	var inventory:Dictionary=w.life.fireside.available()
	var recipe:String="roast-pumpkin" if int(inventory.get("pumpkin",0))>=2 else "tomato-salad" if int(inventory.get("tomato",0))>=4 else ""
	if recipe.is_empty():return
	var result:bool=BBQ.meal(w,"recipe:"+recipe,["human"]+pair,"home.barbecue",frame)
	actions.append({"at":elapsed,"actor":"human","intent":"barbecue_recipe","recipe_id":recipe,"ok":result})
func run()->void:
	var dir:=OS.get_environment("HABITAT_DATA_DIR");var out:=OS.get_environment("HABITAT_HUNGER_EVIDENCE");assert(dir.contains("youqi-test-") and not out.is_empty())
	if not OS.get_environment("HABITAT_HUNGER_DAYS").is_empty():duration=float(OS.get_environment("HABITAT_HUNGER_DAYS"))*1500
	w=World.new("res://content/home-v3/world.json");w.residents.provision(w);w.library=Library.new();w.library.configure(dir)
	check(Opening.apply(w,w.library).ok,"real showcase opening")
	check(Save.save_world(w,dir) and Save.archive_progress(dir),"explicit archival reset in temporary data")
	var identity:Dictionary={}
	for id in w.actors:identity[id]={"name":w.actors[id].name,"appearance_id":w.actors[id].appearance_id,"controller":w.actors[id].controller}
	w=World.new("res://content/home-v3/world.json");w.residents.provision(w);w.library=Library.new();w.library.configure(dir);Opening.apply(w,w.library);Save.apply_identity(w,identity)
	w.world_id="intelligence-hunger-simulation";w.weather.weather_seed=1027;w.fishing.rng.seed=1027
	w.intelligence.activate_presets();w.hunger.start();var i:=0
	for id in w.director.routines:w.director.routines[id].rng.seed=1027+i;w.director.routines[id].set_enabled(true);i+=1
	initial_wood=B.wood_total(w);initial_food=food_total()
	for object in w.objects.values():
		if object.kind=="tree":old_trees[object.id]=object.status
	var tree:Dictionary=w.objects.values().filter(func(o):return o.kind=="tree" and o.zone_id=="home.forest")[0]
	job("human",{"intent":"gather_wood","zone_id":tree.zone_id,"target_id":tree.id,"tree_count":1})
	# A genuine accepted long task is allowed to be abandoned only by its own hunger.
	w.command("codex",{"intent":"gather_wood","zone_id":tree.zone_id,"tree_count":20})
	var next_meal:=600.0;var next_garden:=900.0;var grilled:=false
	while elapsed<duration:
		if elapsed>=next_meal and elapsed<duration-180:
			next_meal=elapsed+900
			if not grilled:barbecue();grilled=true
			serve_pair(["codex","companion-2"]);serve_pair(["npc.mira","npc.nora"])
		if elapsed>=next_garden and elapsed<duration-180:
			next_garden=elapsed+1200;replenish()
		frame()
	var harvested:=0
	for farm in w.farms.farms.values():harvested+=int(farm.harvested)
	var fed:=0
	for item in w.hunger.consumed:
		if not w.hunger.is_meal(item):fed+=int(w.hunger.consumed[item])
	var wood:int=B.wood_total(w)
	var fuel:=0
	for bbq in w.barbecues.values():fuel+=int(bbq.station.fuel_used)+int(bbq.station.supplies.get("wood",0))
	check(wood+fuel==initial_wood+wood_generated,"all cut wood conserved across hunger abandonment")
	check(food_total()+used_food+fed==initial_food+harvested,"all raw crops accounted for after actual barbecue recipes")
	check(unexpected_interruptions.is_empty(),"no unexplained task interruptions")
	var residents:Dictionary={}
	for id in w.director.routines:
		var lines:Array=speech.filter(func(e):return e.actor_id==id)
		residents[id]={"speech_count":lines.size(),"state_seconds":w.hunger.statistics.state_seconds.get(id,{}),"behavior_seconds":behavior.get(id,{}),"abandoned":w.hunger.statistics.abandoned.filter(func(e):return e.actor_id==id).size(),"state":w.hunger.summary(id),"position":w.actors[id].position,"intelligence":w.intelligence.summary(id)}
	for id in residents:
		var seconds:Dictionary=residents[id].state_seconds;var total:float=seconds.values().reduce(func(a,b):return a+float(b),0.0)
		residents[id]["state_percent"]={}
		for state in w.hunger.STATES:residents[id].state_percent[state]=snappedf(float(seconds.get(state,0))/maxf(1,total)*100,.01)
		check(float(residents[id].state_percent.very_hungry)<=20,"very hungry at most twenty percent: "+id)
	var formation:Dictionary={"human_position":w.actors.human.position.duplicate(),"slots":{}}
	for id in w.hunger.follow_targets:
		var slot:Dictionary=w.hunger.follow_targets[id]
		formation.slots[id]={"region_id":slot.region,"destination":[slot.point.x,slot.point.y],"position":w.actors[id].position.duplicate(),"moving":w._routes.has(id)}
	check(Save.save_world(w,dir),"simulated world saves without schema change")
	var report:Dictionary={"game_days":int(duration/1500),"real_advance_seconds":elapsed,"zero_model_calls":true,"residents":residents,"statistics":w.hunger.statistics,"food":{"initial":initial_food,"harvested":harvested,"used_for_cooking":used_food,"fed":fed,"remaining":food_total()},"wood":{"initial":initial_wood,"generated":wood_generated,"physical":wood,"fuel_and_supplies":fuel},"unexpected_interruptions":unexpected_interruptions,"actions":actions,"following":w.hunger.follow_targets.size(),"formation":formation,"checks":checks,"failed":failed,"packed_food":{"packed":w.hunger.statistics.packed,"fed":w.hunger.statistics.fed_meals,"in_hand":w.actors.human.carry.keys().filter(func(k):return w.hunger.is_meal(k)).reduce(func(total,k):return total+int(w.actors.human.carry[k]),0)}}
	var f:=FileAccess.open(out.path_join("simulation-"+str(int(duration/1500))+"d.json"),FileAccess.WRITE);f.store_string(JSON.stringify(report,"  "));f.close()
	print("Intelligence hunger simulation: ",checks," checks, failed=",failed," days=",int(duration/1500)," speech=",speech.size()," meals=",w.hunger.statistics.meals," abandoned=",w.hunger.statistics.abandoned.size())
	quit(1 if failed else 0)

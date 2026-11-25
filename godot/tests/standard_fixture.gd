extends RefCounted
const World=preload("res://scripts/world_state.gd")
const Library=preload("res://scripts/character_library.gd")
const Opening=preload("res://scripts/world_opening.gd")
const BBQ=preload("res://tests/barbecue_fixture.gd")
var w:RefCounted
var elapsed:=0.0
var timeline:Array=[]
var ranks:Dictionary={}
var interruptions:Array=[]
var checks:=0
var failed:=false
var initial_wood:=0
var produced:=0
var tree_states:Dictionary={}
var raw_used:Dictionary={}
var served_batches:Array=[]
var previous_fuel:Dictionary={}
var audit_sources:=false
var next_source_audit:=0.0
var source_audits:Array=[]
func start(dir:String)->void:
	w=World.new("res://content/home-v3/world.json");w.residents.provision(w);w.library=Library.new();w.library.configure(dir)
	assert(Opening.apply(w,w.library,"standard").ok);w.intelligence.activate_presets();w.hunger.start();w.director.set_all_enabled(true)
	initial_wood=int(w.standard.config.storage.wood)
	w.world_id="standard-probe";w.fishing.rng.seed=1029
	for id in w.director.routines:w.director.routines[id].rng.seed=hash(id)
	for tree in w.objects.values():
		if tree.kind=="tree":tree_states[tree.id]=tree.status
	note("opening")
func note(event:String)->void:
	var state:Dictionary={}
	for id in w.standard.config.companions:state[id]=w.hunger.summary(id).state
	timeline.append({"event":event,"seconds":elapsed,"day":w.days.day(),"phase":w.days.phase().id,"hunger":state})
func tick(delta:float=.1)->void:
	var jobs:Dictionary=w.work.jobs.duplicate(true);w.advance(delta);elapsed+=delta
	for life in w.barbecues.values():
		var current:Dictionary=life.fireside.state.get("current",{})
		if not current.is_empty() and current.id not in served_batches:
			served_batches.append(current.id)
			for crop in current.receipt:raw_used[crop]=int(raw_used.get(crop,0))+int(current.receipt[crop])
	for tree in w.objects.values():
		if tree.kind=="tree":
			if tree_states.get(tree.id)=="mature" and tree.status=="stump":produced+=int(w.forest.settings.large_wood if int(tree.wood_yield)>8 else w.forest.settings.normal_wood)
			tree_states[tree.id]=tree.status
	for id in w.standard.config.companions:
		var state:int=w.hunger.rank(id)
		if ranks.get(id)!=state:ranks[id]=state;note("hunger:"+id)
	for id in jobs:
		if jobs[id].get("source")=="local_rules" or jobs[id].get("intent")=="shared_barbecue" or jobs[id].id==w.work.jobs.get(id,{}).get("id"):continue
		if not w.work.events.any(func(e):return e.get("job_id")==jobs[id].id) and not w.hunger.statistics.abandoned.any(func(e):return e.job_id==jobs[id].id):interruptions.append({"id":id,"job":jobs[id].id,"at":elapsed})
	if audit_sources and elapsed>=next_source_audit:
		next_source_audit=elapsed+30
		var trees:Array=w.objects.values().filter(func(o):return o.kind=="tree" and o.status=="mature")
		var food:Array=w.all_mushrooms().values().filter(func(p):return p.amount>0)
		var wood:bool=trees.any(func(t):return not w.approach_route("human",t).is_empty())
		var meal:bool=food.any(func(p):return not w.approach_route("human",p).is_empty())
		if not meal:
			meal=w.farms.farm_plots("farm.home").any(func(p):return not p.crop_id.is_empty() and p.watered and not w.approach_route("human",p).is_empty())
		source_audits.append({"seconds":elapsed,"reachable_wood":wood,"reachable_food":meal})
		check(wood and meal,"periodic real source reachability")
func advance(seconds:float)->void:
	for frame in range(int(ceil(seconds/.1))):tick()
func wait(id:String,limit:float=600)->bool:
	var deadline:float=elapsed+limit
	while elapsed<deadline:
		if not w.work.jobs.has(id) and not w._routes.has(id):return true
		tick()
	return false
func job(args:Dictionary,id:String="human")->bool:
	var result:Dictionary=w.command(id,args)
	if not result.ok:print("STANDARD ACTION REJECTED ",elapsed," ",id," ",args," ",result)
	return result.ok and wait(id)
func check(ok:bool,msg:String)->bool:
	checks+=1
	if not ok:failed=true;push_error(msg)
	return ok
func build_first()->bool:
	var tree:Dictionary=w.objects.values().filter(func(o):return o.kind=="tree" and o.zone_id=="home.forest")[0]
	if not check(job({"intent":"gather_wood","zone_id":tree.zone_id,"tree_count":1}),"one real tree chopped and hauled"):return false
	if not check(job({"intent":"build_facility","target_id":"play.standard.camp"}),"real six-wood camp built"):return false
	note("camp_built")
	for id in w.standard.config.forage_ids:
		if not check(job({"intent":"forage","target_id":id}),"real nearby mushrooms harvested and stored"):return false
	note("mushrooms_stored");return true
func shared_meal()->bool:
	var guests:Array=["human"]+w.standard.config.companions
	var result:Dictionary=BBQ.start(w,"single:mushroom",guests,"home.barbecue",tick)
	if not check(result.ok,"host explicitly approaches lights invites all four and roasts real mushrooms"):print(result);return false
	for id in guests:
		if not check(BBQ.ate(w,id,"home.barbecue",tick),"actual invited diner finishes "+id):return false
	BBQ.end(w);note("first_meal_finished")
	return check(not w.standard.first_meal.is_empty(),"real first shared meal committed once")
func wood_audit()->Dictionary:
	var B=preload("res://tests/backpack_fixture.gd");var fuel:int=0
	for life in w.barbecues.values():fuel+=int(life.station.fuel_used)+int(life.station.supplies.get("wood",0))
	var total:int=B.wood_total(w)
	return {"initial":initial_wood,"produced":produced,"physical_and_invested":total,"fuel":fuel,"conserved":initial_wood+produced==total+fuel}
func food_audit()->Dictionary:
	var items:Dictionary={};var good:=true
	for crop in w.farms.crops.keys()+["mushroom"]:
		var physical:=0
		physical+=w.storage.count(crop)
		for actor in w.actors.values():physical+=int(actor.carry.get(crop,0))
		for life in w.barbecues.values():physical+=int(life.station.supplies.get(crop,0))
		var source:=0
		if crop=="mushroom":
			source=w.all_mushrooms().size()*4
			source+=int(w.standard.config.storage.get("mushroom",0))
			for patch in w.all_mushrooms().values():physical+=int(patch.amount)
		else:
			# This script grows turnips only; every genuine harvest retains its crop count.
			if crop=="turnip":
				for farm in w.farms.farms.values():source+=int(farm.harvested)
		var used:int=int(raw_used.get(crop,0))
		items[crop]={"source":source,"physical":physical,"used":used,"conserved":source==physical+used};good=good and source==physical+used
	var seed_physical:=0;var harvested_seeds:=0;var planted_seeds:=0
	for chest in [{"items":w.storage.saved().items}]:
		for key in chest.items:
			if str(key).begins_with("seed."):seed_physical+=int(chest.items[key])
	for actor in w.actors.values():
		for key in actor.carry:
			if str(key).begins_with("seed."):seed_physical+=int(actor.carry[key])
	for plot in w.farms.plots.values():
		harvested_seeds+=int(plot.harvests);planted_seeds+=int(plot.harvests)+(0 if plot.crop_id.is_empty() else 1)
	var seeds:Dictionary={"initial":8,"retained_from_harvest":harvested_seeds,"planted":planted_seeds,"physical":seed_physical,"conserved":8+harvested_seeds==planted_seeds+seed_physical}
	return {"items":items,"seeds":seeds,"conserved":good and seeds.conserved}

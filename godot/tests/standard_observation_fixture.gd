extends "res://tests/standard_fixture.gd"
var samples:Array=[]
var next_sample:=0.0
var hunger_seconds:Dictionary={}
var first_very:Dictionary={}
var gaps:Array=[]
var want_food:=false
var gap_start:=-1.0
var actions:Array=[]
func food()->Dictionary:
	var ground:=0;var crops:Dictionary={};var portions:=0
	for p in w.all_mushrooms().values():ground+=int(p.amount)
	for box in [{"items":w.storage.saved().items}]:
		for key in box.items:
			if key in w.farms.crops or key=="mushroom":crops[key]=int(crops.get(key,0))+int(box.items[key])
	for life in w.barbecues.values():portions+=int(life.station.portions)
	var carried:=0
	for id in w.actors:
		for key in w.actors[id].carry:
			if key in w.farms.crops or key=="mushroom" or key.begins_with("meal."):carried+=int(w.actors[id].carry[key])
	var ready_crops:=0
	for p in w.farms.plots.values():
		if w.farms.stage(p)=="mature":ready_crops+=int(w.farms.crops[p.crop_id]["yield"])
	return {"ground_mushrooms":ground,"box_crops":crops,"station_portions":portions,"carried_food":carried,"mature_crop_units":ready_crops}
func tick(delta:float=.25)->void:
	if elapsed>=3600:return
	var dt:float=minf(delta,3600-elapsed)
	for id in w.standard.config.companions:
		var state:String=w.hunger.summary(id).state
		if not hunger_seconds.has(id):hunger_seconds[id]={}
		hunger_seconds[id][state]=float(hunger_seconds[id].get(state,0))+dt
		if w.hunger.rank(id)==3 and not first_very.has(id):first_very[id]=elapsed
	super.tick(dt)
	var f:Dictionary=food()
	var empty:bool=f.ground_mushrooms==0 and f.box_crops.values().all(func(n):return n==0) and f.station_portions==0 and f.carried_food==0 and f.mature_crop_units==0
	if want_food and empty and gap_start<0:gap_start=elapsed
	if (not empty or not want_food) and gap_start>=0:gaps.append({"start":gap_start,"end":elapsed});gap_start=-1
	if elapsed>=next_sample:
		next_sample=elapsed+30;f["seconds"]=elapsed;f["hunger"]={}
		for id in w.standard.config.companions:f.hunger[id]=w.hunger.summary(id).state
		samples.append(f)
func wait(id:String,limit:float=600)->bool:
	var deadline:float=minf(3600,elapsed+limit)
	while elapsed<deadline:
		if not w.work.jobs.has(id) and not w._routes.has(id):return true
		tick()
	return false
func advance(seconds:float)->void:
	var end:float=minf(3600,elapsed+seconds)
	while elapsed<end:tick(minf(.5,end-elapsed))
func meal()->bool:
	if elapsed>=3500:return false
	var stock:int=int(w.life.fireside.available().get("turnip",0))
	if stock>=6:
		var guests:Array=w.standard.config.companions.duplicate();guests.sort_custom(func(a,b):return w.hunger.rank(a)>w.hunger.rank(b))
		for group in [guests.slice(0,2),guests.slice(2,4)]:
			var result:Dictionary=BBQ.start(w,"recipe:turnip-soup",["human"]+group,"home.barbecue",tick)
			if not result.ok:actions.append({"at":elapsed,"barbecue_recipe_rejected":result});return false
			if not BBQ.finish(w,["human"]+group,"home.barbecue",tick):return false
		actions.append({"at":elapsed,"meal":"two_real_soup_batches_four_companions_plus_human"});return true
	var mushrooms:int=int(w.life.fireside.available().get("mushroom",0))
	if mushrooms<5:
		var patches:Array=w.all_mushrooms().values().filter(func(p):return p.amount>0)
		patches.sort_custom(func(a,b):return w.point(a).distance_squared_to(w.point(w.actors.human))<w.point(b).distance_squared_to(w.point(w.actors.human)))
		for p in patches:
			if not job({"intent":"forage","target_id":p.id}):continue
			mushrooms=int(w.life.fireside.available().get("mushroom",0))
			if mushrooms>=5:break
	if mushrooms<5:actions.append({"at":elapsed,"meal_unavailable":"fewer_than_five_portions_for_whole_group","food":food()});return false
	var wood:=0
	wood+=w.storage.count("wood")
	if wood<2:
		if not job({"intent":"gather_wood","zone_id":"home.forest","tree_count":1}):return false
	var ok:bool=shared_meal();actions.append({"at":elapsed,"meal":"real_barbecue_five_diners","ok":ok});return ok
func crop_cycle()->void:
	for p in w.farms.farm_plots("farm.home").slice(0,4):
		if elapsed>=3500:return
		if w.farms.stage(p)=="mature":job({"intent":"harvest","target_id":p.id})
		if p.crop_id.is_empty():
			if job({"intent":"plant","target_id":p.id,"crop_id":"turnip"}):job({"intent":"water","target_id":p.id})
func result()->Dictionary:
	if gap_start>=0:gaps.append({"start":gap_start,"end":elapsed});gap_start=-1
	return {"elapsed_seconds":elapsed,"timeline":timeline,"food_timeline":samples,"hunger_seconds":hunger_seconds,"first_very_hungry":first_very,"no_food_intervals":gaps,"actions":actions,"wood":wood_audit(),"food":food_audit(),"task_interruptions":interruptions,"failed":failed,"checks":checks}

extends SceneTree
## A scripted human drives existing commands. Only frame() advances the disposable world.
const F=preload("res://tests/cooking_fixture.gd")
const BBQ=preload("res://tests/barbecue_fixture.gd")
const DURATION:=4500.0
var world: RefCounted
var elapsed:=0.0
var serial:=0
var speech: Array=[]
var behavior: Dictionary={}
var actions: Array=[]
var interruptions: Array=[]
var failed_jobs: Array=[]
var checks:=0
var failed:=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok:failed=true;push_error(text)
func real_job(job: Dictionary) -> bool:return not job.is_empty() and job.get("source")!="local_rules"
func frame() -> bool:
	if elapsed>=DURATION:return false
	var jobs: Dictionary={}
	for id in world.work.jobs:
		if real_job(world.work.jobs[id]):jobs[id]=world.work.jobs[id].duplicate(true)
	world.advance(.5);elapsed+=.5
	for id in jobs:
		if world.work.jobs.get(id,{}).get("id")==jobs[id].id:continue
		var receipts: Array=world.work.events.filter(func(event):return event.job_id==jobs[id].id)
		if receipts.is_empty():interruptions.append({"at":elapsed,"actor":id,"job_id":jobs[id].id,"intent":jobs[id].intent,"reason":"accepted job disappeared without completion/block receipt"})
		elif receipts[-1].status!="completed":failed_jobs.append(receipts[-1].duplicate(true))
	for id in world.director.routines:
		var r: RefCounted=world.director.routines[id];var job: Dictionary=world.work.jobs.get(id,{})
		if real_job(job) and not r.kind.is_empty():interruptions.append({"at":elapsed,"actor":id,"reason":"local behavior overlaps genuine accepted job","kind":r.kind})
		var kind: String="task:"+str(job.intent) if real_job(job) else r.kind if not r.kind.is_empty() else "idle"
		behavior[id][kind]=float(behavior[id].get(kind,0))+.5
	for event in world.director.events:
		if event.serial<=serial:continue
		serial=event.serial;speech.append(event.duplicate(true))
	return true
func input() -> void:
	world.director.moods.player_input();world.relationships.player_input()
func command(id: String,args: Dictionary) -> Dictionary:
	input();var result: Dictionary=world.command(id,args)
	actions.append({"at":elapsed,"actor":id,"command":args.duplicate(true),"ok":result.ok,"reason":result.get("message",result.get("error",""))})
	return result
func wait_job(id: String,limit: float=600) -> bool:
	var end: float=minf(DURATION,elapsed+limit)
	while elapsed<end:
		if not frame():return false
		if not world.work.jobs.has(id) and not world._routes.has(id):return true
	return false
func job(id: String,args: Dictionary) -> bool:
	return command(id,args).ok and wait_job(id)
func go_near(id: String) -> bool:
	var p: Vector2=world.point(world.actors[id])
	for offset in [Vector2(2,0),Vector2(-2,0),Vector2(0,2),Vector2(0,-2)]:
		var target: Vector2=p+offset
		if world.walkable(world.actors[id].region_id,target) and job("human",{"intent":"move","x":target.x,"y":target.y}):return true
	return false
func report() -> Dictionary:
	var residents: Dictionary={};var occurrences: Dictionary={};var max_repeat:=0;var repeated:=0
	for id in world.director.routines:
		var lines: Array=speech.filter(func(event):return event.actor_id==id);var contexts: Dictionary={}
		for event in lines:
			contexts[event.context]=int(contexts.get(event.context,0))+1
			var key: String=id+":"+event.text;var stamps: Array=occurrences.get(key,[])
			stamps.append(float(event.time));occurrences[key]=stamps
			var recent: int=stamps.filter(func(stamp):return float(event.time)-float(stamp)<3600).size();max_repeat=maxi(max_repeat,recent)
			if stamps.size()>1:repeated+=1
		var starts: int=world.schedules.statistics.started.get(id,0);var arrivals: int=world.schedules.statistics.arrived.get(id,0)
		residents[id]={"name":world.actors[id].name,"controller":world.actors[id].controller,"personality":world.personality.summary(id),"speech_count":lines.size(),"speech_contexts":contexts,"behavior_seconds":behavior[id],"relationship":world.relationships.summary(id),"credited_true_event_counts":world.relationships.states.get(id,{}).get("counts",{}).duplicate(true),"wishes_generated":world.wishes.statistics.generated.get(id,0),"wishes_completed":world.wishes.statistics.completed.get(id,0),"wishes_active":world.wishes.summary(id),"schedule_started":starts,"schedule_arrived":arrivals,"schedule_hit_rate":float(arrivals)/starts if starts>0 else 0.0}
	var wood:=0
	for chest in [{"id":"storage","items":world.storage.saved().items,"capacity":9007199254740991,"kind":"storage"}]:wood+=int(chest.items.get("wood",0))
	for actor in world.actors.values():wood+=int(actor.carry.get("wood",0))
	for drop in world.drops.values():wood+=int(drop.wood)
	wood+=int(world.homestead.site.delivered.get("wood",0))
	for life in world.barbecues.values():wood+=int(life.station.fuel_used)
	return {"seconds":elapsed,"advance_frames":int(elapsed/.5),"delta":.5,"calendar_start":1,"calendar_end":world.days.day(),"real_model_calls":0,"scripted_human_actions":actions,"residents":residents,"utterances":speech,"utterance_total":speech.size(),"repeated_utterances":repeated,"max_same_line_in_any_hour":max_repeat,"true_task_interruptions":interruptions,"genuinely_blocked_jobs":failed_jobs,"homestead_completed":world.homestead.completed(),"physical_wood_from_harvested_trees":wood,"turnip_left":F.amount(world,"turnip"),"fish_instances":world.fishing.fish.size(),"shared_meals":world.memories.records.filter(func(entry):return entry.kind=="shared_barbecue"),"weather_days":[world.weather.for_day(1).name,world.weather.for_day(2).name,world.weather.for_day(3).name],"model_scheduler_instantiated":false}
func run() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	world=F.fresh();world.world_id="00000000-0000-4000-8000-000000001027";world.weather.weather_seed=1027;world.fishing.rng.seed=1027;world.fishing.life.rng.seed=1028
	var index:=0
	# B/C: DIRECTION 2026-11-10 makes following the default. This explicitly tests the existing free-idle mode.
	# Keep all original schedule, distance, physical-conservation and interruption assertions.
	for id in world.director.routines:
		world.activities.default_follow_excluded[id]=true
		behavior[id]={};world.director.routines[id].rng.seed=1027+index;index+=1;world.director.routines[id].set_enabled(true)
	check(job("human",{"intent":"assign_farm","farm_id":"farm.home","manager_id":"codex"}),"script human assigns genuine farm")
	var plots: Array=world.farms.farm_plots("farm.home").slice(0,5)
	for plot in plots:
		check(job("human",{"intent":"plant","target_id":plot.id,"crop_id":"turnip"}) and job("human",{"intent":"water","target_id":plot.id}),"script plants/waters one genuine seed "+plot.id)
	check(job("human",{"intent":"gather_wood","tree_count":11,"zone_id":"home.forest"}),"eleven physical trees include real barbecue fuel and project stock")
	var coastal:=false
	for shore in world.fishing.nearby_shores("human"):
		if job("human",{"intent":"move","x":shore.position[0],"y":shore.position[1]}) and not world.fishing.shore("human").is_empty():coastal=true;break
	check(coastal,"human really walks to sea while crops grow")
	input();var invitation: Dictionary=world.fishing.invite_host(["codex","companion-2"])
	actions.append({"at":elapsed,"actor":"human","host_invite_fishing":invitation.duplicate(true)})
	check(invitation.ok and job("human",{"intent":"fish"}),"explicit invitation and actual human fishing")
	for id in invitation.get("accepted",[]):check(wait_job(id),"invited physics task finishes without model "+id)
	for id in world.actors:
		var held: Dictionary=world.fishing.held(id)
		if not held.is_empty():check(command(id,{"intent":"stock_fish","fish_id":held.id,"pen_id":world.fishing.pens.keys()[0]}).ok,"actual owned fish goes to real pen "+id)
	while plots.any(func(plot):return world.farms.stage(plot)!="mature") and elapsed<2000:frame()
	for plot in plots:check(job("human",{"intent":"harvest","target_id":plot.id}),"human harvests mature crop into real box "+plot.id)
	var guests: Array=["human","codex","npc.mira"]
	for id in world.director.routines:
		if world.wishes.active(id).get("template_id")=="soup" and id!="codex":guests=["human","codex",id];break
	input();var cooked:Dictionary=BBQ.start(world,"recipe:turnip-soup",guests,"home.barbecue",frame)
	actions.append({"at":elapsed,"host_barbecue_recipe":cooked.duplicate(true),"invited":guests.duplicate()})
	check(cooked.ok and BBQ.ready(world,"home.barbecue",frame),"actual crop-funded soup served on real fire")
	for id in guests:check(BBQ.ate(world,id,"home.barbecue",frame),"explicit invited guest really eats "+id)
	BBQ.end(world)
	check(world.life.fireside.state.committed,"real finished eaters commit shared meal")
	# Residents' legitimate routes can transiently cross the unstarted site.
	# Observe and genuinely advance until it clears before submitting the plan.
	var site_wait_end: float = minf(DURATION, elapsed + 180.0)
	while not world.homestead.occupancy().is_empty() and elapsed < site_wait_end: frame()
	var host_delivery:bool=deliver_project("human",5,3)
	check(host_delivery and world.homestead.site.delivered.get("wood",0)==5 and world.homestead.crop_count(world.homestead.site.delivered)==3,"human contributes genuine five wood/three crops")
	check(deliver_project("codex",19,7) and world.homestead.funded(),"partner contributes rest from actual boxes")
	var build_end:float=minf(DURATION,elapsed+180)
	var build:Dictionary={"ok":false}
	while elapsed<build_end:
		while not world.homestead.occupancy().is_empty() and elapsed<build_end:frame()
		build=command("codex",{"intent":"homestead_build","plan_id":world.homestead.plans.codex.id})
		if build.ok and wait_job("codex") and world.homestead.completed():break
		if not build.ok and build.get("error","")!="occupied":break
		frame()
	check(build.ok and world.homestead.completed(),"real funded six-second construction completes once")
	for id in world.director.routines:
		check(go_near(id),"scripted player visits own-life resident "+id)
		var until: float=minf(DURATION,elapsed+140)
		while elapsed<until:frame()
	while elapsed<DURATION:frame()
	var data:=report()
	check(elapsed==DURATION and world.days.day()==4,"three complete game days genuinely advance through9000 frames")
	check(interruptions.is_empty(),"local rules interrupt exactly zero genuine tasks")
	check(data.physical_wood_from_harvested_trees==33 and data.turnip_left==2,"eleven trees33 wood including real fuel plus five harvests15 crops conserved through real24+10 project and3-crop soup")
	check(data.fish_instances==3 and data.shared_meals.size()==1,"three genuine catches and one genuinely eaten cleaned meal")
	check(data.max_same_line_in_any_hour<=2 and speech.all(func(event):return event.source=="local_rules"),"all delivered speech honest local and repeat-bounded")
	check(data.residents.values().all(func(resident):return resident.speech_count>0 and resident.schedule_started>0),"each companion has perceptible life and actual schedule choices")
	var output:=OS.get_environment("HABITAT_LOCAL_LIFE_SIMULATION_OUTPUT")
	if not output.is_empty():
		var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(data,"  "));file.close()
	print("Local life three-day simulation: %s checks, failed=%s; seconds=%s, utterances=%d, interruptions=%d"%[checks,failed,elapsed,speech.size(),interruptions.size()]);quit(1 if failed else 0)

func deliver_project(id:String,wood:int,crops:int)->bool:
	var end:float=minf(DURATION,elapsed+180)
	var before_wood:int=int(world.homestead.site.delivered.get("wood",0))
	var before_crops:int=world.homestead.crop_count(world.homestead.site.delivered)
	while elapsed<end:
		while not world.homestead.occupancy().is_empty() and elapsed<end:frame()
		var plan:Dictionary=world.homestead.plans.get(id,{})
		var args:Dictionary={"intent":"homestead_start","site_id":world.homestead.config.site.id,"wood_limit":wood,"crop_limit":crops}
		if not plan.is_empty():args={"intent":"homestead_resume","plan_id":plan.id,"wood_limit":maxi(0,before_wood+wood-int(world.homestead.site.delivered.get("wood",0))),"crop_limit":maxi(0,before_crops+crops-world.homestead.crop_count(world.homestead.site.delivered))}
		var result:Dictionary=command(id,args)
		if result.ok and wait_job(id):
			if int(world.homestead.site.delivered.get("wood",0))>=before_wood+wood and world.homestead.crop_count(world.homestead.site.delivered)>=before_crops+crops:return true
			if not world.homestead.plans[id].reason.contains("工程点"):return false
		elif result.get("error","")!="occupied":return false
		if not frame():break
	return false

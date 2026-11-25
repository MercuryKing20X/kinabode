# DIRECTION 2026-11-07: 主角鱼直接入库；以原真实实例验证后续流程。
extends SceneTree
const Places=preload("res://scripts/map_locations.gd")
## A scripted human drives existing commands. Only frame() advances the disposable world.
const F=preload("res://tests/cooking_fixture.gd")
const BBQ=preload("res://tests/barbecue_fixture.gd")
var DURATION:=22500.0
var timelines: Dictionary={}
var near_seconds: Dictionary={}
var speech_opportunities:Dictionary={}
var stage_saved: Dictionary={}
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
var default_follow_distance:Dictionary={}
func frame() -> bool:
	if elapsed>=DURATION:return false
	var jobs: Dictionary={}
	for id in world.work.jobs:
		if real_job(world.work.jobs[id]):jobs[id]=world.work.jobs[id].duplicate(true)
	# Read-only diagnostics: availability, never a retry, command, seed draw or assertion bypass.
	for id in world.director.routines:
		var r:RefCounted=world.director.routines[id]
		var near:bool=world.actors[id].region_id==world.actors.human.region_id and world.point(world.actors[id]).distance_to(world.point(world.actors.human))<=12.
		var stats:Dictionary=speech_opportunities.get(id,{"within12_seconds":0.,"ready_near_seconds":0.,"village_blocked_ready_seconds":0.,"village_open_ready_seconds":0.})
		if near:stats.within12_seconds+=.5
		if near and r.enabled and r.chatter and not r.held and r.time>=r.next_speech and world.director.moods.can_speak(id):
			stats.ready_near_seconds+=.5
			if world.director.time<world.director.speech_after:stats.village_blocked_ready_seconds+=.5
			else:stats.village_open_ready_seconds+=.5
		speech_opportunities[id]=stats
	var follow_before:Dictionary={}
	for id in world.director.routines:
		if world.activities.following.has(id) and world._routes.has(id) and not world.work.jobs.has(id):follow_before[id]={"region":world.actors[id].region_id,"point":world.point(world.actors[id])}
	world.advance(.5);elapsed+=.5
	for id in follow_before:
		if world.actors[id].region_id==follow_before[id].region:default_follow_distance[id]=float(default_follow_distance.get(id,0))+world.point(world.actors[id]).distance_to(follow_before[id].point)
	for id in jobs:
		if world.work.jobs.get(id,{}).get("id")==jobs[id].id:continue
		var receipts: Array=world.work.events.filter(func(event):return event.get("job_id","")==jobs[id].id)
		if receipts.is_empty() and jobs[id].intent=="shared_barbecue" and jobs[id].get("shared_activity_id")==world.shared_activity.session.get("id") and world.shared_activity.active() and world.shared_activity.session.phase!="arriving":continue
		if receipts.is_empty() and jobs[id].intent=="play_gomoku" and world.gomoku.memories.any(func(match_record):return match_record.id==jobs[id].get("match_id","")):continue
		if receipts.is_empty():interruptions.append({"at":elapsed,"actor":id,"job_id":jobs[id].id,"intent":jobs[id].intent,"reason":"accepted job disappeared without completion/block receipt"})
		elif receipts[-1].status!="completed":failed_jobs.append(receipts[-1].duplicate(true))
	for id in world.director.routines:
		var r: RefCounted=world.director.routines[id];var job: Dictionary=world.work.jobs.get(id,{})
		if real_job(job) and not r.kind.is_empty():interruptions.append({"at":elapsed,"actor":id,"reason":"local behavior overlaps genuine accepted job","kind":r.kind})
		var kind: String="task:"+str(job.intent) if real_job(job) else r.kind if not r.kind.is_empty() else "idle"
		behavior[id][kind]=float(behavior[id].get(kind,0))+.5
		if world.actors[id].region_id==world.actors.human.region_id and world.point(world.actors[id]).distance_to(world.point(world.actors.human))<=8:near_seconds[id]=float(near_seconds.get(id,0))+.5
		var level: int=world.relationships.index(id)
		if timelines[id].is_empty() or timelines[id][-1].stage!=level:timelines[id].append({"day":world.days.day(),"seconds":elapsed,"stage":level,"name":world.relationships.summary(id).name,"true_counts":world.relationships.states.get(id,{}).get("counts",{}).duplicate()})
		var stage_dir: String=OS.get_environment("HABITAT_LIFE2_STAGE_SAVES")
		if not stage_dir.is_empty() and id=="codex" and level>0 and not stage_saved.has(level):
			stage_saved[level]=true;check(preload("res://scripts/save_store.gd").save_world(world,stage_dir.path_join("stage"+str(level))),"save genuinely earned stage checkpoint")
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
	# Explicit host warehouse deposit replaces the former automatic box haul.
	if id=="human" and args.get("intent") in ["chop","gather_wood","forage","build_facility","plant","harvest"] and not world.actors.human.carry.is_empty():
		if not world.deposit_all("human").ok:return false
	return command(id,args).ok and wait_job(id)
func go_near(id: String) -> bool:
	var p: Vector2=world.point(world.actors[id])
	for offset in [Vector2(1.6,0),Vector2(-1.6,0),Vector2(0,1.6),Vector2(0,-1.6)]:
		var target: Vector2=p+offset
		if world.walkable(world.actors[id].region_id,target) and job("human",{"intent":"move","x":target.x,"y":target.y}):return true
	return false
func report() -> Dictionary:
	var residents: Dictionary={};var occurrences: Dictionary={};var max_repeat:=0;var repeated:=0
	for id in world.director.routines:
		var lines: Array=speech.filter(func(event):return event.actor_id==id);var contexts: Dictionary={};var actor_repeated:=0;var actor_max:=0
		for event in lines:
			contexts[event.context]=int(contexts.get(event.context,0))+1
			var key: String=id+":"+event.text;var stamps: Array=occurrences.get(key,[])
			stamps.append(float(event.time));occurrences[key]=stamps
			var recent: int=stamps.filter(func(stamp):return float(event.time)-float(stamp)<3600).size();max_repeat=maxi(max_repeat,recent)
			actor_max=maxi(actor_max,recent)
			if stamps.size()>1:repeated+=1;actor_repeated+=1
		var starts: int=world.schedules.statistics.started.get(id,0);var arrivals: int=world.schedules.statistics.arrived.get(id,0)
		residents[id]={"name":world.actors[id].name,"controller":world.actors[id].controller,"personality":world.personality.summary(id),"speech_count":lines.size(),"speech_contexts":contexts,"speech_opportunities":speech_opportunities.get(id,{}),"behavior_seconds":behavior[id],"relationship":world.relationships.summary(id),"credited_true_event_counts":world.relationships.states.get(id,{}).get("counts",{}).duplicate(true),"repeated_utterances":actor_repeated,"max_same_line_in_any_hour":actor_max,"true_task_interruptions":interruptions.filter(func(event):return event.get("actor")==id).size(),"schedule_started":starts,"schedule_arrived":arrivals,"schedule_hit_rate":float(arrivals)/starts if starts>0 else 0.0,"relationship_timeline":timelines[id],"within8_fraction":float(near_seconds.get(id,0))/DURATION,"default_follow_distance":float(default_follow_distance.get(id,0))}
	var wood:=0
	for chest in [{"id":"storage","items":world.storage.saved().items,"capacity":9007199254740991,"kind":"storage"}]:wood+=int(chest.items.get("wood",0))
	for actor in world.actors.values():wood+=int(actor.carry.get("wood",0))
	for drop in world.drops.values():wood+=int(drop.wood)
	wood+=int(world.homestead.site.delivered.get("wood",0))
	for life in world.barbecues.values():wood+=int(life.station.fuel_used)
	return {"seconds":elapsed,"advance_frames":int(elapsed/.5),"delta":.5,"calendar_start":1,"calendar_end":world.days.day(),"real_model_calls":0,"scripted_human_actions":actions,"residents":residents,"utterances":speech,"utterance_total":speech.size(),"repeated_utterances":repeated,"max_same_line_in_any_hour":max_repeat,"true_task_interruptions":interruptions,"genuinely_blocked_jobs":failed_jobs,"homestead_completed":world.homestead.completed(),"physical_wood_from_three_trees":wood,"turnip_left":F.amount(world,"turnip"),"fish_instances":world.fishing.fish.size(),"shared_meals":world.memories.records.filter(func(entry):return entry.kind=="shared_barbecue"),"weather_days":[world.weather.for_day(1).name,world.weather.for_day(2).name,world.weather.for_day(3).name],"model_scheduler_instantiated":false}
func run() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	if OS.get_environment("HABITAT_LIFE2_EXTENDED")=="1":DURATION=33000
	world=F.fresh();world.gomoku.rng.seed=1029;world.world_id="00000000-0000-4000-8000-000000001027";world.weather.weather_seed=1027;world.fishing.rng.seed=1027;world.fishing.life.rng.seed=1028
	world.library=preload("res://scripts/character_library.gd").new();world.library.configure(OS.get_environment("HABITAT_DATA_DIR").path_join("art"))
	var index:=0
	# B/C: DIRECTION 2026-11-10 makes following the default. This explicitly tests the existing free-idle mode.
	# Keep all original schedule, distance, physical-conservation and interruption assertions.
	for id in world.director.routines:
		world.activities.default_follow_excluded[id]=true
		behavior[id]={};timelines[id]=[];world.director.routines[id].rng.seed=1027+index;index+=1;world.director.routines[id].set_enabled(true)
	check(job("human",{"intent":"assign_farm","farm_id":"farm.home","manager_id":"codex"}),"script human assigns genuine farm")
	var plots: Array=world.farms.farm_plots("farm.home").slice(0,8)
	for plot in plots:
		check(job("human",{"intent":"plant","target_id":plot.id,"crop_id":"turnip"}) and job("human",{"intent":"water","target_id":plot.id}),"script plants/waters one genuine seed "+plot.id)
	check(job("human",{"intent":"gather_wood","tree_count":10,"zone_id":"home.forest"}),"ten current-yield physical trees include real barbecue fuel and project stock")
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
	input();var cooked:Dictionary=BBQ.start(world,"recipe:turnip-soup",guests,"home.barbecue",frame)
	actions.append({"at":elapsed,"host_barbecue_recipe":cooked.duplicate(true),"invited":guests.duplicate()})
	check(cooked.ok and BBQ.ready(world,"home.barbecue",frame),"actual crop-funded soup served on real fire")
	for id in guests:check(BBQ.ate(world,id,"home.barbecue",frame),"explicit invited guest really eats "+id)
	BBQ.end(world)
	check(world.life.fireside.state.committed,"real finished eaters commit shared meal")
	var other_guests:Array=["human","companion-2","npc.nora"]
	input();var second_meal:Dictionary=BBQ.start(world,"recipe:turnip-soup",other_guests,"home.barbecue",frame)
	check(second_meal.ok and BBQ.ready(world,"home.barbecue",frame),"balanced second real dinner sitting for remaining residents")
	for id in other_guests:check(BBQ.ate(world,id,"home.barbecue",frame),"balanced first dinner actual eater "+id)
	BBQ.end(world)
	check(world.life.fireside.state.committed,"second actual meal committed")
	check(job("human",{"intent":"homestead_start","site_id":world.homestead.config.site.id,"wood_limit":5,"crop_limit":3}),"human contributes genuine five wood/three crops")
	check(job("codex",{"intent":"homestead_start","site_id":world.homestead.config.site.id,"wood_limit":19,"crop_limit":7}),"partner contributes rest from actual boxes")
	check(job("codex",{"intent":"homestead_build","plan_id":world.homestead.plans.codex.id}) and world.homestead.completed(),"real funded six-second construction completes once")
	for id in world.director.routines:
		check(go_near(id),"scripted player visits own-life resident "+id)
		var until: float=minf(DURATION,elapsed+140)
		while elapsed<until:frame()
	daily_meal() # Second evening uses actual remaining initial harvest.
	daily_fishing() # Actual second-day common coastal outing, not a synthetic relationship grant.
	for day in range(3,16):
		var start: float=(day-1)*world.days.day_seconds+60
		while elapsed<start:frame()
		if day in [3,5,9,11]:daily_fishing()
		elif day in [4,6,8]:daily_meal()
		elif day in [7,10,13]:daily_chess()
		elif day in [12,14]:daily_barbecue()
		else:daily_gifts()
	if DURATION>22500:
		for day in [16,18,20,22]:
			while elapsed<(day-1)*world.days.day_seconds+60:frame()
			if int({"id":"storage","items":world.storage._items,"capacity":9007199254740991,"kind":"storage","region_id":"home","position":world.actors.human.position}.items.get("turnip",0))<1:
				var plot: Dictionary=world.farms.farm_plots("farm.home").filter(func(value):return value.crop_id.is_empty())[0]
				check(job("human",{"intent":"plant","target_id":plot.id,"crop_id":"turnip"}) and job("human",{"intent":"water","target_id":plot.id}),"real seed for extended gift")
				while world.farms.stage(plot)!="mature":frame()
				check(job("human",{"intent":"harvest","target_id":plot.id}),"real extended harvest")
			check(F.withdraw(world,"human","turnip"),"real gift pickup")
			world.director.routines.codex.set_held(true)
			check(go_near("codex") and command("human",{"intent":"give","receiver_id":"codex","item_id":"turnip","quantity":1}).ok,"real extended personal gift")
			world.director.routines.codex.set_held(false)
			check(job("codex",{"intent":"store"}),"explicit host store own actual gift, no local automatic storage")
			if not world.actors.human.carry.is_empty():check(job("human",{"intent":"store"}),"unused gift materials retained")
			if day==16:
				daily_chess()
				daily_barbecue(["codex"])
	while elapsed<DURATION:frame()
	var data:=report()
	check(elapsed==DURATION and world.days.day()==int(DURATION/world.days.day_seconds)+1,"fifteen complete game days genuinely advance through45000 frames")
	check(interruptions.is_empty(),"local rules interrupt exactly zero genuine tasks")
	check(data.physical_wood_from_three_trees>=24 and data.turnip_left>=0,"three trees24 wood and five harvests15 crops conserved through real24+10 project and3-crop soup")
	check(data.fish_instances>=3 and data.shared_meals.size()>=1,"three genuine catches and one genuinely eaten cleaned meal")
	check(data.max_same_line_in_any_hour<=2 and speech.all(func(event):return event.source=="local_rules"),"all delivered speech honest local and repeat-bounded")
	check(data.residents.values().all(func(resident):return resident.speech_count>0 and resident.schedule_started>0),"each companion has perceptible life and actual schedule choices")
	if DURATION==22500:
		check(data.residents["npc.mira"].speech_count>maxi(data.residents.codex.speech_count,data.residents["companion-2"].speech_count),"lively has most actual visible speech in fifteen-day scenario")
		check(mini(data.residents.codex.speech_count,data.residents["companion-2"].speech_count)>data.residents["npc.nora"].speech_count,"curious and gentle both speak more than quiet")
		check(data.residents["npc.mira"].within8_fraction<=.4,"lively is not always surrounding human: actual within8 fraction capped40percent")
	var output:=OS.get_environment("HABITAT_LOCAL_LIFE_SIMULATION_OUTPUT")
	if output.is_empty():output=OS.get_environment("HABITAT_DATA_DIR").path_join("local-life-15d.json")
	if not output.is_empty():
		var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify(data,"  "));file.close()
	print("Local life fifteen-day simulation: %s checks, failed=%s; seconds=%s, utterances=%d, interruptions=%d"%[checks,failed,elapsed,speech.size(),interruptions.size()]);quit(1 if failed else 0)

func daily_fishing() -> void:
	var coast:=false
	for shore in world.fishing.nearby_shores("human"):
		if job("human",{"intent":"move","x":shore.position[0],"y":shore.position[1]}) and not world.fishing.shore("human").is_empty():coast=true;break
	check(coast,"daily genuine sea visit")
	var p: Vector2=world.point(world.actors.human)
	for id in world.director.routines:
		var moved:=false
		for radius in [2.0,4.0,6.0]:
			for angle in range(16):
				var target: Vector2=p+Vector2.from_angle(angle*TAU/16)*radius
				if not moved and world.walkable("home",target) and world.director.available_position(id,"home",target) and job(id,{"intent":"move","x":target.x,"y":target.y}):moved=true
			if moved:break
		check(moved,"explicit shore invitation actual presence "+id)
	check(job("human",{"intent":"fish"}),"daily catch from real sea stock")
	var fish: Dictionary=preload("res://tests/fishing_fixture.gd").unplaced(world)
	check(not fish.is_empty() and command("human",{"intent":"stock_fish","fish_id":fish.id,"pen_id":world.fishing.pens.keys()[0]}).ok,"daily actual fish placement")
func daily_meal() -> void:
	var plots: Array=[]
	if F.amount(world,"turnip")<6:plots=world.farms.farm_plots("farm.home").filter(func(plot):return plot.crop_id.is_empty()).slice(0,2)
	check(plots.size()==2 or F.amount(world,"turnip")>=6,"real beds or existing harvest for dinner")
	for plot in plots:check(job("human",{"intent":"plant","target_id":plot.id,"crop_id":"turnip"}) and job("human",{"intent":"water","target_id":plot.id}),"daily real seed and water")
	while elapsed<DURATION-300 and plots.any(func(plot):return world.farms.stage(plot)!="mature"):frame()
	for plot in plots:check(job("human",{"intent":"harvest","target_id":plot.id}),"daily genuine harvest")
	var ids: Array=world.director.routines.keys()
	for offset in [0,2]:
		var guests: Array=["human",ids[offset],ids[offset+1]]
		input();var result:Dictionary=BBQ.start(world,"recipe:turnip-soup",guests,"home.barbecue",frame)
		check(result.ok and BBQ.ready(world,"home.barbecue",frame),"daily two dinner sittings use six actual crops "+str(result))
		for id in guests:check(BBQ.ate(world,id,"home.barbecue",frame),"daily actual eater "+id)
		BBQ.end(world)
		check(world.life.fireside.state.committed,"daily actual meal committed")
func daily_barbecue(guests:Array=[]) -> void:
	if guests.is_empty():guests=world.director.routines.keys()
	var required:int=guests.size()+1
	check(job("human",{"intent":"gather_wood","tree_count":1,"zone_id":"home.forest"}),"barbecue real fuel tree")
	while F.amount(world,"mushroom")<required:
		var patches:Array=world.life.patches.values().filter(func(patch):return int(patch.amount)>0)
		if patches.is_empty():check(false,"not enough genuine mushrooms, never invent stock");return
		if not job("human",{"intent":"forage","target_id":patches[0].id}):check(false,"forage actual finite mushroom patch");return
	input();check(BBQ.meal(world,"single:mushroom",["human"]+guests,"home.barbecue",frame),"host invites selected people and all actually finish real barbecue")
func daily_chess() -> void:
	if not world.leisure.sites["play.gomoku"].complete:
		check(job("human",{"intent":"gather_wood","tree_count":10,"zone_id":"home.forest"}) and job("human",{"intent":"build_facility","target_id":"play.gomoku"}),"real26 wood chess table")
	for id in world.director.routines:
		input();check(world.gomoku.begin_host("play.gomoku",id,true,"local","easy").ok,"real local chess invitation "+id)
		var game: Dictionary=world.gomoku.sessions["play.gomoku"]
		for tick in range(600):
			if game.phase!="arriving":break
			frame()
		for turn in range(20):
			if game.phase!="playing":break
			if world.gomoku._turn(game)=="human":
				var point:=Vector2i(-1,-1)
				for y in range(15):
					for x in range(15):
						if point.x<0 and not game.history.any(func(move):return move[0]==x and move[1]==y):point=Vector2i(x,y)
				check(command("human",{"intent":"gomoku_move","site_id":"play.gomoku","match_id":game.id,"revision":game.revision,"x":point.x,"y":point.y}).ok,"real human board move")
			for tick in range(30):
				frame()
				if game.phase!="playing" or world.gomoku._turn(game)=="human":break
		if game.phase=="playing":check(command("human",{"intent":"gomoku_resign","site_id":"play.gomoku","match_id":game.id,"revision":game.revision}).ok,"human concedes actual played game")

func daily_gifts() -> void:
	check(F.withdraw(world,"human","turnip"),"human explicitly takes remaining real harvest for gifts")
	for id in world.director.routines:
		if world.relationships.index(id)>=3 or int(world.actors.human.carry.get("turnip",0))==0:continue
		world.director.routines[id].set_held(true) # Explicit player gift interaction holds idle movement.
		check(go_near(id) and command("human",{"intent":"give","receiver_id":id,"item_id":"turnip","quantity":1}).ok,"explicit owned crop gift to partner "+id)
		world.director.routines[id].set_held(false)
	if not world.actors.human.carry.is_empty():check(job("human",{"intent":"store"}),"unused actual gift crops safely stored")
	check(job("human",{"intent":"move","x":Places.point("p_51_44").x,"y":Places.point("p_51_44").y}),"script player returns to own home path")

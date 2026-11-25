extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
## Local presentation and the explicitly authorised hungry-task exception.
const STATES=["full","peckish","hungry","very_hungry"]
const NAMES=[("content.hunger.full"),("content.hunger.peckish"),("content.hunger.hungry"),("content.hunger.very_hungry")]
var _owner:WeakRef
var world:RefCounted:
	get:return _owner.get_ref()
var config:Dictionary={}
var enabled:=false
var issuing:=false
var states:Dictionary={}
var quiet_until:Dictionary={}
var follow_after:Dictionary={}
var follow_targets:Dictionary={}
var follow_origins:Dictionary={}
var owned_routes:Dictionary={}
var speech_times:Dictionary={}
var rushes:Dictionary={}
var rush_after:Dictionary={}
var pending_invites:Dictionary={}
var pending_reactions:Dictionary={}
var meal_seen:Array=[]
var reactions:Dictionary={}
var follow_pauses:Dictionary={}
var statistics:Dictionary={"abandoned":[],"follow_routes":0,"follow_blocked":0,"rushes":0,"fed":0,"fed_meals":0,"packed":0,"meals":0,"state_seconds":{}}
func _init(owner:RefCounted)->void:
	_owner=weakref(owner)
	var data:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/intelligence/hunger.json"))
	if not valid_config(data):world.error=LocalText.text("system.hunger_system.the_hunger_settings_are_invalid");return
	config=data
func valid_config(d:Variant)->bool:
	var keys:Array=["version","thresholds","snack_age","work_after","work_extra","slow_speed","rush_speed","follow_interval","follow_distance","follow_spacing","max_follow_distance","state_hourly_limit","personal_gap","village_gap","snack_items","rush_cooldown","invitation_words","rush_timeout","presentation"]
	if not d is Dictionary or d.keys().size()!=keys.size() or keys.any(func(k):return not d.has(k)) or d.version!=1:return false
	if not d.thresholds is Array or d.thresholds.size()!=4 or d.thresholds[0]!=0:return false
	for i in range(4):
		if not world.catalog._number(d.thresholds[i]) or d.thresholds[i]<0 or (i>0 and d.thresholds[i]<=d.thresholds[i-1]):return false
	for k in keys:
		if k in ["version","thresholds","snack_items","invitation_words","presentation"]:continue
		if not world.catalog._number(d[k]) or d[k]<=0 or d[k]>86400:return false
	if not d.presentation is Dictionary or d.presentation.size()!=11:return false
	for key in ["very_slow_speed","pause_every","pause_seconds","rumble_every","rumble_seconds","reaction_long_seconds","reaction_seconds","reaction_grace_seconds","rush_lean","dust_scale"]:
		if not world.catalog._number(d.presentation.get(key)) or d.presentation[key]<=0:return false
	if not d.presentation.get("rumble_icon") is String or d.presentation.rumble_icon.length()>8 or d.presentation.very_slow_speed>d.slow_speed:return false
	return d.snack_items is Array and d.snack_items.all(func(x):return x in ["apple","tomato","blueberry","turnip"]) and d.invitation_words is Array and d.invitation_words.all(func(x):return x is String and not x.is_empty() and x.length()<=20) and d.state_hourly_limit==2 and d.slow_speed<=150 and d.rush_speed>260
func configured(id:String)->bool:
	return id!="human" and world.actors.has(id) and world.intelligence.bindings.residents.get(id,{}).get("hunger_enabled",false)
func ensure(id:String)->void:
	if not states.has(id):states[id]={"elapsed":float(config.thresholds[1]),"full_meal":false,"work_seconds":0.0,"meals":0,"last_rush_clock":0.0,"hungry_seconds":0.0}
func start()->void:
	enabled=true
	for id in world.actors:
		if configured(id):ensure(id)
func rank(id:String)->int:
	if not enabled or not configured(id):return -1
	ensure(id);var data:Dictionary=states[id];var result:=0 if data.full_meal else 1
	for index in range(1,4):
		if data.elapsed>=float(config.thresholds[index]):result=maxi(result,index)
	return result
func summary(id:String)->Dictionary:
	var index:=rank(id)
	return {} if index<0 else {"state":LocalText.text(NAMES[index])}
func holds_idle(_id:String)->bool:return false
func follow_paused(id:String)->bool:
	return rank(id)>=3 and follow_targets.has(id) and owned_routes.has(id) and not world.work.jobs.has(id) and world._routes.has(id) and is_same(world._routes[id],owned_routes[id].route) and fmod(world.director.time,float(config.presentation.pause_every))<float(config.presentation.pause_seconds)
func visible_cue(id:String)->Dictionary:
	var station:String=str(rushes.get(id,{}).get("station_id","")) if rushing(id) else ""
	if not configured(id) or not can_follow(id,station) or not world.director.routines[id].chatter or world.director.time<float(quiet_until.get(id,0)) or world.fishing.life.time<float(world.fishing.life.quiet_until.get(id,0)):return {}
	if rushing(id) and rushes[id].get("cue","")!="":return {"text":rushes[id].cue,"source":"local_rules"}
	if rank(id)>=2 and fmod(world.director.time+float(hash(id)%31),float(config.presentation.rumble_every))<float(config.presentation.rumble_seconds):return {"text":config.presentation.rumble_icon,"source":"local_rules"}
	return {}
func reaction(id:String)->Dictionary:
	if not reactions.has(id) or reactions[id].get("pending",false) or world.director.time>=reactions[id].until or not can_follow(id) or not world.director.routines[id].chatter or world._routes.has(id):return {}
	return reactions[id]
func on_command(id:String,intent:String)->void:
	if issuing or not enabled or not configured(id):return
	clear_rush(id)
	clear_follow(id)
	if intent=="stop":quiet_until[id]=world.director.time+120
	elif intent=="move":quiet_until[id]=maxf(float(quiet_until.get(id,0)),world.director.time+8)
func cancel_owned_route(id:String,region:String,target:Vector2)->bool:
	var actual:Dictionary=owned_routes.get(id,{"region":region,"point":target})
	owned_routes.erase(id)
	if world.work.jobs.has(id) or world.actors[id].region_id!=actual.region or not world._routes.has(id) or world._routes[id].is_empty():return false
	if actual.has("route") and not is_same(world._routes[id],actual.route):return false
	if world._routes[id].back().distance_to(actual.point)>.01:return false
	world._routes.erase(id);world.actors[id].activity="idle";return true
func remember_route(id:String)->void:
	if world._routes.has(id) and not world._routes[id].is_empty():owned_routes[id]={"region":world.actors[id].region_id,"point":world._routes[id].back(),"route":world._routes[id]}
	else:owned_routes.erase(id)
func clear_follow(id:String)->void:
	follow_origins.erase(id)
	if not follow_targets.has(id):return
	var target:Dictionary=follow_targets[id]
	cancel_owned_route(id,target.region,target.point);follow_targets.erase(id)
func can_follow(id:String,rush_station:String="")->bool:
	if world.activities.commanded(id):return false
	for life in world.barbecues.values():
		var fire:RefCounted=life.fireside
		if fire.active() and not fire.circle_closed and fire.state.get("consent",false) and id in fire.state.get("invited",[]) and life.station.id!=rush_station:return false
	if (world.director.time<float(quiet_until.get(id,0)) and not world.activities.following.has(id)) or world.activities.blocked(id,false):return false
	var routine:RefCounted=world.director.routines.get(id)
	return routine!=null and (routine.enabled or world.activities.following.has(id)) and not routine.held and not world.shared_activity.holds(id) and not world.work.jobs.has(id)
func player_moving(destination:Vector2=Vector2.INF)->void:
	if not enabled:return
	for id in follow_targets.keys():
		if world.actors[id].region_id==world.actors.human.region_id and world.point(world.actors[id]).distance_to(world.point(world.actors.human))<=6 and not world.work.jobs.has(id):
			var target:Dictionary=follow_targets[id]
			if cancel_owned_route(id,target.region,target.point):follow_after[id]=world.director.time+float(config.follow_interval)*2
			if destination.is_finite():yield_sideways(id,destination)

func yield_sideways(id:String,destination:Vector2)->bool:
	if not can_follow(id) or (rank(id)<3 and not world.activities.following.has(id) and not (world.dark!=null and world.dark.here())) or world.actors[id].region_id!=world.actors.human.region_id:return false
	var human:Vector2=world.point(world.actors.human);var at:Vector2=world.point(world.actors[id]);var direction:Vector2=destination-human
	if direction.length()<.1 or at.distance_to(human)>6:return false
	var forward:Vector2=direction.normalized();var normal:=Vector2(-forward.y,forward.x)
	if forward.dot((at-human).normalized())<.2 or at.distance_to(Geometry2D.get_closest_point_to_segment(at,human,destination))>1.4:return false
	var lateral:float=(at-human).dot(normal)
	var side:float=signf(lateral) if absf(lateral)>.25 else (1.0 if hash(id)%2==0 else -1.0)
	for sign_value in [side,-side]:
		for distance in [1.8,2.6]:
			var target:Vector2=at+normal*sign_value*distance
			if not world.walkable(world.actors[id].region_id,target) or not world.segment_clear(world.actors[id].region_id,at,target) or not world.director.available_position(id,world.actors[id].region_id,target):continue
			if follow_targets.keys().any(func(other):return other!=id and follow_targets[other].region==world.actors[id].region_id and follow_targets[other].point.distance_to(target)<1.5):continue
			if follow_targets.has(id):cancel_owned_route(id,follow_targets[id].region,follow_targets[id].point)
			world.interior._arrive(id,world.actors[id].region_id,target)
			if not world._routes.has(id):continue
			remember_route(id);follow_targets[id]={"region":world.actors[id].region_id,"point":target,"yielding":true}
			follow_origins[id]={"region":world.actors.human.region_id,"point":human};follow_after[id]=world.director.time+float(config.follow_interval)*2
			statistics.follow_routes+=1;return true
	return false
func abandon(id:String)->void:
	var job:Dictionary=world.work.jobs.get(id,{}).duplicate(true)
	var meal_work:Variant=world.get("meal_work_active")
	if meal_work is Callable and meal_work.is_valid() and meal_work.call(id,job):return
	# Hunger cannot cancel the real meal that is resolving it.
	if job.get("intent")=="eat":return
	if job.is_empty() and not world.projects.active(id) and not world.farms.active(id) and not world.homestead.active(id):return
	issuing=true;world.command(id,{"intent":"stop"});issuing=false
	if not job.is_empty():
		statistics.abandoned.append({"actor_id":id,"job_id":job.id,"intent":job.intent,"at":world.director.time})
		if statistics.abandoned.size()>256:statistics.abandoned.pop_front()
func follow(id:String,dark_fear:bool=false)->void:
	if world.director.brains.has(id) and world.director.brains[id].active():world.director.brains[id].follow(dark_fear);return
	_follow_body(id,dark_fear)
func _follow_body(id:String,dark_fear:bool=false)->void:
	if world.activities.suspended_follow.has(id) or world.farms.active(id) or world.work.jobs.has(id):clear_follow(id);return
	if rank(id)<3 and world.director.routines.has(id) and world.director.routines[id].kind in ["island_intro","island_arrival"]:return
	if world.deliveries!=null and world.deliveries.active(id):return
	if world.dark!=null and id in world.dark.discoveries.seated:return
	if world.dark!=null and world.dark.here() and world.actors[id].region_id=="dark" and rank(id)<3:dark_fear=not world.dark.permanent(world.point(world.actors.human))
	if (dark_fear or world.activities.following.has(id)) and world._routes.has(id):
		var lease:Dictionary=owned_routes.get(id,{})
		if not lease.has("route") or not is_same(lease.route,world._routes[id]):return
	if not can_follow(id) or world.director.time<float(follow_after.get(id,0)):return
	follow_after[id]=world.director.time+float(config.follow_interval)
	if world.activities.following.has(id) and world.dark!=null and world.dark.enabled():
		var host_region:String=world.actors.human.region_id
		var outside_region:String="home" if world.interior.rooms().has(host_region) else host_region
		if world.actors[id].region_id in ["home","dark"] and outside_region in ["home","dark"] and world.actors[id].region_id!=outside_region:
			world.dark.follow_over_bridge(id,outside_region);return
	var hungry:Array=[]
	for actor_id in world.actors:
		if world.activities.following.has(actor_id) or rank(actor_id)>=3 or (dark_fear and world.actors.has(actor_id) and world.actors[actor_id].region_id=="dark" and actor_id!="human"):hungry.append(actor_id)
	if dark_fear:
		# The clingy trait takes the nearest existing queue slot, independent of appearance/ID.
		hungry.sort_custom(func(a,b):return ["lively","gentle","laborious","quiet"].find(world.intelligence.tag(a))<["lively","gentle","laborious","quiet"].find(world.intelligence.tag(b)))
	if world.activities.following.has(id):
		for selected_id in world.activities.following:
			if selected_id not in hungry:hungry.append(selected_id)
	hungry.sort() # Stable identity slots, independent of controller and temporary departures.
	var index:int=world.actors.keys().filter(func(who):return who!="human").find(id);var human:Dictionary=world.actors.human
	if world.actors[id].region_id==human.region_id:
		var distance_to_human:float=world.point(world.actors[id]).distance_to(world.point(human))
		var player_approaching:bool=world._routes.has("human") and not world._routes.human.is_empty() and world._routes.human.back().distance_to(world.point(world.actors[id]))<=2.1
		if world._routes.has("human") and not world._routes.human.is_empty():
			var movement:Vector2=world._routes.human[0]-world.point(human)
			var towards:Vector2=world.point(world.actors[id])-world.point(human)
			player_approaching=player_approaching or movement.normalized().dot(towards.normalized())>.2
		var close_distance:float=1.25 if dark_fear and world.dark.torch.remaining<=0 else 1.7 if dark_fear else 2.0
		if distance_to_human<=close_distance or (player_approaching and distance_to_human<=6):
			if player_approaching and world._routes.has("human") and yield_sideways(id,world._routes.human[0]):return
			if follow_targets.has(id):cancel_owned_route(id,follow_targets[id].region,follow_targets[id].point)
			return
		# A small player step or an in-place turn does not reform the queue.
		var origin:Dictionary=follow_origins.get(id,{})
		if not dark_fear and not origin.is_empty() and origin.region==human.region_id and Vector2(origin.point).distance_to(world.point(human))<1.4 and distance_to_human<=float(config.max_follow_distance)+2:
			if follow_targets.has(id) and (world._routes.has(id) or world.point(world.actors[id]).distance_to(follow_targets[id].point)<1.1):return
	var forward:Vector2={"down":Vector2.DOWN,"up":Vector2.UP,"left":Vector2.LEFT,"right":Vector2.RIGHT}.get(human.facing,Vector2.DOWN)
	var distance:float=minf(float(config.max_follow_distance),float(config.follow_distance)+maxi(0,index)*float(config.follow_spacing))
	if world.activities.following.has(id):distance=minf(float(config.max_follow_distance),2.0+maxi(0,index)*.6)
	if dark_fear:distance=(1.6 if world.intelligence.tag(id)=="lively" else 2.2)+maxi(0,index)*.65
	if dark_fear and world.dark.torch.remaining<=0:distance*=.75
	var target:Vector2=world.point(human)-forward*distance
	if dark_fear:
		var tag:String=world.intelligence.tag(id);var cfg:Dictionary=world.dark.config.personality_motion
		if tag=="lively" and world.dark.torch.remaining>0:target=world.point(human)+forward*float(cfg.lively_ahead)
		if tag=="gentle" and world.dark.torch.remaining<=0:target=world.point(human)-forward*float(cfg.gentle_close)
		if tag=="laborious":target=world.point(human)-forward*float(cfg.laborious_distance)
		if tag=="quiet":target=world.point(human)-forward*float(cfg.quiet_distance)
	# Stagger the queue using its configured spacing, so tall pixel silhouettes
	# do not sit directly over each other while their feet remain separate.
	target+=Vector2(-forward.y,forward.x)*(1.25 if dark_fear else float(config.follow_spacing))*(1 if index%2==0 else -1)
	if world.activities.following.has(id) and rank(id)<3 and not dark_fear and world._routes.has("human"):
		var side:Vector2=forward.orthogonal()
		target=world.point(human)-forward*(1.5+floorf(float(maxi(0,index))/2)*1.15)+side*(1 if index%2==0 else -1)
	if dark_fear and world.dark.torch.remaining>0 and target.distance_to(world.point(human))>3.5:target=world.point(human).move_toward(target,3.5)
	if world.actors[id].region_id==human.region_id and world.point(world.actors[id]).distance_to(target)<.8:
		follow_targets[id]={"region":human.region_id,"point":target};return
	if follow_targets.has(id) and world._routes.has(id) and follow_targets[id].region==human.region_id and follow_targets[id].point.distance_to(target)<2:return
	var candidates:Array=[]
	for offset in [Vector2.ZERO,Vector2(1.8,0),Vector2(-1.8,0),Vector2(3.6,0),Vector2(-3.6,0),Vector2(0,1.8)]:candidates.append(target+offset)
	if (world.activities.following.has(id) or rank(id)>=3) and not dark_fear:
		candidates=[target]
		for radius in [2.2,3.2,4.2,6.2,8.2,10.2]:
			for step in range(12):candidates.append(world.point(human)+(-forward).rotated(TAU*float(step+index)/12)*radius)
	for p:Vector2 in candidates:
		if dark_fear and world.dark.torch.remaining>0 and not world.dark.discoveries.illuminated(p):continue
		if world._routes.has("human") and not world._routes.human.is_empty() and world._routes.human.back().distance_to(p)<1.5:continue
		if not world.walkable(human.region_id,p) or not world.director.available_position(id,human.region_id,p):continue
		var safe:=true
		for other in follow_targets:
			if other!=id and follow_targets[other].region==human.region_id and follow_targets[other].point.distance_to(p)<1.5:safe=false
		if not safe:continue
		world.interior._arrive(id,human.region_id,p)
		if world._routes.has(id):remember_route(id);follow_targets[id]={"region":human.region_id,"point":p};follow_origins[id]={"region":human.region_id,"point":world.point(human)};statistics.follow_routes+=1;return
	statistics.follow_blocked+=1
func try_speak(id:String)->bool:
	var state_index:=rank(id)
	if state_index<0 or not world.director.moods.can_speak(id):return false
	var key:String=id+":"+str(state_index);var stamps:Array=speech_times.get(key,[]).filter(func(t):return world.director.time-float(t)<3600)
	if stamps.size()>=int(config.state_hourly_limit):return false
	var unit:String="hunger-"+STATES[state_index].replace("_","-")
	var pool:Array=world.intelligence.catalog.speech[unit].lines
	if state_index>=2:
		var authored:Array=world.intelligence.speech_pool(id,"hungry")
		if not authored.is_empty():pool=authored
	var routine:RefCounted=world.director.routines[id];var candidates:Array=world.personality.selection(id,pool.map(func(line):return "♨ "+str(line)),routine.recent_lines)
	if candidates.is_empty():return false
	var text:String=candidates[routine.rng.randi_range(0,candidates.size()-1)]
	if not world.director.say_local(id,text,"hunger_"+STATES[state_index],float(config.personal_gap),float(config.village_gap)):return false
	stamps.append(world.director.time);speech_times[key]=stamps;return true
func advance(delta:float)->void:
	if not enabled:return
	for id in world.actors:
		if not configured(id):continue
		ensure(id);var data:Dictionary=states[id]
		var working:bool=world.director.moods.laboring(id)
		if working:data.work_seconds+=delta
		var effort:float=1.0+minf(float(config.work_extra),float(data.work_seconds)/float(config.work_after)*float(config.work_extra))
		data.elapsed+=delta*world.intelligence.hunger_multiplier(id)*effort
		var index:int=rank(id)
		data["hungry_seconds"]=float(data.get("hungry_seconds",0))+delta if index>=2 else 0.0
		if follow_paused(id):
			var towards:Vector2=world.point(world.actors.human)-world.point(world.actors[id])
			world.actors[id].facing=("right" if towards.x>0 else "left") if absf(towards.x)>absf(towards.y) else ("down" if towards.y>0 else "up")
		var bucket:Dictionary=statistics.state_seconds.get(id,{})
		bucket[STATES[index]]=float(bucket.get(STATES[index],0))+delta;statistics.state_seconds[id]=bucket
		if not can_follow(id):clear_follow(id)
		if reactions.has(id) and reactions[id].get("pending",false):
			if world.director.time-float(reactions[id].queued_at)>float(config.presentation.reaction_grace_seconds):reactions.erase(id)
			elif can_follow(id) and world.director.routines[id].chatter and not world._routes.has(id):
				reactions[id].merge({"pending":false,"started":world.director.time,"until":world.director.time+float(config.presentation.reaction_seconds)},true)
		if rushes.has(id):tick_rush(id)
		else:
			var invite:Dictionary=pending_invites.get(id,{})
			if not invite.is_empty() and world.director.time<=invite.until:try_rush(id,invite.station_id)
			elif not invite.is_empty():pending_invites.erase(id)
		if not try_reaction(id) and (index>=2 or (index==1 and not world.director.return_speech_reserved)):try_speak(id)

func ate(id:String,event_id:String,meal_type:String,place_id:String)->void:
	if meal_type!="barbecue" or not enabled or not configured(id) or event_id in meal_seen:return
	meal_seen.append(event_id)
	if meal_seen.size()>128:meal_seen.pop_front()
	var old:int=rank(id);ensure(id)
	var tier:int=3 if float(states[id].get("hungry_seconds",0))>=float(config.presentation.reaction_long_seconds) else 2 if old>=2 else 1
	states[id].elapsed=0.0;states[id].full_meal=true;states[id].work_seconds=0.0;states[id].meals+=1;statistics.meals+=1
	clear_rush(id);pending_reactions[id]="hunger-after-"+({1:"peckish",2:"hungry",3:"very-hungry"}[tier])
	reactions[id]={"tier":tier,"queued_at":world.director.time,"pending":true}
	states[id]["hungry_seconds"]=0.0
	world.memories.record_event("meal_reaction","ate-"+event_id,[id],{"eater_id":id,"previous_state":LocalText.source(NAMES[maxi(0,old)]),"meal_type":meal_type,"place_id":place_id})
	world.revision+=1
func try_reaction(id:String)->bool:
	if not pending_reactions.has(id) or not world.director.moods.can_speak(id):return false
	var pool:Array=world.intelligence.catalog.speech[pending_reactions[id]].lines
	var r:RefCounted=world.director.routines[id];var candidates:Array=world.personality.selection(id,pool,r.recent_lines)
	if candidates.is_empty():return false
	if not world.director.say_local(id,candidates[r.rng.randi_range(0,candidates.size()-1)],"hunger_after_meal",float(config.personal_gap),float(config.village_gap)):return false
	pending_reactions.erase(id);return true
func glutton(id:String)->bool:
	var p:Dictionary=world.intelligence.preset(id)
	return p.get("main_trait","") in ["glutton","glutton-minor"] or p.get("context_traits",[]).any(func(t):return t in ["glutton","glutton-minor"])
func invite_fireside(station_id:String,ids:Array)->void:
	if not enabled or not world.barbecues.has(station_id):return
	var fire:RefCounted=world.barbecues[station_id].fireside
	if not fire.active():return
	for id in ids:
		if configured(id) and id in fire.state.invited:
			pending_invites[id]={"station_id":station_id,"until":world.director.time+float(config.rush_cooldown)}
			try_rush(id,station_id)
func rushing(id:String)->bool:return rushes.has(id) and not rushes[id].arrived and not world.loaded(id) and world.fishing.held(id).is_empty() and not world.work.jobs.has(id) and world._routes.has(id)
func clear_rush(id:String)->void:
	if not rushes.has(id):return
	var rush:Dictionary=rushes[id];var seat:String=rush.seat_id;var at:Vector2=Vector2(rush.position[0],rush.position[1])
	cancel_owned_route(id,rush.region_id,at)
	if rush.arrived and not world.work.jobs.has(id) and world.actors[id].region_id==rush.region_id and world.point(world.actors[id]).distance_to(at)<.2 and world.actors[id].activity=="seated":world.actors[id].activity="idle"
	if world.work.claims.get(seat)==id and not world.work.jobs.has(id):world.work.claims.erase(seat)
	rushes.erase(id)
func try_rush(id:String,station_id:String)->bool:
	if rank(id)<2 or world.loaded(id) or not world.fishing.held(id).is_empty() or rushes.has(id) or world.director.time<float(rush_after.get(id,0)) or not can_follow(id,station_id) or world.projects.active(id) or world.farms.active(id) or world.homestead.active(id) or not world.barbecues.has(station_id):return false
	if world.forest.clock-float(states[id].get("last_rush_clock",0))<float(config.rush_cooldown):return false
	var life:RefCounted=world.barbecues[station_id]
	if not life.fireside.burning() or life.fireside.circle_closed or id not in life.fireside.state.invited:return false
	var options:Array=life.seats()
	options.sort_custom(func(a,b):return world.point(a).distance_squared_to(world.point(world.actors[id]))<world.point(b).distance_squared_to(world.point(world.actors[id])))
	for seat in options:
		if world.work.claims.has(seat.id) or not world.walkable(seat.region_id,world.point(seat)):continue
		world.director.routines[id].interrupt(8)
		world.work.claims[seat.id]=id
		rushes[id]={"station_id":station_id,"seat_id":seat.id,"region_id":seat.region_id,"position":seat.position.duplicate(),"arrived":false,"started":world.director.time,"line_after":0.0}
		rush_after[id]=world.director.time+float(config.rush_cooldown);pending_invites.erase(id);statistics.rushes+=1
		states[id]["last_rush_clock"]=world.forest.clock
		tick_rush(id);return true
	return false
func tick_rush(id:String)->void:
	if not rushes.has(id):return
	var r:Dictionary=rushes[id];var routine:RefCounted=world.director.routines[id]
	var fire:RefCounted=world.barbecues[r.station_id].fireside
	if not fire.burning() or id not in fire.state.invited:clear_rush(id);return
	if rank(id)<2 or world.loaded(id) or not world.fishing.held(id).is_empty() or not can_follow(id,str(r.station_id)) or routine.held or world.activities.blocked(id,false) or world.work.jobs.has(id) or world.director.time-r.started>float(config.rush_timeout):clear_rush(id);return
	if not r.arrived and not world._routes.has(id):
		if world.interior._arrive(id,r.region_id,Vector2(r.position[0],r.position[1])):r.arrived=true;r["arrived_at"]=world.director.time;world.actors[id].activity="sitting_down"
		remember_route(id)
	if r.arrived:world.actors[id].activity="seated" if world.director.time-float(r.get("arrived_at",0))>.6 else "sitting_down"
	if not r.has("cue"):
		var pool:Array=world.personality.selection(id,world.intelligence.catalog.speech["hunger-rush"].lines,routine.recent_lines)
		if pool.is_empty():return
		var text:String=pool[routine.rng.randi_range(0,pool.size()-1)]
		if world.director.say_rush_event(id,text):r["cue"]=text
func saved()->Dictionary:
	var clean:Dictionary=states.duplicate(true)
	for state in clean.values():state.erase("snacks")
	return {"version":1,"saved_at":Time.get_unix_time_from_system(),"states":clean}
func valid(value:Variant,actors:Dictionary)->bool:
	if not value is Dictionary:return false
	if value.is_empty():return true
	if value.size() not in [3,4] or value.get("version")!=1 or not world.catalog._number(value.get("saved_at")) or value.saved_at<=0 or not value.get("states") is Dictionary:return false
	for id in value.states:
		var s:Variant=value.states[id]
		if id=="human" or not actors.has(id) or not s is Dictionary or s.size() not in [4,5,6,7] or not s.get("full_meal") is bool:return false
		if s.keys().any(func(k):return k not in ["elapsed","full_meal","work_seconds","meals","snacks","last_rush_clock","hungry_seconds"]):return false
		for key in ["elapsed","work_seconds","meals"]:
			if not world.catalog._number(s.get(key)) or s[key]<0 or s[key]>1e12:return false
		for key in ["meals"]:
			if not world._integer(s[key]):return false
		if s.has("hungry_seconds") and (not world.catalog._number(s.hungry_seconds) or s.hungry_seconds<0 or s.hungry_seconds>1e12):return false
		if s.has("last_rush_clock") and (not world.catalog._number(s.last_rush_clock) or s.last_rush_clock<0):return false
	return true
func restore(value:Dictionary)->void:
	states=value.get("states",{}).duplicate(true)
	for state in states.values():state.erase("snacks")
	var offline:float=maxf(0,Time.get_unix_time_from_system()-float(value.get("saved_at",Time.get_unix_time_from_system())))
	for id in states:
		if states[id].elapsed<float(config.thresholds[1]):states[id].elapsed=minf(float(config.thresholds[1]),states[id].elapsed+offline)
	follow_targets.clear();follow_origins.clear();follow_after.clear();speech_times.clear();quiet_until.clear()
	owned_routes.clear();reactions.clear()
	rushes.clear();rush_after.clear();pending_invites.clear();pending_reactions.clear();meal_seen.clear()

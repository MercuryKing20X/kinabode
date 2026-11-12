class_name ResidentActivity
extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
var _owner: WeakRef
var world: RefCounted:
	get: return _owner.get_ref()
var gathering: Dictionary = {}
var following:Dictionary={}
var squad_leader:=""
# Session-only authority of an explicit selection; automatic proximity is not a lock.
var explicit_selected:Dictionary={}
var command_busy:Callable
func commanded(id:String)->bool:
	# A real ingredient approach is owned work even though it has no WorkSystem job.
	return (world.ingredients!=null and world.ingredients.resident_pending.has(id) and world.hunger.rank(id)<3) or (command_busy.is_valid() and command_busy.call(id))
var default_follow_excluded:Dictionary={}
# The app opts in; raw legacy engine sessions retain transient selections.
var persist_follow:=false
var follow_issuing:=false
var suspended_follow:Dictionary={}
var members: Dictionary = {}
var held: Dictionary = {}
var elapsed := 0.0
func _init(source: RefCounted) -> void: _owner=weakref(source)
func blocked(id: String,include_follow:bool=true) -> bool: return members.has(id) or gathering.get("failures",{}).has(id) or bool(held.get(id,false)) or (world.shared_activity != null and world.shared_activity.holds(id))
func pause_work(id: String) -> void:
	world.farms.pause(id)
	if world.projects.active(id): world.projects.pause(id,LocalText.text("system.resident_activity.joining_the_activity_first_earlier_work_is_kept"))
	world.work.stop(id,false)
	world.director.command_received(id,"activity")
	if world.village.states.has(id):world.village.states[id].owned_route=false;world.village.states[id].next=world.village.time+5
func dismiss(id: String = "",include_follow:bool=true) -> void:
	if include_follow:
		for who in following.keys():
			if id.is_empty() or id==who:release_follow(who)
	for who in members.keys():
		if not id.is_empty() and who!=id:continue
		world.work.stop(who,false);members.erase(who)
	if not id.is_empty() and not gathering.is_empty():gathering.failures.erase(id)
	if members.is_empty():gathering.clear()
	world.revision+=1
func pause_follow(id:String)->void:
	world.hunger.clear_follow(id)
func release_follow(id:String)->void:
	explicit_selected.erase(id)
	if not following.has(id):return
	world.hunger.clear_follow(id);following.erase(id);world.revision+=1
func set_followers(ids:Array,selection_scope:Array=[])->Dictionary:
	if ids.any(func(id):return id=="human" or not world.actors.has(id) or not world.residents.supports(world.actors[id],"move")):return world._error("invalid_participant")
	# A full host selection is authoritative. A resident's own follow/unfollow
	# may change only that resident's opt-out, never the rest of the village.
	if selection_scope.any(func(id):return id=="human" or not world.actors.has(id)):return world._error("invalid_participant")
	if not selection_scope.is_empty():
		for id in following:
			if id not in ids and id not in selection_scope:return world._error("invalid_participant")
		for id in ids:
			if not following.has(id) and id not in selection_scope:return world._error("invalid_participant")
	for id in world.director.routines:
		if not selection_scope.is_empty() and id not in selection_scope:continue
		if id in ids:default_follow_excluded.erase(id)
		else:default_follow_excluded[id]=true
	for id in following.keys():
		if id not in ids:release_follow(id)
	var added:Array=[]
	for id in ids:
		if following.has(id):continue
		world.shared_activity.pause_actor(id,LocalText.text("system.resident_activity.the_host_called_her_to_follow_the_fireside"))
		dismiss(id);pause_work(id);world.hunger.clear_rush(id);world.hunger.clear_follow(id)
		following[id]=true;added.append(id)
	for id in world.director.routines:
		if not selection_scope.is_empty() and id not in selection_scope:continue
		if id in ids:explicit_selected[id]=true
		else:explicit_selected.erase(id)
	for id in added:
		world.hunger.follow_after.erase(id);world.hunger.follow(id)
	world.revision+=1
	return {"ok":true,"message":LocalText.text("system.resident_activity.selected_companions_will_come_along_the_path_and") if not following.is_empty() else LocalText.text("system.resident_activity.following_canceled")}
func gather() -> Dictionary:
	world.shared_activity.pause(LocalText.text("system.resident_activity.gathering_first_the_barbecue_is_paused"))
	var human: Dictionary=world.actors.human
	var center: Vector2=world.point(human)
	var ids: Array=world.actors.keys().filter(func(id):return id!="human")
	# Freeze all residents immediately; route through doors using normal movement.
	dismiss();gathering={"phase":"arriving","remaining":60.0,"region_id":human.region_id,"failures":{},"total":ids.size()};elapsed=0
	var assigned: Array=[]
	for id in ids:
		pause_work(id)
		var destination:=Vector2.ZERO;var found:=false
		for row in range(5):
			for column in range(6):
				var candidate:=center+Vector2((column-2.5)*2.2,[3.0,-3.0,5.0,-5.0,7.0][row])
				if assigned.any(func(p):return p.distance_to(candidate)<1.5):continue
				if not world.walkable(human.region_id,candidate):continue
				if world.actors[id].region_id==human.region_id and world.find_route(id,candidate).is_empty():continue
				destination=candidate;found=true;break
			if found:break
		if not found:gathering.failures[id]=LocalText.text("system.resident_activity.no_reachable_standing_spot_nearby");continue
		assigned.append(destination);members[id]={"arrived":false,"position":[destination.x,destination.y]}
		world.work.serial+=1
		world.work.jobs[id]={"id":"job-%s"%world.work.serial,"intent":"gather_residents","phase":"activity_work","step":"gather","region_id":human.region_id,"position":[destination.x,destination.y],"time":0.0}
	world.revision+=1
	return {"ok":true,"status":"accepted","message":LocalText.text("system.resident_activity.gathering")}
func start(id: String,args: Dictionary) -> Dictionary:
	var intent: String=args.intent
	for key in args:
		if key not in ["intent","target_id"]:return world._error("invalid_command")
	if intent=="greet":
		if world.actors[id].region_id!=world.actors.human.region_id:return world._error("different_region")
		return {"ok":true,"status":"completed","message":LocalText.text("system.resident_activity.yes_i_am_here"),"source":"local_rules"}
	if world.work.jobs.has(id) or world.projects.active(id) or world.farms.active(id):return world._error("busy")
	var target: Vector2=world.point(world.actors[id]);var region: String=world.actors[id].region_id
	if intent=="come_near":
		region=world.actors.human.region_id;var origin: Vector2=world.point(world.actors.human);var found:=false
		for offset in [Vector2(2,0),Vector2(-2,0),Vector2(0,2),Vector2(0,-2)]:
			if world.walkable(region,origin+offset):target=origin+offset;found=true;break
		if not found:return world._error("unreachable")
	world.work.serial+=1;world.work.jobs[id]={"id":"job-%s"%world.work.serial,"intent":intent,"phase":"activity_work","step":intent,"region_id":region,"position":[target.x,target.y],"time":0.0}
	return {"ok":true,"status":"accepted"}
func tick(id: String,job: Dictionary,delta: float) -> void:
	var destination:=Vector2(job.position[0],job.position[1])
	if not world.interior._arrive(id,job.region_id,destination):return
	var actor: Dictionary=world.actors[id]
	if job.step=="gather":
		if not members.has(id):world.work.stop(id,false);return
		members[id].arrived=true;actor.activity="assembled"
		actor.facing="up" if world.point(world.actors.human).y<destination.y else "down"
		return
	actor.activity="dancing" if job.step=="dance" else "local_look"
	job.time+=delta
	if job.time>= (20 if job.step=="dance" else 2):world.work._finish(id,LocalText.text("system.resident_activity.activity_ended"))
func advance(delta: float) -> void:
	var followers:Array=following.keys() if squad_leader.is_empty() else []
	for id in followers:
		if not world.actors.has(id):following.erase(id);continue
		if id==squad_leader:continue
		if command_busy.is_valid() and command_busy.call(id):continue
		if suspended_follow.has(id) or blocked(id,false) or world.work.jobs.has(id) or world.farms.active(id) or world.hunger.rushes.has(id):
			world.hunger.clear_follow(id);continue
		world.hunger.follow(id)
	if gathering.is_empty():return
	elapsed+=delta
	for id in members.keys():
		if not world.work.jobs.has(id) or (elapsed>90 and not members[id].arrived):
			gathering.failures[id]=LocalText.text("system.resident_activity.the_gathering_point_cannot_be_reached_right_now");world.work.stop(id,false);members.erase(id)
	if gathering.phase=="arriving" and members.values().all(func(member):return member.arrived):gathering.phase="holding"
	elif gathering.phase=="holding":
		gathering.remaining=maxf(0,float(gathering.remaining)-delta)
		if gathering.remaining<=0:dismiss("",false)
func snapshot() -> Dictionary:
	var result:=gathering.duplicate(true);result["members"]=members.duplicate(true);return result

## Explicit host-selected gathering at a real target. Original World jobs and60s hold.
## No human actor, no unrelated participant cancellation, and no second movement owner.
func gather_selected(ids:Array,region_id:String,center:Vector2)->Dictionary:
	if ids.is_empty() or ids.size()>world.actors.size()-1 or not gathering.is_empty():return world._error("busy")
	if region_id!=world.actors.human.region_id or not world.catalog.regions.has(region_id):return world._error("different_region")
	var unique:Dictionary={}
	for id in ids:
		if not id is String or id=="human" or not world.actors.has(id) or unique.has(id) or world.actors[id].region_id!=region_id or not world.residents.supports(world.actors[id],"move"):return world._error("invalid_participant")
		unique[id]=true
		var routine:RefCounted=world.director.routines.get(id)
		if world.farms.active(id) or world.projects.active(id) or world.hunger.rank(id)>=3 or (world.work.jobs.has(id) and (routine==null or not routine.owns_job())):return world._error("busy")
	var destinations:Dictionary={};var assigned:Array=[]
	for id in ids:
		var found:=false
		for row in range(5):
			for column in range(6):
				var candidate:Vector2=center+Vector2((column-2.5)*2.2,[3.0,-3.0,5.0,-5.0,7.0][row])
				if assigned.any(func(p):return p.distance_to(candidate)<1.5) or not world.walkable(region_id,candidate) or world.find_route(id,candidate).is_empty():continue
				destinations[id]=candidate;assigned.append(candidate);found=true;break
			if found:break
		if not found:return world._error("unreachable")
	gathering={"phase":"arriving","remaining":60.0,"region_id":region_id,"failures":{},"total":ids.size()};elapsed=0
	for id in ids:
		release_follow(id);pause_work(id)
		var at:Vector2=destinations[id];members[id]={"arrived":false,"position":[at.x,at.y]}
		world.work.serial+=1;world.work.jobs[id]={"id":"job-%s"%world.work.serial,"intent":"gather_residents","phase":"activity_work","step":"gather","region_id":region_id,"position":[at.x,at.y],"time":0.0}
	world.revision+=1
	return {"ok":true,"status":"accepted","message":LocalText.text("system.resident_activity.gathering")}

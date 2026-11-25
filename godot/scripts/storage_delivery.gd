extends RefCounted
const Text=preload("res://scripts/localization.gd")
const CarryRetention=preload("res://scripts/carry_retention.gd")
var _owner:WeakRef
var world:RefCounted:
	get:return _owner.get_ref()
var pending:Dictionary={}
var time:=0.0
var party:Array=[]
var visits:Dictionary={}
func party_working()->bool:
	return party.any(func(id):return world.gomoku.active(id) or world.work.jobs.get(id,{}).get("intent","") in ["chop","gather_wood","forage"] and world.work.jobs[id].get("phase","")!="storage_delivery")
var arrival_serial:=0
var service_after:=0.0
func visit_slot(id:String)->Vector2:
	var host:Dictionary=world.actors.human
	var center:Vector2=world.point(host)
	if visits.has(id) and visits[id].center.distance_to(center)<=1:return visits[id].point
	var used:Array=[]
	for other in visits:
		if other!=id:used.append(visits[other].point)
	var forward:Vector2={"down":Vector2.DOWN,"up":Vector2.UP,"left":Vector2.LEFT,"right":Vector2.RIGHT}.get(host.facing,Vector2.DOWN)
	for radius in [2.8,4.5,6.0]:
		for index in 7:
			var point:Vector2=center+forward.rotated(-PI/2+PI*index/6)*radius
			if used.any(func(p):return p.distance_to(point)<1.5) or not world.walkable(host.region_id,point):continue
			if world.point(world.actors[id]).distance_to(point)>.1 and world.find_route(id,point).is_empty():continue
			visits[id]={"point":point,"center":center,"arrival":0};return point
	return Vector2.INF
func visit_ready(id:String)->bool:
	if not visits.has(id):return false
	var state:Dictionary=visits[id]
	if world._routes.has(id) or world.point(world.actors[id]).distance_to(state.point)>.5:return false
	if state.arrival==0:arrival_serial+=1;state.arrival=arrival_serial
	return time>=service_after and not visits.values().any(func(v):return v.arrival>0 and v.arrival<state.arrival)
func finish_visit(id:String)->void:
	visits.erase(id);service_after=time+1.2
func route_visit(id:String)->bool:
	var target:Vector2=visit_slot(id)
	if not target.is_finite():return false
	return world.route_to(id,target)
func _init(owner:RefCounted)->void:_owner=weakref(owner)
func active(id:String)->bool:return pending.has(id)
func request(id:String,route_now:bool=true,allow_retained:bool=false)->bool:
	if id=="human":return world.deposit_all(id).ok
	if not world.actors.has(id) or world.actors[id].carry.is_empty():return false
	if not allow_retained and CarryRetention.unprotected(world.actors[id]).is_empty():
		# Real capacity blockage must stop/pause safely instead of an empty delivery loop.
		var message:String=Text.text("system.world_state.your_backpack_is_full_store_something_first")
		if world.work.jobs.get(id,{}).get("phase")=="storage_delivery":world.work._finish(id,message,false)
		if world.farms.active(id) and world.work.carry_space(id)<4:world.farms.pause(id,message)
		return false
	if not pending.has(id):pending[id]={"elapsed":0.0,"retry":0.0,"arrived":false,"allow_retained":allow_retained}
	elif allow_retained:pending[id].allow_retained=true
	var actor:Dictionary=world.actors[id];var host:Dictionary=world.actors.human
	var routine:RefCounted=world.director.routines.get(id)
	if route_now and not (id in party and party_working()) and actor.region_id==host.region_id and not world._routes.has(id) and not actor.has("furniture_id") and (routine==null or not routine.held) and not world.activities.members.has(id) and not world.shared_activity.contains(id) and (not world.work.jobs.has(id) or world.work.jobs[id].get("phase")=="storage_delivery") and world.point(actor).distance_to(visit_slot(id))>.5:
		if route_visit(id):pending[id]["route"]=world._routes.get(id,[])
	return true
func cancel(id:String)->void:
	var state:Dictionary=pending.get(id,{})
	if state.has("route") and world._routes.has(id) and is_same(state.route,world._routes[id]):
		world._routes.erase(id);world._forced_runs.erase(id)
	pending.erase(id);visits.erase(id)
func advance(delta:float)->void:
	time+=delta
	# Old carried goods and hunger-follow gifts are handed over only while idle.
	for id in world.actors:
		if id=="human" or CarryRetention.unprotected(world.actors[id]).is_empty() or pending.has(id):continue
		var brain:RefCounted=world.director.brains.get(id)
		if brain!=null and not brain.paused_wood.is_empty():continue
		var due:bool=world.work.carry_space(id)==0 or world.activities.following.has(id) or world.hunger.rank(id)>=3
		if due and not world.work.jobs.has(id) and not world.actors[id].has("furniture_id") and world.homestead.plans.get(id,{}).get("receipt",{}).is_empty():request(id)
	for id in pending.keys():
		var actor:Dictionary=world.actors[id];var host:Dictionary=world.actors.human;var state:Dictionary=pending[id]
		if actor.carry.is_empty():pending.erase(id);visits.erase(id);continue
		var routine:RefCounted=world.director.routines.get(id)
		if (routine!=null and routine.held) or world.activities.members.has(id) or world.shared_activity.contains(id):
			state.elapsed=0.0
			if state.has("route") and world._routes.has(id) and is_same(state.route,world._routes[id]):world._routes.erase(id)
			continue
		if world.work.jobs.has(id) and world.work.jobs[id].get("phase")!="storage_delivery":continue
		if actor.region_id!=host.region_id:
			state.elapsed=0.0;state.arrived=false
			if state.has("route") and world._routes.has(id) and is_same(state.route,world._routes[id]):world._routes.erase(id)
			continue
		if actor.has("furniture_id") or not world.fishing.held(id).is_empty():continue
		var visit_point:Vector2=visit_slot(id)
		var distance:float=world.point(actor).distance_to(visit_point)
		if id in party and party_working() and not world._routes.has(id):continue
		if distance>.5:
			state.elapsed=0.0;state.arrived=false
			if time>=float(state.retry):
				state.retry=time+1.0
				if not world._routes.has(id) and route_visit(id):state["route"]=world._routes.get(id,[])
			continue
		if not visit_ready(id):continue
		# Real settled arrival, then reuse the existing put-down action frames.
		world.work.face(actor,host);actor.activity="putting_down";state.elapsed+=delta
		if float(state.elapsed)<.65:continue
		var result:Dictionary=world.deposit_all(id,not bool(state.get("allow_retained",false)))
		if not result.ok:continue
		var wood:int=int(result.items.get("wood",0))
		world.work.visual_event("deposit",host,id)
		var labels:Array=[]
		for item in result.items:labels.append(Text.text("storage.delivery")%[int(result.items[item]),Text.text("storage.item."+item)])
		world.work.visual_event("storage_text",actor,id)
		world.work.visual_events[-1]["storage_text"]=" · ".join(labels)
		world.work.events.append({"id":"storage-"+str(world.revision),"actor_id":id,"status":"progress","message":" · ".join(labels)})
		pending.erase(id);finish_visit(id);actor.activity="idle"
		if world.work.jobs.has(id):
			var job:Dictionary=world.work.jobs[id]
			if job.get("intent")=="gather_wood":job.wood_stored+=wood
			if job.has("storage_resume"):
				job.phase=job.storage_resume;job.erase("storage_resume")
				var target:Dictionary=world.life_for_job(job).patches.get(job.target_id,{}) if job.phase=="life_forage" else world.object_by_id(str(job.target_id))
				if target.is_empty() or not world.approach(id,target):world.work._finish(id,Text.text("storage.return_blocked"),false)
			elif world.drops.has(str(job.get("drop_id",""))):
				job.phase="pickup";world.approach(id,world.drops[job.drop_id])
			elif job.get("intent")=="gather_wood":world.gathering.after_delivery(id,job)
			else:world.work._finish(id,Text.text("storage.deposited"))

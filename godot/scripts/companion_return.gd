extends RefCounted
## Social-only visits. All motion belongs to the routine's original World route.
const DEFAULT={"interval_seconds":480.0,"far_distance":24.0,"far_seconds":180.0,"stay_seconds":18.0,"stagger_seconds":35.0,"route_timeout_seconds":120.0}
var defaults:Dictionary=DEFAULT.duplicate()
func _init()->void:
	var data:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/companions/return-visit.json"))
	if valid(data):defaults.merge(data,true)
	else:push_error("Invalid return visit content")
var due:=-1.0
var last_seen:=0.0
var arrivals:Array=[]
var started:=0.0
var retry_after:=0.0
var diagnostics:Dictionary={}
func mark(reason:String)->void:diagnostics[reason]=int(diagnostics.get(reason,0))+1
static func valid(v:Variant)->bool:
	if not v is Dictionary or v.keys().any(func(k):return not DEFAULT.has(k)):return false
	for k in v:
		var bounds:Array={"interval_seconds":[300,900],"far_distance":[16,80],"far_seconds":[90,600],"stay_seconds":[5,40],"stagger_seconds":[15,90],"route_timeout_seconds":[24,300]}[k]
		if not ((v[k] is int or v[k] is float) and is_finite(v[k]) and v[k]>=bounds[0] and v[k]<=bounds[1]):return false
	return true
func options(r:RefCounted)->Dictionary:
	var result:Dictionary=defaults.duplicate()
	var main_trait:String=str(r.world.intelligence.preset(r.ID).get("main_trait",""))
	result.merge(r.world.intelligence.catalog.traits.get(main_trait,{}).get("return_visit",{}),true)
	return result
func tick(r:RefCounted,delta:float)->bool:
	if delta<=0:return false
	var w:RefCounted=r.world
	# Bare World compatibility projection is frozen; Main activates layered presets
	# for every loaded world (including old saves) before local life begins.
	if w.intelligence.compatibility:return false
	var now:float=r.time;var cfg:=options(r)
	var actor:Dictionary=w.actors[r.ID];var human:Dictionary=w.actors.human
	var same:bool=actor.region_id==human.region_id
	var distance:float=w.point(actor).distance_to(w.point(human)) if same else INF
	if due<0:
		var index:int=w.director.routines.keys().find(r.ID)
		due=now+float(cfg.interval_seconds)+index*float(cfg.stagger_seconds);last_seen=now
	if distance<=8:last_seen=now
	if r.kind=="return_visit":
		r.elapsed+=delta
		if r.owns_route and w._routes.has(r.ID):
			if r.elapsed>float(cfg.route_timeout_seconds):r.interrupt(12)
			return true
		if r.owns_route:
			r.owns_route=false;r.elapsed=0
			if distance>8:r.interrupt(12);return true
			r._face_human();actor.activity="local_look";r._speak("arrive")
			arrivals.append({"at":now,"distance":distance,"travel_seconds":now-started});if arrivals.size()>64:arrivals.pop_front()
		if r.elapsed>=float(cfg.stay_seconds):r.interrupt(8)
		return true
	if not r.kind.is_empty() or now<r.next_decision or now<r.visual_quiet_until:return false
	if now<retry_after:return false
	if now<due and not (distance>float(cfg.far_distance) and now-last_seen>=float(cfg.far_seconds)):return false
	if not same or w.director.time<w.director.return_visit_after:return false
	if w.shared_activity.holds(r.ID) or w.gomoku.active(r.ID):return false
	for camp in w.barbecues.values():
		if r.ID in camp.fireside.selected_guests or r.ID in camp.fireside.state.get("invited",[]):return false
	# Reuse hunger follow's rear/side geometry, original spacing and position validation.
	var forward:Vector2={"down":Vector2.DOWN,"up":Vector2.UP,"left":Vector2.LEFT,"right":Vector2.RIGHT}.get(human.facing,Vector2.DOWN)
	var base:Vector2=w.point(human)-forward*float(w.hunger.config.follow_distance)
	var targets:Array=[]
	for offset in [Vector2(-forward.y,forward.x)*float(w.hunger.config.follow_spacing),Vector2(1.8,0),Vector2(-1.8,0),Vector2(0,1.8)]:targets.append(base+offset)
	for radius in [float(w.hunger.config.follow_distance),minf(float(w.hunger.config.max_follow_distance),float(r.config.notice_radius)-1)]:
		for angle in range(16):targets.append(w.point(human)+Vector2.from_angle(angle*TAU/16)*radius)
	for target in targets:
		if w._routes.has("human") and not w._routes.human.is_empty() and w._routes.human.back().distance_to(target)<1.5:continue
		if not w.walkable(actor.region_id,target) or not w.director.available_position(r.ID,actor.region_id,target):continue
		mark("candidate")
		if r._move_to(target):
			mark("started");r.kind="return_visit";r.elapsed=0;started=now;due=now+float(cfg.interval_seconds)
			w.director.return_visit_after=w.director.time+float(cfg.stagger_seconds);w.revision+=1;return true
	mark("no_route");retry_after=now+float(cfg.stagger_seconds);due=retry_after
	return false

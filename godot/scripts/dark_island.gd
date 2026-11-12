extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
## Host-only exploration. World owns routes; Fireside owns all physical debits.
var _owner:WeakRef
var world:RefCounted:
	get:return _owner.get_ref()
var config:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/dark-island.json"))
var discoveries:RefCounted
var companions:RefCounted
var party:Array=[]
var fires:Array=[]
var beacons:Array=[]
var torch:Dictionary={"owned":false,"remaining":0.0,"planted":false,"position":[0,0]}
var pending:Dictionary={}
var phase:=""
var gesture_left:=0.0
var spread:Dictionary={}
var events:Array=[]
var was_working:=false
var hand_phase:=""
var hand_left:=0.0
var serial:=0
var life:RefCounted
func _init(source:RefCounted)->void:
	_owner=weakref(source)
	discoveries=preload("res://scripts/dark_discoveries.gd").new(self)
	companions=preload("res://scripts/dark_companions.gd").new(self)
	if not enabled():return
	var offsets:Array=world.life.activity_rules.seat_offsets.duplicate(true)
	life=preload("res://scripts/shared_life.gd").new(world,{"id":"dark.barbecue","name":LocalText.source("content.place.dark_camp"),"position":config.camp,"region_id":"dark","place_id":"dark.camp","seat_offsets":offsets,"mushrooms":[{"id":"dark.mushrooms.1","position":[34,95]}]})
	world.barbecues[life.station.id]=life
func enabled()->bool:return world.catalog.regions.has("dark")
func here()->bool:return enabled() and world.actors.human.region_id=="dark"
func p(value:Array)->Vector2:return Vector2(value[0],value[1])
func emit(kind:String,at:Vector2)->void:
	serial+=1;events.append({"serial":serial,"kind":kind,"position":[at.x,at.y],"region_id":"dark","time":world.director.time})
	if events.size()>32:events.pop_front()
func allowed_party(ids:Array)->Dictionary:
	var accepted:Array=[];var reasons:Array=[]
	for id in ids:
		if id=="human" or not world.actors.has(id) or id in accepted or world.actors[id].region_id!="home":continue
		if world.hunger.rank(id)>=3 and not world.activities.following.has(id):reasons.append(LocalText.text("ui.dark.party_hungry")%LocalText.resident(world,id));continue
		if (world.work.jobs.has(id) and not world.director.routines[id].owns_job()) or (world._routes.has(id) and not world.director.routines[id].owns_route and not world.director.routines[id].owns_job() and not world.hunger.owned_routes.has(id)) or world.director.routines[id].held:reasons.append(LocalText.text("ui.dark.party_busy")%LocalText.resident(world,id));continue
		accepted.append(id)
	return {"ids":accepted,"message":"\n".join(reasons)}
func travel(ids:Array,walking:bool=false)->Dictionary:
	if not enabled():return world._error("unavailable")
	var origin:String=world.actors.human.region_id
	if origin not in ["home","dark"]:return world._error("wrong_region")
	var boat:Vector2=p(config.walking_connection.dark_end if origin=="dark" else config.walking_connection.home_end) if walking else p(config.dock if origin=="dark" else config.home_dock)
	if world.point(world.actors.human).distance_to(boat)>4:return world.work.fail("too_far",LocalText.text("ui.dark.boat_distance"))
	if world.work.jobs.has("human") or world.actors.human.has("furniture_id"):return world.work.fail("busy",LocalText.text("ui.dark.finish_or_put_away"))
	var destination:String="home" if origin=="dark" else "dark"
	if destination=="dark":party=allowed_party(Array(ids)+world.activities.following.keys()).ids
	var people:Array=["human"]
	if origin=="dark":people.append_array(world.actors.keys().filter(func(id):return id!="human" and world.actors[id].region_id=="dark"))
	else:people.append_array(party)
	var at:Vector2=p(config.walking_connection.home_end if destination=="home" else config.walking_connection.dark_end) if walking else p(config.home_arrival if destination=="home" else config.arrival)
	var landing:Array=[]
	for i in range(people.size()):
		var found:Vector2=Vector2.INF
		for ring in range(5):
			for k in range(16):
				var candidate:Vector2=at+Vector2.from_angle(TAU*k/16.0)*ring*1.8
				if not world.walkable(destination,candidate) or landing.any(func(v):return v.distance_to(candidate)<1.6):continue
				if world.actors.values().any(func(a):return a.id not in people and a.region_id==destination and world.point(a).distance_to(candidate)<1.6):continue
				found=candidate;break
			if found.is_finite():break
		if not found.is_finite():return world.work.fail("landing_blocked",LocalText.text("ui.dark.landing_busy"))
		landing.append(found)
	for i in range(people.size()):
		var id:String=people[i]
		world.work.stop(id,false)
		if id!="human":world.director.routines[id].interrupt(8);world.hunger.clear_follow(id)
		world.actors[id].region_id=destination
		var spot:Vector2=landing[i]
		world.actors[id].position=[spot.x,spot.y];world.actors[id].activity="idle"
	world.reset_motion();pending.clear();phase="";torch.planted=false
	if destination=="home":party=[]
	world.revision+=1;return {"ok":true,"region_id":destination}
func follow_over_bridge(id:String,destination:String)->bool:
	# A selected resident walks the same real seam as the human; no remote landing.
	if not enabled() or id=="human" or not world.activities.following.has(id) or world.work.jobs.has(id):return false
	var actor:Dictionary=world.actors[id];var origin:String=actor.region_id
	if origin not in ["home","dark"] or destination not in ["home","dark"] or origin==destination:return false
	var index:int=world.activities.following.keys().find(id)
	var lateral:float=[-1.5,0.0,1.5][posmod(index,3)]
	var edge:Vector2=p(config.walking_connection.home_end if origin=="home" else config.walking_connection.dark_end)+Vector2(lateral,0)
	if world.point(actor).distance_to(edge)>.2:
		if not world._routes.has(id) or world._routes[id].back().distance_to(edge)>.1:
			if not world.route_to(id,edge):return false
		world.hunger.remember_route(id)
		world.hunger.follow_targets[id]={"region":origin,"point":edge}
		return false
	var landing:Vector2=p(config.walking_connection.home_end if destination=="home" else config.walking_connection.dark_end)+Vector2(lateral,0)
	if not world.walkable(destination,landing) or world.actors.values().any(func(a):return a.id!=id and a.region_id==destination and world.point(a).distance_to(landing)<1.2):return false
	world.hunger.clear_follow(id)
	actor.region_id=destination;actor.position=[landing.x,landing.y];actor.activity="idle"
	if destination=="dark" and id not in party:party.append(id)
	elif destination=="home":party.erase(id)
	world.hunger.follow_after.erase(id);world.revision+=1
	return true
func area_at(at:Vector2)->Dictionary:
	for area in config.areas:
		if Geometry2D.is_point_in_polygon(at,PackedVector2Array(area.polygon.map(func(v):return p(v)))):return area
	return {}
func permanent(at:Vector2)->bool:
	if at.distance_to(p(config.camp))<=float(config.camp_radius):return true
	for fire in fires:
		if at.distance_to(p(fire.position))<=float(config.fire_radius):return true
	var area:=area_at(at)
	return not area.is_empty() and area.id in beacons
func light_sources()->Array:
	var result:Array=[{"position":config.camp,"radius":config.camp_radius}]
	for fire in fires:result.append({"position":fire.position,"radius":config.fire_radius})
	return result
func visible_radius()->float:return float(config.torch_radius) if torch.remaining>0 and not torch.planted else float(config.bare_radius)
func fire_near(at:Vector2)->bool:
	if at.distance_to(p(config.camp))<=float(config.interact_radius):return true
	for fire in fires:
		if at.distance_to(p(fire.position))<=float(config.interact_radius):return true
	for area in config.areas:
		if area.id in beacons and area.has("beacon") and at.distance_to(p(area.beacon))<=float(config.interact_radius):return true
	return false
func cancel()->void:
	pending.clear()
	hand_phase=""
	if not phase.is_empty():world.actors.human.activity="idle";phase=""
func fire_site(at:Vector2)->bool:
	if not world.walkable("dark",at):return false
	for object in world.objects.values():
		if object.region_id=="dark" and world.point(object).distance_to(at)<2:return false
	if world.actors.values().any(func(a):return a.id!="human" and a.region_id=="dark" and world.point(a).distance_to(at)<1.5):return false
	return true
func light_portable_torch()->Dictionary:
	if not here() or not pending.is_empty() or world.work.jobs.has("human"):return world.work.fail("busy",LocalText.text("ui.dark.finish_task"))
	if not str(world.actors.human.get("furniture_id","")).is_empty() or not world.fishing.held("human").is_empty():return world.work.fail("hands_full",LocalText.text("ui.dark.put_away"))
	if torch.remaining>0:return {"ok":true,"message":LocalText.text("ui.dark.torch_already_lit")}
	var receipt:Dictionary=life.fireside.debit({"wood":int(config.torch_wood)})
	if not receipt.ok:return world.work.fail("missing_wood",LocalText.text("ui.dark.torch_wood_missing"))
	torch.owned=true;torch.remaining=float(config.torch_seconds);torch.planted=false
	emit("torch_light",world.point(world.actors.human));world.revision+=1
	return {"ok":true,"message":LocalText.text("ui.dark.torch_raised")}
func start(kind:String,at:Vector2)->Dictionary:
	if kind not in ["fire","torch","beacon"]:return world._error("unknown_action")
	if not here() or not pending.is_empty() or world.work.jobs.has("human"):return world.work.fail("busy",LocalText.text("ui.dark.finish_task"))
	if world.actors.human.has("furniture_id") or not world.fishing.held("human").is_empty() or not world.homestead.plans.get("human",{}).get("receipt",{}).is_empty():return world.work.fail("hands_full",LocalText.text("ui.dark.put_away"))
	if kind=="fire":
		if not fire_site(at):return world.work.fail("blocked",LocalText.text("ui.dark.fire_blocked"))
		if permanent(at) or fires.any(func(f):return p(f.position).distance_to(at)<float(config.fire_spacing)):return world.work.fail("already_lit",LocalText.text("ui.dark.already_bright"))
		if int(life.fireside.available().get("wood",0))<int(config.fire_wood):return world.work.fail("missing_wood",LocalText.text("ui.dark.fire_wood_missing")%int(config.fire_wood))
	if kind=="beacon":
		var area:=area_at(at)
		if area.is_empty() or not area.has("beacon") or p(area.beacon).distance_to(at)>.1:return world._error("unknown_beacon")
		if area.id in beacons:return world.work.fail("already_lit",LocalText.text("ui.dark.already_bright"))
		if torch.remaining<=0:return world.work.fail("no_flame",LocalText.text("ui.dark.no_flame"))
	if kind=="torch" and not fire_near(at):return world.work.fail("no_flame",LocalText.text("ui.dark.light_at_fire"))
	var goal:Vector2=at
	if kind in ["beacon","torch"]:
		var found:=false
		for offset in [Vector2(0,1.8),Vector2(1.8,0),Vector2(-1.8,0),Vector2(0,-1.8)]:
			if world.walkable("dark",at+offset) and not world.find_route("human",at+offset).is_empty():goal=at+offset;found=true;break
		if not found:return world._error("unreachable")
	var result:Dictionary=world.command("human",{"intent":"move","x":goal.x,"y":goal.y})
	if not result.ok:return result
	pending={"kind":kind,"position":[at.x,at.y],"goal":[goal.x,goal.y]};return {"ok":true,"message":LocalText.text("ui.dark.lighting") if kind=="fire" else LocalText.text("ui.dark.walking")}
func finish_action()->void:
	var at:Vector2=p(pending.position);var kind:String=pending.kind
	var cost:int=int(config.torch_wood) if kind=="torch" and not torch.owned else int(config.fire_wood) if kind=="fire" else int(config.beacon_wood) if kind=="beacon" else 0
	if kind=="beacon" and torch.remaining<=0:emit("failed",at);return
	if kind=="torch" and not fire_near(at):return
	if kind=="fire" and (permanent(at) or not fire_site(at) or fires.any(func(f):return p(f.position).distance_to(at)<float(config.fire_spacing))):return
	var receipt:Dictionary=life.fireside.debit({"wood":cost})
	if not receipt.ok:emit("missing_wood",at);return
	if kind=="torch":torch.owned=true;torch.remaining=float(config.torch_seconds);torch.planted=false;emit("torch_light",at)
	elif kind=="fire":fires.append({"id":"fire-"+str(fires.size()+1),"position":[at.x,at.y]});emit("small_fire",at)
	elif kind=="beacon":
		var area:=area_at(at)
		if area.id in beacons:return
		beacons.append(area.id);companions.ritual(at);spread={"area_id":area.id,"elapsed":0.0};emit("beacon",at)
		var participants:Array=["human"]
		for id in party:
			if world.actors[id].region_id=="dark" and area_at(world.point(world.actors[id])).get("id")==area.id:participants.append(id)
		world.memories.record_event("dark_beacon","dark:"+area.id,participants,{"area_id":area.id,"name":area.name,"beacon":area.beacon.duplicate()})
	world.revision+=1
func hands_busy(delta:float)->bool:
	if not here() or torch.remaining<=0:return false
	was_working=true
	if not torch.planted and hand_phase.is_empty():
		torch.planted=true;torch.position=world.actors.human.position.duplicate();hand_phase="plant";hand_left=float(config.gesture_seconds);emit("torch_plant",world.point(world.actors.human))
	if hand_phase=="plant":
		world.actors.human.activity="picking_up";hand_left-=delta
		if hand_left<=0:hand_phase=""
		return true
	return false
func block_motion(delta:float)->bool:
	if not here() or torch.remaining<=0:return false
	if torch.planted and hand_phase.is_empty():hand_phase="lift";hand_left=float(config.gesture_seconds);emit("torch_lift",p(torch.position))
	if hand_phase=="lift":
		world.actors.human.activity="picking_up";hand_left-=delta
		if hand_left<=0:torch.planted=false;hand_phase="";world.actors.human.activity="walking"
		return true
	return false
func advance(delta:float)->void:
	if not enabled():return
	discoveries.advance(delta)
	if not spread.is_empty():spread.elapsed=minf(float(config.beacon_spread_seconds),float(spread.elapsed)+delta)
	if not here():return
	if was_working and torch.planted and not world.work.jobs.has("human") and not world._routes.has("human"):
		if block_motion(delta) and not torch.planted:world.actors.human.activity="idle";was_working=false
	var before:float=torch.remaining
	torch.remaining=maxf(0,float(torch.remaining)-delta)
	if before>float(config.torch_warning_seconds) and torch.remaining<=float(config.torch_warning_seconds):emit("torch_warning",world.point(world.actors.human))
	if before>0 and torch.remaining==0:torch.planted=false;hand_phase="";emit("torch_out",world.point(world.actors.human))
	if not pending.is_empty():
		if world._routes.has("human"):
			if world._routes.human.back().distance_to(p(pending.goal))>.1:pending.clear()
			return
		if world.point(world.actors.human).distance_to(p(pending.goal))>.2:pending.clear();return
		if phase.is_empty():
			gesture_left=float(config.gesture_seconds)
			if pending.kind in ["fire","beacon"] and torch.remaining>0 and not torch.planted:
				phase="plant";torch.planted=true;torch.position=world.actors.human.position.duplicate();was_working=true
				emit("torch_plant",world.point(world.actors.human))
			else:phase="ignite"
		world.actors.human.activity="picking_up" if phase=="plant" else "gathering"
		gesture_left-=delta
		if gesture_left<=0:
			if phase=="plant":phase="ignite";gesture_left=float(config.gesture_seconds)
			else:finish_action();pending.clear();phase="";world.actors.human.activity="idle"
func nearest_light()->Vector2:
	var choices:Array=light_sources()
	for area in config.areas:
		if area.id in beacons and area.has("beacon"):choices.append({"position":area.beacon,"radius":0})
	var origin:Vector2=world.point(world.actors.human)
	choices.sort_custom(func(a,b):return origin.distance_to(p(a.position))<origin.distance_to(p(b.position)))
	for choice in choices:
		var at:=p(choice.position)
		for offset in [Vector2(0,2),Vector2(2,0),Vector2(-2,0)]:
			if not world.find_route("human",at+offset).is_empty():return at+offset
	return Vector2.INF
func saved()->Dictionary:
	return {"version":1,"fires":fires.duplicate(true),"beacons":beacons.duplicate(),"torch":torch.duplicate(true),"party":party.duplicate(),"discoveries":discoveries.saved()}
func restore(data:Dictionary)->void:
	fires=data.get("fires",[]).duplicate(true);beacons=data.get("beacons",[]).duplicate();party=data.get("party",[]).duplicate()
	torch=data.get("torch",{"owned":false,"remaining":0.0,"planted":false,"position":[0,0]}).duplicate(true)
	pending.clear();phase="";hand_phase="";was_working=false;spread.clear();events.clear();companions.clear();discoveries.restore(data.get("discoveries",{}))
func valid(data:Variant,actors:Dictionary)->bool:
	if data is Dictionary and data.is_empty():return not actors.values().any(func(a):return a.get("region_id")=="dark")
	if not enabled() or not data is Dictionary or data.keys().any(func(k):return k not in ["version","fires","beacons","torch","party","discoveries"]) or data.get("version")!=1:return false
	if not discoveries.valid(data.get("discoveries",{})):return false
	if not data.get("fires") is Array or data.fires.size()>1024 or not data.get("beacons") is Array or not data.get("party") is Array:return false
	var seen:Array=[]
	for fire in data.fires:
		if not fire is Dictionary or fire.size()!=2 or not fire.get("id") is String or fire.id in seen or not world.catalog._pair(fire.get("position")) or not world.walkable("dark",p(fire.position)):return false
		seen.append(fire.id)
	seen=[]
	for id in data.beacons:
		if id in seen or config.areas.filter(func(a):return a.id==id and a.has("beacon")).is_empty():return false
		seen.append(id)
	seen=[]
	for id in data.party:
		if id=="human" or not actors.has(id) or id in seen:return false
		seen.append(id)
	var t:Variant=data.get("torch")
	return t is Dictionary and t.size()==4 and t.get("owned") is bool and t.get("planted") is bool and world.catalog._number(t.get("remaining")) and t.remaining>=0 and t.remaining<=float(config.torch_seconds) and (t.remaining==0 or t.owned) and world.catalog._pair(t.get("position")) and (not t.planted or world.walkable("dark",p(t.position)))

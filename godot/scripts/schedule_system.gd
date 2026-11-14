extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
## Idle preferences on the existing LocalCompanion; no competing advance loop or work.
var _owner: WeakRef
var world: RefCounted:
	get:return _owner.get_ref()
var config: Dictionary={}
var next_after: Dictionary={}
var targets: Dictionary={}
var statistics: Dictionary={"started":{},"arrived":{}}
func _init(source: RefCounted) -> void:
	_owner=weakref(source)
	var data: Variant=world.locations.read("schedules")
	if not valid_config(data):world.error=LocalText.text("content.remaining.invalid_schedule_configuration");return
	config=data
func valid_config(data: Variant) -> bool:
	if not data is Dictionary or data.get("version")!=1 or not data.get("phases") is Dictionary or not data.get("weather_preferences") is Dictionary or not data.get("labels") is Dictionary or not data.get("offsets") is Array or data.offsets.size()!=4:return false
	for key in ["first_after","chance","interval","retry","stay_seconds","max_distance","arrival_radius"]:
		if not world.catalog._number(data.get(key)) or data[key]<=0 or data[key]>86400:return false
	if data.chance>1 or data.max_distance>64:return false
	for phase in world.days.config.phases:
		if not data.phases.get(phase.id) is Array or data.phases[phase.id].is_empty():return false
		for option in data.phases[phase.id]:
			if not option is Dictionary or option.get("place") not in ["sea","garden","camp","shelter"] or not world.catalog._number(option.get("weight")) or option.weight<=0 or option.weight>10:return false
	for offsets in data.offsets:
		if not offsets is Array or offsets.size()!=2 or not offsets.all(func(n):return world.catalog._number(n) and absf(n)<=6):return false
	for weather in ["sunny","cloudy","rain","fog"]:
		if not data.weather_preferences.get(weather) is Dictionary:return false
		for place in data.weather_preferences[weather]:
			if place not in data.labels or not world.catalog._number(data.weather_preferences[weather][place]) or data.weather_preferences[weather][place]<0 or data.weather_preferences[weather][place]>10:return false
	return true
func options(id: String) -> Array:
	var actor: Dictionary=world.actors[id];var point: Vector2=world.point(actor);var found: Array=[]
	if actor.region_id!="home":return found
	var preferred: Dictionary={}
	for item in config.phases[world.days.phase().id]:preferred[item.place]=float(item.weight)
	var wet: Dictionary=config.weather_preferences[world.weather.current().id]
	for place in wet:
		preferred[place]=float(preferred.get(place,1))*float(wet[place])
	for place in preferred:
		preferred[place]=float(preferred[place])*float(world.personality.profile(id).schedule_weights.get(place,1))
		var anchors: Array=[]
		if not world.locations.v3():
			match str(place):
				"sea":
					for entry in world.fishing.nearby_shores(id,6):anchors.append({"id":str(entry.water_id) if entry.has("water_id") else "coast","point":Vector2(entry.position[0],entry.position[1])})
				"garden":
					for farm in world.farms.farms.values():
						var rect: Rect2=world.farms.bounds(farm);anchors.append({"id":farm.id,"point":Vector2(rect.get_center().x,rect.end.y+2)})
				"camp":anchors.append({"id":world.life.station.id,"point":world.point(world.life.station)})
				"shelter":
					for room_id in world.interior.rooms():anchors.append({"id":room_id,"point":world.interior.outside(room_id)})
					for site in world.leisure.sites.values():
						if site.complete and world.leisure.art(site).get("recreation",{}).get("behavior")=="sit":anchors.append({"id":site.id,"point":world.point(site)})
		if world.locations.v3():
			anchors.clear()
			if place=="shelter" and world.days.phase().id=="night":
				for room in world.interior.rooms().values():
					if room.owner_id==id:anchors.append({"id":room.id,"point":world.interior.outside(room.id)})
			else:
				for key in world.catalog.regions.home.layout.schedule_anchors[str(place)]:
					var p:Array=world.map_anchor(key);anchors.append({"id":key,"point":Vector2(p[0],p[1])})
		for anchor in anchors:
			var candidates: Array=[anchor.point] if place in ["sea","garden"] else config.offsets.map(func(offset):return anchor.point+Vector2(offset[0],offset[1]))
			for destination in candidates:
				if point.distance_to(destination)>float(config.max_distance) or not world.walkable(actor.region_id,destination) or not world.director.available_position(id,actor.region_id,destination):continue
				found.append({"place":place,"target_id":anchor.id,"point":destination,"weight":float(preferred[place])/(1+point.distance_to(destination)*.03)})
	var moon:Dictionary=world.catalog.regions.home.get("layout",{}).get("moon",{})
	if not moon.is_empty() and world.days.phase().id=="night" and posmod(world.days.day(),int(moon.schedule_interval_days))==0:
		var residents:Array=world.director.routines.keys();residents.sort()
		if not residents.is_empty() and residents[posmod(world.days.day(),residents.size())]==id:
			var p:Array=world.map_anchor("moon.lookout");var destination:=Vector2(p[0],p[1])
			if world.walkable("home",destination):found.append({"place":"moon","target_id":moon.platform_id,"point":destination,"weight":float(moon.schedule_weight)})
	var shared: Dictionary=world.relationships.our_place(id)
	if not shared.is_empty() and shared.region_id==actor.region_id:
		var anchor:=Vector2(shared.position[0],shared.position[1])
		for offset in config.offsets:
			var destination: Vector2=anchor+Vector2(offset[0],offset[1])
			if point.distance_to(destination)<=float(config.max_distance) and world.walkable(actor.region_id,destination) and world.director.available_position(id,actor.region_id,destination):found.append({"place":"our_place","target_id":shared.target_id,"point":destination,"weight":float(config.get("shared_place_weight",2))/(1+point.distance_to(destination)*.03)})
	return found
func try_start(routine: RefCounted) -> bool:
	var id: String=routine.ID
	if routine.time<float(config.first_after) or routine.time<float(next_after.get(id,0)) or routine.blocked() or not routine.kind.is_empty() or not routine.enabled:return false
	next_after[id]=routine.time+float(config.retry)
	if routine.decision_rng.randf()>float(config.chance):return false
	var candidates:=options(id)
	if candidates.is_empty():return false
	var total: float=candidates.reduce(func(sum,item):return sum+float(item.weight),0.0);var roll: float=routine.decision_rng.randf()*total;var selected: Dictionary=candidates[-1]
	for item in candidates:
		roll-=float(item.weight)
		if roll<=0:selected=item;break
	routine.interrupt(8)
	if not routine._move_to(selected.point):return false
	routine.kind="schedule";routine.elapsed=0;routine.duration=float(config.stay_seconds);routine.last_walk=routine.time
	routine.route_timeout=24.0
	if selected.place=="moon":
		var moon:Dictionary=world.catalog.regions.home.layout.moon;var length:=0.0;var before:Vector2=world.point(world.actors[id])
		for waypoint in world._routes.get(id,[]):length+=before.distance_to(waypoint);before=waypoint
		routine.route_timeout=minf(float(moon.schedule_route_max_seconds),length/world.SPEED+float(moon.schedule_route_grace_seconds))
	targets[id]={"place":selected.place,"target_id":selected.target_id,"point":selected.point,"phase":world.days.phase().id,"arrived":false}
	next_after[id]=routine.time+float(config.interval);statistics.started[id]=int(statistics.started.get(id,0))+1;world.revision+=1;return true
func arrived(id: String) -> void:
	if not targets.has(id) or targets[id].arrived:return
	if world.point(world.actors[id]).distance_to(targets[id].point)>float(config.arrival_radius):return
	targets[id].arrived=true;statistics.arrived[id]=int(statistics.arrived.get(id,0))+1
	if targets[id].get("place")=="moon":
		var routine:RefCounted=world.director.routines[id];routine.issuing=true
		var result:Dictionary=world.command(id,{"intent":"use_facility","target_id":targets[id].target_id})
		routine.issuing=false
		if result.ok and world.work.jobs.has(id):
			world.work.jobs[id]["source"]="local_rules";routine.owned_job_id=world.work.jobs[id].id;routine.kind="facility";routine.elapsed=0
func summary(id: String) -> Dictionary:
	var target: Dictionary=targets.get(id,{})
	return {"source":"local_rules","phase":world.days.phase().id,"preference":str(config.labels.get(target.get("place",""),LocalText.text("content.remaining.wandering_freely"))),"target_id":target.get("target_id","") if world.director.routines.has(id) and world.director.routines[id].kind=="schedule" else "","active":world.director.routines.has(id) and world.director.routines[id].kind=="schedule"}
func reset() -> void:next_after.clear();targets.clear()

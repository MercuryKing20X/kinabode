extends RefCounted
## A non-resident pet. No inventory, hunger, work, model or relationship authority.
const Text=preload("res://scripts/localization.gd")
var owner:WeakRef
var world:RefCounted:
	get:return owner.get_ref()
var discovered:=false
var initialized:=false
var region:="home"
var position:=Vector2.ZERO
var carrier:=""
var pose:="sit"
var facing:="down"
var clock:=0.0
var next_decision:=0.0
var route:Array[Vector2]=[]
var memories:Dictionary={}
var interactions:Dictionary={}
var actor_poses:Dictionary={}
var fish_rub_serial:=0
var fish_rub_meal:=""
var textures:Dictionary={}
var social_target:=""
var social_until:=0.0
var recent_social:Array=[]
var rng:=RandomNumberGenerator.new()
var excursion_phase:=0
var next_excursion:=600.0
func _init(w:RefCounted)->void:owner=weakref(w);rng.seed=28041
func initialize()->void:
	if initialized:return
	initialized=true
	discovered=world.locations.v3() or world.opening_id=="showcase"
	position=home_anchor()
func home_anchor()->Vector2:
	for plot in world.catalog.regions.home.get("layout",{}).get("residential",[]):
		if plot.get("owner_id")=="human" and world.objects.has(plot.site_id):
			var site:Dictionary=world.objects[plot.site_id]
			for offset in [Vector2(2,world.site_size(site).y/2+2),Vector2(-2,world.site_size(site).y/2+2),Vector2(0,world.site_size(site).y/2+4)]:
				var at:Vector2=world.point(site)+offset
				if world.walkable("home",at):return at
	if world.locations.v3():
		var plaza:Array=world.map_anchor("plaza.center")
		return Vector2(plaza[0],plaza[1])
	return world.point(world.actors.human)+Vector2(2,0)
func discover()->void:
	if discovered:return
	discovered=true;region=world.actors.human.region_id;position=world.point(world.actors.human)+Vector2(1,0);memories["discovered"]=true
func available(id:String)->bool:
	if not world.actors.has(id):return false
	var a:Dictionary=world.actors[id]
	if a.region_id!=region or world.point(a).distance_to(position)>3:return false
	if world.work.jobs.has(id) or world._routes.has(id) or world.activities.blocked(id) or world.projects.active(id) or world.farms.active(id):return false
	if id!="human":
		var r:RefCounted=world.director.routines.get(id)
		if r==null or r.blocked() or not r.enabled or r.held or r.time<r.visual_quiet_until:return false
	for camp in world.barbecues.values():
		if id in camp.fireside.state.get("invited",[]):return false
	return true
func interact(id:String,action:String)->bool:
	if action=="release" and carrier==id and world.actors.has(id):carrier="";pose="jump";next_decision=clock+2;return true
	if not discovered or not available(id) or not carrier.is_empty() and carrier!=id:return false
	if action=="release":carrier="";pose="jump";next_decision=clock+2;return true
	if action not in ["hold","pet"]:return false
	carrier=id if action=="hold" else "";pose="held" if action=="hold" else "pet";route.clear();next_decision=clock+5
	actor_poses[id]={"action":action,"until":clock+5}
	if id!="human":
		var r:RefCounted=world.director.routines[id]
		r.interrupt(0)
		r.kind="cat_pet";r.duration=5;r.elapsed=0
		world.work.face(world.actors[id],{"position":[position.x,position.y]})
	var first:bool=not memories.has(action+":"+id)
	memories[action+":"+id]=true;interactions[id]=int(interactions.get(id,0))+1;world.revision+=1
	if first:world.memories.record_event("cat_contact",action+":"+id,[id],{"actor_id":id,"action":action})
	return true
func advance(delta:float)->void:
	initialize();clock+=delta
	if not discovered:
		if world.actors.human.region_id=="home" and world.home_island.contains(world.point(world.actors.human)):
			var at:Array=world.home_island.config.cat_home
			var anchor:=Vector2(at[0],at[1])
			if world.point(world.actors.human).distance_to(anchor)<4:discover()
		return
	if not carrier.is_empty():
		var a:Dictionary=world.actors.get(carrier,{})
		if a.is_empty():carrier=""
		else:region=a.region_id;position=world.point(a);return
	world.advance_pet_route(self,delta)
	# A newly committed real fish meal wins over cosmetic social seeking.
	# Once this meal has received its one rub, ordinary pet life may resume.
	for camp in world.barbecues.values():
		var meal:Dictionary=camp.fireside.state.get("current",{})
		if camp.station.region_id!=region or meal.is_empty() or meal.get("fish",{}).is_empty() or not camp.fireside.burning():continue
		if fish_rub_meal==str(meal.get("id","")):continue
		if int(meal.get("eaten",0))+int(meal.get("wasted",0))>=int(meal.get("total",0)):continue
		social_target=""
		var at:Vector2=world.point(camp.station)+Vector2(2,2)
		if route.is_empty() or route.back().distance_to(at)>.1:world.route_pet(self,at)
		pose="rub"
		if world.point(camp.station).distance_to(position)<5:
			fish_rub_meal=str(meal.get("id",""));fish_rub_serial+=1;next_decision=clock+5
		return
	if region=="home" and world.home_island!=null and not world.home_island.legacy:
		if excursion_phase==0 and clock>=next_excursion:
			var at:Array=world.home_island.config.cat_home
			if world.route_pet(self,Vector2(at[0],at[1])):excursion_phase=1;social_target=""
			else:next_excursion=clock+600
		if excursion_phase>0:
			if not route.is_empty():pose="walk";return
			if excursion_phase==1:
				excursion_phase=2;next_decision=clock+20;pose="sleep";return
			if excursion_phase==2:
				if clock<next_decision:return
				if world.route_pet(self,home_anchor()):excursion_phase=3;pose="walk";return
			excursion_phase=0;next_excursion=clock+600+rng.randf()*600
	if not social_target.is_empty():
		if clock>social_until or not world.actors.has(social_target) or world.actors[social_target].region_id!=region:
			social_target="";route.clear()
		elif available(social_target):
			var id:String=social_target
			social_target=""
			if interact(id,"pet"):
				recent_social.append(id)
				if recent_social.size()>3:recent_social.pop_front()
				return
		elif route.is_empty():social_target=""
		else:return
	if clock<next_decision:return
	next_decision=clock+8+rng.randf()*18
	if world.days.phase().id=="night" and region=="home":
		if position.distance_to(home_anchor())>2:
			if world.route_pet(self,home_anchor()):pose="walk";return
		else:pose="sleep";return
	for id in world.director.routines:
		if available(id) and rng.randf()<.22:interact(id,"pet");return
	# The pet seeks idle company itself; residents keep their own work/route authority.
	var candidates:Array=world.director.routines.keys().filter(func(id):
		var actor:Dictionary=world.actors[id];var r:RefCounted=world.director.routines[id]
		return actor.region_id==region and not id in recent_social and r.enabled and not r.held and not r.blocked() and not world.activities.following.has(id) and world.point(actor).distance_to(position)<=24)
	if not candidates.is_empty():
		var id:String=candidates[rng.randi_range(0,candidates.size()-1)]
		if world.route_pet(self,world.point(world.actors[id])+Vector2(1.5,0)):
			social_target=id;social_until=clock+24;pose="walk";return
	pose=["sit","sleep","stretch","lick","belly"][rng.randi_range(0,4)]
	var h:Dictionary=world.actors.human
	if h.region_id==region and world.point(h).distance_to(position)>4:
		world.route_pet(self,world.point(h)+Vector2(1,1));pose="walk"
	elif rng.randf()<.4:
		world.route_pet(self,position+Vector2(rng.randf_range(-4,4),rng.randf_range(-4,4)));pose="walk"

func saved()->Dictionary:
	initialize()
	var value:Dictionary={"version":1,"discovered":discovered,"memories":memories.duplicate(true)}
	if discovered:
		value["region_id"]=region;value["position"]=[position.x,position.y]
	return value
static func valid(v:Variant)->bool:
	if not v is Dictionary or v.keys().any(func(k):return k not in ["version","discovered","memories","region_id","position"]):return false
	if v.get("version")!=1 or not v.get("discovered") is bool or not v.get("memories") is Dictionary or v.memories.size()>16:return false
	if not v.memories.keys().all(func(k):return k is String and k.length()<64 and v.memories[k] is bool and v.memories[k]):return false
	if v.has("region_id")!=v.has("position"):return false
	if v.has("position"):
		if not v.discovered or not v.region_id is String or v.region_id.is_empty() or v.region_id.length()>128:return false
		if not v.position is Array or v.position.size()!=2 or not v.position.all(func(n):return (n is int or n is float) and is_finite(n)):return false
	return true
func restore(v:Dictionary)->void:
	initialized=true;discovered=v.discovered or world.locations.v3();memories=v.memories.duplicate(true)
	# Old three-key records never stored a location; keep their original load rule.
	region=str(v.get("region_id",world.actors.human.region_id)) if v.discovered else "home"
	position=Vector2(v.position[0],v.position[1]) if v.discovered and v.has("position") else (world.point(world.actors.human)+Vector2(2,0) if v.discovered else home_anchor())
	carrier="";route.clear();excursion_phase=0;next_excursion=clock+600

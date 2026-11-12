extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
## Explicit host interactions. No inference, autonomous work, or separate movement.
var _owner:WeakRef
var dark:RefCounted:
	get:return _owner.get_ref()
var world:RefCounted:
	get:return dark.world
var config:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/dark-discoveries.json"))
var found:Array=[]
var catches:Dictionary={}
var loose:=0
var lamps:Array=[]
var star_days:Array=[]
var pending:Dictionary={}
var seated:Array=[]
var seats:Dictionary={}
func _init(d:RefCounted)->void:_owner=weakref(d)
func illuminated(at:Vector2)->bool:
	return dark.permanent(at) or dark.torch.remaining>0 and at.distance_to(dark.p(dark.torch.position) if dark.torch.planted else world.point(world.actors.human))<=float(dark.config.torch_radius)
func eligible(item:Dictionary)->bool:
	if item.id in found or not illuminated(dark.p(item.position)):return false
	if not item.has("tag"):return true
	return item.id in dark.companions.revealed and companions().any(func(id):return world.intelligence.tag(id)==item.tag and world.point(world.actors[id]).distance_to(dark.p(item.position))<=6)
func companions()->Array:
	return world.actors.keys().filter(func(id):return id!="human" and world.actors[id].region_id=="dark" and (id in dark.party or world.activities.following.has(id)))
func fireflies()->Array:
	var result:Array=[]
	for i in range(dark.config.glows.size()):
		var g:Dictionary=dark.config.glows[i]
		if g.kind=="firefly" and not dark.permanent(dark.p(g.position)):result.append({"id":"fly-"+str(i),"position":g.position})
	return result
func stop_stars()->void:
	for id in seated:
		if not world.work.jobs.has(id):world.actors[id].activity="idle"
	seated.clear();seats.clear()
	for id in companions():dark.companions.reacted.erase(id+"stars")
func begin(id:String,at:Vector2)->Dictionary:
	stop_stars();pending.clear()
	if not dark.here() or world.work.jobs.has("human") or world.loaded("human"):return world.work.fail("busy",LocalText.text("ui.dark.put_away"))
	if id.begins_with("fly-") and int(catches.get(id,0))==world.days.day():return world.work.fail("caught_today",LocalText.text("ui.dark.fly_caught_today"))
	if id.begins_with("fly-") and loose==2 and world.work.carry_space("human")<1:return world.work.fail("backpack_full",LocalText.text("ui.dark.backpack_full_store"))
	var result:Dictionary=world.command("human",{"intent":"move","x":at.x,"y":at.y})
	if result.ok:pending={"id":id,"position":[at.x,at.y],"gesture":0.0}
	return result
func advance(delta:float)->void:
	if not seated.is_empty():
		if world._routes.has("human") or not dark.here():stop_stars()
		else:
			for who in seated:
				if not world._routes.has(who):world.actors[who].activity="local_sit"
			if seated.all(func(who):return not world._routes.has(who)):
				var day:int=world.days.day()
				if day not in star_days:star_days.append(day);memory("stars",seated.filter(func(who):return world.point(world.actors[who]).distance_to(dark.p(config.star_seat))<8))
		return
	if pending.is_empty():return
	if not dark.here():pending.clear();return
	var at:Vector2=dark.p(pending.position)
	if world._routes.has("human"):
		if world._routes.human.back().distance_to(at)>.2:pending.clear()
		return
	if world.point(world.actors.human).distance_to(at)>.3:pending.clear();return
	world.actors.human.activity="picking_up";pending.gesture+=delta
	if pending.gesture<.5:return
	var id:String=pending.id;pending.clear();world.actors.human.activity="idle"
	if id=="stars":
		seated=["human"]
		for actor in companions():
			if not world.work.jobs.has(actor):seated.append(actor)
		for i in range(seated.size()):
			var who:String=seated[i]
			world.hunger.clear_follow(who)
			if who!="human":
				var goal:Vector2=at+Vector2((i-2)*2.0,2.0)
				if world.walkable("dark",goal):world.route_to(who,goal)
			if not world._routes.has(who):world.actors[who].activity="local_sit"
			if seated.all(func(who):return not world._routes.has(who)):
				var day:int=world.days.day()
				if day not in star_days:star_days.append(day);memory("stars",seated.filter(func(who):return world.point(world.actors[who]).distance_to(dark.p(config.star_seat))<8))
		return
	if id.begins_with("fly-"):
		if dark.permanent(at) or int(catches.get(id,0))==world.days.day():return
		if loose==2 and world.work.carry_space("human")<1:return
		catches[id]=world.days.day();loose+=1;dark.emit("firefly",at)
		if loose==3:loose=0;world.actors.human.carry["firefly.jar"]=int(world.actors.human.carry.get("firefly.jar",0))+1;world.actors.human.pocketed=true
		world.revision+=1;return
	for item in config.objects:
		if item.id==id and eligible(item):
			found.append(id);dark.emit("relic",at);var people:Array=["human"]
			if item.has("tag"):
				for who in companions():
					if world.intelligence.tag(who)==item.tag and world.point(world.actors[who]).distance_to(at)<=6:people.append(who);break
			memory(id,people);world.revision+=1;return
func memory(id:String,people:Array)->void:
	world.memories.record_event("dark_discovery","dark-discovery:"+id+(":"+str(world.days.day()) if id=="stars" else ""),people,{"id":id})
func saved()->Dictionary:return {"found":found.duplicate(),"catches":catches.duplicate(),"loose":loose,"lamps":lamps.duplicate(true),"star_days":star_days.duplicate()}
func restore(data:Dictionary)->void:
	found=data.get("found",[]).duplicate();catches=data.get("catches",{}).duplicate();loose=int(data.get("loose",0));lamps=data.get("lamps",[]).duplicate(true);star_days=data.get("star_days",[]).duplicate();pending.clear();seated.clear()
func valid(data:Variant)->bool:
	if not data is Dictionary or data.keys().any(func(k):return k not in ["found","catches","loose","lamps","star_days"]):return false
	if not data.get("found",[]) is Array or not data.get("catches",{}) is Dictionary or not data.get("lamps",[]) is Array or not data.get("star_days",[]) is Array:return false
	var ids:Array=config.objects.map(func(i):return i.id)
	var seen:Array=[]
	for id in data.get("found",[]):
		if id not in ids or id in seen:return false
		seen.append(id)
	if not world.catalog._number(data.get("loose",0)) or int(data.get("loose",0))!=data.get("loose",0) or data.get("loose",0)<0 or data.get("loose",0)>2:return false
	for id in data.get("catches",{}):
		if not id.begins_with("fly-") or not id.trim_prefix("fly-").is_valid_int():return false
		var i:int=int(id.trim_prefix("fly-"))
		if i<0 or i>=dark.config.glows.size() or dark.config.glows[i].kind!="firefly":return false
		if not world.catalog._number(data.catches[id]) or data.catches[id]<1 or floor(data.catches[id])!=data.catches[id]:return false
	for day in data.get("star_days",[]):
		if not world.catalog._number(day) or day<1 or floor(day)!=day:return false
	for lamp in data.get("lamps",[]):
		if not lamp is Dictionary or not lamp.get("region") is String or (lamp.region!="home" and not world.interior.rooms().has(lamp.region)) or not world.catalog._pair(lamp.get("position")):return false
	return true
func place_jar()->Dictionary:
	var actor:Dictionary=world.actors.human
	if actor.region_id!="home" and not world.interior.rooms().has(actor.region_id):return world._error("wrong_region")
	if world.work.jobs.has("human") or int(actor.carry.get("firefly.jar",0))<1:return world.work.fail("no_jar",LocalText.text("ui.dark.no_firefly_jar"))
	var at:Vector2=world.point(actor)
	if lamps.any(func(l):return l.region==actor.region_id and dark.p(l.position).distance_to(at)<1):return world.work.fail("occupied",LocalText.text("ui.dark.jar_occupied"))
	actor.carry["firefly.jar"]-=1
	if actor.carry["firefly.jar"]==0:actor.carry.erase("firefly.jar")
	lamps.append({"region":actor.region_id,"position":[at.x,at.y]});world.revision+=1
	return {"ok":true,"message":LocalText.text("ui.dark.jar_placed")}
func reclaim_jar()->Dictionary:
	if world.work.carry_space("human")<1:return world.work.fail("backpack_full",LocalText.text("ui.dark.backpack_full"))
	for lamp in lamps:
		if lamp.region==world.actors.human.region_id and dark.p(lamp.position).distance_to(world.point(world.actors.human))<2:
			lamps.erase(lamp);world.actors.human.carry["firefly.jar"]=int(world.actors.human.carry.get("firefly.jar",0))+1;world.actors.human.pocketed=true;return {"ok":true,"message":LocalText.text("ui.dark.jar_reclaimed")}
	return world.work.fail("not_near",LocalText.text("ui.dark.jar_distance"))

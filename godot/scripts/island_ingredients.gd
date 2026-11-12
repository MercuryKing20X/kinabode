extends RefCounted
## Host-only renewable collection. World retains all route ownership.
var owner:WeakRef
var world:RefCounted:
	get:return owner.get_ref()
var config:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/island-ingredients.json"))
var ready_at:Dictionary={}
var discovered:Array=[]
var pending:Dictionary={}
var resident_pending:Dictionary={}
var drying:Dictionary={}
func _init(w:RefCounted)->void:owner=weakref(w)
func sources()->Array:
	var result:Array=[]
	for original in config.items:
		var item:Dictionary=original.duplicate(true)
		if item.has("facility"):
			var site:Dictionary=facility(str(item.facility),str(item.owner))
			if site.is_empty():continue
			item.position=collection_position(site)
		if world.resort!=null and world.resort.retired(item):continue
		result.append(item)
	return result
func facility(template:String,actor:String)->Dictionary:
	for s in world.leisure.sites.values():
		if world.resort!=null and world.resort.retired(s):continue
		if s.get("complete",false) and s.template_id==template and world.home_island.territory_at(world.point(s))==actor:return s
	return {}
func collection_position(site:Dictionary)->Array:
	var at:Vector2=world.point(site)
	for offset in [Vector2(0,4),Vector2(4,0),Vector2(-4,0),Vector2(0,-4),Vector2(0,6)]:
		var p:Vector2=at+offset
		if world.walkable("home",p):return [p.x,p.y]
	return [at.x,at.y]
func dry_position()->Vector2:
	var site:Dictionary=facility("produce-fishrack","companion-2")
	if site.is_empty():return Vector2.INF
	var point:Array=collection_position(site)
	return Vector2(point[0],point[1])
func visible(item:Dictionary)->bool:
	if item.get("metadata_only",false) or not world.locations.v3() or item.region!=world.actors.human.region_id:return false
	if item.has("farm_gate") and not world.farms.ready(str(item.farm_gate)):return false
	if item.region=="dark" and not world.dark.discoveries.illuminated(Vector2(item.position[0],item.position[1])):return false
	if item.has("facility"):
		return world.leisure.sites.values().any(func(s):return s.template_id==item.facility and s.get("complete",false) and world.home_island.territory_at(world.point(s))==item.owner)
	return true
func available(item:Dictionary)->bool:
	if not visible(item):return false
	if item.has("facility") and not ready_at.has(item.id):return false
	if world.forest.clock<float(ready_at.get(item.id,0)):return false
	if item.get("night",false) and world.days.phase().id!="night":return false
	if item.get("low_tide",false) and fmod(world.forest.clock,float(config.tide_period_seconds))>=float(config.low_tide_seconds):return false
	return true
func begin(id:String)->Dictionary:
	pending.clear()
	for item in sources():
		if item.id!=id:continue
		if not available(item) or world.work.jobs.has("human") or world.farms.active("human") or world.projects.active("human") or not world.fishing.held("human").is_empty():return world._error("ingredient_unavailable")
		var result:Dictionary=world.command("human",{"intent":"move","x":item.position[0],"y":item.position[1]})
		if result.ok:pending=item.duplicate(true)
		return result
	return world._error("unknown_ingredient")
func begin_resident(actor:String,source_id:String)->Dictionary:
	if world.hunger.rank(actor)>=2:return world._error("hungry")
	if actor=="human" or not world.actors.has(actor) or world.actors[actor].region_id!=world.actors.human.region_id:return world._error("different_region")
	if world.work.jobs.has(actor) or world.farms.active(actor) or world.projects.active(actor) or not world.fishing.held(actor).is_empty():return world._error("busy")
	for item in sources():
		if item.id!=source_id:continue
		if not available(item) or resident_pending.values().any(func(order):return order.id==source_id) or pending.get("id")==source_id:return world._error("ingredient_unavailable")
		var result:Dictionary=world.command(actor,{"intent":"move","x":item.position[0],"y":item.position[1]})
		if result.get("ok",false):resident_pending[actor]=item.duplicate(true)
		return result
	return world._error("unknown_ingredient")
func advance(_delta:float)->void:
	for actor in resident_pending.keys():
		var item:Dictionary=resident_pending[actor]
		var at:=Vector2(item.position[0],item.position[1])
		if world.actors[actor].region_id!=item.region or world.work.jobs.has(actor) or not available(item):resident_pending.erase(actor);continue
		if world._routes.has(actor):
			if world._routes[actor].back().distance_to(at)>.2:resident_pending.erase(actor)
			continue
		if world.point(world.actors[actor]).distance_to(at)<=.4:
			var harvest:Dictionary={str(item.id):int(item.amount)}
			if item.get("seed",false):harvest["seed."+str(item.id)]=1
			if world.storage.add(harvest):
				ready_at[item.id]=world.forest.clock+float(item.regrow_seconds)
				if item.id not in discovered:discovered.append(item.id)
				world.revision+=1
		resident_pending.erase(actor)

	for item in config.items:
		if item.has("facility") and not ready_at.has(item.id) and not facility(str(item.facility),str(item.owner)).is_empty():ready_at[item.id]=world.forest.clock+float(item.regrow_seconds)
	if not drying.is_empty() and world.forest.clock>=float(drying.ready_at) and drying.get("collect",false):
		if world.storage.add({"dried_fish":1}):
			if "dried_fish" not in discovered:discovered.append("dried_fish")
			drying.clear();world.revision+=1
	if pending.is_empty():return
	var at:=Vector2(pending.position[0],pending.position[1])
	if world.actors.human.region_id!=pending.region:pending.clear();return
	if world._routes.has("human"):
		if world._routes.human.back().distance_to(at)>.2:pending.clear()
		return
	if world.point(world.actors.human).distance_to(at)>.4 or not available(pending):pending.clear();return
	var harvest:Dictionary={str(pending.id):int(pending.amount)}
	if pending.get("seed",false):harvest["seed."+str(pending.id)]=1
	if world.storage.add(harvest):
		ready_at[pending.id]=world.forest.clock+float(pending.regrow_seconds)
		if pending.id not in discovered:discovered.append(pending.id)
		world.revision+=1
	pending.clear()
func saved()->Dictionary:
	var retained:Dictionary=drying.duplicate(true)
	if not retained.is_empty():retained.collect=false
	return {"ready_at":ready_at.duplicate(),"discovered":discovered.duplicate(),"drying":retained}
func valid(v:Variant)->bool:
	if not v is Dictionary or v.keys().any(func(k):return k not in ["ready_at","discovered","drying"]) or not v.get("ready_at",{}) is Dictionary or not v.get("discovered",[]) is Array:return false
	var ids:Array=config.items.map(func(i):return i.id)+world.farms.crops.keys()+["mushroom","fish"]
	for id in v.get("ready_at",{}):
		if id not in ids or not world.catalog._number(v.ready_at[id]) or v.ready_at[id]<0:return false
	var d:Variant=v.get("drying",{})
	if not d is Dictionary or (not d.is_empty() and (d.size()!=3 or d.keys().any(func(k):return k not in ["fish_id","ready_at","collect"]) or not d.get("fish_id") is String or d.fish_id.is_empty() or d.fish_id.length()>64 or not world.catalog._number(d.get("ready_at")) or d.ready_at<0 or not d.get("collect") is bool)):return false
	return v.get("discovered",[]).all(func(id):return id in ids and v.discovered.count(id)==1)
func restore(v:Dictionary)->void:
	resident_pending.clear()
	drying=v.get("drying",{}).duplicate(true)
	if not drying.is_empty():drying.collect=false
	ready_at=v.get("ready_at",{}).duplicate();discovered=v.get("discovered",[]).duplicate();pending.clear()

func dry_fish()->Dictionary:
	var at:Vector2=dry_position()
	if world.actors.human.region_id!="home" or world.point(world.actors.human).distance_to(at)>3 or world.work.jobs.has("human") or world._routes.has("human"):return world._error("not_near_drying_rack")
	if not world.leisure.sites.values().any(func(s):return s.get("complete",false) and s.template_id=="produce-fishrack" and world.home_island.territory_at(world.point(s))=="companion-2"):return world._error("unfinished_facility")
	if not drying.is_empty():
		if world.forest.clock<float(drying.ready_at):return world._error("fish_still_drying")
		drying.collect=true;return {"ok":true}
	var fish:Dictionary=world.fishing.held("human")
	if fish.is_empty():return world._error("no_owned_pending_fish")
	drying={"fish_id":str(fish.id),"ready_at":world.forest.clock+float(config.dry_seconds),"collect":false}
	world.fishing.fish.erase(fish.id);world.revision+=1
	return {"ok":true}

func note_obtained(id:String)->void:
	if id not in discovered:discovered.append(id)

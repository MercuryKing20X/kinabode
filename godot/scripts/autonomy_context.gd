extends RefCounted
## Bounded, provider-neutral view. Arguments are host data, never mutations or permissions.
const MAX_BYTES := 4096
static func build(world: RefCounted,id: String,events: Array=[],history: Array=[]) -> Dictionary:
	if not world.actors.has(id) or id=="human":return {"ok":false,"error":"unknown_autonomy_resident"}
	var actor: Dictionary=world.actors[id];var job: Dictionary=world.work.jobs.get(id,{})
	var result: Dictionary={"ok":true,"version":1,"world_id":world.world_id,"resident_id":id,"source":"game_event","self":{"id":id,"name":str(actor.name).left(24),"region_id":actor.region_id,"position":actor.position.duplicate(),"activity":actor.activity,"carry":actor.carry.duplicate(),"mood":world.director.moods.summary(id)},"goal":{"intent":job.get("intent",""),"phase":job.get("phase",""),"target_id":job.get("target_id","")},"nearby":[],"nearby_total":0,"events":[],"recent_dialogue":[],"truncated":false}
	var nearby: Array=world.actors.values().filter(func(other):return other.id!=id and other.region_id==actor.region_id and world.point(other).distance_to(world.point(actor))<=12)
	result.self["relationship"]=world.relationships.summary(id)
	result.self["wish"]=world.wishes.summary(id)
	result.self["weather"]=world.weather.summary()
	if world.moon!=null and not world.moon.config.is_empty():result.self["moon_island"]=world.moon.summary();result.self["barbecues"]=world.barbecue_summaries().filter(func(s):return s.region_id==actor.region_id).map(func(s):return {"id":s.id,"position":s.position,"state":s.state,"portions":s.portions})
	result.self["schedule"]=world.schedules.summary(id)
	result.self["personality"]=world.personality.summary(id)
	result.self["intelligence"]=world.intelligence.summary(id)
	if world.hunger!=null and world.hunger.has_method("summary"):result.self["hunger"]=world.hunger.summary(id)
	nearby.sort_custom(func(a,b):return world.point(a).distance_squared_to(world.point(actor))<world.point(b).distance_squared_to(world.point(actor)))
	result.nearby_total=nearby.size()
	for other in nearby.slice(0,16):result.nearby.append({"id":str(other.id).left(64),"name":str(other.name).left(24),"activity":str(other.activity).left(32)})
	for entry in events.slice(0,6):
		if entry is Dictionary:result.events.append({"id":str(entry.get("id","")).left(96),"kind":str(entry.get("kind","")).left(40),"text":str(entry.get("text","")).left(80)})
	for entry in history.slice(maxi(0,history.size()-3)):
		if entry is Dictionary:result.recent_dialogue.append({"sender_id":str(entry.get("sender_id","")).left(64),"kind":str(entry.get("kind","message")).left(20),"text":str(entry.get("text","")).left(100)})
	if world.projects.active(id):result.goal={"intent":"build_house","target_id":world.projects.plans[id].site_id}
	elif world.farms.active(id):result.goal={"intent":"manage_farm","target_id":world.farms.orders[id].farm_id}
	elif world.homestead.active(id):result.goal={"intent":"homestead","target_id":world.homestead.config.site.id}
	result.truncated=nearby.size()>result.nearby.size() or events.size()>result.events.size()
	while JSON.stringify(result).to_utf8_buffer().size()>MAX_BYTES:
		result.truncated=true
		if not result.nearby.is_empty():result.nearby.pop_back()
		elif not result.events.is_empty():result.events.pop_back()
		elif not result.recent_dialogue.is_empty():result.recent_dialogue.pop_front()
		else:return {"ok":false,"error":"autonomy_context_too_large"}
	return result.duplicate(true)

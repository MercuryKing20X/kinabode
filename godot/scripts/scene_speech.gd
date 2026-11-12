extends RefCounted
## Observes existing simulation only. All output is selected inside the original idle outlet.
var owner:WeakRef
var world:RefCounted:
	get:return owner.get_ref()
var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/companions/scene-speech.json"))
var pending:Dictionary={}
var previous:Dictionary={}
var near_seconds:Dictionary={}
var distant:Dictionary={}
var first_seen:Dictionary={}
var assigned:Dictionary={}
var phase_seen:Dictionary={}
var recent_positions:Array=[]
var still:=0.0
var walked:=0.0
var reversals:=0
var last_vector:=Vector2.ZERO
var last_check:=0.0
var seen_work:Array=[]
var seen_fish:Array=[]
var seen_ingredients:Array=[]
var seen_journal:Dictionary={}
var delivered:Array=[]
var said:Dictionary={}
var said_day:=-1
var day:=-1
func _init(w:RefCounted)->void:owner=weakref(w)
func reset()->void:
	previous.clear();pending.clear();near_seconds.clear();distant.clear();first_seen.clear();assigned.clear();phase_seen.clear();recent_positions.clear();still=0;walked=0;reversals=0;seen_work=world.work.events.map(func(e):return e.id);seen_fish=world.fishing.fish.keys();seen_ingredients=world.ingredients.discovered.duplicate();seen_journal=world.journal.discoveries.duplicate(true);last_check=world.director.time;said.clear();said_day=-1
func emit_at(scene:String,region:String,at:Vector2,exclude:String="")->void:
	for id in world.director.routines:
		var actor:Dictionary=world.actors[id]
		if id==exclude or actor.region_id!=region or world.point(actor).distance_to(at)>12:continue
		var queue:Array=pending.get(id,[])
		if queue.any(func(e):return e.scene==scene):continue
		queue.append({"scene":scene,"expires":world.director.time+60,"region":region,"at":at})
		if queue.size()>12:queue.pop_front()
		pending[id]=queue
func advance()->void:
	var now:float=world.director.time
	if now-last_check<.5:return
	var dt:float=now-last_check;last_check=now
	var h:Dictionary=world.actors.human;var p:Vector2=world.point(h);var region:String=h.region_id
	if day!=world.days.day():day=world.days.day();first_seen.clear();phase_seen.clear();assigned.clear()
	var weather:String=world.weather.current().id
	var south:bool=region=="home" and world.home_island.contains(p)
	var snap:Dictionary={"point":p,"region":region,"weather":weather,"south":south,"run":world.is_running("human"),"cat":world.cat.pose,"cat_point":world.cat.position,"cat_region":world.cat.region}
	if previous.is_empty():previous=snap;return
	var move:Vector2=p-previous.point if region==previous.region else Vector2.ZERO
	still=still+dt if move.length()<.03 else 0.0
	if move.length()>.15:
		walked+=move.length()
		if last_vector.length()>.1 and move.normalized().dot(last_vector.normalized())<-.5:reversals+=1
		last_vector=move
		recent_positions.append({"point":p,"time":now})
		recent_positions=recent_positions.filter(func(e):return now-e.time<40)
		if recent_positions.size()>80:recent_positions.pop_front()
		if walked>10 and (reversals>=3 or (recent_positions.size()>8 and p.distance_to(recent_positions[0].point)<2)):
			emit_at("loops",region,p);walked=0;reversals=0;recent_positions.clear()
	if snap.run and not previous.run and move.length()>.1:emit_at("sprint",region,p)
	if previous.weather=="rain" and weather!="rain":emit_at("rain_stop",region,p)
	if previous.region.begins_with("room.") and region=="home":emit_at("exit_house",region,p)
	if region=="home" and previous.region=="home" and south!=previous.south:
		emit_at("arrive_south" if south else "back_home",region,p);emit_at("cross_bridge",region,p)
	elif region=="home" and previous.region!="home" and not previous.region.begins_with("room."):emit_at("back_home",region,p)
	for id in world.director.routines:
		var a:Dictionary=world.actors[id];var close:bool=a.region_id==region and world.point(a).distance_to(p)<=3
		if move.length()>.1 and a.region_id==region and world.point(a).distance_to(p)>16:distant[id]=true
		if close and move.length()>.1 and distant.get(id,false):emit_at("reunion",region,world.point(a));distant.erase(id)
		near_seconds[id]=float(near_seconds.get(id,0))+dt if close and still>0 else 0.0
		if world.work.jobs.has(id) and not world.director.routines[id].owns_job():assigned[id]=true
		if world.farms.active(id):assigned[id]=true
		if a.region_id==region and world.farms.active(id):emit_at("peer_farm",region,world.point(a),id)
		var was_moving:bool=bool(previous.get("moving_"+id,false))
		var moving:bool=world._routes.has(id)
		if was_moving and not moving and close:emit_at("peer_stop",region,world.point(a),id)
		snap["moving_"+id]=moving
	if world.cat.discovered:
		if snap.cat!=previous.cat:
			var context:String={"rub":"cat_rub","held":"cat_hold","sleep":"cat_sleep"}.get(snap.cat,"")
			if not context.is_empty():emit_at(context,world.cat.region,world.cat.position)
		if world.cat.region==previous.cat_region and world.cat.position.distance_to(previous.cat_point)>.5:emit_at("cat_run",world.cat.region,world.cat.position)
	for e in world.work.events:
		if e.id in seen_work:continue
		seen_work.append(e.id)
		if e.status=="completed" and e.has("progress") and world.actors.has(e.actor_id):emit_at("peer_chop",world.actors[e.actor_id].region_id,world.point(world.actors[e.actor_id]),e.actor_id)
	seen_work=world.work.events.map(func(e):return e.id)
	for fid in world.fishing.fish:
		if fid in seen_fish:continue
		var fish:Dictionary=world.fishing.fish[fid];var catcher:String=str(fish.owner_id)
		if world.actors.has(catcher):emit_at("peer_fish",world.actors[catcher].region_id,world.point(world.actors[catcher]),catcher)
	seen_fish=world.fishing.fish.keys()
	for item in world.ingredients.discovered:
		if item not in seen_ingredients:emit_at("new_ingredient",region,p)
	seen_ingredients=world.ingredients.discovered.duplicate()
	for catcher in world.journal.discoveries:
		if world.journal.discoveries[catcher].size()>seen_journal.get(catcher,{}).size() and world.actors.has(catcher):emit_at("new_fish",world.actors[catcher].region_id,world.point(world.actors[catcher]))
	seen_journal=world.journal.discoveries.duplicate(true)
	previous=snap
func contexts(id:String)->Array:
	var result:Array=[];var a:Dictionary=world.actors[id];var h:Dictionary=world.actors.human
	if a.region_id!=h.region_id:return result
	var p:Vector2=world.point(a);var hp:Vector2=world.point(h)
	for e in pending.get(id,[]):
		if e.expires>=world.director.time and e.region==a.region_id and p.distance_to(e.at)<=12:result.append(e.scene)
	if a.region_id.begins_with("room."):return result
	var phase:String=world.days.phase().id
	if not first_seen.has(id) and phase=="morning":result.append("morning")
	var phase_key:String=id+":"+phase
	if not phase_seen.has(phase_key):
		var context:String={"afternoon":"noon","dusk":"dusk","night":"night"}.get(phase,"")
		if not context.is_empty():result.append(context)
	if float(near_seconds.get(id,0))>=10:result.append("quiet_company")
	if still>=30:result.append("idle")
	if world.days.within_day()>=world.days.day_seconds*.9 and not assigned.has(id):result.append("no_work")
	if world.weather.current().id=="rain":result.append("rain")
	if still>2 and hp.distance_to(p)<=12 and not world.fishing.shore("human").is_empty():result.append("water")
	var facing:Vector2={"up":Vector2.UP,"down":Vector2.DOWN,"left":Vector2.LEFT,"right":Vector2.RIGHT}.get(a.facing,Vector2.DOWN)
	if a.region_id=="home":
		var layout:Dictionary=world.catalog.regions.home.get("layout",{})
		for cliff in layout.get("cliffs",[]):
			var poly:PackedVector2Array=PackedVector2Array(cliff.polygon.map(func(v):return Vector2(v[0],v[1])))
			if poly.size()>0 and p.distance_to(poly[0])<12 and (poly[0]-p).normalized().dot(facing)>.5:result.append("mountain")
		var coast:Dictionary=world.fishing.shore(id)
		if not coast.is_empty():
			var hook:=Vector2(coast.hook[0],coast.hook[1])
			if (hook-p).normalized().dot(facing)>.5:result.append("sea")
		var bridge:Rect2=Rect2(79.5,108,3,75)
		if bridge.grow(3).has_point(p):result.append("bridge")
		if phase=="night" and world.moon!=null and world.moon.contains(p):result.append("moon")
		for site in world.objects.values():
			if site.get("kind")=="construction_site" and site.get("owner_id","")==id and int(site.get("stage_index",0))==5 and hp.distance_to(world.point(site))<5 and still>=3:result.append("her_door")
	if world.cat.discovered and world.cat.region==a.region_id and world.cat.position.distance_to(p)<8:
		if world.cat.pose=="sleep":result.append("cat_sleep")
		elif world.cat.pose=="held":result.append("cat_hold")
		elif world.cat.pose=="rub":result.append("cat_rub")
	return result
func choose(id:String)->Dictionary:
	if said_day!=world.days.day():said.clear();said_day=world.days.day()
	var tag:String=world.personality.tag(id)
	if not data.scenes.values()[0].has(tag):return {}
	for scene in contexts(id):
		var options:Array=data.scenes[scene][tag].filter(func(row):return not said.get(id,{}).has(row.id) and world.personality.allowed_line(id,row.en if TranslationServer.get_locale().begins_with("en") else row.zh))
		if options.is_empty():continue
		var row:Dictionary=options[0]
		return {"scene":scene,"text":row.en if TranslationServer.get_locale().begins_with("en") else row.zh,"id":row.id}
	return {}
func note(id:String,scene:String,line_id:String="")->void:
	if world.director.local_dialogue!=null:world.director.local_dialogue.note_scene(id,line_id)
	if said_day!=world.days.day():said.clear();said_day=world.days.day()
	var own:Dictionary=said.get(id,{});own[line_id]=true;said[id]=own
	if scene=="morning":first_seen[id]=true
	if scene in ["noon","dusk","night"]:phase_seen[id+":"+str(world.days.phase().id)]=true
	var queue:Array=pending.get(id,[]);pending[id]=queue.filter(func(e):return e.scene!=scene and e.expires>=world.director.time)
	delivered.append({"actor_id":id,"scene":scene,"time":world.director.time})
	if delivered.size()>256:delivered.pop_front()

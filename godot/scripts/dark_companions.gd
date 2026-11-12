extends RefCounted
## Local authored behavior only. Reuses Hunger queue and World routes, shared speech gates.
var _owner:WeakRef
var dark:RefCounted:
	get:return _owner.get_ref()
var world:RefCounted:
	get:return dark.world
var after:Dictionary={}
var spoken:Dictionary={}
var reacted:Dictionary={}
var owned:Dictionary={}
var looking:Dictionary={}
var noticed:Dictionary={}
var relaxing:Dictionary={}
var revealed:Array=[]
var rituals:Dictionary={}
func _init(source:RefCounted)->void:_owner=weakref(source)
func clear()->void:after.clear();spoken.clear();reacted.clear();owned.clear();looking.clear();noticed.clear();relaxing.clear()
func route_lit(route:Array,origin:Vector2)->bool:
	for point in route:
		var steps:int=ceili(origin.distance_to(point)*2)
		for step in range(steps+1):
			if not dark.permanent(origin.lerp(point,float(step)/maxi(1,steps))):return false
		origin=point
	return true
func owns_follow(id:String)->bool:
	var lease:Dictionary=world.hunger.owned_routes.get(id,{})
	return world._routes.has(id) and lease.has("route") and is_same(world._routes[id],lease.route)
func owns_wander(id:String)->bool:
	return world._routes.has(id) and owned.has(id) and is_same(world._routes[id],owned[id])
func retire_wander(r:RefCounted,cancel:bool)->void:
	# A later route to the same endpoint belongs to the later command.
	if cancel and owns_wander(r.ID):world._routes.erase(r.ID);world.actors[r.ID].activity="idle"
	if owned.has(r.ID):
		owned.erase(r.ID);r.owns_route=false;r.kind="";r.elapsed=0.0;world.director.destinations.erase(r.ID)
func blocked(r:RefCounted)->bool:
	var id:String=r.ID
	return not r.enabled or r.held or r.time<r.visual_quiet_until or world.director.time<float(world.hunger.quiet_until.get(id,0)) or world.fishing.life.time<float(world.fishing.life.quiet_until.get(id,0)) or world.activities.blocked(id,false) or world.shared_activity.holds(id) or world.work.jobs.has(id) or world.projects.active(id) or world.farms.active(id) or world.homestead.active(id) or r.transporting() or not world.fishing.held(id).is_empty()
func speech(r:RefCounted,context:String)->bool:
	if blocked(r) or not r.chatter or not world.director.can_say_local(r.ID,context):return false
	var pool:Array=world.intelligence.speech_pool(r.ID,context)
	var candidates:Array=world.personality.selection(r.ID,pool,r.recent_lines)
	if candidates.is_empty():return false
	var index:int=int(spoken.get(r.ID+context,0))%candidates.size()
	var gap:float=r.rng.randf_range(r.config.speech_interval[0],r.config.speech_interval[1])*world.director.moods.interval(r.ID,"speech")*world.personality.speech_scale(r.ID)
	if world.director.say_local(r.ID,candidates[index],context,gap,float(world.director.moods.config.get("village_gap",14))):
		spoken[r.ID+context]=index+1;r.recent_lines.append(candidates[index])
		if r.recent_lines.size()>6:r.recent_lines.pop_front()
		return true
	return false
func clear_relax(id:String)->void:
	relaxing.erase(id)
	if not world.work.jobs.has(id) and not world._routes.has(id) and world.actors[id].activity in ["local_look","local_sit","local_rest","local_rise"]:world.actors[id].activity="idle"
func landmark(origin:Vector2)->Vector2:
	var candidates:Array=[]
	for glow in dark.config.glows:
		var at:Vector2=dark.p(glow.position)
		if not dark.permanent(at) and not noticed.has(str(at)):candidates.append(at)
	for area in dark.config.areas:
		if area.has("beacon") and area.id not in dark.beacons and not noticed.has(str(dark.p(area.beacon))):candidates.append(dark.p(area.beacon))
	if candidates.is_empty():return Vector2.INF
	candidates.sort_custom(func(a,b):return origin.distance_squared_to(a)<origin.distance_squared_to(b))
	return candidates[0]
func ritual(at:Vector2)->void:
	for id in dark.discoveries.companions():
		if world.point(world.actors[id]).distance_to(at)<12:rituals[id]={"point":at,"until":world.director.time+120}
func tick(r:RefCounted,_delta:float)->bool:
	if not dark.here() or world.actors[r.ID].region_id!="dark":return false
	var id:String=r.ID
	if owned.has(id) and not owns_wander(id):
		var arrived:bool=not world._routes.has(id)
		retire_wander(r,false)
		if arrived:relaxing[id]={"started":world.director.time,"until":world.director.time+5.0}
	if blocked(r):
		retire_wander(r,true);looking.erase(id);clear_relax(id)
		return true
	# Darkness never steals an explicit movement, even when it has no Work job.
	if world._routes.has(id) and not owns_wander(id) and not owns_follow(id):clear_relax(id);return true
	var at:Vector2=world.point(world.actors[id]);var human:Vector2=world.point(world.actors.human)
	for glow in dark.config.glows:
		var glow_at:Vector2=dark.p(glow.position)
		if glow_at.distance_to(human)<=dark.visible_radius():noticed[str(glow_at)]=true
	for area in dark.config.areas:
		if area.has("beacon") and dark.p(area.beacon).distance_to(human)<=dark.visible_radius():noticed[str(dark.p(area.beacon))]=true
	if id in dark.discoveries.seated:
		if not reacted.get(id+"stars",false) and speech(r,"dark_stars"):reacted[id+"stars"]=true
		return true
	var tag:String=world.intelligence.tag(id)
	if tag=="quiet" and not reacted.has(id+"black_truffle"):
		for ingredient in world.ingredients.sources():
			if ingredient.id!="black_truffle" or not world.ingredients.available(ingredient):continue
			var truffle_at:=Vector2(ingredient.position[0],ingredient.position[1])
			if at.distance_to(truffle_at)<=6 and speech(r,"ingredient_truffle"):reacted[id+"black_truffle"]=true
	if rituals.has(id):
		var ceremony:Dictionary=rituals[id]
		if world.director.time>ceremony.until:rituals.erase(id)
		elif speech(r,"dark_beacon"):
			rituals.erase(id)
		elif not world._routes.has(id):
			var index:int=dark.discoveries.companions().find(id)
			var goal:Vector2=ceremony.point+Vector2.from_angle(index*TAU/4)*3
			var path:Array=world.find_route(id,goal)
			if not path.is_empty() and route_lit(path,at):
				world.hunger.clear_follow(id);world.route_to(id,goal);owned[id]=world._routes[id];r.owns_route=true;r.kind="wander"
		return true
	for item in dark.discoveries.config.objects:
		if item.get("tag","")!=tag or item.id in dark.discoveries.found or item.id in revealed:continue
		var spot:Vector2=dark.p(item.position)
		if at.distance_to(spot)<1.6 and dark.discoveries.illuminated(spot):revealed.append(item.id);speech(r,"dark_own")
		elif at.distance_to(spot)<5 and dark.discoveries.illuminated(spot) and dark.torch.remaining>0 and not world._routes.has(id):
			var path:Array=world.find_route(id,spot)
			var safe:bool=not path.is_empty()
			var previous:Vector2=at
			for end in path:
				for step in range(10):
					if not dark.discoveries.illuminated(previous.lerp(end,step/9.0)):safe=false
				previous=end
			if safe:
				world.hunger.clear_follow(id);world.route_to(id,spot);owned[id]=world._routes[id];r.owns_route=true;r.kind="wander";speech(r,"dark_own");return true
	var fear:bool=not dark.permanent(human) or not dark.permanent(at)
	if fear and tag=="gentle" and not looking.has(id) and world.director.time>=float(after.get(id+"pause",0)):
		for glow in dark.config.glows:
			var target_at:Vector2=dark.p(glow.position)
			if dark.discoveries.illuminated(target_at) and at.distance_to(target_at)<4:
				world.hunger.clear_follow(id);looking[id]={"target":target_at,"until":world.director.time+float(dark.config.personality_motion.gentle_pause_seconds)};after[id+"pause"]=world.director.time+30;break
	if not fear and world.hunger.rank(id)>=3:
		retire_wander(r,true);clear_relax(id);looking.erase(id)
		world.hunger.follow(id)
		return true
	if looking.has(id):
		if not fear or world.director.time>=float(looking[id].until):looking.erase(id)
		else:
			if float(world.motion_state(id).get("still_seconds",0))>=.3:r._face(looking[id].target)
			return true
	if fear:
		clear_relax(id)
		retire_wander(r,true)
		world.hunger.follow(id,true)
	else:
		world.hunger.clear_follow(id)
		if relaxing.has(id):
			var elapsed:float=world.director.time-float(relaxing[id].started)
			if world.director.time>=float(relaxing[id].until):clear_relax(id)
			else:
				world.actors[id].activity="local_look" if tag=="quiet" else "local_sit"
				if tag in ["gentle","laborious"]:r._face(dark.p(dark.config.camp))
				if elapsed<1 and float(world.motion_state(id).get("still_seconds",0))>=.3:
					var glow:Vector2=landmark(at)
					if glow.is_finite():r._face(glow)
		if world.hunger.rank(id)<2 and not relaxing.has(id) and world.director.time>=float(after.get(id,0)) and not world._routes.has(id):
			var unit:Dictionary=world.intelligence.catalog.behavior.get(dark.config.get("companion_behaviors",{}).get(world.intelligence.tag(id),""),{})
			after[id]=world.director.time+float(unit.get("cooldown_seconds",30))+float(posmod(hash(id),9))
			for i in range(8):
				var angle:float=float(posmod(hash(id)+i*73+int(world.director.time),360))*PI/180
				var target:Vector2=at+Vector2(cos(angle),sin(angle))*2.8
				if not dark.permanent(target) or not world.director.available_position(id,"dark",target):continue
				var route:Array=world.find_route(id,target)
				if route.is_empty() or not route_lit(route,at):continue
				var previous_issuing:bool=world.hunger.issuing
				world.hunger.issuing=true
				var moved:bool=r._move_to(target)
				world.hunger.issuing=previous_issuing
				if moved:
					if tag=="lively" and world.hunger.rank(id)<2:world._forced_runs[id]=true
					r.kind="wander";r.owns_route=true;owned[id]=world._routes[id]
					break
	if world.director.time<float(reacted.get(id,0)):return true
	var context:="dark_fear" if fear else "dark_glow"
	var target:=Vector2.INF
	if dark.torch.remaining>0 and dark.torch.remaining<=float(dark.config.torch_warning_seconds):context="dark_warning"
	elif dark.torch.owned and dark.torch.remaining==0 and fear:context="dark_out"
	else:
		for event in dark.events:
			if event.kind in ["small_fire","beacon","torch_light","relic","firefly"] and int(event.serial)>int(reacted.get(id+"serial",0)):context="dark_beacon" if event.kind=="beacon" else "dark_relic" if event.kind=="relic" else "dark_firefly" if event.kind=="firefly" else "dark_fire"
	if tag=="laborious" and fear:
		var light:Vector2=dark.nearest_light()
		if light.is_finite() and human.distance_to(light)>float(dark.config.personality_motion.orange_return_distance):context="dark_warning"
	if tag=="quiet" and context=="dark_fear":
		var relics:Array=dark.discoveries.config.objects.filter(func(i):return i.id not in dark.discoveries.found and (not i.has("tag") or i.tag=="quiet"))
		relics.sort_custom(func(a,b):return at.distance_to(dark.p(a.position))<at.distance_to(dark.p(b.position)))
		target=dark.p(relics[0].position) if not relics.is_empty() else landmark(at)
		if not target.is_finite():return true
	if speech(r,context):
		reacted[id]=world.director.time+38
		if not dark.events.is_empty():reacted[id+"serial"]=dark.events.back().serial
		# Only pause the exact owned follow, and turn after the body settles.
		if target.is_finite():
			world.hunger.clear_follow(id)
			looking[id]={"target":target,"until":world.director.time+1.0}
	return true

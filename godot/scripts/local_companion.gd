class_name LocalCompanion
extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
const DecisionRandom=preload("res://scripts/decision_random.gd")

# Engine-authored ambient behavior, never inference, never a substitute model reply.
# Shared implementation for every non-human resident; fixtures stay passive.
var ID := "codex"
var _owner: WeakRef
var world: RefCounted:
	get: return _owner.get_ref()
var enabled := false
var chatter := true
var held := false
var visual_quiet_until := 0.0
var intelligence_preset_id:=""
var issuing := false
var time := 0.0
var next_decision := 6.0
var needs=preload("res://scripts/resident_needs.gd").new()
var next_speech := 12.0
var wander_anchor := Vector2.ZERO
var anchor_region := ""
var was_busy := true
var last_walk := -100.0
var kind := ""
var elapsed := 0.0
var duration := 0.0
var route_timeout:=24.0
var owns_route := false
var seat_id := ""
var owned_job_id := ""
var facility_cooldowns: Dictionary = {}
var focus_point := Vector2.ZERO
var preferences: Dictionary = {}
var events: Array = []
var serial := 0
var recent_lines: Array = []
var recent_behaviors: Array = []
var rng := RandomNumberGenerator.new()
var decision_rng:DecisionRandom
var config: Dictionary = {}
var return_visit=preload("res://scripts/companion_return.gd").new()

func _init(owner_world: RefCounted, resident_id: String = "codex") -> void:
	_owner = weakref(owner_world); ID = resident_id
	preferences = world.residents.preferences_for(ID)
	config = JSON.parse_string(FileAccess.get_file_as_string("res://content/companions/local-life.json"))
	rng.randomize()
	decision_rng=DecisionRandom.new(rng)

func set_enabled(value: bool) -> void:
	if enabled != value: world.revision += 1
	enabled = value
	if not enabled: interrupt(8)
	else: next_decision = time + decision_rng.randf_range(1.5, 4.5)

func set_chatter(value: bool) -> void:
	if chatter != value: world.revision += 1
	chatter = value

func set_held(value: bool) -> void:
	if value == held: return
	held = value
	world.revision += 1
	interrupt(8)
	next_speech = maxf(next_speech, time + 12)

func interrupt(cooldown: float = 35.0) -> void:
	if world.flower_gifts != null: world.flower_gifts.cancel(ID)
	var cancel_job := owns_job()
	owned_job_id = ""
	if cancel_job: world.work.stop(ID, false)
	if world.director != null: world.director.destinations.erase(ID)
	if owns_route: world._routes.erase(ID)
	if not seat_id.is_empty() and world.work.claims.get(seat_id) == ID: world.work.claims.erase(seat_id)
	if not kind.is_empty() and not world.work.jobs.has(ID) and (owns_route or not world._routes.has(ID)):
		world.actors[ID].activity = "idle"
		world.revision += 1
	owns_route = false; seat_id = ""; kind = ""; elapsed = 0.0
	next_decision = maxf(next_decision, time + cooldown)

func command_received(actor_id: String, intent: String) -> void:
	if actor_id != ID or issuing: return
	if intent == "stop": visual_quiet_until = time + 120.0
	interrupt(120.0 if intent == "stop" else 35.0)
	next_speech = maxf(next_speech, time + 12)

func owns_job() -> bool:
	return not owned_job_id.is_empty() and world.work.jobs.get(ID, {}).get("id") == owned_job_id

func transporting() -> bool:
	# Existing gift/legacy carry stays physical; no idle take, store or consumption.
	# Preserve real in-flight engineering receipts and unfinished cooking/furniture.
	if not str(world.actors[ID].get("furniture_id","")).is_empty():return true
	if not world.homestead.plans.get(ID,{}).get("receipt",{}).is_empty():return true
	return false

func blocked(include_follow:bool=true,include_pending_fish:bool=true) -> bool:
	return world.shared_activity.contains(ID) or (world.deliveries!=null and world.deliveries.active(ID)) or held or world.activities.blocked(ID,include_follow) or world.farms.orders.get(ID,{}).get("status") == "working" or world.projects.active(ID) or (world.work.jobs.has(ID) and not owns_job()) or transporting() or (include_pending_fish and world.fishing!=null and not world.fishing.held(ID).is_empty()) or (world._routes.has(ID) and not owns_route and not owns_job() and not (not include_follow and world.activities.following.has(ID) and world.hunger.owned_routes.get(ID,{}).has("route") and is_same(world.hunger.owned_routes[ID].route,world._routes[ID])))

func state() -> Dictionary:
	var result := {"source": "local_rules", "enabled": enabled, "chatter": chatter, "paused": held, "behavior": kind if not kind.is_empty() else "idle", "target_id": world.work.jobs.get(ID,{}).get("target_id", seat_id), "mood":world.director.moods.summary(ID)}
	if kind == "flower_gift":
		var gesture: Dictionary = world.flower_gifts.presentation(ID)
		gesture.erase("progress") # Rendering clocks are not authoritative snapshot changes.
		result["gesture"] = gesture
	return result

func advance(delta: float) -> void:
	time += delta
	world.director.local_speech_window.emit(ID)
	if not world.intelligence.compatibility and intelligence_preset_id!=world.intelligence.preset_id(ID):apply_intelligence_preferences()
	if not enabled or not world.residents.supports(world.actors[ID],"move"):return
	if world.director.brains.has(ID) and world.director.brains[ID].active():
		# The brain chooses; this legacy routine retains only the shared speech outlet.
		if not held and not world.work.jobs.has(ID) and time>=next_speech and not world.activities.blocked(ID,false):
			if not world.director.memory_reminders.try_speak(ID) and not world.relationships.try_event(ID) and not world.wishes.try_event(ID) and not world.personality.try_event(ID):_speak("near")
		return
	# DIRECTION: 托管时其它系统不能直接让人走或打断。
	if not world.activities.squad_leader.is_empty():return
	if world.dark!=null and world.dark.companions.tick(self,delta):return
	if world.their_island!=null and world.their_island.story_tick(self,delta):return
	if world.activities.following.has(ID) and not held and not world.work.jobs.has(ID) and not world.activities.blocked(ID,false) and world.director.time>=float(world.hunger.quiet_until.get(ID,0)) and world.fishing.life.time>=float(world.fishing.life.quiet_until.get(ID,0)):
		var fact_spoken:=false
		if chatter and time>=next_speech and (world.days==null or not world.days.defer_idle(ID)):
			fact_spoken=world.director.memory_reminders.try_speak(ID) or world.relationships.try_event(ID) or world.wishes.try_event(ID) or world.personality.try_event(ID)
		if not fact_spoken:_speak("near")
	# A newly caught pending fish blocks idle movement, not its true thank-you.
	if needs.waiting.get(ID,{}).get("kind")=="fish" and needs.choose(world,ID).get("kind")=="satisfied":
		_speak("need_satisfied")
	if world.hunger!=null and world.hunger.has_method("holds_idle") and world.hunger.holds_idle(ID):return
	if blocked() or world.activities.suspended_follow.has(ID) or world.activities.commanded(ID):
		was_busy = true
		if not kind.is_empty(): interrupt(8)
		next_decision = maxf(next_decision, time + 8)
		return
	if not world.activities.default_follow_excluded.has(ID) and not world.work.jobs.has(ID) and world.director.time>=visual_quiet_until and world.hunger.can_follow(ID) and world.fishing.held(ID).is_empty() and not (kind in ["watch","look","stretch"] and not owns_route):
		if owns_route:interrupt(0)
		world.activities.following[ID]=true
		world.hunger.follow(ID)
		return
	if was_busy:
		if world.standard!=null and world.standard.react(ID):return
		wander_anchor = world.point(world.actors[ID]); anchor_region = world.actors[ID].region_id; was_busy = false
	if world.standard!=null and world.standard.waiting_reaction(ID):world.standard.react(ID);return
	if world.their_island!=null and world.their_island.try_finish_speech(self):return
	if return_visit.tick(self,delta):return
	if kind == "flower_gift":
		world.flower_gifts.advance(self, delta)
		return
	if kind in ["facility","daily_gesture"]:
		elapsed += delta
		if not owns_job() or elapsed > (6 if kind=="daily_gesture" else 120): interrupt(decision_rng.randf_range(5, 9)*world.director.moods.interval(ID,"action"))
		return
	if not kind.is_empty():
		elapsed += delta
		if owns_route:
			if world._routes.has(ID):
				if elapsed > (route_timeout if kind=="schedule" else 24.0): interrupt(12)
				return
			owns_route = false; elapsed = 0.0
			if kind=="relationship_sit_approach":
				if _start("rest"):duration=float(world.relationships.config.rewards.stay_seconds)
				return
			if kind == "rest":
				world.actors[ID].activity = "local_sit"
				if world.interior.furniture.has(seat_id): world.actors[ID].facing = world.interior.furniture[seat_id].facing
			else:
				world.actors[ID].activity = "local_look"
				if kind in ["garden","relationship_sea"]: _face(focus_point)
				else: _face_human()
				if kind == "nearby": _speak("arrive")
				if kind == "schedule":world.schedules.arrived(ID)
			world.revision += 1
		if kind == "rest":
			var activity := "local_sit" if elapsed < .55 else "local_rest" if elapsed < duration else "local_rise"
			if world.actors[ID].activity != activity:
				world.actors[ID].activity = activity; world.revision += 1
		elif kind == "look":
			var facing: String = ["left", "down", "right", "down"][mini(3, int(elapsed / 1.1))]
			if world.actors[ID].facing != facing: world.actors[ID].facing = facing; world.revision += 1
		if elapsed >= duration + (.5 if kind == "rest" else 0.0):
			interrupt(decision_rng.randf_range(config.decision_interval[0], config.decision_interval[1])*world.director.moods.interval(ID,"action"))
	elif time >= next_decision:
		if world.days==null or not world.days.defer_idle(ID,true):
			var spoken:=false
			if chatter and time>=next_speech and (world.days==null or not world.days.defer_idle(ID)):
				spoken=world.director.memory_reminders.try_speak(ID) or world.relationships.try_event(ID) or world.wishes.try_event(ID) or world.personality.try_event(ID)
			if not spoken:_choose()
	if chatter and time >= next_speech and not owns_route:
		if world.days==null or not world.days.defer_idle(ID):
			if not world.director.memory_reminders.try_speak(ID) and not world.relationships.try_event(ID) and not world.wishes.try_event(ID) and not world.personality.try_event(ID):_speak()

func apply_intelligence_preferences()->void:
	preferences=world.intelligence.preferences_for(ID)
	intelligence_preset_id=world.intelligence.preset_id(ID)

func _choose() -> void:
	var actor: Dictionary = world.actors[ID]
	var human: Dictionary = world.actors.human
	if preferences.weights.values().reduce(func(sum,value):return sum+float(value),0.0)>0 and world.relationships.try_reward(ID):return
	var weights: Dictionary = world.director.moods.weights(ID,preferences.weights)
	weights=world.relationships.weights(ID,weights)
	weights=world.personality.weights(ID,weights)
	weights=world.intelligence.behavior_weights(ID,weights)
	if weights.has("nearby"):weights.nearby*=float(config.get("idle_nearby_by_personality",{}).get(preferences.get("personality",""),config.get("idle_nearby_scale",1.0)))
	if weights.values().reduce(func(sum,value):return sum+float(value),0.0)>0 and world.schedules.try_start(self):return
	var options: Array = []
	for choice in weights:
		if choice == "flower_gift" and not world.flower_gifts.eligible(ID): continue
		if choice == "nearby" and (actor.region_id != human.region_id or world.point(actor).distance_to(world.point(human)) > 16): continue
		if choice in ["facility", "garden"] and (actor.region_id != "home" or world.farms.active(ID)): continue
		if not recent_behaviors.is_empty() and choice == recent_behaviors.back(): continue
		for i in range(int(round(float(weights[choice])*10))): options.append(choice)
	if last_walk < -50 and float(weights.get("wander",0))>0 and float(weights.get("wander",0))>=float(preferences.weights.get("wander",0)) and _start("wander"): return
	for attempt in range(4):
		if options.is_empty(): break
		var choice: String = options[decision_rng.randi_range(0, options.size()-1)]
		if _start(choice): return
		options = options.filter(func(value): return value != choice)
	next_decision = time + decision_rng.randf_range(3, 6)*world.director.moods.interval(ID,"action")

func _move_to(destination: Vector2) -> bool:
	if world.director.brains.has(ID) and world.director.brains[ID].active() and not world.director.brains[ID].executing:return false
	# The same move validation and authoritative movement as human/model commands.
	if not world.director.available_position(ID, world.actors[ID].region_id, destination): return false
	issuing = true
	var brain_move:bool=world.director.brains.has(ID) and world.director.brains[ID].active() and world.director.brains[ID].executing and world.director.brains[ID].current.get("source","")=="local"
	var already_host:bool=world.host_issuing.has(ID)
	if brain_move:world.host_issuing[ID]=true
	var result: Dictionary = world.command(ID, {"intent": "move", "x": destination.x, "y": destination.y})
	issuing = false
	if brain_move and not already_host:world.host_issuing.erase(ID)
	owns_route = result.ok
	if result.ok: world.director.destinations[ID] = {"region":world.actors[ID].region_id, "point":destination}
	return result.ok

func _start(choice: String) -> bool:
	if world.director.brains.has(ID) and world.director.brains[ID].active() and not world.director.brains[ID].executing:
		world.director.brains[ID].offer(choice,func():return _start(choice));return false
	if blocked(): return false
	interrupt(8)
	var actor: Dictionary = world.actors[ID]
	var point: Vector2 = world.point(actor)
	if choice == "flower_gift":
		if not world.flower_gifts.start(self): return false
	elif choice == "facility":
		if not _facility(): return false
		duration = 120
	elif choice == "garden":
		if not _garden(): return false
		duration = decision_rng.randf_range(4, 8)
	elif choice == "rest":
		if actor.region_id == "home" and world.shared_activity.locked(): return false
		var seated := false
		var seats: Array = world.nearby_camp_seats(ID) if actor.region_id == "home" else world.interior.furniture.values().filter(func(item): return item.recipe_id == "chair" and item.region_id == actor.region_id and world.interior.placed(item))
		if world.relationships.index(ID)>=2:
			seats=seats.filter(func(seat):return world.actors.human.region_id==actor.region_id and world.point(seat).distance_to(world.point(world.actors.human))<=float(world.relationships.config.seat_near_radius))
			seats.sort_custom(func(a,b):return world.point(a).distance_squared_to(world.point(world.actors.human))<world.point(b).distance_squared_to(world.point(world.actors.human)))
		for seat in seats:
			if world.work.claims.has(seat.id) or point.distance_to(world.point(seat)) > 8: continue
			if _move_to(world.point(seat)):
				world.work.claims[seat.id] = ID; seat_id = seat.id; seated = true; break
		if not seated: return false
		duration = decision_rng.randf_range(7, 12)
	elif choice in ["wander", "nearby"]:
		var origin: Vector2 = world.point(world.actors.human) if choice == "nearby" else point
		if choice == "nearby" and (point.distance_to(origin) > 18 or actor.region_id != world.actors.human.region_id): return false
		if choice == "wander" and actor.region_id == anchor_region and point.distance_to(wander_anchor)>float(preferences.wander_radius): origin=wander_anchor
		var found := false
		for attempt in range(6):
			var offset := Vector2.from_angle(decision_rng.randf_range(0, TAU)) * decision_rng.randf_range(2.0, minf(float(preferences.wander_radius),6.0))
			var target := origin + offset
			var human_distance: float = target.distance_to(world.point(world.actors.human))
			if human_distance < 1.8: continue
			if choice == "wander" and point.distance_to(world.point(world.actors.human)) <= 12 and human_distance > 12: continue
			if _move_to(target): found = true; break
		if not found: return false
		duration = decision_rng.randf_range(1.2, 2.8)
		last_walk = time
	else:
		actor.activity = "local_stretch" if choice == "stretch" else "local_look"
		if choice == "watch": _face_human()
		duration = 2.8 if choice == "stretch" else 4.4
	kind = choice; elapsed = 0.0
	recent_behaviors.append(choice)
	world.intelligence.note_behavior(ID,choice)
	if recent_behaviors.size() > 4: recent_behaviors.pop_front()
	world.revision += 1
	return true

func _face_human() -> void:
	var actor: Dictionary = world.actors[ID]
	var offset: Vector2 = world.point(world.actors.human) - world.point(actor)
	if actor.region_id != world.actors.human.region_id or offset.length() > float(config.notice_radius): return
	actor.facing = ("right" if offset.x > 0 else "left") if absf(offset.x) > absf(offset.y) else ("down" if offset.y > 0 else "up")

func greet() -> Dictionary:
	if not enabled: return {"ok": false, "message": LocalText.text("content.remaining.enable_daily_activities_first")}
	if blocked(): return {"ok": false, "message": LocalText.text("content.remaining.this_companion_is_busy_say_hello_when_they_re_free")}
	if world.actors[ID].region_id != world.actors.human.region_id: return {"ok": false, "message": LocalText.text("content.remaining.come_to_the_same_place_before_saying_hello")}
	if world.point(world.actors[ID]).distance_to(world.point(world.actors.human)) > 8: return {"ok": false, "message": LocalText.text("content.remaining.a_little_far_away_come_closer_to_say_hello")}
	_start("watch")
	_speak("greet", true)
	return {"ok": true}

func come_near() -> Dictionary:
	if not enabled: return {"ok": false, "message": LocalText.text("content.remaining.enable_daily_activities_first")}
	if not _start("nearby"): return {"ok": false, "message": LocalText.text("content.remaining.can_t_come_over_right_now_wait_until_they_re_free_or_come_closer")}
	return {"ok": true, "message": LocalText.text("content.remaining.they_re_walking_over_to_you")}

func _context() -> String:
	var actor: Dictionary = world.actors[ID]
	var point: Vector2 = world.point(actor)
	if kind == "rest": return "rest"
	if actor.region_id != "home": return "indoors"
	var camp:RefCounted=world.nearest_barbecue(ID,7)
	if camp!=null:
		if camp.station.state == "needs_turn": return "turn"
		if camp.station.state == "cooking": return "fire"
		if camp.station.state in ["ready", "eating"]: return "ready"
	if point.distance_to(world.point(world.actors.human)) < 7:
		if world.actors.human.activity == "chopping": return "working"
		if rng.randf() < .5: return "near"
	for object in world.objects.values():
		if object.region_id != actor.region_id or point.distance_to(world.point(object)) > 8: continue
		if object.kind == "construction_site":
			if int(object.get("stage_index", 0)) == 5: return "finished_home"
			if int(object.get("stage_index", 0)) > 0: return "building"
		if object.kind == "tree" and object.status == "mature": return "trees"
	return "ambient"

func _speak(context: String = "", explicit: bool = false) -> void:
	if not explicit and (not chatter or time < next_speech): return
	if not explicit and not world.director.moods.can_speak(ID,context):return
	if not explicit:
		var actor:Dictionary=world.actors[ID];var listener:Dictionary=world.actors.human
		# An inaudible candidate is not a delivered personal speech turn.
		if actor.region_id!=listener.region_id or world.point(actor).distance_to(world.point(listener))>12:return
		if world.director.time<world.director.speech_after:return
		if world.director.collecting_idle:
			world.director.queue_idle_speech(ID,context);return
	# Context may draw the routine RNG. Resolve it only after this candidate
	# has actually won the ordinary speech outlet, never while merely queued.
	if context.is_empty():context=_context()
	var pool: Array=config.lines.get(context,config.lines.ambient)
	if context in ["greet","arrive"]:pool=world.personality.pool(ID,"greet")
	elif context in ["ambient","near","rest","indoors","trees","finished_home","building","working","fire","ready"]:
		var mood: String=world.director.moods.summary(ID).id
		pool=world.personality.pool(ID,mood if mood!="calm" else "ambient")
		if kind=="schedule" and world.actors[ID].region_id=="home" and world.weather.current().id in ["rain","fog"] and mood=="calm":pool=world.personality.pool(ID,world.weather.current().id)
	var ordinary:bool=context in ["ambient","near","rest","indoors","trees","finished_home","building","working","fire","ready"]
	var scene_line:Dictionary=world.scene_speech.choose(ID) if ordinary and not explicit and world.scene_speech!=null else {}
	var relationship_lines: Array=world.relationships.lines(ID,context)
	var candidates:Array=world.personality.selection(ID,relationship_lines,recent_lines)
	# A small relationship aside must not silence the whole authored personality
	# once those particular lines reach their unchanged hourly repeat limit.
	if candidates.is_empty():candidates=world.personality.selection(ID,pool,recent_lines)
	if candidates.is_empty() and not scene_line.is_empty():candidates=[scene_line.text]
	var need:Dictionary=needs.choose(world,ID) if (ordinary or context=="need_satisfied") and not explicit else {}
	if candidates.is_empty() and need.is_empty():
		next_speech=time+float(config.speech_interval[0])*world.director.moods.interval(ID,"speech")*world.personality.speech_scale(ID)
		return
	var text: String = candidates[rng.randi_range(0, candidates.size() - 1)] if not candidates.is_empty() else ""
	if not scene_line.is_empty():text=scene_line.text;context="scene_"+scene_line.scene
	if not need.is_empty():text=("" if need.kind=="satisfied" else "☞ ")+need.text;context=("need_satisfied" if need.kind=="satisfied" else "need_"+need.kind)
	var gap: float=rng.randf_range(config.speech_interval[0],config.speech_interval[1])*world.director.moods.interval(ID,"speech")*world.personality.speech_scale(ID)
	var delivered:=false
	if not explicit:
		delivered=world.director.say_local(ID,text,context,gap,float(world.director.moods.config.get("village_gap",14)))
		# A village-gate rejection is not a delivered personal turn. Retry only
		# once the same gate opens; all actual delivery checks remain in Director.
		if not delivered:next_speech=maxf(time+.5,world.director.speech_after)
		else:
			if not need.is_empty():needs.delivered(ID,need.kind,time,world)
			world.relationships.delivered(ID,text)
			if need.is_empty() and not scene_line.is_empty():world.scene_speech.note(ID,scene_line.scene,scene_line.id)
	if delivered or explicit:
		recent_lines.append(text)
		if recent_lines.size() > 6: recent_lines.pop_front()
	serial += 1
	events.append({"serial": serial, "source": "local_rules", "context": context, "text": text, "time": time, "explicit": explicit, "actor_id":ID,"handled":not explicit,"delivered":delivered})
	if events.size() > 16: events.pop_front()
	if explicit:next_speech = time + gap

func _face(target: Vector2) -> void:
	var offset: Vector2 = target-world.point(world.actors[ID])
	world.actors[ID].facing = ("right" if offset.x>0 else "left") if absf(offset.x)>absf(offset.y) else ("down" if offset.y>0 else "up")

func _facility() -> bool:
	if world.actors[ID].region_id != "home" or world.farms.active(ID): return false
	var candidates: Array = []
	for site in world.leisure.sites.values():
		if world.leisure.art(site).get("recreation",{}).has("game"):continue
		if not site.complete or float(facility_cooldowns.get(site.id,0))>time: continue
		var distance: float = world.point(site).distance_to(world.point(world.actors[ID]))
		if distance > float(preferences.facility_radius): continue
		var art: Dictionary = world.leisure.art(site)
		if art.is_empty(): continue
		var weight: float = preferences.facilities.get(art.recreation.behavior, 1)
		candidates.append({"site":site,"score":weight*decision_rng.randf_range(.7,1.3)/(1+distance*.04)})
	candidates.sort_custom(func(a,b):return a.score>b.score)
	for candidate in candidates:
		var site: Dictionary = candidate.site
		issuing = true
		var result: Dictionary = world.command(ID,{"intent":"use_facility","target_id":site.id})
		issuing = false
		if not result.ok: facility_cooldowns[site.id]=time+12; continue
		owned_job_id = result.job_id
		world.work.jobs[ID]["source"] = "local_rules"
		facility_cooldowns[site.id] = time+100
		return true
	return false

func _garden() -> bool:
	if world.actors[ID].region_id!="home": return false
	var farms: Array = world.farms.farms.values().duplicate()
	farms.sort_custom(func(a,b):return world.farms.bounds(a).get_center().distance_squared_to(world.point(world.actors[ID]))<world.farms.bounds(b).get_center().distance_squared_to(world.point(world.actors[ID])))
	for farm in farms:
		var rect: Rect2 = world.farms.bounds(farm)
		if rect.get_center().distance_to(world.point(world.actors[ID]))>float(preferences.facility_radius): continue
		for p in [Vector2(rect.get_center().x,rect.end.y+2),Vector2(rect.position.x-2,rect.get_center().y),Vector2(rect.end.x+2,rect.get_center().y)]:
			if _move_to(p): focus_point=rect.get_center();last_walk=time;return true
	return false

func authored_reaction(choice: String) -> bool:
	# Short local feedback may be delivered while seated; never rise just to speak.
	if kind=="rest" and not owns_route:return true
	return _start(choice)

func advance_brain_executor(delta:float)->void:
	if kind == "flower_gift":
		world.flower_gifts.advance(self, delta)
		return
	if kind in ["facility","daily_gesture"]:
		elapsed += delta
		if not owns_job() or elapsed > (6 if kind=="daily_gesture" else 120): interrupt(decision_rng.randf_range(5, 9)*world.director.moods.interval(ID,"action"))
		return
	if not kind.is_empty():
		elapsed += delta
		if owns_route:
			if world._routes.has(ID):
				if elapsed > (route_timeout if kind=="schedule" else 24.0): interrupt(12)
				return
			owns_route = false; elapsed = 0.0
			if kind=="relationship_sit_approach":
				if _start("rest"):duration=float(world.relationships.config.rewards.stay_seconds)
				return
			if kind == "rest":
				world.actors[ID].activity = "local_sit"
				if world.interior.furniture.has(seat_id): world.actors[ID].facing = world.interior.furniture[seat_id].facing
			else:
				world.actors[ID].activity = "local_look"
				if kind in ["garden","relationship_sea"]: _face(focus_point)
				else: _face_human()
				if kind == "nearby": _speak("arrive")
				if kind == "schedule":world.schedules.arrived(ID)
			world.revision += 1
		if kind == "rest":
			var activity := "local_sit" if elapsed < .55 else "local_rest" if elapsed < duration else "local_rise"
			if world.actors[ID].activity != activity:
				world.actors[ID].activity = activity; world.revision += 1
		elif kind == "look":
			var facing: String = ["left", "down", "right", "down"][mini(3, int(elapsed / 1.1))]
			if world.actors[ID].facing != facing: world.actors[ID].facing = facing; world.revision += 1
		if elapsed >= duration + (.5 if kind == "rest" else 0.0):
			interrupt(decision_rng.randf_range(config.decision_interval[0], config.decision_interval[1])*world.director.moods.interval(ID,"action"))

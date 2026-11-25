class_name ResidentDirector
extends RefCounted
var quote_books:WeakRef
var quote_next:Dictionary={}
signal local_speech_window(actor_id:String)
signal world_speech(actor_id:String,target:String,line:String)
const LocalText=preload("res://scripts/localization.gd")

# One local routine per identity. Model bindings and capabilities are separate.
const Routine = preload("res://scripts/local_companion.gd")
var _owner: WeakRef
var world: RefCounted:
	get: return _owner.get_ref()
var routines: Dictionary = {}
var brains:Dictionary={}
var brain_trace_directory:=""
var destinations: Dictionary = {}
var seen: Dictionary = {}
var events: Array = []
var serial := 0
var speech_after := 0.0
var command_speech_after: Dictionary = {}
var return_visit_after := 0.0
var time := 0.0
var collecting_idle:=false
var idle_candidates:Dictionary={}
var moment_pacing:RefCounted
var memory_reminders: RefCounted
var moods: RefCounted
var local_dialogue:RefCounted
var old_spoken_at:Dictionary={}

func _init(source: RefCounted) -> void:
	_owner = weakref(source)
	memory_reminders=preload("res://scripts/memory_reminders.gd").new(source)
	moods=preload("res://scripts/resident_moods.gd").new(source)
	for id in world.actors: register(id)
	local_dialogue=preload("res://scripts/local_dialogue.gd").new(source)

func register(id: String) -> void:
	if id == "human" or routines.has(id): return
	routines[id] = Routine.new(world, id)
	brains[id]=preload("res://scripts/resident_brain.gd").new(world,id)
	brains[id].trace_directory=brain_trace_directory

func model_controlled(id: String) -> bool:
	return world.actors.has(id) and world.actors[id].get("controller", "local") == "model"

func set_controller(id: String, source: String) -> Dictionary:
	if id == "human" or not world.actors.has(id) or source not in ["local", "model"]:
		return world._error("invalid_controller")
	if world.actors[id].controller == source: return {"ok": true, "status": "completed"}
	if world.shared_activity.contains(id): world.shared_activity.pause(LocalText.text("content.remaining.a_participant_s_control_source_changed_pause_the_barbecue"))
	world.activities.dismiss(id,false)
	world.farms.pause(id)
	if world.projects.active(id): world.projects.pause(id, LocalText.text("content.remaining.control_source_changed_the_existing_plan_is_safe"))
	command_received(id, "controller_change")
	world.work.stop(id, false)
	world.actors[id].controller = source
	world.revision += 1
	return {"ok": true, "status": "completed"}

func command_received(id: String, intent: String) -> void:
	if world.fishing!=null and world.fishing.life!=null:world.fishing.life.cancel(id,intent)
	if routines.has(id): routines[id].command_received(id, intent)

func issuing(id: String) -> bool:
	return routines.has(id) and routines[id].issuing

func interrupt_all(cooldown: float = 8) -> void:
	for routine in routines.values(): routine.interrupt(cooldown)

func set_all_enabled(value: bool) -> void:
	for routine in routines.values(): routine.set_enabled(value)

func set_held(id: String, value: bool) -> void:
	if routines.has(id): routines[id].set_held(value)

func available_position(id: String, region: String, p: Vector2) -> bool:
	for actor in world.actors.values():
		if actor.id != id and actor.region_id == region and world.point(actor).distance_to(p) < 1.5: return false
	for other in destinations:
		if other != id and destinations[other].region == region and destinations[other].point.distance_to(p) < 1.5: return false
	return true

func state(id: String) -> Dictionary:
	if not routines.has(id): return {"controller": "human", "effective": "human"}
	var routine: RefCounted = routines[id]
	var effective := "idle"
	if world.activities.blocked(id) and world.activities.members.has(id): effective = "assembly"
	elif world.shared_activity.holds(id): effective = "shared_activity"
	elif routine.held: effective = "conversation"
	elif world.projects.active(id) or world.farms.active(id) or (world.work.jobs.has(id) and not routine.owns_job()): effective = "task"
	elif world.activities.following.has(id):effective="following"
	elif world._routes.has(id) and not routine.owns_route and not routine.owns_job(): effective = "command"
	elif not routine.kind.is_empty() or (brains.has(id) and brains[id].active() and brains[id].current.get("source","")=="local"): effective = "local_rules"
	return {"controller": world.actors[id].controller, "effective": effective, "capabilities": world.residents.capabilities(world.actors[id]), "local_life": routine.state()}

var company_night_owner:=""
signal return_speech_window
var return_speech_reserved:=false
var heart_speech_window:Callable
func can_say_local(id:String,context:String="",listener_id:String="human")->bool:
	if not routines.has(id):return false
	var routine: RefCounted=routines[id];var actor: Dictionary=world.actors[id]
	if actor.has("world_door_client") and context!="world_door":return false
	if not routine.enabled or routine.held or not routine.chatter:return false
	if context=="company_night" and not company_night_owner.is_empty():
		var listener:Dictionary=world.actors.human
		return time>=routine.visual_quiet_until and listener.region_id==actor.region_id and world.point(listener).distance_to(world.point(actor))<=12
	if context in ["heart_social","heart_call"] and (time<routine.visual_quiet_until or world.activities.blocked(id,false) or world.fishing.life.time<float(world.fishing.life.quiet_until.get(id,0))):return false
	if routine.time<routine.next_speech or time<speech_after:return false
	if listener_id!="human":
		if context in ["heart_social","world_door"]:pass
		elif context in ["local_pair","brain_pair"]:
			if local_dialogue==null or not local_dialogue.pair_allowed(id,listener_id,context=="brain_pair"):return false
		elif not context.begins_with("gomoku_"):return false
		var allowed: bool=world.gomoku.sessions.values().any(func(g):return g.get("mode")=="ai" and id in world.gomoku.players(g) and listener_id in world.gomoku.players(g) and id!=listener_id and (g.phase=="playing" or (g.phase=="finished" and world.gomoku.memories.any(func(record):return record.id==g.id))))
		if context not in ["local_pair","brain_pair","heart_social","world_door"] and not allowed:return false
	var listener: Dictionary=world.actors.get(listener_id,{})
	if listener.is_empty() or actor.region_id!=listener.region_id or world.point(actor).distance_to(world.point(listener))>(20 if context=="heart_social" else 50 if context=="heart_call" else 12):return false
	return true

func say_local(id: String,text: String,context: String,personal_gap: float,group_gap: float,listener_id: String="human",source:String="local_rules") -> bool:
	if not can_say_local(id,context,listener_id):return false
	var routine:RefCounted=routines[id]
	if world.personality!=null and not world.personality.allowed_line(id,text):return false
	if world.personality!=null:world.personality.note_line(id,text)
	serial+=1;events.append({"serial":serial,"actor_id":id,"source":source,"context":context,"text":text,"explicit":false,"time":time})
	if events.size()>24:events.pop_front()
	routine.next_speech=routine.time+personal_gap;speech_after=time+group_gap
	old_spoken_at[id]=time
	return true

func say_command(id: String, target: String, line: String) -> bool:
	if not routines.has(id) or not world.actors.has(target):return false
	var routine:RefCounted=routines[id]
	if routine.held or time<float(command_speech_after.get(id,0)):return false
	var speaker:Dictionary=world.actors[id]
	var listener:Dictionary=world.actors[target]
	if speaker.region_id!=listener.region_id or world.point(speaker).distance_to(world.point(listener))>8:return false
	if not preload("res://scripts/island_notes.gd").valid_text(line):return false
	command_speech_after[id]=time+12
	routine.next_speech=maxf(routine.next_speech,routine.time+12)
	speech_after=maxf(speech_after,time+8)
	serial+=1
	events.append({"serial":serial,"actor_id":id,"source":"model","context":"world_door","text":line,"explicit":false,"time":time})
	if events.size()>24:events.pop_front()
	world_speech.emit(id,target,line)
	return true

func say_rush_event(id:String,text:String)->bool:
	if not routines.has(id) or not world.hunger.rushes.has(id):return false
	var r:RefCounted=routines[id]
	if not r.enabled or not r.chatter or r.held or world.activities.blocked(id,false) or world.work.jobs.has(id) or world.shared_activity.holds(id):return false
	if time<float(world.hunger.quiet_until.get(id,0)) or world.fishing.life.time<float(world.fishing.life.quiet_until.get(id,0)):return false
	if not world.personality.allowed_line(id,text):return false
	world.personality.note_line(id,text)
	serial+=1;events.append({"serial":serial,"actor_id":id,"source":"local_rules","context":"hunger_rush","text":text,"explicit":false,"time":time})
	if events.size()>24:events.pop_front()
	return true

func say_fireside(id:String,text:String,context:String,station_id:String)->bool:
	if not routines.has(id) or not world.barbecues.has(station_id):return false
	var fire:RefCounted=world.barbecues[station_id].fireside
	var r:RefCounted=routines[id]
	if not fire.burning() or fire.circle_closed or not fire.jobs.has(id) or id not in fire.state.attended or fire.held(id):return false
	if not r.enabled or not r.chatter or r.held or r.time<r.next_speech:return false
	if time<float(world.hunger.quiet_until.get(id,0)) or world.fishing.life.time<float(world.fishing.life.quiet_until.get(id,0)):return false
	if not world.personality.allowed_line(id,text):return false
	world.personality.note_line(id,text)
	serial+=1;events.append({"serial":serial,"actor_id":id,"source":"local_rules","context":context,"station_id":station_id,"text":text,"explicit":false,"time":time})
	if events.size()>24:events.pop_front()
	r.next_speech=r.time+float(world.hunger.config.personal_gap);speech_after=time+float(world.hunger.config.village_gap)
	return true

func advance(delta: float) -> void:
	time += delta
	moods.advance(delta)
	for id in brains:
		if brains[id].active():
			# Advance the original personal clock once before its speech window.
			# Otherwise a deadline opens only later in routine.advance(), where
			# generic reminders can consume it before anniversary/host feedback.
			routines[id].time+=delta
	if delta>0:return_speech_window.emit()
	for id in brains:
		if brains[id].active():local_speech_window.emit(id)
	if delta>0 and heart_speech_window.is_valid():heart_speech_window.call()
	for brain in brains.values():brain.advance(delta)
	for id in brains:
		var r:RefCounted=routines[id]
		if world.actors[id].has("world_door_client"):continue
		if brains[id].active() and not brains[id].provider_running and str(brains[id].current.get("coop","")).is_empty() and r.enabled and r.chatter and not r.held and time>=r.next_speech and not world.days.defer_idle(id):
			if not r.try_need_speech() and not memory_reminders.try_speak(id) and old_spoken_at.has(id) and float(moods.changed_at.get(id,0))>0 and float(old_spoken_at.get(id,-INF))<float(moods.changed_at.get(id,-INF)):r._speak("near")
	idle_candidates.clear();collecting_idle=true
	for id in routines:
		var routine: RefCounted = routines[id]
		routine.advance(0.0 if brains.has(id) and brains[id].active() else delta)
		for event in routine.events:
			if int(event.serial) <= int(seen.get(id, 0)): continue
			seen[id] = event.serial
			if event.get("handled",false):continue
			if routine.held or not routine.chatter: continue
			var actor: Dictionary = world.actors[id]
			if not event.explicit and (time < speech_after or actor.region_id != world.actors.human.region_id or world.point(actor).distance_to(world.point(world.actors.human)) > 12): continue
			if world.personality!=null:
				if not world.personality.allowed_line(id,str(event.text)):continue
				world.personality.note_line(id,str(event.text))
			serial += 1
			var line: Dictionary = event.duplicate(true)
			line.serial = serial; line.actor_id = id
			events.append(line)
			if events.size() > 24: events.pop_front()
			speech_after = time + 14

	collecting_idle=false
	if local_dialogue!=null:local_dialogue.advance(delta,false)
	if time<speech_after:return
	# A real pending reply may borrow its own next turn; later old deliveries
	# repay that debt. New exchanges still require three actual old deliveries.
	if local_dialogue!=null and local_dialogue.reply_ready() and try_new_spoken():return
	var ready:Array=idle_candidates.keys().filter(func(id):
		var r:RefCounted=routines[id]
		return r.enabled and not r.held and r.chatter and r.time>=r.next_speech and moods.can_speak(id,str(idle_candidates[id])))
	var needs_due:Dictionary={}
	for id in ready:needs_due[id]=not routines[id].needs.choose(world,id).is_empty()
	ready.sort_custom(func(a,b):
		if needs_due[a] and needs_due[b]:
			var at:float=float(old_spoken_at.get(a,-INF));var bt:float=float(old_spoken_at.get(b,-INF))
			if at!=bt:return at<bt
		if needs_due[a]!=needs_due[b]:return needs_due[a]
		return routines[a].next_speech<routines[b].next_speech)
	for candidate_id in ready:
		# Saved AI words reuse the existing idle opportunity and all speech gates.
		if not needs_due[candidate_id] and not model_controlled(candidate_id) and quote_books!=null and quote_books.get_ref()!=null and time>=float(quote_next.get(candidate_id,0)):
			var books:RefCounted=quote_books.get_ref()
			var quotes:Array=books.local_quotes(candidate_id)
			if not quotes.is_empty() and local_dialogue.idle(candidate_id) and local_dialogue.say_spoken(candidate_id,books.quote_label(quotes[-1]),"ai_kept_quote"):
				quote_next[candidate_id]=time+3600;return
		# New content may replace only this resident's existing ordinary turn.
		if try_new_spoken(str(candidate_id)):return
		var before:int=serial
		routines[candidate_id]._speak(str(idle_candidates[candidate_id]))
		if serial>before:return

func try_new_spoken(actor_id:String="")->bool:
	if local_dialogue==null:return false
	if time<speech_after:return false
	return local_dialogue.try_spoken(func(id:String):return actor_id.is_empty() or id==actor_id)

func queue_idle_speech(id:String,context:String)->void:
	if not idle_candidates.has(id):idle_candidates[id]=context

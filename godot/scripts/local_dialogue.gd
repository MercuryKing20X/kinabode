extends RefCounted
## Authored observation only. No jobs, routes, resources, model calls or human speech.
var owner_ref:WeakRef
var world:RefCounted:
	get:return owner_ref.get_ref()
var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/companions/local-dialogue.json"))
var thoughts:Dictionary={}
var thought_due:Dictionary={}
var host_due:Dictionary={}
var delivered:Array=[]
var said:Dictionary={}
var day:=-1
var next_check:=0.0
var next_pair:=0.0
var pending:Dictionary={}
var cursor:=0
var next_solo_kind:="sense"
var pair_cursor:=0
var pair_order:Array=[]
var spoken_ready:=false
var spoken_opportunity:=false
var pair_served:Dictionary={}
var solo_served:Dictionary={}
var solo_last:Dictionary={}
var cadence_rngs:Dictionary={}
var pair_authored:Dictionary={}
var pair_diagnostics:Array=[]
var last_pair_diagnostic:=""
var mood_provider:Callable
var daily:=ConfigFile.new()
var daily_path:=""
var persistent_ready:=false
var hydrated_key:=""
func _init(source:RefCounted)->void:
	owner_ref=weakref(source)
	# Interleave the six pair families, rather than ten consecutive groups
	# of one family. The cursor moves only when a first line is really delivered.
	var families:Dictionary={};var depth:=0
	for group in data.pairs:
		for row in group.lines:pair_authored[row.actor_id]=int(pair_authored.get(row.actor_id,0))+1
		var key:String=",".join(group.actors)
		if not families.has(key):families[key]=[]
		families[key].append(group);depth=maxi(depth,families[key].size())
	for index in range(depth):
		for groups in families.values():
			if index<groups.size():pair_order.append(groups[index])
func idle(id:String,allow_local_motion:bool=false,allow_brain_scene:bool=false)->bool:
	if not world.director.routines.has(id) or not world.actors.has(id):return false
	var r:RefCounted=world.director.routines[id]
	return r.enabled and r.chatter and not r.held and r.kind!="flower_gift" and r.time>=r.visual_quiet_until and not world.activities.blocked(id) and not world.work.jobs.has(id) and (not world._routes.has(id) or (allow_local_motion and (r.owns_route or world.activities.following.has(id)))) and not world.projects.active(id) and not world.farms.active(id) and not world.homestead.active(id) and not world.shared_activity.holds(id) and not world.gomoku.active(id) and world.director.time>=float(world.hunger.quiet_until.get(id,0)) and world.fishing.life.time>=float(world.fishing.life.quiet_until.get(id,0))
func pair_allowed(a:String,b:String,allow_brain_scene:bool=false)->bool:
	return a!=b and idle(a,false,allow_brain_scene) and idle(b,false,allow_brain_scene) and world.actors[a].region_id==world.actors[b].region_id and world.point(world.actors[a]).distance_to(world.point(world.actors[b]))<=4
func pair_waitable(a:String,b:String)->bool:
	# Brief local following/yielding may delay a reply, never speak during motion.
	# Real tasks, commands, separation, held and stop still discard the exchange.
	return a!=b and idle(a,true) and idle(b,true) and world.actors[a].region_id==world.actors[b].region_id and world.point(world.actors[a]).distance_to(world.point(world.actors[b]))<=4
func english()->bool:return TranslationServer.get_locale().begins_with("en")
func text(row:Dictionary)->String:return row.en if english() else row.zh
func persistent_setup()->void:
	if persistent_ready:return
	var base:String=OS.get_environment("HABITAT_DATA_DIR")
	if world.library!=null and not world.library.directory.is_empty():base=world.library.directory.get_base_dir()
	if base.is_empty():return
	daily_path=base.path_join("local-dialogue-day.cfg");daily.load(daily_path);persistent_ready=true
	# Only the current game day's no-repeat receipts survive. These aren't memories.
	var prefix:String=world.world_id+"/"
	var keep:String=prefix+str(world.days.day())+"/"
	for section in daily.get_sections():
		if section.begins_with(prefix) and not section.begins_with(keep):daily.erase_section(section)
func daily_section(id:String)->String:return world.world_id+"/"+str(world.days.day())+"/"+id
func persist_delivery(id:String,row:Dictionary)->void:
	persistent_setup()
	if not persistent_ready:return
	var section:String=daily_section(id);var key:String=str(row.get("source_id",row.id))
	if daily.get_value(section,key,false):return
	daily.set_value(section,key,true)
	if daily.save(daily_path+".tmp")==OK:DirAccess.rename_absolute(daily_path+".tmp",daily_path)
func mark_pair(reason:String)->void:
	if pending.is_empty():return
	var key:String=str(pending.id)+":"+str(pending.index)+":"+str(pending.expires)+":"+reason
	if key==last_pair_diagnostic:return
	last_pair_diagnostic=key
	var actors:Dictionary={}
	for id in pending.actors:
		var r:RefCounted=world.director.routines[id]
		actors[id]={"position":world.actors[id].position.duplicate(),"region":world.actors[id].region_id,"idle":idle(id),"waitable_idle":idle(id,true),"enabled":r.enabled,"chatter":r.chatter,"held":r.held,"route":world._routes.has(id),"owns_local_route":r.owns_route,"following":world.activities.following.has(id),"task":world.work.jobs.has(id),"speech_due":r.next_speech,"time":r.time,"visual_quiet_until":r.visual_quiet_until,"hunger_quiet_until":world.hunger.quiet_until.get(id,0),"fishing_quiet_until":world.fishing.life.quiet_until.get(id,0)}
	pair_diagnostics.append({"at":world.director.time,"reason":reason,"id":pending.id,"index":pending.index,"expires":pending.expires,"shared_speech_due":world.director.speech_after,"actors":actors})
	if pair_diagnostics.size()>64:pair_diagnostics.pop_front()
func cancel_pair(reason:String)->void:
	mark_pair(reason);pending.clear()
func count_spoken(id:String,kind:String)->void:
	if kind=="dialogue":pair_served[id]=int(pair_served.get(id,0))+1
	elif kind in ["sense","host"]:
		solo_served[id]=int(solo_served.get(id,0))+1;solo_last[id]=world.director.time
		# Only an actual solo delivery advances its category; check-clock phase
		# and rejected opportunities cannot starve one valid kind.
		next_solo_kind="host" if kind=="sense" else "sense"
func pair_budget(id:String)->bool:
	var catalogue:Dictionary=data.residents[id]
	var solo_lines:int=catalogue.sense.size()+catalogue.host.size()
	var ratio:float=float(pair_authored.get(id,0))/maxi(1,solo_lines)
	var scale:float=world.personality.speech_scale(id)
	# One initial participation; later opportunities derive from the actual
	# catalogue ratio and the unchanged authored personality speech scale.
	return float(pair_served.get(id,0))<1+float(solo_served.get(id,0))*ratio/scale
func note_scene(id:String,line_id:String)->void:
	# The old SceneSpeech calls this only after its real delivered line.
	if not data.residents.has(id):return
	for kind in ["sense","host"]:
		for row in data.residents[id][kind]:
			if row.get("source_id","")!=line_id:continue
			var own:Dictionary=said.get(id,{})
			if own.has(row.zh) or own.has(row.en):return
			own[row.zh]=true;own[row.en]=true;said[id]=own
			persist_delivery(id,row)
			count_spoken(id,kind)
			delivered.append({"actor_id":id,"id":row.id,"kind":kind,"day":world.days.day(),"at":world.director.time,"text":text(row),"outlet":"scene_speech"})
			if delivered.size()>512:delivered.pop_front()
			return
func unused(id:String,row:Dictionary)->bool:
	persistent_setup()
	if persistent_ready and daily.get_value(daily_section(id),str(row.get("source_id",row.id)),false):return false
	var own:Dictionary=said.get(id,{})
	if own.has(row.zh) or own.has(row.en):return false
	# Curated lines retain the old source ID: one shared daily delivery budget.
	if world.scene_speech!=null and world.scene_speech.said_day==world.days.day() and world.scene_speech.said.get(id,{}).has(row.get("source_id","")):return false
	return true
func note(id:String,row:Dictionary,kind:String)->void:
	persist_delivery(id,row)
	count_spoken(id,kind)
	var own:Dictionary=said.get(id,{});own[row.zh]=true;own[row.en]=true;said[id]=own
	if row.has("source_id") and world.scene_speech!=null:
		world.scene_speech.note(id,row.trigger,row.source_id)
	delivered.append({"actor_id":id,"id":row.id,"kind":kind,"day":day,"at":world.director.time,"text":text(row)})
	if delivered.size()>512:delivered.pop_front()
func contexts(id:String)->Array:
	var result:Array=world.scene_speech.contexts(id) if world.scene_speech!=null else []
	if world.hunger.rank(id)>=2:result.append("hungry")
	if world.days.phase().id=="night":result.append("night")
	if world.weather.current().id=="rain":result.append("rain")
	if idle(id):result.append("idle")
	# Sea thoughts use validated current natural coast, without choosing a route.
	if not world.fishing.shore(id).is_empty():result.append("sea")
	return result
func choose(id:String,kind:String)->Dictionary:
	if not data.residents.has(id):return {}
	var valid:Array=contexts(id)
	var candidates:Array=data.residents[id][kind].filter(func(row):return row.trigger in valid and unused(id,row))
	if candidates.is_empty():return {}
	# Hunger takes precedence; optional life mood only ranks existing safe text.
	if "hungry" in valid:
		var hungry:Array=candidates.filter(func(row):return row.trigger=="hungry")
		if not hungry.is_empty():return hungry[0]
	if mood_provider.is_valid():
		var mood:Variant=mood_provider.call(id)
		if mood is Dictionary and float(mood.get("curious",0))>=60:
			var scenery:Array=candidates.filter(func(row):return row.trigger in ["sea","mountain","moon"])
			if not scenery.is_empty():return scenery[0]
	# Deterministic round-robin gives all genuine active scenes a chance.
	return candidates[posmod(cursor+hash(id),candidates.size())]
func advance(delta:float,allow_spoken:bool=true)->void:
	spoken_ready=false
	if delta<=0:spoken_opportunity=false;return
	if not is_finite(next_check):spoken_opportunity=false
	spoken_ready=spoken_opportunity
	var now:float=world.director.time
	if day!=world.days.day():
		cancel_pair("day_change")
		day=world.days.day();said.clear();thoughts.clear();persistent_ready=false
	persistent_setup()
	if world.scene_speech!=null and persistent_ready and hydrated_key!=world.world_id+":"+str(day):
		hydrated_key=world.world_id+":"+str(day)
		if world.scene_speech.said_day!=day:world.scene_speech.said.clear();world.scene_speech.said_day=day
		for id in data.residents:
			var own:Dictionary=world.scene_speech.said.get(id,{})
			for kind in ["sense","host"]:
				for row in data.residents[id][kind]:
					if daily.get_value(daily_section(id),row.source_id,false):own[row.source_id]=true
			world.scene_speech.said[id]=own
	for id in thoughts.keys():
		if not idle(id) or now>=float(thoughts[id].until):thoughts.erase(id)
	if now<next_check:
		# A reply must compete on the same frame as ordinary speech when its
		# original gates open. New exchanges retain the one-second check.
		if is_finite(next_check) and reply_ready():spoken_opportunity=true;spoken_ready=true
		return
	spoken_opportunity=true;spoken_ready=true
	next_check=now+1;cursor+=1
	for id in data.residents:
		if not idle(id):continue
		if now>=float(thought_due.get(id,20+posmod(hash(id),25))):
			var thought:Dictionary=choose(id,"thought")
			thought_due[id]=now+45+posmod(hash(id),20)
			if not thought.is_empty():
				thoughts[id]={"text":text(thought),"zh":thought.zh,"en":thought.en,"until":now+6,"id":thought.id};note(id,thought,"thought")
	if not pending.is_empty() and (not pair_waitable(pending.actors[0],pending.actors[1]) or now>float(pending.expires)):cancel_pair("expired" if now>float(pending.expires) else "wait_gate")
	if allow_spoken:try_spoken()
func try_spoken(admission:Callable=Callable())->bool:
	if not spoken_ready:return false
	spoken_ready=false;spoken_opportunity=false
	# Director grants one fair opportunity; original personal/village gates remain.
	var now:float=world.director.time
	if not pending.is_empty():
		if not pair_waitable(pending.actors[0],pending.actors[1]) or now>float(pending.expires):cancel_pair("expired" if now>float(pending.expires) else "wait_gate")
		else:
			if int(pending.index)==0 and admission.is_valid() and not admission.call(str(pending.lines[0].actor_id)):return false
			return deliver_pending()
	if now>=next_pair:
		var options:Array=[]
		for offset in range(pair_order.size()):
			var index:int=posmod(pair_cursor+offset,pair_order.size());var group:Dictionary=pair_order[index]
			var a:String=group.actors[0];var b:String=group.actors[1]
			if not pair_allowed(a,b) or not pair_budget(a) or not pair_budget(b) or not unused(a,group.lines[0]) or not unused(b,group.lines[1]):continue
			var first:String=group.lines[0].actor_id;var listener:String=b if first==a else a
			if admission.is_valid() and not admission.call(first):continue
			if not world.director.can_say_local(first,"local_pair",listener):continue
			options.append({"index":index,"offset":offset,"served":int(pair_served.get(a,0))+int(pair_served.get(b,0))})
		options.sort_custom(func(a,b):return a.offset<b.offset if a.served==b.served else a.served<b.served)
		if not options.is_empty():
			var index:int=options[0].index
			pending=pair_order[index].duplicate(true);pending.index=0;pending.expires=now+120;pending.cursor_next=(index+1)%pair_order.size()
			mark_pair("started")
			# This is the same granted attempt, not a recursive second grant.
			return deliver_pending()
	# Compare only currently eligible speakers; a distant or held resident
	# never reserves the outlet. Counts and time advance only after delivery.
	var solo_options:Array=[];var ids:Array=data.residents.keys()
	for offset in range(ids.size()):
		var id:String=ids[posmod(cursor+offset,ids.size())]
		if not idle(id) or now<float(host_due.get(id,30+posmod(hash(id),30))):continue
		var actor:Dictionary=world.actors[id];var human:Dictionary=world.actors.human
		if actor.region_id!=human.region_id or world.point(actor).distance_to(world.point(human))>6:continue
		if admission.is_valid() and not admission.call(id):continue
		if not world.director.can_say_local(id,"local_host"):continue
		solo_options.append({"id":id,"served":float(solo_served.get(id,0))*world.personality.speech_scale(id),"last":float(solo_last.get(id,-INF)),"offset":offset})
	solo_options.sort_custom(func(a,b):
		if a.served!=b.served:return a.served<b.served
		if a.last!=b.last:return a.last<b.last
		return a.offset<b.offset)
	for option in solo_options:
		var id:String=option.id
		var kind:String=next_solo_kind
		var row:Dictionary=choose(id,kind)
		if row.is_empty():
			kind="host" if kind=="sense" else "sense";row=choose(id,kind)
		if row.is_empty():continue
		if say_spoken(id,text(row),"local_"+kind):
			note(id,row,kind);host_due[id]=now+90*world.personality.speech_scale(id);return true
	return false
func reply_ready()->bool:
	if pending.is_empty() or int(pending.index)<=0 or world.director.time>float(pending.expires):return false
	var a:String=pending.actors[0];var b:String=pending.actors[1]
	if not pair_allowed(a,b):return false
	var row:Dictionary=pending.lines[int(pending.index)];var who:String=row.actor_id;var listener:String=b if who==a else a
	return unused(who,row) and world.director.can_say_local(who,"local_pair",listener)
func deliver_pending()->bool:
	if pending.is_empty():return false
	var a:String=pending.actors[0];var b:String=pending.actors[1]
	if not pair_allowed(a,b):mark_pair("waiting_stationary_pair");return false
	var row:Dictionary=pending.lines[int(pending.index)];var who:String=row.actor_id;var listener:String=b if who==a else a
	# An already-started reply uses its existing gates, not a new budget check.
	if not unused(who,row):mark_pair("already_delivered");return false
	if not say_spoken(who,text(row),"local_pair",listener):mark_pair("delivery_gate");return false
	mark_pair("line_delivered")
	if pending.index==0:pair_cursor=int(pending.cursor_next)
	note(who,row,"dialogue");pending.index+=1
	if pending.index>=pending.lines.size():
		mark_pair("completed")
		delivered.append({"id":pending.id,"kind":"dialogue_group","day":day,"at":world.director.time});pending.clear();next_pair=world.director.time+60
	return true
func say_spoken(id:String,line:String,context:String,listener_id:String="human")->bool:
	if not world.director.say_local(id,line,context,0,14,listener_id):return false
	# Only a real delivery samples this new presentation stream. Keep the
	# original public/decision streams untouched; explicit original seed changes
	# reset this stream too. The authored interval, mood and scale stay unchanged.
	var r:RefCounted=world.director.routines[id]
	if not cadence_rngs.has(id) or cadence_rngs[id].seed!=r.rng.seed:
		var fresh_rng:=RandomNumberGenerator.new();fresh_rng.seed=r.rng.seed
		cadence_rngs[id]={"seed":r.rng.seed,"rng":fresh_rng}
	var presentation_rng:RandomNumberGenerator=cadence_rngs[id].rng
	var gap:float=presentation_rng.randf_range(r.config.speech_interval[0],r.config.speech_interval[1])*world.director.moods.interval(id,"speech")*world.personality.speech_scale(id)
	r.next_speech=r.time+gap
	return true

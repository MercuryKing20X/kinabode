extends RefCounted
## Observes committed world facts. Only ResidentBrain can choose an approach.
var owner:WeakRef
var brain:RefCounted:
	get:return owner.get_ref()
var w:RefCounted:
	get:return brain.world
var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/brain-interactions.json"))
var event_queue:Array=[]
var pending:Dictionary={}
var seen:Dictionary={}
var said:Dictionary={}
var sustained:Dictionary={}
var receipts:Array=[]
var samples:Array=[]
var previous:=Vector2.INF
var previous_region:=""
var previous_moon:=false
var previous_distance:=INF
var previous_speed:=0.0
var idle_since:=0.0
var far_since:=-1.0
var talked_day:=-1
var next_observe:=0.0
var next_delivery:=0.0
var next_pair:=0.0
var near_since:=-1.0
var peer_session:=""
var peer_reply:=false
func _init(b:RefCounted)->void:owner=weakref(b)
static func host_event(world:RefCounted,scene:String,proof:String,only:String="")->void:
	if not world.actors.has("human"):return
	for who in world.director.brains:
		var brain:RefCounted=world.director.brains[who]
		if not brain.active() or (not only.is_empty() and who!=only):continue
		if world.actors[who].region_id!=world.actors.human.region_id or brain.distance()>float(brain.config.host_replies.witness_radius):continue
		var item:Dictionary={"scene":scene,"proof":proof,"until":world.director.time+float(brain.config.host_replies.ttl_seconds),"kind":"host_reply"}
		if brain.interactions.event_queue.any(func(row):return row.proof==proof and row.scene==scene):continue
		brain.interactions.event_queue.append(item)
		if brain.interactions.event_queue.size()>int(brain.config.host_replies.queue_limit):brain.interactions.event_queue.pop_front()
func enqueue(scene:String,proof:String)->void:
	if not pending.is_empty() or not data.scenes.has(scene) or line(scene).is_empty():return
	pending={"scene":scene,"proof":proof,"until":brain.clock+float(data.event_ttl)}
func condition(scene:String,on:bool,since:float)->void:
	if not on:return
	var stage:int=mini(int(data.scene_stages)-1,int(maxf(0,brain.clock-since)/float(data.sustained_step_seconds)))
	var key:String=str(w.days.day())+":"+scene+":"+str(since)+":"+str(stage)
	if not seen.has(key):enqueue(scene,key)
func observe()->void:
	while not event_queue.is_empty() and float(event_queue[0].until)<brain.clock:event_queue.pop_front()
	if not event_queue.is_empty() and pending.get("kind","")!="host_reply":pending=event_queue.pop_front()
	if brain.clock<next_observe:return
	next_observe=brain.clock+float(data.observation_seconds)
	if not pending.is_empty() and brain.clock>float(pending.until):pending.clear()
	var host:Dictionary=w.actors.human
	var pos:Vector2=w.point(host)
	var same:bool=host.region_id==w.actors[brain.id].region_id
	var dist:float=brain.distance()
	if previous_region=="dark" and host.region_id=="home":host_event(w,"host_dark_return","return_dark:"+str(brain.clock),brain.id)
	var on_moon:bool=host.region_id=="home" and w.moon.contains(pos)
	if previous_moon and not on_moon and host.region_id=="home":host_event(w,"host_moon_return","return_moon:"+str(brain.clock),brain.id)
	previous_moon=on_moon
	if not same and far_since<0:far_since=brain.clock
	var speed:float=0 if not previous.is_finite() or host.region_id!=previous_region else pos.distance_to(previous)/float(data.observation_seconds)
	if speed>.02:idle_since=brain.clock
	var idle:float=brain.clock-idle_since
	if same:
		if dist>float(data.far_distance) and far_since<0:far_since=brain.clock
		if dist<=float(data.near_distance):
			if far_since>=0 and brain.clock-far_since>=float(data.return_seconds):enqueue('returned','far_since:'+str(far_since))
			far_since=-1
			if near_since<0 and speed>.02:near_since=brain.clock
		else:near_since=-1
		if previous_distance<=float(data.near_distance) and dist>float(data.far_distance):enqueue('far','departure:'+str(brain.clock))
		if speed>6 and previous_speed<5:enqueue('sprint','speed:'+str(speed))
		samples.append({"at":brain.clock,"p":pos})
		while not samples.is_empty() and brain.clock-float(samples[0].at)>float(data.loop_window):samples.pop_front()
		if samples.size()>10 and pos.distance_to(samples[0].p)<2:
			var length:=0.0
			for i in range(1,samples.size()):length+=samples[i].p.distance_to(samples[i-1].p)
			if length>=float(data.loop_distance):enqueue('circles','loop_length:'+str(length));samples.clear()
		if idle>=float(data.idle_seconds):
			condition('hungry_idle',w.hunger.rank(brain.id)>=2,idle_since)
			condition('watch_work',w.work.jobs.has(brain.id) and dist<=5,idle_since)
			condition('water',not w.fishing.shore("human").is_empty(),idle_since)
			condition('idle',true,idle_since)
		condition('near_silent',near_since>=0 and brain.clock-near_since>=30 and talked_day!=w.days.day(),near_since)
		condition('rain',w.weather.current().id=='rain' and not str(host.region_id).begins_with('room.'),0)
		condition('night',w.days.phase().id=='night' and host.region_id=='home',0)
		condition('no_chat',talked_day!=w.days.day() and brain.clock>=float(data.no_chat_seconds),0)
		for site in w.objects.values():
			if site.get('kind','')=='construction_site' and site.get('owner_id','')==brain.id and int(site.get('stage_index',0))>=5 and w.point(site).distance_to(pos)<=4:condition('home_near',true,idle_since)
	previous=pos;previous_region=host.region_id;previous_distance=dist;previous_speed=speed
func still_true(scene:String)->bool:
	var host:Dictionary=w.actors.human
	var same:bool=host.region_id==w.actors[brain.id].region_id
	if not same:return false
	match scene:
		"rain":return w.weather.current().id=="rain" and not str(host.region_id).begins_with("room.")
		"night":return w.days.phase().id=="night" and host.region_id=="home"
		"idle":return brain.clock-idle_since>=float(data.idle_seconds)
		"hungry_idle":return w.hunger.rank(brain.id)>=2 and brain.clock-idle_since>=float(data.idle_seconds)
		"watch_work":return w.work.jobs.has(brain.id) and brain.distance()<=5 and brain.clock-idle_since>=float(data.idle_seconds)
		"water":return not w.fishing.shore("human").is_empty() and brain.clock-idle_since>=float(data.idle_seconds)
		"no_chat":return talked_day!=w.days.day()
		"far":return brain.distance()>float(data.far_distance)
	return true
func deliver_pending()->bool:
	if (w.dark!=null and w.dark.here()) or pending.is_empty() or (pending.get("kind","")!="host_reply" and brain.clock<next_delivery):return false
	var fact:Dictionary=pending.duplicate(true)
	if not still_true(fact.scene):pending.clear();return false
	if not deliver(fact.scene,fact.proof,"human",str(fact.get("kind","interaction"))):return false
	seen[fact.proof]=true;pending.clear()
	if fact.get("kind","")!="host_reply":next_delivery=brain.clock+float(data.personal_seconds)
	return true
func candidate()->Dictionary:
	if (w.dark!=null and w.dark.here()) or pending.is_empty() or (pending.get("kind","")!="host_reply" and brain.clock<next_delivery) or brain.distance()>12:return {}
	return {"action":"host_interaction","score":float(brain.config.host_replies.score) if pending.get("kind","")=="host_reply" else float(data.score),"reasons":["interaction_"+str(pending.scene)],"partner":"","interaction":pending.duplicate(true)}
func line(scene:String)->Dictionary:
	var voice:Dictionary=data.scenes[scene].voices.get(brain.tag(),data.scenes[scene].voices.gentle)
	w.director.local_dialogue.persistent_setup()
	var section:String=w.director.local_dialogue.daily_section(brain.id)
	for index in voice.zh.size():
		var key:String=str(w.days.day())+":"+scene+":"+str(index)
		if not said.has(key) and not w.director.local_dialogue.daily.get_value(section,"brain:"+scene+":"+str(index),false) and not w.director.local_dialogue.daily.get_value(section,"brain-line:"+str(voice.zh[index]).sha256_text(),false):return {"key":key,"zh":voice.zh[index],"en":voice.en[index]}
	return {}
func deliver(scene:String,proof:String,listener:String='human',kind:String='interaction')->bool:
	var row:Dictionary=line(scene)
	if row.is_empty():return false
	return deliver_authored(row,scene,proof,listener,kind,data.scenes[scene].reason)
func deliver_authored(row:Dictionary,scene:String,proof:String,listener:String,kind:String,reason:Array)->bool:
	w.director.local_dialogue.persistent_setup()
	var section:String=w.director.local_dialogue.daily_section(brain.id)
	if w.director.local_dialogue.daily.get_value(section,"brain-line:"+str(row.zh).sha256_text(),false):return false
	var r:RefCounted=w.director.routines[brain.id]
	if brain.clock<r.visual_quiet_until or w.activities.held.get(brain.id,false) or w.activities.members.has(brain.id) or brain.clock<float(w.hunger.quiet_until.get(brain.id,0)) or w.fishing.life.time<float(w.fishing.life.quiet_until.get(brain.id,0)):return false
	var text:String=row.en if TranslationServer.get_locale().begins_with('en') else row.zh
	if not w.director.say_local(brain.id,text,'brain_interaction' if listener=='human' else 'local_pair',float(w.hunger.config.personal_gap),float(w.hunger.config.village_gap),listener):return false
	said[row.key]=true
	w.director.local_dialogue.persist_delivery(brain.id,{"id":"brain:"+scene+":"+str(row.key.get_slice(":",2))})
	w.director.local_dialogue.persist_delivery(brain.id,{"id":"brain-line:"+str(row.zh).sha256_text()})
	var entry:Dictionary={"actor":brain.id,"at":brain.clock,"day":w.days.day(),"event":kind,"choice":"host_interaction" if listener=='human' else 'peer_interaction',"source":"local","scene":scene,"reasons":["interaction_"+scene] if data.scenes.has(scene) else ["rhythm_"+str(w.days.phase().id)] if scene.begins_with("rhythm:") else ["brain_social"],"reason":reason,"proof":proof,"listener":listener,"zh":row.zh,"en":row.en,"outcome":"completed"}
	receipts.append(entry.duplicate(true));if receipts.size()>256:receipts.pop_front()
	brain.trace(entry);brain.history.append(entry.duplicate(true));if brain.history.size()>int(brain.config.history_limit):brain.history.pop_front()
	return true
func tick_current()->void:
	if brain.current.get('action','')!='host_interaction' or w._routes.has(brain.id):return
	var fact:Dictionary=brain.current.interaction
	if pending.is_empty():brain.finish('completed','trigger_expired');return
	if pending.proof!=fact.proof:brain.finish('completed','trigger_superseded');return
	if not still_true(fact.scene):pending.clear();brain.finish("completed","conditions_changed");return
	if deliver_pending():brain.finish('completed','interaction_delivered')
	elif brain.clock-float(brain.current.start)>float(data.event_ttl):brain.finish('timeout','speech_gate')
func social(action:String,from:String='human')->Dictionary:
	if action not in ['play','chess','walk','stars','chat','back_to_back','sea_watch','sweep','pair_sea','pair_sweep','small_coop']:return {"ok":false,"error":"not_social"}
	var reason:String='refuse_hunger' if w.hunger.rank(brain.id)>=2 else 'refuse_command' if brain.busy() or brain.current.get('source','') in ['command','steward'] else 'refuse_tired' if float(brain.needs.tired)>=float(brain.config.tired_refusal) else 'refuse' if brain.rng.randf()<float(data.refusal_chance.get(brain.tag(),.2)) else ''
	if not reason.is_empty():
		# Queue the full authored reason until the original speech gate can deliver it.
		brain.refusal={"reason":reason,"from":from,"action":action,"until":brain.clock+float(data.event_ttl)}
		var decision:Dictionary={"actor":brain.id,"at":brain.clock,"day":w.days.day(),"event":"social_decision","choice":"peer_interaction","source":"local","action":action,"listener":from,"reason":reason,"reasons":["interaction_refuse" if reason=="refuse" else reason],"social":true,"outcome":"declined"}
		brain.trace(decision);brain.history.append(decision)
		if brain.history.size()>int(brain.config.history_limit):brain.history.pop_front()
		return {"ok":false,"error":reason,"social":true,"reason":data.scenes.refuse.reason.duplicate()}
	return {"ok":true,"social":true}
func refusal_tick()->void:
	if brain.refusal.is_empty():return
	var r:RefCounted=w.director.routines[brain.id]
	if brain.clock<r.visual_quiet_until or w.fishing.life.time<float(w.fishing.life.quiet_until.get(brain.id,0)):return
	var ref:Dictionary=brain.refusal
	if brain.clock>float(ref.until):brain.refusal.clear();return
	if ref.reason=='refuse':
		if deliver('refuse','social:'+ref.action,ref.from,'social_refusal'):brain.refusal.clear()
	else:
		w.director.local_dialogue.persistent_setup()
		var section:String=w.director.local_dialogue.daily_section(brain.id)
		if w.director.local_dialogue.daily.get_value(section,"brain-refusal:"+str(ref.reason),false):brain.refusal.clear();return
		if w.director.say_local(brain.id,brain.text(ref.reason),'brain_invite',float(w.hunger.config.personal_gap),float(w.hunger.config.village_gap),ref.from):
			var entry:Dictionary={"actor":brain.id,"at":brain.clock,"day":w.days.day(),"event":"social_refusal","choice":"peer_interaction","source":"local","scene":"refuse","listener":ref.from,"reason":[brain.text(ref.reason,"zh"),brain.text(ref.reason,"en")],"reasons":[ref.reason],"zh":brain.text(ref.reason,"zh"),"en":brain.text(ref.reason,"en"),"social":true,"outcome":"completed"}
			w.director.local_dialogue.persist_delivery(brain.id,{"id":"brain-refusal:"+str(ref.reason)})
			brain.trace(entry);receipts.append(entry);brain.history.append(entry.duplicate(true))
			if receipts.size()>256:receipts.pop_front()
			if brain.history.size()>int(brain.config.history_limit):brain.history.pop_front()
			brain.refusal.clear()

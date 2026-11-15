extends RefCounted
## Session conversation ledger. Only a brain starts/finishes its own local route.
var owner:WeakRef
var w:RefCounted:
	get:return owner.get_ref()
var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/brain-social.json"))
var sessions:Dictionary={}
var by_actor:Dictionary={}
var due:Dictionary={}
var used:Dictionary={}
var completed:Dictionary={}
var serial:=0
var generation:=-1
var used_day:=-1
func _init(world:RefCounted)->void:owner=weakref(world);generation=world.session_generation
func cfg()->Dictionary:return w.director.brains.values()[0].config.social_scenes
func reset_if_needed()->void:
	if used_day!=w.days.day():used.clear();used_day=w.days.day()
	if generation==w.session_generation:return
	sessions.clear();by_actor.clear();due.clear();used.clear();completed.clear();generation=w.session_generation
func eligible(id:String)->bool:
	if not w.director.brains.has(id):return false
	if w.hunger.rank(id)>=3:return false
	if not w.activities.following.has(id) and w.director.brains[id].clock>=w.director.brains[id].next_visit:return false
	var b:RefCounted=w.director.brains[id];var r:RefCounted=w.director.routines[id]
	return b.active() and r.enabled and r.chatter and not r.held and not b.busy() and w.director.time>=r.visual_quiet_until and w.fishing.held(id).is_empty() and not w._routes.has(id)
func contexts(a:String,b:String)->Array:
	var result:Array=['idle']
	if w.weather.current().id=='rain':result.push_front('rain')
	if w.hunger.rank(a)>=2 and w.hunger.rank(b)>=2:result.push_front('waiting')
	if w.director.brains[a].current.get('action','') in ['read','daydream','night_rest','local_sit'] or w.director.brains[b].current.get('action','') in ['read','daydream','night_rest','local_sit']:result.append('rest')
	if not w.fishing.shore(a).is_empty() and not w.fishing.shore(b).is_empty():result.append('sea')
	for life in w.barbecues.values():
		if life.fireside.jobs.has(a) and life.fireside.jobs.has(b) and not life.fireside.state.current.is_empty():result.append('meal')
	return result
func observe(brain:RefCounted)->void:
	reset_if_needed()
	var id:String=brain.id
	if by_actor.has(id):tick(brain);return
	if brain.clock<float(cfg().first_after) or brain.clock<float(due.get(id,0)) or not eligible(id):return
	if w.hunger.rank(id)<2:
		for peer in w.director.brains:
			if peer==id or by_actor.has(peer) or not eligible(peer) or brain.clock<float(due.get(peer,0)):continue
			if w.actors[peer].region_id!=w.actors[id].region_id or w.point(w.actors[peer]).distance_to(w.point(w.actors[id]))>float(cfg().pair_distance):continue
			if not kinds_for(brain,peer).is_empty() and (int(completed.get(id,0))==0 or int(completed.get(peer,0))==0):return
	var peers:Array=w.director.brains.keys();peers.sort_custom(func(a,b):return int(completed.get(a,0))<int(completed.get(b,0)) if completed.get(a,0)!=completed.get(b,0) else str(a)<str(b))
	for peer in peers:
		if peer==id or by_actor.has(peer) or not eligible(peer) or brain.clock<float(due.get(peer,0)):continue
		if w.actors[peer].region_id!=w.actors[id].region_id or w.point(w.actors[peer]).distance_to(w.point(w.actors[id]))>float(cfg().pair_distance):continue
		var pair_rows:Array=data.pairs.filter(func(p):return id in p.actors and peer in p.actors)
		if pair_rows.is_empty():continue
		var real:Array=contexts(id,peer)
		for context in real:
			for script in pair_rows[0].scripts:
				var key:String=str(w.days.day())+':'+str(script.id)
				if script.context!=context or used.has(key):continue
				brain.effect('local','social_banter',func():begin(id,peer,script,key))
				return
func begin(a:String,b:String,script:Dictionary,key:String)->void:
	serial+=1;var token:String='social-'+str(serial)
	var lines:Array=script.lines.duplicate(true)
	if w.director.brains[a].distance()<=float(cfg().near_host):
		var judge:Dictionary=data.judge.voices.get(w.intelligence.tag(a),data.judge.voices.gentle)
		lines.append({'actor':a,'zh':judge.zh,'en':judge.en,'listener':'human'})
	sessions[token]={'id':token,'members':[a,b],'kind':'banter','context':script.context,'lines':lines,'index':0,'started':w.director.time,'next':w.director.time,'reason':['我们正因为身边的事拌两句嘴','we are trading banter about what is happening nearby'],'proof':key,'relation_stages':[w.relationships.index(a),w.relationships.index(b)],'delivered':{}}
	used[key]=true;by_actor[a]=token;by_actor[b]=token
	for who in [a,b]:
		var participant:RefCounted=w.director.brains[who]
		participant.invitation={'from':b if who==a else a,'action':'social_banter','until':w.director.time+float(cfg().expiry_seconds),'point':w.point(w.actors[who]),'paired':true,'coop':token}
		participant.next_decision=w.director.time
		w.director.brains[who].trace({'actor':who,'at':w.director.time,'event':'social_begin','kind':'banter','session':token,'context':script.context,'reasons':['brain_social']})
func candidate(brain:RefCounted)->Dictionary:
	reset_if_needed()
	if by_actor.has(brain.id) or brain.clock<float(cfg().first_after) or brain.clock<float(due.get(brain.id,0)) or w.hunger.rank(brain.id)>=2:return {}
	for peer in w.director.brains:
		if peer==brain.id or by_actor.has(peer) or w.hunger.rank(peer)>=2 or not eligible(peer) or brain.clock<float(due.get(peer,0)):continue
		if w.actors[peer].region_id!=w.actors[brain.id].region_id or w.point(w.actors[peer]).distance_to(w.point(w.actors[brain.id]))>float(cfg().pair_distance):continue
		if kinds_for(brain,peer).is_empty():continue
		return {'action':'small_coop','score':float(cfg().candidate_score),'reasons':['brain_social'],'partner':peer}
	return {}
func kinds_for(brain:RefCounted,peer:String)->Array:
	var kinds:Array=['butterfly']
	if not w.fishing.shore(brain.id).is_empty():kinds.append('sea')
	if w.cat.discovered and w.cat.region==w.actors[brain.id].region_id and w.cat.position.distance_to(w.point(w.actors[brain.id]))<=float(cfg().pair_distance):kinds.append('cat')
	for life in w.barbecues.values():
		if w.standard.ready(life.station.id) and life.station.region_id==w.actors[brain.id].region_id and w.point(life.station).distance_to(w.point(w.actors[brain.id]))<=float(cfg().pair_distance):kinds.append('camp')
	return kinds.filter(func(kind):return not used.has('coop:'+brain.id+':'+kind) and not used.has('coop:'+peer+':'+kind))
func prepare(brain:RefCounted,choice:Dictionary)->bool:
	var peer:String=choice.partner
	if by_actor.has(brain.id) or by_actor.has(peer) or not eligible(peer):return false
	if not w.director.brains[peer].interactions.social('small_coop',brain.id).ok:return false
	var kinds:Array=kinds_for(brain,peer)
	if kinds.is_empty():return false
	var kind:String=kinds[brain.rng.randi_range(0,kinds.size()-1)]
	for who in [brain.id,peer]:used['coop:'+who+':'+kind]=true
	var center:Vector2=w.point(w.actors[peer])
	if w.activities.following.has(brain.id) and w.actors[brain.id].region_id==w.actors.human.region_id and brain.distance()<=float(brain.config.follow_max):
		var direction:Vector2=(center-w.point(w.actors.human)).normalized()
		if direction.length()<.1:direction=Vector2.RIGHT
		center=w.point(w.actors.human)+direction*float(cfg().coop_host_radius)
	var at:Vector2=center+Vector2(0,1.5)
	if not w.walkable(w.actors[brain.id].region_id,at) or not w.walkable(w.actors[peer].region_id,center):
		var found:=false
		for attempt in int(brain.config.destination_attempts):
			center=w.point(w.actors.human)+Vector2.from_angle(float(attempt)*TAU/float(brain.config.destination_attempts))*float(cfg().coop_host_radius) if w.activities.following.has(brain.id) else w.point(w.actors[peer])+Vector2.from_angle(float(attempt)*TAU/float(brain.config.destination_attempts))*1.5
			at=center+Vector2(0,1.5)
			if w.walkable(w.actors[brain.id].region_id,at) and w.walkable(w.actors[peer].region_id,center):found=true;break
		if not found:return false
	serial+=1;var token:String='social-'+str(serial);var lines:Array=[]
	for stage in ['begin','middle','end']:
		for who in [brain.id,peer]:
			var voice:Dictionary=data.cooperation[kind].voices.get(w.intelligence.tag(who),data.cooperation[kind].voices.gentle)
			lines.append({'actor':who,'zh':voice[stage][0],'en':voice[stage][1],'stage':stage})
	sessions[token]={'id':token,'members':[brain.id,peer],'kind':'cooperation','context':kind,'lines':lines,'index':0,'started':brain.clock,'next':brain.clock,'reason':data.cooperation[kind].reason,'proof':token,'delivered':{}}
	by_actor[brain.id]=token;by_actor[peer]=token
	choice.merge({'point':at,'paired':true,'coop':token},true)
	brain.current.merge({'paired':true,'coop':token,'duration':float(cfg().session_seconds)},true)
	w.director.brains[peer].invitation={'from':brain.id,'action':'small_coop','until':brain.clock+float(cfg().expiry_seconds),'point':center,'paired':true,'coop':token}
	w.director.brains[peer].next_decision=brain.clock
	return true
func tick(brain:RefCounted)->void:
	var token:String=by_actor.get(brain.id,'')
	if token.is_empty() or not sessions.has(token):return
	var s:Dictionary=sessions[token];var ids:Array=s.members
	if brain.clock-float(s.started)>float(cfg().expiry_seconds):end(s,'timeout');return
	if ids.any(func(id):return w.hunger.rank(id)>=3):end(s,'very_hungry');return
	if ids.any(func(id):return not eligible(id) and not w._routes.has(id)):
		# Held/real work cancels conversation. A pending local arrival is allowed below.
		if ids.any(func(id):return w.director.routines[id].held or w.work.jobs.has(id) or w.activities.members.has(id) or w.director.time<w.director.routines[id].visual_quiet_until):end(s,'interrupted');return
	if ids.any(func(id):return w.director.brains[id].current.get('coop','')!=token):
		if ids.any(func(id):return w.director.brains[id].current.get('coop','')!=token and w.director.brains[id].invitation.get('coop','')!=token):end(s,'interrupted')
		return
	if ids.any(func(id):return w._routes.has(id)):return
	if w.actors[ids[0]].region_id!=w.actors[ids[1]].region_id or w.point(w.actors[ids[0]]).distance_to(w.point(w.actors[ids[1]]))>float(cfg().pair_distance):end(s,'separated');return
	if s.kind=='cooperation':
		for index in ids.size():
			w.lively.active[ids[index]]={'action':data.cooperation[s.context].poses[index],'start':brain.clock,'until':brain.clock+1}
	if int(s.index)>=s.lines.size():end(s,'completed' if ids.all(func(id):return int(s.delivered.get(id,0))>=(3 if s.kind=='cooperation' else 2)) else 'exhausted');return
	var item:Dictionary=s.lines[int(s.index)]
	if item.actor!=brain.id or brain.clock<float(s.next) or not eligible(brain.id):return
	var other:String=ids[1] if brain.id==ids[0] else ids[0]
	var row:Dictionary={'zh':item.zh,'en':item.en,'key':str(w.days.day())+':'+s.proof+':'+str(s.index)}
	var section:String=w.director.local_dialogue.daily_section(brain.id)
	if w.director.local_dialogue.daily.get_value(section,"brain-line:"+str(row.zh).sha256_text(),false):s.index+=1;return
	var scene:String='social_'+s.proof
	if brain.interactions.deliver_authored(row,scene,s.proof,str(item.get('listener',other)),'banter_line' if s.kind=='banter' else 'cooperation_line',s.reason):
		s.delivered[brain.id]=int(s.delivered.get(brain.id,0))+1
		s.index+=1;s.next=brain.clock+float(cfg().reply_seconds)
func end(s:Dictionary,outcome:String)->void:
	for who in s.members:
		var b:RefCounted=w.director.brains[who]
		b.trace({'actor':who,'at':w.director.time,'day':w.days.day(),'event':'social_episode','kind':s.kind,'session':s.id,'context':s.context,'outcome':outcome,'reasons':['brain_social']})
		if outcome=='completed':completed[who]=int(completed.get(who,0))+1
		if b.invitation.get('coop','')==s.id:b.invitation.clear()
		by_actor.erase(who);due[who]=w.director.time+float(cfg().cooldown_seconds)
		if b.current.get('coop','')==s.id:b.finish('completed' if outcome=='completed' else 'interrupted','social_'+outcome)
	sessions.erase(s.id)

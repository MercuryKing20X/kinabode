extends Node2D
## Session-only shared play. Every displacement goes through World.command.
const Text=preload("res://scripts/localization.gd")
const GAMES=["hide","fireflies","circle","shuttlecock","rope"]
var render_probe:Dictionary={}
var rope_rng:=RandomNumberGenerator.new()
var rope_assignment:Array=[]
var rope_assignments:Array=[]
var rope_ready:=false
var rope_time:=0.0
var rope_count:=0
var rope_limit:=8
var rope_round:=0
var rope_pause:=0.0
var rope_last_cycle:=-1
var rope_swaps:=0
var rope_counts:Array=[]
var cute_counts:Dictionary={}
var cute_events:Array=[]
var nearby:Dictionary={}
var nearby_config:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/nearby_play.json"))
var duration:=0.0
var last_auto_kind:=""
var game:Node
var kind:=""
var members:Array=[]
var leader:=""
var anchor:=Vector2.ZERO
var elapsed:=0.0
var beat:=0
var owned:Dictionary={}
var completed:Array=[]
var auto_day:=0
var auto_count:=0
var last_auto:=0.0
var found:Dictionary={}
var speech_serial:=0
var hide_targets:Dictionary={}
var last_meal_count:=0
var was_raining:=false
var finale:=0.0
var release_points:Array=[]
func setup(host:Node)->void:
	z_index=20
	rope_rng.randomize()
	game=host;game.view.play_stage=self;last_meal_count=game.world.shared_activity.memories.size();was_raining=int(game.world.weather.current().get("rain",0))>0
func free_actor(id:String)->bool:
	return game.world.actors.has(id) and game.world.actors[id].region_id=="home" and game.world.hunger.rank(id)<3 and not game.world.work.jobs.has(id) and not game.world.shared_activity.contains(id) and not game.world.activities.commanded(id) and not game.world.farms.active(id) and game.world.fishing.pending(id).is_empty() and not game._resident_chat_busy(id) and not game.intentions.plans.has(id) and (not game.world._routes.has(id) or game.world.activities.following.has(id) or game.world.director.routines[id].owns_route)
func can_invite_guest(id:String)->bool:
	var w:RefCounted=game.world
	if not w.director.routines.has(id) or not free_actor(id):return false
	var routine:RefCounted=w.director.routines[id]
	var brain:RefCounted=w.director.brains.get(id)
	return routine.enabled and not routine.held and not w.activities.blocked(id,false) and not w.actors[id].has("world_door_client") and not w.director.model_controlled(id) and (brain==null or (not brain.busy() and brain.current.get("origin","")!="island_ai"))

func invite(initiator:String,which:String,guests:Array)->Dictionary:
	if which not in GAMES or not kind.is_empty():return {"ok":false,"error":"play_active_or_unknown"}
	var w:RefCounted=game.world
	if not w.director.routines.has(initiator) or not free_actor(initiator) or w.director.routines[initiator].held:return {"ok":false,"error":"play_needs_available_friends"}
	var selected:Array=[initiator]
	for guest in guests:
		if guest in selected or not can_invite_guest(guest):return {"ok":false,"error":"play_needs_available_friends"}
		selected.append(guest)
	return start(which,false,selected,initiator)

var assembly_age:=0.0
var assembly_ready:=false
func start(which:String,join_human:bool=false,selected_residents:Array=[],initiator:String="")->Dictionary:
	if which not in GAMES:return {"ok":false,"error":"play_active_or_unknown"}
	if not kind.is_empty():
		if which!=kind:return {"ok":false,"error":"play_active_or_unknown"}
		if join_human and "human" not in members and game.world.actors.human.region_id=="home" and not game.world.work.jobs.has("human"):members.append("human")
		return {"ok":true,"participants":members.duplicate()}
	for who in nearby:
		if owned.has(who) and is_same(game.world._routes.get(who,[]),owned[who]):game.world._routes.erase(who)
		game.world.activities.suspended_follow.erase(who);game.view.motion.play_poses.erase(who)
	nearby.clear()
	members=[]
	for id in (game.world.director.routines.keys() if selected_residents.is_empty() else selected_residents):
		if free_actor(id):members.append(id)
	if members.size()<(4 if which=="rope" else 3):
		members.clear()
		return {"ok":false,"error":"play_needs_available_friends"}
	leader=initiator if initiator in members else "codex" if "codex" in members else str(members[0])
	members.erase(leader);members.push_front(leader)
	if join_human and game.world.actors.human.region_id=="home" and not game.world.work.jobs.has("human"):members.append("human")
	rope_assignment.clear();rope_assignments.clear();rope_ready=false
	duration=0;rope_time=0;rope_count=0;rope_round=0;rope_pause=0;rope_last_cycle=-1;rope_swaps=0;rope_counts.clear();rope_limit=randi_range(5,15)
	anchor=game.world.point(game.world.actors[leader]);kind=which;elapsed=0;beat=0;found.clear();owned.clear();hide_targets.clear();finale=0;release_points.clear()
	if which=="rope":
		var safe_anchor:=Vector2.INF
		for radius in [0,2,4,6,8,10,12]:
			for angle in range(8):
				var center:Vector2=anchor+Vector2.from_angle(TAU*angle/8)*radius
				if not game.world.segment_clear("home",center+Vector2(-3.5,0),center+Vector2(3.5,0)):continue
				var safe:=true
				for offset in [Vector2(-3.5,0),Vector2(3.5,0),Vector2(-.5,0),Vector2(.5,0)]:
					if not game.world.walkable("home",center+offset):safe=false;break
				if safe:safe_anchor=center;break
			if safe_anchor.is_finite():break
		if not safe_anchor.is_finite():kind="";members.clear();return {"ok":false,"error":"play_unreachable"}
		anchor=safe_anchor
	if which in ["hide","fireflies"]:
		for offset in [Vector2.ZERO,Vector2(-8,0),Vector2(8,0),Vector2(0,8),Vector2(0,-8)]:
			var center:Vector2=anchor+offset
			var safe:=true
			for i in range(8):
				if not game.world.walkable("home",center+Vector2(cos(TAU*i/8),sin(TAU*i/8))*4):safe=false;break
			if safe:anchor=center;break
	if which=="rope":assign_rope_roles()
	for id in members:
		game.world.hunger.clear_follow(id)
		game.world.activities.suspended_follow[id]=true
		if id!="human":game.world.director.routines[id].interrupt(180)
	if kind=="circle":
		var camps:Array=game.world.barbecues.values()
		if not camps.is_empty():anchor=game.world.point(camps[0].station)
	if kind=="hide":
		var covers:Array=game.world.objects.values().filter(func(o):return o.get("region_id","")=="home" and o.get("kind","") in ["tree","construction_site"] and game.world.point(o).distance_to(anchor)<30)
		covers.sort_custom(func(a,b):return game.world.point(a).distance_to(anchor)<game.world.point(b).distance_to(anchor))
		for i in range(1,members.size()):
			if covers.is_empty():break
			for offset in [Vector2(0,2),Vector2(2,0),Vector2(-2,0),Vector2(0,-2)]:
				var at:Vector2=game.world.point(covers[(i-1)%covers.size()])+offset
				if game.world.walkable("home",at):hide_targets[members[i]]=at;break
	assembly_age=0;assembly_ready=false
	for i in members.size():
		if members[i]!="human" and kind!="rope":route(members[i],anchor+Vector2.from_angle(TAU*i/members.size())*4)
	line(leader,"playground.start."+kind)
	return {"ok":true,"participants":members.duplicate()}
func line(id:String,key:String)->void:
	if id=="human" or not game.world.actors.has(id) or kind.is_empty():return
	var text:String=Text.text(key)
	if key in ["playground.round","playground.end","playground.found"] or key.begins_with("playground.start."):
		var tag:String=game.world.intelligence.tag(id)
		if tag not in ["gentle","lively","laborious","quiet"]:tag="gentle"
		var voice_key:="playground.voice."+kind+"."+tag+"."+("start" if key.begins_with("playground.start.") else key.get_slice(".",1))+"."+str(speech_serial%4)
		var voice:=Text.text(voice_key)
		if voice!=voice_key:text=voice
		speech_serial+=1
	game.view.say(text,"local_rules",id,"playground")
	game._record_chat(game.Channels.ALL,id,text,"local")
	if id==leader and (key.begins_with("playground.start.") or key in ["playground.round","playground.end"]) and game.world.director.model_controlled(id):
		var link:Node=game.links.get(id)
		if link!=null and link.has_method("uses_intents") and link.uses_intents() and not link.is_busy():
			var snapshot:Dictionary=game._snapshot_for_chat(id,game.Channels.direct(id),[id],"")
			snapshot.intent_card["playground_speech"]={"game":kind,"stage":key,"participants":members.duplicate(),"speech_only":true}
			game.immediate_turns[id]={"command":false,"plan":true,"playground":true,"memory_sources":[],"memory_request":{}}
			link.send_message(Text.text("playground.ai_cue"),snapshot)
			game.immediate_turns[id]["turn_key"]=link.turn_key
func route(id:String,at:Vector2)->void:
	var w:RefCounted=game.world
	if w._routes.has(id):return
	if not w.walkable("home",at):return
	var result:Dictionary=w.command(id,{"intent":"move","region_id":"home","x":at.x,"y":at.y})
	if result.get("ok",false):owned[id]=w._routes.get(id,[])
func stop()->void:
	if not release_points.is_empty() and game.view.get("atmosphere")!=null:
		var lights:Array=game.view.atmosphere.particles.get("fireflies",[])
		for i in mini(lights.size(),release_points.size()):lights[i].point=release_points[i]
	release_points.clear()
	for id in members:
		game.view.motion.play_poses.erase(id)
		game.view.motion.play_phases.erase(id)
		game.world.activities.suspended_follow.erase(id)
	for id in owned:
		if is_same(game.world._routes.get(id,[]),owned[id]):
			# Releasing a game-owned route is not a new player stop order.
			game.world._routes.erase(id)
			game.world.actors[id].activity="idle"
	kind="";members.clear();owned.clear();rope_assignment.clear();rope_ready=false
func tick(delta:float)->void:
	if game==null:return
	queue_redraw()
	var w:RefCounted=game.world
	var meal_count:int=w.shared_activity.memories.size()
	var raining:bool=int(w.weather.current().get("rain",0))>0
	last_meal_count=meal_count;was_raining=raining
	if kind.is_empty():
		nearby_tick(delta)
		return
	duration+=delta
	if duration>=120:finish();return
	for id in members:
		if w.hunger.rank(id)>=3 or w.work.jobs.has(id) or w.farms.active(id) or (owned.has(id) and w._routes.has(id) and not is_same(w._routes[id],owned[id])):stop();return
	for id in members:
		if kind not in ["shuttlecock","rope"]:game.view.motion.play_poses.erase(id)
		if not w._routes.has(id):
			if kind=="hide" and id==leader and beat<=10:game.view.motion.play_poses[id]="fire_squat"
	if finale>0:
		for i in members.size():
			var who:String=str(members[i])
			if w.point(w.actors[who]).distance_to(anchor)>6 and not w._routes.has(who):
				var angle:float=TAU*i/members.size()
				route(who,anchor+Vector2(cos(angle),sin(angle))*4)
		if members.any(func(id):return w._routes.has(id) or w.point(w.actors[id]).distance_to(anchor)>6):return
		finale+=delta
		for id in members:game.view.motion.play_poses[id]="fire_sit"
		if kind=="fireflies" and game.view.get("atmosphere")!=null:
			var lights:Array=game.view.atmosphere.particles.get("fireflies",[])
			for i in lights.size():
				if release_points.size()<lights.size():release_points.append(lights[i].point)
				var angle:float=TAU*i/maxi(1,lights.size())
				lights[i].point=anchor+Vector2(cos(angle),sin(angle))*(1+finale*1.5)
		if finale>=6:finish()
		return
	if not assembly_ready:
		assembly_age+=delta
		if members.any(func(who):return w._routes.has(who)):
			if assembly_age>=60:stop()
			return
		assembly_ready=true
	if kind=="rope":rope_tick(delta);return
	elapsed+=delta
	if elapsed<1:return
	elapsed-=1;beat+=1
	if beat%8==4 and not members.is_empty():
		var speaker:String=str(members[int(beat/8)%members.size()])
		if speaker=="human":speaker=leader
		line(speaker,"playground.round")
	if kind=="hide" and beat<=10:
		line(leader,"playground.count."+str(11-beat))
		for i in range(1,members.size()):route(members[i],hide_targets.get(members[i],anchor+Vector2(8+i*2,(-1 if i%2 else 1)*7)))
		if beat==10:
			for id in members.slice(1):line(id,"playground.hush")
	elif kind in ["shuttlecock","rope"]:
		for i in members.size():
			var target:Vector2=anchor+Vector2.from_angle(TAU*i/members.size())*3
			if kind=="rope":target=anchor+Vector2((i-1)*2.5,0)
			route(members[i],target)
			game.view.motion.play_poses[members[i]]=("play_kick" if i==int(duration/3)%members.size() else "gesture_wave") if kind=="shuttlecock" else ("play_jump" if i>=2 else "gesture_wave")
	elif beat>=40 and kind!="hide":
		pass
	elif kind in ["circle","fireflies"]:
		for i in members.size():
			var angle:float=TAU*i/members.size()+beat*.25
			var target:Vector2=anchor+Vector2(cos(angle),sin(angle))*4
			if kind=="fireflies" and game.view.get("atmosphere")!=null:
				var lights:Array=game.view.atmosphere.particles.get("fireflies",[])
				if not lights.is_empty():target=lights[(i+int(beat/8))%lights.size()].point
			route(members[i],target)
		if beat%8==1:line(leader,"playground.notes")
	elif kind=="hide":
		var index:int=1
		while index<members.size()-1 and found.has(members[index]):index+=1
		if not found.has(members[index]) and not w._routes.has(leader):route(leader,w.point(w.actors[members[index]]))
		if not found.has(members[index]) and w.point(w.actors[leader]).distance_to(w.point(w.actors[members[index]]))<3:
			found[members[index]]=true;line(members[index],"playground.found");route(members[index],anchor)
	# Two minutes is the upper bound. Preserve the original completed-round
	# exit once all movement from the existing forty beats has really ended.
	if beat>=40 and kind in ["circle","fireflies"] and members.all(func(id):return not w._routes.has(id)):
		finale=.01;line(leader,"playground.release" if kind=="fireflies" else "playground.rest")
func finish()->void:
	if kind.is_empty():return
	if kind in ["rope","shuttlecock"]:game.view.atmosphere.leave_trace(game.view,kind,anchor)
	var id:String="play:"+Crypto.new().generate_random_bytes(12).hex_encode()
	var participants:Array=members.duplicate()
	var photo_entry:=""
	completed.append({"id":id,"game":kind,"participants":participants,"day":game.world.days.day()})
	for who in participants:
		if who=="human":continue
		if game.memory_books.add(who,game.world.world_id,id,"facts","playground.memory."+kind,{},game.world.days.day(),"game",participants,game.world.forest.clock):
			var entries:Array=game.memory_books.list_for(who,"facts").filter(func(e):return e.event_id==id)
			if not entries.is_empty() and photo_entry.is_empty():photo_entry=entries[0].id
	if not photo_entry.is_empty():game.memory_life.capture(photo_entry,true)
	line(leader,"playground.end")
	stop()

func _draw()->void:pass
func draw_props(view:Node2D,behind:bool=false)->void:
	view.draw_set_transform(Vector2.ZERO)
	if not behind:render_probe={"kind":kind,"ready":assembly_ready,"members":members.size()}
	if kind=="rope" and assembly_ready and rope_ready and rope_assignment.size()>=4:
		var ids:Array=rope_roles()
		var phase:float=fposmod(rope_time,1.6)/1.6
		if behind!=(phase<.25 or phase>.75):return
		var a:Vector2=view.screen(game.world.point(game.world.actors[ids[0]]))+preload("res://scripts/play_frames.gd").hand(phase,true,game.library.visual_appearance(game.world.actors[ids[0]]),str(game.world.actors[ids[0]].facing))*view.zoom
		var b:Vector2=view.screen(game.world.point(game.world.actors[ids[1]]))+preload("res://scripts/play_frames.gd").hand(phase,false,game.library.visual_appearance(game.world.actors[ids[1]]),str(game.world.actors[ids[1]].facing))*view.zoom
		render_probe["a"]=[a.x,a.y];render_probe["b"]=[b.x,b.y]
		var points:=PackedVector2Array()
		for i in range(49):
			var t:float=i/48.0
			points.append(a.lerp(b,t)+Vector2(0,(-39-cos(phase*TAU)*73)*sin(t*PI))*view.zoom)
		view.draw_polyline(points,Color("ffe08a"),maxf(2,3*view.zoom),false)
		view.draw_circle(a,2*view.zoom,Color("ffe08a"));view.draw_circle(b,2*view.zoom,Color("ffe08a"))
	elif not behind and kind=="shuttlecock" and not members.is_empty():
		var index:int=int(duration/3)%members.size()
		var a:Vector2=view.screen(game.world.point(game.world.actors[members[index]]))
		var b:Vector2=view.screen(game.world.point(game.world.actors[members[(index+1)%members.size()]]))
		var t:float=fmod(duration,3)/3
		var at:Vector2=a.lerp(b,t)+Vector2(0,-sin(t*PI)*55-15)*view.zoom
		view.draw_circle(at,3*view.zoom,Color("d68644"))
		for i in range(3):view.draw_line(at,at+Vector2((i-1)*4,-12)*view.zoom,Color("fff1be"),maxf(1,2*view.zoom))
func rope_roles()->Array:
	# Rendering and observers read a stable copy; they never draw randomness.
	return rope_assignment.duplicate()
func shuffle_rope(values:Array)->void:
	for i in range(values.size()-1,0,-1):
		var j:int=rope_rng.randi_range(0,i)
		var previous:Variant=values[i];values[i]=values[j];values[j]=previous
func assign_rope_roles()->void:
	var roster:Array=[]
	for id in members:
		if id!="human" and id not in roster:roster.append(id)
	if roster.size()<4:rope_assignment.clear();rope_ready=false;return
	var previous:Array=rope_assignment.slice(2,4);previous.sort()
	var choices:Array=[]
	for i in roster.size():
		for j in range(i+1,roster.size()):
			var pair:Array=[roster[i],roster[j]];pair.sort()
			if pair!=previous:choices.append(pair)
	var jumpers:Array=choices[rope_rng.randi_range(0,choices.size()-1)].duplicate()
	var turners:Array=roster.filter(func(id):return id not in jumpers)
	shuffle_rope(turners);shuffle_rope(jumpers)
	rope_assignment=turners.slice(0,2)+jumpers+turners.slice(2)
	rope_ready=false
	if game!=null:
		for id in roster:
			game.view.motion.play_poses.erase(id);game.view.motion.play_phases.erase(id)
	rope_assignments.append({"round":rope_round,"roles":rope_assignment.duplicate(),"elapsed":duration})
	if rope_assignments.size()>16:rope_assignments.pop_front()
func play_bubble(id:String,key:String)->void:
	# Activity cues use the original outlet; count is ephemeral, never a memory.
	var routine:RefCounted=game.world.director.routines.get(id)
	var numeric:bool=key.begins_with("rope.count.")
	var cue_allowed:bool=routine!=null and routine.enabled and routine.chatter and not routine.held and routine.time>=routine.visual_quiet_until and not game.questions.has(id) and not game.group_questions.has(id)
	if cue_allowed and (numeric or key.begins_with("rope.trip") or key.begins_with("rope.laugh") or game.world.director.can_say_local(id,"playground")):
		if not numeric and not game.world.personality.allowed_line(id,Text.text(key)):return
		if not numeric:game.world.personality.note_line(id,Text.text(key))
		game.view.say(Text.text(key),"local_rules",id,"playground")
func rope_tick(delta:float)->void:
	var w:RefCounted=game.world;var ids:Array=rope_roles()
	if ids.size()<4:return
	var targets:Array=[anchor+Vector2(-3.5,0),anchor+Vector2(3.5,0),anchor+Vector2(-.5,0),anchor+Vector2(.5,0)]
	for i in ids.size():
		var at:Vector2=targets[i] if i<4 else anchor+Vector2(0,2.5)
		if w.point(w.actors[ids[i]]).distance_to(at)>.25:route(ids[i],at)
	if ids.any(func(id):return w._routes.has(id) or float(w.motion_state(id).get("still_seconds",0))<.3):
		rope_ready=false
		for id in ids:
			game.view.motion.play_poses.erase(id);game.view.motion.play_phases.erase(id)
		return
	rope_ready=true
	if rope_pause>0:
		for i in ids.size():
			game.view.motion.play_poses[ids[i]]="rope_turn" if i<2 else "play_jump" if i in [2,3] else "gesture_wave"
			game.view.motion.play_phases[ids[i]]=fposmod(rope_time,1.6)/1.6 if i<2 else .9
		rope_pause-=delta
		if rope_pause<=0:
			rope_round+=1;rope_swaps+=1;rope_count=0;rope_time=0;rope_last_cycle=-1;rope_limit=randi_range(5,15)
			assign_rope_roles()
		return
	rope_time+=delta
	var phase:float=fposmod(rope_time,1.6)/1.6
	for i in ids.size():
		game.view.motion.play_poses[ids[i]]="rope_turn" if i<2 else "play_jump" if i in [2,3] else "gesture_wave"
		game.view.motion.play_phases[ids[i]]=phase
		if i<2:w.actors[ids[i]].facing="right" if i==0 else "left"
	var cycle:int=int((rope_time+.8)/1.6)
	if cycle>rope_last_cycle and phase>=.5:
		rope_last_cycle=cycle;rope_count+=1;rope_counts.append(rope_count)
		var jumper:String=ids[2]
		for who in ids.slice(2,4):play_bubble(who,"rope.count."+str(rope_count))
		if rope_count>=rope_limit:
			play_bubble(jumper,"rope.trip."+str(rope_round%4));play_bubble(ids[3] if ids.size()>3 else ids[0],"rope.laugh."+str(rope_round%4))
			rope_pause=2.5
		elif rope_count%4==0:play_bubble(jumper,"rope.gentle" if w.intelligence.tag(jumper)=="gentle" else "rope.cheer")

# Cosmetic session state; World remains the sole movement owner.
func nearby_tick(delta:float)->void:
	if not game.world.intelligence.compatibility:return
	var w:RefCounted=game.world
	for id in game.world.director.routines.keys():
		var routine:RefCounted=w.director.routines.get(id)
		var eligible:bool=free_actor(id) and w.activities.following.has(id) and not w.activities.blocked(id,false) and w.hunger.rank(id)<3 and routine!=null and routine.enabled and not routine.held and w.director.time>=float(w.hunger.quiet_until.get(id,0))
		if not eligible:
			if nearby.has(id):
				w.activities.suspended_follow.erase(id);game.view.motion.play_poses.erase(id);nearby.erase(id)
			continue
		if not nearby.has(id):nearby[id]={"left":0.0,"action":"","history":[]}
		var state:Dictionary=nearby[id]
		var host:Vector2=w.point(w.actors.human)
		if w.actors[id].region_id!=w.actors.human.region_id or w._routes.has("human") or w.point(w.actors[id]).distance_to(host)>5.5:
			w.activities.suspended_follow.erase(id);game.view.motion.play_poses.erase(id);state.left=0.0
			w.hunger.follow(id);continue
		w.hunger.clear_follow(id);w.activities.suspended_follow[id]=true
		state.left-=delta
		if state.left<=0:
			var actions:Array=nearby_config.actions
			var weights:Array=nearby_config.weights.get(w.intelligence.tag(id),nearby_config.weights.gentle)
			var total:=0
			for weight in weights:total+=int(weight)
			var roll:int=randi()%total;var choice:=0
			for i in weights.size():
				roll-=int(weights[i])
				if roll<0:choice=i;break

			state.action=actions[choice];state["age"]=0.0;state.left=randf_range(float(nearby_config.interval_min),float(nearby_config.interval_max))
			if state.action=="play_lie":state.left=randf_range(float(nearby_config.lie_seconds[0]),float(nearby_config.lie_seconds[1]))
			if state.action=="play_cute":
				if owned.has(id) and w._routes.has(id) and is_same(w._routes[id],owned[id]):
					w._routes.erase(id);w.actors[id].activity="idle"
				state["last_cute_cycle"]=-1
				state["repeats"]=randi_range(2,3) if w.intelligence.tag(id)=="lively" and randf()<float(nearby_config.cute_repeat_chance) else 1
				if randf()<float(nearby_config.cute_bubble_chance):play_bubble(id,"cute.yay" if randi()%2==0 else "cute.hey")
			state["duration"]=state.left
			state.history.append(state.action)
			if state.history.size()>64:state.history.pop_front()
			var target:Vector2=host+Vector2.from_angle(randf()*TAU)*randf_range(2,float(nearby_config.radius))
			if state.action in ["play_lie","play_cute"]:target=w.point(w.actors[id])
			if not w._routes.has(id) and w.segment_clear(w.actors[id].region_id,w.point(w.actors[id]),target) and w.walkable(w.actors[id].region_id,target):
				w.hunger.issuing=true
				var result:Dictionary=w.command(id,{"intent":"move","region_id":w.actors[id].region_id,"x":target.x,"y":target.y})
				w.hunger.issuing=false
				if result.get("ok",false):owned[id]=w._routes.get(id,[])
		state["age"]=float(state.get("age",0))+delta
		var phase:float=clampf(float(state.age)/maxf(.1,float(state.get("duration",1))),0,1)
		if state.action=="play_cute":
			var period:float=float(nearby_config.cute_period)
			phase=fposmod(float(state.age),period)/period
			var cycle:int=int(float(state.age)/period)
			if phase>=.25 and cycle<int(state.get("repeats",1)) and cycle>int(state.get("last_cute_cycle",-1)):
				state.last_cute_cycle=cycle;cute_counts[id]=int(cute_counts.get(id,0))+1
				cute_events.append({"id":id,"at":w.forest.clock,"cycle":cycle})
				if cute_events.size()>128:cute_events.pop_front()
			if float(state.age)>=period*int(state.get("repeats",1)):
				game.view.motion.play_poses[id]="idle";game.view.motion.play_phases.erase(id);continue
		game.view.motion.play_phases[id]=phase
		game.view.motion.play_poses[id]=state.action

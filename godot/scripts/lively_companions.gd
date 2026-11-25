extends RefCounted
## New idle-only presentation units; never suspend jobs or own a route.
const Text=preload("res://scripts/localization.gd")
var owner:WeakRef
var world:RefCounted:
	get:return owner.get_ref()
var config:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/lively-actions.json"))
var enabled:=true
var active:Dictionary={}
var counts:Dictionary={}
var pair_counts:Dictionary={}
var recent_pairs:Array=[]
var due:Dictionary={}
var pair_due:=0.0
var approaching:Dictionary={}
var proximity:Dictionary={}
var time:=0.0
var rng:=RandomNumberGenerator.new()
func _init(w:RefCounted)->void:owner=weakref(w);rng.seed=28043
func eligible(id:String)->bool:
	if world.director.brains.has(id) and world.director.brains[id].active():return world.director.brains[id].current.get("source","")=="local" and not world._routes.has(id)
	if not world.director.routines.has(id):return false
	var r:RefCounted=world.director.routines[id]
	if not r.enabled or r.held or r.blocked() or r.time<r.visual_quiet_until or (not r.kind.is_empty() and r.kind!="lively_pair") or world.activities.following.has(id):return false
	if world.work.jobs.has(id) or world._routes.has(id) or world.hunger.holds_idle(id):return false
	for camp in world.barbecues.values():
		if id in camp.fireside.selected_guests or id in camp.fireside.state.get("invited",[]):return false
	return true
func socially_idle(id:String)->bool:
	if not world.director.routines.has(id):return false
	var r:RefCounted=world.director.routines[id]
	if not r.kind.is_empty() and r.kind not in ["wander","nearby","look","watch","rest","stretch"]:return false
	if world.work.jobs.has(id) or world.activities.following.has(id) or r.held or not r.enabled:return false
	if r.time<r.visual_quiet_until or world.hunger.holds_idle(id):return false
	if world._routes.has(id) and not r.owns_route:return false
	for camp in world.barbecues.values():
		if id in camp.fireside.selected_guests or id in camp.fireside.state.get("invited",[]):return false
	return not r.blocked()
func advance(delta:float)->void:
	if not world.intelligence.compatibility:return
	if delta<=0 or not enabled:return
	time+=delta
	for id in world.director.routines:
		if not proximity.has(id):proximity[id]={"seconds":0.0,"near_seconds":0.0}
		proximity[id].seconds+=delta
		if world.actors[id].region_id==world.actors.human.region_id and world.point(world.actors[id]).distance_to(world.point(world.actors.human))<=8:proximity[id].near_seconds+=delta
	for id in active.keys():
		if not eligible(id) or time>=float(active[id].until):active.erase(id)
	for id in world.director.routines:
		if not due.has(id):due[id]=time+float(config.interval_seconds)+due.size()*5
		if time<float(due[id]) or not eligible(id) or active.has(id):continue
		due[id]=time+float(config.interval_seconds)
		var trait_id:String=str(world.intelligence.preset(id).get("main_trait",""))
		var tag:String=world.intelligence.tag(id)
		var options:Array=config.actions.get(trait_id,config.actions.get(tag,config.actions.gentle))
		var action:String=options[rng.randi_range(0,options.size()-1)]
		active[id]={"action":action,"start":time,"until":time+float(config.duration_seconds)}
		if not counts.has(id):counts[id]={}
		counts[id][action]=int(counts[id].get(action,0))+1
	if not approaching.is_empty():
		var first:String=approaching.first;var second:String=approaching.second
		if time>float(approaching.until) or not socially_idle(first) or not socially_idle(second):approaching.clear();pair_due=time+float(config.pair_retry_seconds)
		elif world.actors[first].region_id==world.actors[second].region_id and world.point(world.actors[first]).distance_to(world.point(world.actors[second]))<=float(config.pair_distance):
			for id in [first,second]:world.director.routines[id].interrupt(8)
			pair_due=time
			approaching.clear()
		else:return
	if time<pair_due:return
	pair_due=time+float(config.pair_interval_seconds)
	var ids:Array=world.director.routines.keys().filter(socially_idle)
	for i in range(ids.size()):
		for j in range(i+1,ids.size()):
			var a:Dictionary=world.actors[ids[i]];var b:Dictionary=world.actors[ids[j]]
			if a.region_id!=b.region_id:continue
			if world.point(a).distance_to(world.point(b))>float(config.pair_distance):
				if world.point(a).distance_to(world.point(b))>24:continue
				# Social approaches gather at the farther resident, rather than drawing
				# everyone back toward the human. Original follow/return routes still win.
				var mover:String=ids[i];var target:String=ids[j]
				var host:Dictionary=world.actors.human
				if host.region_id==a.region_id and world.point(a).distance_to(world.point(host))>world.point(b).distance_to(world.point(host)):
					mover=ids[j];target=ids[i]
				var approach_r:RefCounted=world.director.routines[mover]
				approach_r.interrupt(0)
				var away:Vector2=(world.point(world.actors[target])-world.point(host)).normalized() if host.region_id==a.region_id else Vector2.RIGHT
				if approach_r._move_to(world.point(world.actors[target])+away*1.8):
					approach_r.kind="wander";approaching={"first":mover,"second":target,"until":time+24};return
				continue
			for id in [ids[i],ids[j]]:world.director.routines[id].interrupt(8)
			var valid_actions:Array=config.pairs.filter(func(item):return item!="cat_watch" or (world.cat.discovered and world.cat.region==a.region_id and world.point(a).distance_to(world.cat.position)<=24 and world.point(b).distance_to(world.cat.position)<=24))
			var options:Array=valid_actions.filter(func(item):return item not in recent_pairs)
			if options.is_empty():recent_pairs.clear();options=valid_actions.duplicate()
			var action:String=options[rng.randi_range(0,options.size()-1)]
			recent_pairs.append(action)
			for id in [ids[i],ids[j]]:
				var partner:String=ids[j] if id==ids[i] else ids[i]
				active[id]={"action":action,"partner":partner,"start":time,"until":time+float(config.duration_seconds)}
				if action!="chase":
					var routine:RefCounted=world.director.routines[id]
					routine.kind="lively_pair";routine.duration=float(config.duration_seconds);routine.elapsed=0
					var aim:Vector2=world.cat.position if action=="cat_watch" else world.point(world.actors[partner])
					if action=="back_to_back":aim=world.point(world.actors[id])*2-aim
					world.work.face(world.actors[id],{"position":[aim.x,aim.y]})
			pair_counts[action]=int(pair_counts.get(action,0))+1
			if action=="chase":
				var first:RefCounted=world.director.routines[ids[i]]
				var second:RefCounted=world.director.routines[ids[j]]
				if first._move_to(world.point(b)+Vector2(2,0)):first.kind="wander"
				if second._move_to(world.point(a)+Vector2(-2,0)):second.kind="wander"
			var r:RefCounted=world.director.routines[ids[i]]
			var gap:float=float(r.config.speech_interval[0])*world.director.moods.interval(ids[i],"speech")*world.personality.speech_scale(ids[i])
			var speech_key:String="lively.pair."+world.intelligence.tag(ids[i])+"."+action
			if not Text.entries.has(speech_key):speech_key="lively."+action
			world.director.say_local(ids[i],Text.text(speech_key),"idle_pair",gap,float(world.director.moods.config.get("village_gap",14)))
			return
	# An unavailable opportunity is not a performed interaction. Retry boundedly.
	pair_due=time+float(config.pair_retry_seconds)
func apply(id:String,pose:Dictionary)->void:
	if not active.has(id) or not eligible(id):return
	var action:String=active[id].action;var phase:float=(time-float(active[id].start))/float(config.duration_seconds)
	if action in ["spin","hop","chase","surprise"]:pose.bob=-absf(sin(phase*TAU*2))*5;pose.lean=sin(phase*TAU)*.08
	elif action in ["stretch","dust","sweep","wood_tidy","wave","flower"]:pose.lean=sin(phase*TAU)*.08
	elif action in ["tree_nap","daydream","back_to_back"]:
		pose.scale.y*=.86
		if action=="back_to_back":pose.frame="seated_"+str(world.actors[id].facing);pose.fallback=str(world.actors[id].facing)+"_0"

func draw(view:Node2D,actor:Dictionary,p:Vector2)->void:
	var id:String=actor.id
	if not active.has(id) or not eligible(id):return
	var action:String=active[id].action
	if action=="flower":
		view.draw_texture_rect(view.textures.flowers,Rect2(p+Vector2(-10,-48)*view.zoom,Vector2(22,22)*view.zoom),false)
	elif action=="surprise":
		view.draw_string(view.font,p+Vector2(-5,-90)*view.zoom,"!",HORIZONTAL_ALIGNMENT_LEFT,-1,int(20*view.zoom),Color("fff1ba"))
	elif action=="cat_watch" and world.cat.discovered and world.cat.region==actor.region_id:
		var aim:Vector2=view.screen(world.cat.position)
		view.draw_arc(p+Vector2(0,-67)*view.zoom,8*view.zoom,0,PI,12,Color("fff1ba"),view.zoom)

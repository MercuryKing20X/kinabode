extends RefCounted

const Notes=preload("res://scripts/island_notes.gd")
const Shapes={"go_to":["target"],"follow":["target","seconds"],"wait":["seconds"],"say":["target","text"],"gesture":["kind"],"write_note":["target","place","text","en"],"pick_up":["item"],"put_down":["item"],"give":["target","item"],"use":["target"],"place":["item"],"build":["target"],"chop_and_haul":["target"],"place_piece":["item","position"],"remove_piece":["position"],"name_place":["position","label"],"eat_mushrooms":["target"],"write_diary":["label"],"set_project":["label"]}
const Roses=preload("res://scripts/island_note_rules.gd").ROSES
const Carry=preload("res://scripts/carry_retention.gd")
const WAYPOINTS=["moon.lookout","moon.camp","plaza.west","dock.west.entry"]
var owner:WeakRef
var request_build:Callable
var result:Dictionary={}
var completed:Callable
const ExtraShapes={"fish":[],"stock_fish":["fish_id","pen_id"],"play_at":["target"],"invite_play":["game","guests"],"paint_line":["item","position","end"],"remove_structure":["target"],"rebuild_camp":["target","position"]}
const NativeShapes={"native_wander":[],"native_own":["operation","target"],"native_field":["operation","target","crop"],"native_flower":["operation","color","text","pattern"],"native_light":["target"],"native_roast":["target","item","guests"],"native_invite":["target","guests"]}
var b:RefCounted:
	get:return owner.get_ref()

func _init(brain:RefCounted)->void:owner=weakref(brain)

func card()->Dictionary:
	var w:RefCounted=b.world
	var stock:Array=[]
	var notes:Array=[]
	var drops:Array=[]
	var actor:Dictionary=w.actors[b.id]
	for item in Roses:
		if w.storage.count(item)>0:stock.append(item)
	if actor.region_id=="home":
		for row in w.island_notes.rows.values():
			if row.recipient==b.id and w.point(actor).distance_to(w.point(row))<=20:notes.append(row.id)
	for row in w.drops.values():
		if row.region_id==actor.region_id and w.point(actor).distance_to(w.point(row))<=10:drops.append(row.id)
	var use_targets:Array=notes.slice(0,4)
	var places:Dictionary=w.island_notes.places() if actor.region_id=="home" else {}
	if places.has("campfire"):use_targets.append("home.barbecue")
	for site in w.leisure.sites.values():
		if site.get("complete",false) and site.region_id==actor.region_id and site.get("template_id")=="play-bench" and not w.standard.sites.has(site.id) and w.point(actor).distance_to(w.point(site))<=14:use_targets.append(site.id)
	for site in w.objects.values():
		if site.kind=="construction_site" and int(site.get("stage_index",0))>=5 and site.region_id==actor.region_id and w.point(actor).distance_to(w.point(site))<=10:use_targets.append(site.id)
	var shapes:=Shapes.duplicate(true)
	shapes.merge(ExtraShapes)
	var waypoints:Dictionary={}
	if actor.region_id=="home":
		for name in WAYPOINTS:
			var anchor:Array=w.map_anchor(name)
			if anchor.size()==2:waypoints[name]=anchor
	return {"steps":shapes,"places":places.keys(),"waypoints":waypoints,"use_targets":use_targets.slice(0,10),"ground_wood":drops.slice(0,4),"warehouse_roses":stock,"carry":actor.carry.duplicate(),"held_fish":w.fishing.held(b.id).get("id",""),"fisheries":w.fishing.pens.keys(),"drop_at":"doorstep"}

func travel(point:Vector2)->bool:
	if not point.is_finite() or not b.world.route_to(b.id,point):return false
	b.route=b.world._routes.get(b.id)
	return true

func accept(value:Dictionary,source:String,action_id:String="")->bool:
	var routine:RefCounted=b.world.director.routines[b.id]
	var eligible:bool=not routine.held and not routine.transporting() and not b.world.hunger.rushes.has(b.id) if source=="native" else b.eligible(true)
	if not b.active() or b.current.has("basic_plan") or not eligible or b.busy() or b.current.has("heart_guest") or b.current.has("ai_plan") or b.current.get("paired",false) or not b.intention.pending.is_empty():return b.intention.reject("basic_plan_busy")
	var prepared:=prepare(value,source)
	if prepared.has("error"):return b.intention.reject(prepared.error)
	var w:RefCounted=b.world
	var owned_route:bool=w._routes.has(b.id) and is_same(b.route,w._routes[b.id])
	if w._routes.has(b.id) and not owned_route:return b.intention.reject("basic_plan_busy")
	b.finish("interrupted","basic_plan")
	b.current={"action":"basic_plan","source":"local","basic_plan":{"reason":value.reason,"steps":prepared.steps},"index":0,"until":b.clock+120,"region":w.actors[b.id].region_id,"origin":source}
	b.current["action_id"]=action_id
	result={}
	b.trace({"event":"basic_plan_accepted","actor":b.id,"at":b.clock,"source":source,"plan":value.duplicate(true)})
	return true

func prepare(value:Dictionary,source:String)->Dictionary:
	if value.size()!=2 or not value.get("reason") is String or value.reason.strip_edges().is_empty() or value.reason.length()>160 or not value.get("steps") is Array or value.steps.is_empty() or value.steps.size()>6:return {"error":"invalid_basic_plan"}
	var expanded:Array=[]
	for index in value.steps.size():
		var step:Variant=value.steps[index]
		if not step is Dictionary or not step.get("action") is String or (not Shapes.has(step.action) and not ExtraShapes.has(step.action) and not (source=="native" and NativeShapes.has(step.action))):return {"error":"invalid_basic_step"}
		if step.action=="invite_play" and (source!="island_ai" or index!=value.steps.size()-1 or not b.world.play_invite.is_valid()):return {"error":"invalid_basic_step"}
		var fields:Array=Shapes.get(step.action,ExtraShapes.get(step.action,NativeShapes.get(step.action,[])))
		if step.keys().any(func(key):return key!="action" and key not in fields):return {"error":"invalid_basic_step"}
		if step.action=="invite_play" and step.get("game") not in ["hide","fireflies","circle","shuttlecock","rope"]:return {"error":"play_active_or_unknown"}
		for key in fields:
			if key=="seconds":
				if not Notes.number(step.get(key)) or step.seconds<1 or step.seconds>30:return {"error":"invalid_basic_wait"}
			elif key in ["position","end"]:
				if not b.world.flower_creation.point({"position":step.get(key)}).is_finite():return {"error":"invalid_position"}
			elif key=="guests":
				var guests:Variant=step.get(key)
				if not guests is Array or guests.size()>b.world.actors.size()-1:return {"error":"invalid_participant"}
				if step.action=="invite_play" and guests.size()<(3 if step.game=="rope" else 2):return {"error":"play_needs_available_friends"}
				var seen:Dictionary={}
				for guest in guests:
					if not guest is String or guest=="human" or (step.action=="invite_play" and guest==b.id) or not b.world.actors.has(guest) or seen.has(guest):return {"error":"invalid_participant"}
					seen[guest]=true
			elif key=="label":
				if not Notes.valid_text(step.get(key)):return {"error":"invalid_label"}
			elif not step.get(key) is String or step[key].length()>120:return {"error":"invalid_basic_argument"}
		if step.action=="paint_line":
			var line:=paint_steps(step)
			if line.is_empty():return {"error":"invalid_ground_line"}
			expanded.append_array(line)
		else:expanded.append(step.duplicate(true))
	if expanded.size()>24:return {"error":"invalid_basic_plan"}
	return {"steps":expanded}

func paint_steps(step:Dictionary)->Array:
	var catalog:Dictionary=preload("res://scripts/world_creations.gd").Catalog
	if step.item!="path" and not catalog.get(step.item,{}).get("ground",false):return []
	var start:Vector2=b.world.flower_creation.point(step)
	var end:Vector2=b.world.flower_creation.point({"position":step.end})
	var difference:=end-start
	if difference.length()>23 or (difference.x!=0 and difference.y!=0):return []
	var result:Array=[]
	var direction:=difference.sign()
	for i in int(difference.length())+1:
		var at:=start+direction*i
		result.append({"action":"place_piece","item":step.item,"position":[at.x,at.y]})
	return result

func receipt(error:String)->void:
	var c:Dictionary=b.current
	var step:Dictionary=c.basic_plan.steps[c.index]
	var row:Dictionary={"event":"basic_step","actor":b.id,"at":b.clock,"source":c.origin,"index":c.index,"action":step.action,"ok":error.is_empty(),"reason":error}
	b.trace(row)
	if not error.is_empty():
		result={"id":c.action_id,"status":"failed","step":c.index,"error":error}
		var refusal:Dictionary=b.world.flower_creation.creations.last_refusal.get(b.id,{})
		if step.action in ["place_piece","remove_piece","name_place"] and refusal.get("error")==error and refusal.has("message"):result["message"]=refusal.message
		if c.has("job_id") and b.world.work.jobs.get(b.id,{}).get("id")==c.job_id:b.world.work.stop(b.id,false)
		c["failed_step"]=true
		emit_receipt()
		b.intention.feedback(step.action,error);b.intention.changed()
		b.finish("failed",error);return
	c.index+=1;c.erase("at");c.erase("wait");c.erase("job_id");c.erase("job_result");c.erase("build_wait");c.erase("build_answer");c.erase("piece_arrival");c.erase("hand_over_started");c.erase("flower_job")
	if c.index>=c.basic_plan.steps.size():
		result={"id":c.action_id,"status":"completed","steps":c.index}
		emit_receipt()
		b.intention.changed();b.finish("completed")

func interrupted(reason:String)->void:
	var c:Dictionary=b.current
	if c.get("failed_step",false) or int(c.index)>=c.basic_plan.steps.size():return
	var action:String=c.basic_plan.steps[c.index].action
	var why:String=reason if not reason.is_empty() else "interrupted"
	result={"id":c.action_id,"status":"failed","step":c.index,"error":why}
	emit_receipt()
	if c.has("job_id") and b.world.work.jobs.get(b.id,{}).get("id")==c.job_id:b.world.work.stop(b.id,false)
	if c.has("hand_over_started") and is_same(c.hand_over_started,b.world.deliveries.pending.get(b.id)):
		b.world.deliveries.cancel(b.id)
	if c.has("flower_job") and is_same(c.flower_job,b.world.flower_creation.jobs.get(b.id)):
		b.world.flower_creation.cancel(b.id)
	b.trace({"event":"basic_step","actor":b.id,"at":b.clock,"source":c.origin,"index":c.index,"action":action,"ok":false,"reason":why})
	b.intention.feedback(action,why);b.intention.changed()

func emit_receipt()->void:
	if not completed.is_valid():return
	var callback:=completed
	completed=Callable()
	callback.call(result.duplicate(true))

func native_meal(step:Dictionary)->void:
	var w:RefCounted=b.world
	var c:Dictionary=b.current
	var id:String=b.id
	var station:String=str(step.target)
	if w._routes.has(id) and step.action!="native_invite":return
	if station.is_empty():station=str(c.get("meal_station",""))
	if station.is_empty():
		var nearest:float=INF
		for key in w.barbecues:
			var candidate:Dictionary=w.barbecues[key].station
			var distance:float=w.point(candidate).distance_squared_to(w.point(w.actors[id]))
			if candidate.region_id==w.actors[id].region_id and w.standard.ready(key) and distance<nearest:
				nearest=distance;station=key
	if not w.barbecues.has(station) or not w.standard.ready(station):receipt("unbuilt_camp");return
	var fire:RefCounted=w.barbecues[station].fireside
	if step.action!="native_invite" and not fire.near(id,float(fire.config.near_radius)):
		if c.get("native_meal_walk",-1)==c.index:receipt("unreachable");return
		for offset in [Vector2(0,3),Vector2(3,0),Vector2(-3,0),Vector2(0,-3)]:
			var point:Vector2=w.point(w.barbecues[station].station)+offset
			if w.barbecues[station].station.region_id==w.actors[id].region_id and w.walkable(w.actors[id].region_id,point) and travel(point):
				c.native_meal_walk=c.index
				return
		receipt("unreachable");return
	c.meal_station=station
	if step.action=="native_light":
		var light:Dictionary=fire.light_host(true,id)
		receipt("" if light.ok else str(light.get("error","no_fire")));return
	var current:Dictionary=fire.state.get("current",{})
	var guests:Array=step.guests.duplicate()
	if id not in guests:guests.push_front(id)
	guests=guests.filter(func(who):return not w.director.routines[who].held and not w.activities.blocked(who,false) and fire.can_invite([who]).ok)
	if step.action=="native_invite":
		if str(c.get("native_meal_id","")).is_empty() or c.native_meal_id!=current.get("id") or fire.state.get("roast_by")!=id:
			receipt("meal_changed")
		elif fire.waiting_meal() and current.get("direct_grill",false):
			var invited:Dictionary=fire.invite_direct(guests)
			receipt("" if invited.ok else str(invited.get("error","invitation_not_committed")))
		else:
			var returned:Array=guests.filter(func(who):return who in c.get("native_meal_guests",[]))
			receipt("" if returned.all(func(who):return who in fire.state.invited) else "invitation_not_committed")
		return
	if not fire.selected_guests.is_empty():receipt("fire_busy");return
	if fire.active() and not fire.circle_closed and not current.is_empty() and int(current.eaten)+int(current.wasted)<int(current.total):
		receipt("fire_busy");return
	var item:String=step.item
	var fish:Dictionary=w.fishing.held(id)
	if item.begins_with("fish:"):fish=w.fishing.fish.get(item.trim_prefix("fish:"),{})
	elif item=="fish" and fish.is_empty():fish=fire.cooking_fish(id)
	var direct:bool=item.begins_with("fish:") or item=="fish" or (item.is_empty() and not fish.is_empty())
	var outcome:Dictionary
	if direct:
		if not fire.direct_fish_available(fish,id):receipt("fish_not_owned");return
		outcome=fire.direct_grill(fish.id,id)
		if outcome.ok:
			guests=step.guests.duplicate()
			if id not in guests:guests.push_front(id)
			outcome=fire.invite_direct(guests.filter(func(who):return not w.director.routines[who].held and not w.activities.blocked(who,false) and fire.can_invite([who]).ok))
	else:
		if item.is_empty():item="single:mushroom"
		if not fire.menu(id).any(func(option):return option.id==item and int(option.maximum)>0):receipt("missing_food");return
		if guests.is_empty():receipt("no_diners");return
		if not fire.burning():
			outcome=fire.light_host(true,id)
			if not outcome.ok:receipt(str(outcome.get("error","no_fire")));return
		fire.selected_guests=guests
		outcome=fire.roast_host(item,id)
		fire.selected_guests.clear()
	if outcome.ok:
		c.native_meal_id=fire.state.current.id
		c.native_meal_guests=fire.state.invited.duplicate()
	receipt("" if outcome.ok else str(outcome.get("error","meal_unavailable")))

func native_own(step:Dictionary)->void:
	var w:RefCounted=b.world
	var c:Dictionary=b.current
	var id:String=b.id
	var command:Dictionary={"intent":step.operation}
	match step.operation:
		"home":
			var site:Dictionary=b.rhythm.own_house()
			if site.is_empty():receipt("unfinished_home");return
			if w.actors[id].region_id==w.interior.room_for(site.id):receipt("");return
			command={"intent":"enter","target_id":site.id}
		"gather":
			var target:String=step.target
			if target.is_empty():
				var nearest:=INF
				for patch in w.life.patches.values():
					var distance:float=w.point(patch).distance_squared_to(w.point(w.actors[id]))
					if patch.region_id==w.actors[id].region_id and int(patch.get("remaining",0))>0 and distance<nearest:
						nearest=distance;target=patch.id
			if target.is_empty():receipt("no_forage");return
			command={"intent":"forage","target_id":target}
		"pet_cat","hold_cat":
			if not w.cat.discovered or w.actors[id].region_id!=w.cat.region:receipt("cat_unavailable");return
			if w._routes.has(id):return
			if w.point(w.actors[id]).distance_to(w.cat.position)>3:
				var near:Vector2=w.nearest_walkable(w.cat.region,w.cat.position+Vector2(1,0))
				if not travel(near):receipt("cat_unreachable")
				return
			receipt("" if w.cat.interact(id,"hold" if step.operation=="hold_cat" else "pet") else "cat_unavailable");return
		"chess":
			var site:Dictionary=w.gomoku.table("play.gomoku" if str(step.target).is_empty() else step.target)
			if site.is_empty() or not site.complete or site.region_id!=w.actors[id].region_id:receipt("unfinished_facility");return
			var entry:Array=w.leisure.art(site).recreation.entry
			var at:Vector2=w.point(site)+Vector2(entry[0],entry[1])
			if w.point(w.actors[id]).distance_to(at)<.7:receipt("");return
			if travel(at):c.at=at
			else:receipt("unreachable")
			return
		"stars":
			b.executing=true
			var stars:Dictionary=w.resort.begin(w.resort.star_activity(),[id])
			b.executing=false
			if not stars.ok:receipt(str(stars.get("error",stars.get("rejected",{}).get(id,"stars_unavailable"))));return
			c.star_job=w.work.jobs[id].id;c.job_id=c.star_job;b.route=w._routes.get(id)
			return
		"follow","unfollow","stop","hand_over":pass
		_:receipt("unsupported_step");return
	if step.operation=="hand_over" and c.has("hand_over_started"):
		if not is_same(c.hand_over_started,w.deliveries.pending.get(id)):
			receipt("" if w.actors[id].carry.is_empty() else "delivery_interrupted")
		return
	b.executing=true
	var outcome:Dictionary=w.command(id,command)
	b.executing=false
	if not outcome.ok:receipt(str(outcome.get("error","action_unavailable")));return
	if step.operation=="hand_over":
		c.hand_over_started=w.deliveries.pending[id];b.route=w._routes.get(id);return
	if outcome.has("job_id"):c.job_id=outcome.job_id
	else:receipt("")

func native_field(step:Dictionary)->void:
	var w:RefCounted=b.world
	var id:String=b.id
	var operation:String=step.operation
	var exact:Dictionary=w.farms.plots.get(step.target,{})
	var farm_id:String=exact.get("farm_id",step.target)
	var candidates:Array=[exact] if not exact.is_empty() else w.farms.plots.values()
	for plot in candidates:
		if (not farm_id.is_empty() and plot.farm_id!=farm_id) or not w.farms.allowed(id,plot.farm_id):continue
		var crop:String=step.crop
		var args:Dictionary={"intent":operation,"target_id":plot.id}
		match operation:
			"plant":
				if w.farms.stage(plot)!="empty":continue
				if crop.is_empty():crop=w.farms._mixed_crop(plot.farm_id,plot,id)
				if crop.is_empty():continue
				args.crop_id=crop
			"water":
				if w.farms.stage(plot)!="dry":continue
			"harvest":
				if w.farms.stage(plot)!="mature":continue
			_:receipt("unsupported_step");return
		b.executing=true
		var outcome:Dictionary=w.command(id,args)
		b.executing=false
		if outcome.ok:b.current.job_id=outcome.job_id;return
		if not exact.is_empty():receipt(str(outcome.get("error","farm_unavailable")));return
	receipt("farm_unavailable")

func start_native_fishing()->void:
	var w:RefCounted=b.world
	var id:String=b.id
	var outcome:Dictionary=w.fishing.start(id)
	if not outcome.ok and outcome.error=="not_near_sea":
		outcome=w.fishing.invite_from_host_text([id],false,true)
	if outcome.ok:
		b.current.job_id=w.work.jobs[id].id;b.route=w._routes.get(id)
	else:receipt(str(outcome.get("error","unreachable_shore")))

func tick()->void:
	var w:RefCounted=b.world
	var c:Dictionary=b.current
	var id:String=b.id
	var actor:Dictionary=w.actors[id]
	var step:Dictionary=c.basic_plan.steps[c.index]
	if b.clock>=c.until:receipt("plan_timed_out");return
	if c.has("star_job") and w.work.jobs.get(id,{}).get("id")==c.star_job and w.resort.using(id)=="stars":
		c.erase("star_job");b.route=null;receipt("");return
	if c.has("job_id"):
		if w.work.jobs.get(id,{}).get("id")==c.job_id:return
		c.region=actor.region_id
		if step.action=="fish" and c.origin=="local" and c.get("job_result")=="completed":
			var caught:Dictionary=w.fishing.held(id)
			if not caught.is_empty():w.fishing.host_stock_nearest(caught.id)
		receipt("" if c.get("job_result")=="completed" else str(c.get("job_result","job_interrupted")));return
	if c.has("build_answer"):
		receipt(str(c.build_answer));return
	if c.has("build_wait"):return
	if c.has("hand_over_started"):
		native_own(step);return
	if c.has("flower_job"):
		if not is_same(c.flower_job,w.flower_creation.jobs.get(id)):
			b.route=null;receipt("" if c.flower_job.get("committed",false) else "arrangement_interrupted")
		return
	if c.has("meal_count"):
		if int(w.hunger.states.get(id,{}).get("meals",0))>int(c.meal_count):
			c.erase("meal_count");receipt("")
		return
	var bound_fire:RefCounted=null
	if step.action=="native_invite":
		var station:String=step.target if not str(step.target).is_empty() else str(c.get("meal_station",""))
		if w.barbecues.has(station):bound_fire=w.barbecues[station].fireside
		if bound_fire==null or not c.has("native_meal_id") or bound_fire.state.get("current",{}).get("id")!=c.native_meal_id:
			receipt("meal_changed");return
	var dining:bool=bound_fire!=null and bound_fire.state.get("current",{}).get("id")==c.get("native_meal_id","") and bound_fire.jobs.has(id) and bound_fire.jobs[id]==w.work.jobs.get(id,{}).get("id")
	if c.region!=actor.region_id or (w._routes.has(id) and not is_same(b.route,w._routes[id]) and not dining):receipt("route_or_context_changed");return
	if not w.fishing.held(id).is_empty() and step.action not in ["go_to","put_down","stock_fish","wait","say","native_light","native_roast","native_invite"]:receipt("holding_fish");return
	if b.busy() and not dining:receipt("busy");return
	if c.has("wait") and step.action!="follow":
		if b.clock>=c.wait:receipt("")
		return
	if c.has("at"):
		if not w._routes.has(id):receipt("" if w.point(actor).distance_to(c.at)<.7 else "route_interrupted")
		return
	match step.action:
		"native_wander":
			for offset in [Vector2(5,0),Vector2(0,5),Vector2(-5,0),Vector2(0,-5)]:
				var point:Vector2=w.point(actor)+offset
				if w.walkable(actor.region_id,point) and travel(point):c.at=point;return
			receipt("unreachable")
		"native_light","native_roast","native_invite":
			native_meal(step)
		"native_own":native_own(step)
		"native_field":native_field(step)
		"native_flower":
			var args:Dictionary={"intent":step.operation,"color":step.color}
			if not str(step.text).is_empty():args.text=step.text
			if not str(step.pattern).is_empty():args.pattern=step.pattern
			b.executing=true
			var outcome:Dictionary=w.command(id,args)
			b.executing=false
			if not outcome.ok:receipt(outcome.error);return
			c.flower_job=w.flower_creation.jobs[id];b.route=w._routes.get(id)
		"go_to":
			var point:Vector2=Vector2.INF
			if w.actors.has(step.target) and w.actors[step.target].region_id==actor.region_id:
				point=w.nearest_walkable(actor.region_id,w.point(w.actors[step.target])+Vector2(0,1))
			elif actor.region_id=="home":point=w.island_notes.places().get(step.target,Vector2.INF)
			if not point.is_finite() and actor.region_id=="home" and step.target in WAYPOINTS:
				var anchor:Array=w.map_anchor(step.target)
				if anchor.size()==2:point=w.nearest_walkable(actor.region_id,Vector2(anchor[0],anchor[1]))
			var note:Dictionary=w.island_notes.rows.get(step.target,{})
			if note.get("recipient")==id and actor.region_id=="home":point=w.point(note)
			var object:Dictionary=w.objects.get(step.target,w.drops.get(step.target,{}))
			if not object.is_empty() and object.region_id==actor.region_id:point=w.nearest_walkable(actor.region_id,w.point(object))
			if w.leisure.sites.has(step.target) and w.leisure.sites[step.target].region_id==actor.region_id:
				point=w.nearest_walkable(actor.region_id,w.point(w.leisure.sites[step.target])+Vector2(0,2))
			if not point.is_finite() or (w.point(actor).distance_to(point)>0.55 and not travel(point)):receipt("unreachable");return
			if not w._routes.has(id):receipt("");return
			b.route=w._routes[id];c.at=point
		"wait":c.wait=b.clock+float(step.seconds)
		"follow":
			var target:Dictionary=w.actors.get(step.target,{})
			if step.target==id or target.get("region_id")!=actor.region_id:receipt("different_region");return
			if not c.has("wait"):c.wait=b.clock+float(step.seconds)
			if b.clock>=c.wait:
				if w._routes.has(id) and is_same(b.route,w._routes[id]):w._routes.erase(id)
				receipt("");return
			if not w._routes.has(id) and w.point(actor).distance_to(w.point(target))>2.5:
				var near:Vector2=w.nearest_walkable(actor.region_id,w.point(target)+Vector2(0,1.5))
				if not travel(near):receipt("unreachable");return
		"gesture":
			var result:Dictionary=preload("res://scripts/game_actions.gd").gesture(w,id,{"intent":"gesture","gesture":step.kind})
			if result.ok:c.job_id=result.job_id
			else:receipt(result.error)
		"say":
			var near:bool=w.actors.has(step.target) and w.actors[step.target].region_id==actor.region_id and w.point(actor).distance_to(w.point(w.actors[step.target]))<=8
			var spoken:bool=false
			if near and Notes.valid_text(step.text):
				spoken=w.director.say_command(id,step.target,step.text) if c.origin in ["world_door","native_world","island_ai"] else w.director.say_local(id,step.text,"heart_social",12,8,step.target)
			receipt("" if spoken else "speech_unavailable")
		"write_note":
			var outcome: String = w.island_notes.write(id,step.target,step.place,step.text,step.get("en",""))
			if outcome.is_empty():
				w.flower_creation.creations.record(id,"note","",actor.region_id,w.island_notes.places()[step.place],c.basic_plan.reason)
			receipt(outcome)
		"write_diary":receipt(w.flower_creation.creations.write_diary(id,step.label,c.basic_plan.reason))
		"set_project":
			w.flower_creation.creations.projects[id]=step.label
			w.revision+=1
			receipt("")
		"pick_up":
			if w.drops.has(step.item):
				if w.point(actor).distance_to(w.point(w.drops[step.item]))>2:receipt("too_far");return
				var result:Dictionary=w.work.collect(id,step.item,true)
				if result.ok:c.job_id=result.job_id
				else:receipt(result.error)
				return
			if step.item not in Roses or w.work.carry_space(id)<1:receipt("pickup_not_allowed");return
			if not w.storage.take({step.item:1}).ok:receipt("insufficient_materials");return
			actor.carry[step.item]=int(actor.carry.get(step.item,0))+1
			Carry.mark(actor,step.item,1);w.revision+=1;receipt("")
		"chop_and_haul":
			var args:Dictionary={"intent":"gather_wood","tree_count":1}
			if not step.target.is_empty():args["target_id"]=step.target
			b.executing=true
			var work_result:Dictionary=w.command(id,args)
			b.executing=false
			if work_result.ok:c.job_id=work_result.job_id
			else:receipt(work_result.error)
		"stock_fish":
			var transfer:Dictionary=w.fishing.command(id,{"intent":"stock_fish","fish_id":step.fish_id,"pen_id":step.pen_id})
			receipt(str(transfer.get("error","")))
		"fish":
			if c.origin=="native":start_native_fishing();return
			if w._routes.has(id):return
			var result_fish:Dictionary=w.fishing.start(id)
			if result_fish.ok:c.job_id=result_fish.job_id;return
			if result_fish.error!="not_near_sea" or c.has("fishing_walk"):receipt(result_fish.error);return
			for shore in w.fishing.nearby_shores(id,4):
				if travel(w.point(shore)):
					c.fishing_walk=true
					return
			receipt("unreachable_shore")
		"play_at":
			var use_result:Dictionary=w.leisure.command(id,{"intent":"use_facility","target_id":step.target})
			if use_result.ok:c.job_id=use_result.job_id
			else:receipt(use_result.error)
		"invite_play":
			if not w.play_invite.is_valid():receipt("play_active_or_unknown");return
			# The stage owns its routes; keep its first move from replacing this receipt.
			b.executing=true
			var invitation:Dictionary=w.play_invite.call(id,step.game,step.guests)
			b.executing=false
			receipt("" if invitation.ok else str(invitation.error))
		"remove_structure":
			var layer:RefCounted=w.flower_creation.creations
			var issue:Dictionary=layer.structure_check(step.target)
			if not issue.is_empty():
				receipt(issue.error);return
			var site:Dictionary=w.barbecues[step.target].station if w.barbecues.has(step.target) else w.leisure.sites[step.target]
			var at:Vector2=w.point(site)
			if w._routes.has(id):return
			if w.point(actor).distance_to(at)>4:
				var destination:Vector2=w.nearest_walkable("home",at+Vector2(0,2))
				if c.has("piece_arrival") or not travel(destination):receipt("unreachable");return
				c.piece_arrival=b.clock+1.5
				return
			if not c.has("piece_arrival"):c.piece_arrival=b.clock+1.5;return
			if b.clock>=float(c.piece_arrival):receipt(layer.remove_structure(id,step.target,c.basic_plan.reason))
		"rebuild_camp":
			var error:String=w.flower_creation.creations.relocate_camp(id,step.target,step)
			if not error.is_empty():receipt(error);return
			var result:Dictionary=w.leisure.command(id,{"intent":"build_facility","target_id":w.standard.site_for(step.target)})
			if result.ok:c.job_id=result.job_id
			else:receipt(result.error)
		"place_piece","remove_piece","name_place":
			var p: Vector2 = w.flower_creation.point(step)
			if actor.region_id!="home" or not w.terrain_surface(actor.region_id,p):receipt("not_land");return
			if w._routes.has(id):return
			var creations:RefCounted=w.flower_creation.creations
			creations.last_refusal.erase(id)
			var issue:Dictionary=creations.check(id,step.action,step)
			if not issue.is_empty():
				creations.last_refusal[id]=issue;receipt(issue.error);return
			var solid:bool=step.action=="place_piece" and not creations.Catalog.get(step.get("item"),{}).get("walkable",true)
			if w.point(actor).distance_to(p)>2 or (solid and creations.box(p).has_point(w.point(actor))):
				if c.has("piece_arrival"):receipt("route_interrupted");return
				if solid or step.action!="place_piece":
					if not w._apply_route(id,creations.approach(id,p)):receipt("unreachable");return
					b.route=w._routes[id]
				else:
					var destination: Vector2 = w.nearest_walkable(actor.region_id,p)
					if not destination.is_finite() or destination.distance_to(p)>2 or not travel(destination):receipt("unreachable");return
				c.piece_arrival=b.clock+1.0
				return
			if not c.has("piece_arrival"):c.piece_arrival=b.clock+1.0;return
			if b.clock>=float(c.piece_arrival):
				receipt(w.flower_creation.creations.commit(id,step.action,step,c.basic_plan.reason))
		"put_down":receipt(w.island_notes.drop_gift(id,step.item))
		"place":receipt(w.flower_creation.place_carried(id,step.item))
		"build":
			var build_result:Dictionary=w.leisure.command(id,{"intent":"build_facility","target_id":step.target}) if w.leisure.sites.has(step.target) else w.work.start(id,"build",step.target)
			if build_result.ok:c.job_id=build_result.job_id
			else:receipt(build_result.error)
		"eat_mushrooms":
			if step.target not in w.barbecues or not w.standard.ready(step.target):receipt("camp_unavailable");return
			var station:Dictionary=w.barbecues[step.target].station
			if station.region_id!=actor.region_id:receipt("different_region");return
			if w._routes.has(id):return
			var fire:RefCounted=w.barbecues[step.target].fireside
			if not fire.near(id,4):
				var p:Vector2=w.nearest_walkable(actor.region_id,w.point(station)+Vector2(0,2))
				if c.has("meal_route") or not travel(p):receipt("unreachable");return
				c.meal_route=true
				return
			c.erase("meal_route")
			var meal_result:Dictionary=fire.self_mushrooms(id)
			if not meal_result.ok:receipt(meal_result.error);return
			c.meal_count=int(w.hunger.states.get(id,{}).get("meals",0))
		"give":
			var result:Dictionary=w.work.give(id,{"receiver_id":step.target,"item_id":step.item,"quantity":1},false)
			receipt("" if result.ok else result.error)
		"use":
			var note:Dictionary=w.island_notes.rows.get(step.target,{})
			if note.get("recipient")==id and actor.region_id=="home" and w.point(actor).distance_to(w.point(note))<=2:
				var unread:bool=not note.read
				w.island_notes.read_note(step.target,id)
				if unread and note.author in w.director.brains:
					var en:bool=TranslationServer.get_locale().begins_with("en")
					var line:Array={"gentle":["纸条我看见啦，我会记着。","I found your note. I'll remember it."],"lively":["收到！纸条我都看见啦！","Got it! I found your note!"],"quiet":["字条看见了。放心。","I saw your note. Don't worry."],"laborious":["纸条读过了，我放回原处啦。","I've read it and put it back where I found it."]}.get(b.tag(),["我读了你的纸条。","I've read your note."])
					w.director.say_local(id,line[1 if en else 0],"heart_social",12,8,note.author)
				b.trace({"event":"basic_note_read","actor":id,"at":b.clock,"note":note.id})
				receipt("")
			elif step.target=="rod":receipt("host_consent_required")
			elif w.barbecues.has(step.target) and w.standard.ready(step.target) and w.barbecues[step.target].fireside.near(id,4):
				w.hearts.react(id,"calm");receipt("")
			elif w.leisure.sites.has(step.target):
				var site:Dictionary=w.leisure.sites[step.target]
				if not site.get("complete",false) or site.region_id!=actor.region_id or site.template_id!="play-bench" or w.point(actor).distance_to(w.point(site))>4:receipt("object_unavailable");return
				var result:Dictionary=w.leisure.command(id,{"intent":"use_facility","target_id":site.id})
				if result.ok:c.job_id=result.job_id
				else:receipt(result.error)
			elif w.objects.has(step.target):
				var site:Dictionary=w.objects[step.target]
				if site.kind!="construction_site" or int(site.get("stage_index",0))<5 or site.region_id!=actor.region_id or w.point(actor).distance_to(w.interior.outside(w.interior.room_for(site.id)))>2:receipt("object_unavailable");return
				var result:Dictionary=w.interior.start(id,{"intent":"enter","target_id":site.id})
				if result.ok:c.job_id=result.job_id
				else:receipt(result.error)
			else:receipt("object_unavailable")

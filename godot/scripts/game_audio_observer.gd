extends RefCounted
## Session-only cursors over committed presentation facts. No World writes/commands.
const Meal=preload("res://scripts/meal_motion.gd")
const Layout=preload("res://scripts/home_layout.gd")
var audio_ref:WeakRef
var audio:Node:
	get:return audio_ref.get_ref()
var world:RefCounted:
	get:return audio.world_ref.get_ref()
var view:Node:
	get:return audio.view_ref.get_ref()
var visual_serial:=0
var dark_serial:=0
var positions:Dictionary={}
var steps:Dictionary={}
var bubbles:Dictionary={}
var speech_after:Dictionary={}
var heard_text:Dictionary={}
var panel_speaker:=""
var panel_until:=0.0
var hunger_after:Dictionary={}
var actor_phases:Dictionary={}
var meal_columns:Dictionary={}
var meal_finishes:Dictionary={}
var fires:Dictionary={}
var fish:Dictionary={}
var environment_after:=0.0
var gust_until:=0.0
var gust_started:=0.0
var next_gust:=0.0
var next_bird:=0.0
var last_step:=-1000.0
var coast_shapes:Array=[]
var watched:Dictionary={}
var connections:Dictionary={}
var disposed:=false
func _init(manager:Node)->void:
	audio_ref=weakref(manager);visual_serial=world.work.visual_serial
	var dark:RefCounted=world.get("dark")
	if dark!=null:dark_serial=int(dark.serial)
	for id in world.actors:
		positions[id]={"at":world.point(world.actors[id]),"region":world.actors[id].region_id};steps[id]=0.0
		actor_phases[id]=str(world.work.jobs.get(id,{}).get("phase",""));meal_finishes[id]=float(world.work.jobs.get(id,{}).get("meal_finished_at",-1))
		var tier:int=world.hunger.rank(id)
		if tier>0:hunger_after[id]=audio.clock+float(audio.tuning.hunger_intervals_seconds[tier-1])*audio.rng.randf()
	for id in world.barbecues:fires[id]=fire_snapshot(world.barbecues[id])
	for id in world.fishing.fish:fish[id]=world.fishing.fish[id].location
	if world.catalog.regions.has("home"):
		next_gust=audio.clock+audio.rng.randf_range(float(audio.tuning.get("wind",{}).get("interval_min",25)),float(audio.tuning.get("wind",{}).get("interval_max",60)))
		coast_shapes.append(Layout.points(world.catalog.regions.home.land))
		for polygon in world.catalog.regions.home.get("land_extensions",[]):coast_shapes.append(Layout.points(polygon))
	manager.get_tree().node_added.connect(watch_deferred)
	watch_deferred(manager.get_parent())
func watch_deferred(node:Node)->void:
	if not disposed and is_instance_valid(audio) and is_instance_valid(node) and node!=audio and not audio.is_ancestor_of(node):watch(node)
func watch(node:Node)->void:
	if disposed or not is_instance_valid(audio) or not is_instance_valid(node) or node==audio or audio.is_ancestor_of(node):return
	for child in node.get_children():watch(child)
	var relevant:bool=node is BaseButton or node is PopupMenu or node is Window or (node is Control and node.get_script()!=null and str(node.get_script().resource_path).ends_with("_panel.gd"))
	if not relevant or watched.has(node.get_instance_id()):return
	var instance_id:int=node.get_instance_id();watched[instance_id]=weakref(node)
	bind(node,"tree_exited",func():drop(instance_id))
	# Dialog titles/button text may be assigned by setup after node_added.
	# Resolve eligibility on the actual press, not during tree construction.
	if node is BaseButton:bind(node,"pressed",func():if is_instance_valid(audio) and primary_button(node):audio.play_event("ui.click"))
func primary_button(button:BaseButton)->bool:
	return bool(button.get_meta("audio_primary",false))
func closest_voice()->String:
	var ids:Array=view.speech_by_actor.keys();ids.sort();var chosen:="";var distance:=INF
	if audio.clock<panel_until and world.actors.has(panel_speaker):
		var actor:Dictionary=world.actors[panel_speaker]
		if actor.region_id==audio.region_id:
			chosen=panel_speaker;distance=world.point(actor).distance_to(audio.listener)
	for id in ids:
		if id=="human" or not world.actors.has(id):continue
		var actor:Dictionary=world.actors[id];var bubble:Dictionary=view.speech_by_actor[id]
		if actor.region_id!=audio.region_id or float(bubble.get("until",0))<=float(view.clock):continue
		if world.director.routines.has(id) and world.director.routines[id].held:continue
		var d:float=world.point(actor).distance_to(audio.listener)
		if d<distance:distance=d;chosen=id
	return chosen
func closest_eaters()->Array:
	var candidates:Array=[]
	for id in world.actors:
		var actor:Dictionary=world.actors[id]
		if actor.region_id==audio.region_id and world.work.jobs.get(id,{}).get("phase","")=="fire_eat":candidates.append({"id":id,"distance":world.point(actor).distance_to(audio.listener)})
	candidates.sort_custom(func(a,b):return a.id<b.id if is_equal_approx(a.distance,b.distance) else a.distance<b.distance)
	return candidates.slice(0,2).map(func(a):return a.id)
func fire_snapshot(life:RefCounted)->Dictionary:
	return {"remaining":float(life.fireside.state.get("remaining",0)),"burning":life.fireside.burning(),"invited":life.fireside.state.get("invited",[]).duplicate(),"fuel_used":int(life.station.fuel_used)}
func emit(id:String,actor_id:String)->void:
	if world.actors.has(actor_id):audio.play_event(id,world.point(world.actors[actor_id]),world.actors[actor_id].region_id,actor_id)
func advance(delta:float)->void:
	if disposed:return
	# Replay no old event ring after reload; visual serial is baselined in _init.
	for event in world.work.visual_events:
		if int(event.serial)<=visual_serial:continue
		visual_serial=int(event.serial)
		var id:String={"pickup":"work.pickup","deposit":"work.deposit","gomoku_stone":"gomoku.stone","hit":"tree.hit","fall":"wood.fall","fish_splash":"fishing.water","fish_bite":"fishing.bite","fish_caught":"fish.flap","fish_release":"fish.release"}.get(event.kind,"")
		if not id.is_empty():audio.play_event(id,Vector2(event.position[0],event.position[1]),event.region_id,event.actor_id)
	# Observe only committed dark actions; setup baselines the existing ring.
	var dark:RefCounted=world.get("dark")
	if dark!=null:
		for event in dark.events:
			if int(event.serial)<=dark_serial:continue
			dark_serial=int(event.serial)
			var sound:String={"torch_light":"torch.ignite","torch_plant":"torch.plant","torch_lift":"torch.lift","torch_warning":"torch.warning","small_fire":"dark.kindling","beacon":"dark.beacon"}.get(str(event.kind),"")
			if not sound.is_empty():audio.play_event(sound,Vector2(event.position[0],event.position[1]),"dark","human")
	var owner:String=closest_voice();var eaters:Array=closest_eaters()
	for i in range(audio.active.size()-1,-1,-1):
		var item:Dictionary=audio.active[i]
		if str(item.event).begins_with("voice.") and not str(item.key).begins_with("sound-test:") and item.actor!=owner:audio.recycle(item.player);audio.active.remove_at(i)
	for id in world.actors:actor_tick(id,delta,owner,eaters)
	for id in world.barbecues:
		var life:RefCounted=world.barbecues[id];var now:Dictionary=fire_snapshot(life);var old:Dictionary=fires.get(id,now)
		if now.fuel_used>old.fuel_used:audio.play_event("fire.refuel" if old.burning else "fire.ignite",world.point(life.station),life.station.region_id,"human")
		if now.invited.any(func(x):return x not in old.invited):audio.play_event("ui.invite")
		fires[id]=now
	var current_fish:Dictionary={}
	for id in world.fishing.fish:
		var f:Dictionary=world.fishing.fish[id];current_fish[id]=f.location
		if not fish.has(id) and f.location in ["pending","storage"]:audio.play_event("ui.fish_card")
		elif fish.get(id) in ["pending","storage"] and world.fishing.pens.has(f.location):
			var pen:Dictionary=world.fishing.pens[f.location];var rect:Array=pen.rect
			audio.play_event("fish.stock",Vector2(rect[0]+rect[2]/2.0,rect[1]+rect[3]/2.0),str(pen.get("region_id","home")),f.owner_id)
	fish=current_fish
	if audio.clock>=environment_after:environment_after=audio.clock+float(audio.tuning.environment_refresh_seconds);environment()
func actor_tick(id:String,delta:float,owner:String,eaters:Array)->void:
	var actor:Dictionary=world.actors[id];var at:Vector2=world.point(actor);var old:Dictionary=positions.get(id,{"at":at,"region":actor.region_id})
	var distance:float=at.distance_to(old.at) if old.region==actor.region_id else 0.0
	positions[id]={"at":at,"region":actor.region_id}
	# Teleport/load/region changes cannot create a burst of steps; real frame displacement only.
	if id=="human" and distance>0 and distance<=world.movement_speed(id)*delta+.05:
		steps[id]=float(steps.get(id,0))+distance
		var running:bool=distance/delta>float(world.SPEED)+.1;var spacing:float=float(audio.tuning.step_run_tiles if running else audio.tuning.step_walk_tiles)
		if float(steps[id])>=spacing:
			steps[id]=fmod(float(steps[id]),spacing)
			if audio.clock-last_step>=float(audio.tuning.step_global_gap_seconds) and audio.play_event("step."+surface(actor.region_id,at),at,actor.region_id,id,1,float(audio.tuning.run_step_gain) if running else 1.0):last_step=audio.clock
	elif distance<=0:steps[id]=0.0
	var job:Dictionary=world.work.jobs.get(id,{});var phase:String=str(job.get("phase",""));var old_phase:String=str(actor_phases.get(id,""))
	if phase!=old_phase:
		if phase=="fish_approach" and id!="human":audio.play_event("ui.invite")
		if phase=="fish_cast":emit("fishing.cast",id)
		if phase=="fish_reel":emit("fishing.reel",id)
		actor_phases[id]=phase
	if phase=="fire_eat":
		audio.duck_until=maxf(audio.duck_until,audio.clock+.2)
		var motion:Dictionary=Meal.timeline(world,id,job)
		var column:int=int(motion.get("column",0));var previous:int=int(meal_columns.get(id,-1))
		if column!=previous:
			if column in [2,3] and previous not in [2,3]:
				if id in eaters:emit("meal.bite",id)
				else:audio.drop_event("meal.bite","farther_eater",id)
			elif column in [4,5] and previous not in [4,5]:
				if id in eaters:emit("meal.chew",id)
				else:audio.drop_event("meal.chew","farther_eater",id)
		meal_columns[id]=column
	else:meal_columns.erase(id)
	var finished:float=float(job.get("meal_finished_at",-1))
	if finished>float(meal_finishes.get(id,-1)):emit("meal.satisfied",id)
	meal_finishes[id]=finished
	if id=="human":return
	var bubble:Dictionary=view.speech_by_actor.get(id,{})
	var signature:String=str(bubble.get("until",0))+":"+str(bubble.get("text",""))
	if signature!=str(bubbles.get(id,"")):
		bubbles[id]=signature
		if id!=owner and float(bubble.get("until",0))>float(view.clock):audio.drop_event(audio.voice(world,id).event,"farther_speaker",id)
		if float(bubble.get("until",0))>float(view.clock) and audio.speech_enabled and id==owner and audio.clock>=float(speech_after.get(id,-1000)) and world.point(actor).distance_to(audio.listener)<=float(audio.tuning.get("speech_near_tiles",12)) and str(bubble.get("text",""))!=str(heard_text.get(id,"")):
			# One accepted bubble is one soft sound. Suppressed bubbles never queue for later.
			var pack:Dictionary=audio.voice(world,id)
			speech_after[id]=audio.clock+float(audio.tuning.get("speech_gap_seconds",8));heard_text[id]=str(bubble.get("text",""))
			if not (world.director.routines.has(id) and world.director.routines[id].held):emit_voice(id,pack)
	var rank:int=world.hunger.rank(id)
	if rank>0:
		if not hunger_after.has(id):hunger_after[id]=audio.clock+float(audio.tuning.hunger_intervals_seconds[rank-1])
		if audio.clock>=float(hunger_after[id]):
			var head:Vector2=view.screen(world.point(actor))+Vector2(0,-60)*view.zoom
			if view.is_visible_in_tree() and actor.region_id==view.region_id and actor.region_id==audio.region_id and view.get_viewport_rect().has_point(head):view.hunger_symbols[id]=view.clock+1.2
			hunger_after[id]=audio.clock+float(audio.tuning.hunger_intervals_seconds[rank-1])
	else:hunger_after.erase(id)
func emit_voice(id:String,pack:Dictionary)->void:
	var actor:Dictionary=world.actors[id]
	if audio.play_event(pack.event,world.point(actor),actor.region_id,id,float(pack.pitch)):speech_after[id]=audio.clock+float(audio.tuning.get("speech_gap_seconds",8))
func panel_bubble(event:Dictionary)->bool:
	var id:String=str(event.get("actor_id",""))
	if not world.actors.has(id) or not audio.speech_enabled:return false
	var signature:String=str(event.get("id",""))+":"+str(event.get("key",""))
	if str(heard_text.get(id,""))==signature or audio.clock<float(speech_after.get(id,-1000)):return false
	# The same sound cooldown serves world and board bubbles, with no queued sound.
	heard_text[id]=signature;speech_after[id]=audio.clock+float(audio.tuning.get("speech_gap_seconds",8))
	var actor:Dictionary=world.actors[id]
	if actor.region_id!=audio.region_id or world.point(actor).distance_to(audio.listener)>float(audio.tuning.get("speech_near_tiles",12)):return false
	panel_speaker=id;panel_until=audio.clock+3.6
	if closest_voice()!=id:return false
	return audio.play_event(str(audio.voice(world,id).event),world.point(actor),actor.region_id,id,float(audio.voice(world,id).pitch),1,"chess-bubble:"+signature)
func surface(region:String,at:Vector2)->String:
	if region=="dark":
		var dark:RefCounted=world.get("dark")
		if dark!=null and at.distance_to(Vector2(dark.config.dock[0],dark.config.dock[1]))<4:return "wood"
		return "sand"
	if region!="home":return "wood"
	var layout:Dictionary=world.catalog.regions.home.layout
	for dock in layout.get("dock_surfaces",[]):
		if dock.id=="moon.platform" and not world.standard.ready("moon.lookout"):continue
		if Geometry2D.is_point_in_polygon(at,Layout.points(dock.polygon)):return "wood"
	for pond in layout.get("ponds",[]):
		if pond.has("crossing_anchor"):
			var p:Array=layout.anchors[pond.crossing_anchor];var size:=Vector2(pond.crossing_size[0],pond.crossing_size[1])
			if Rect2(Vector2(p[0],p[1])-size/2,size).has_point(at):return "wood"
	for cliff in layout.get("cliffs",[]):
		var stairs:Array=cliff.stairs
		if Rect2(Vector2(stairs[0][0],stairs[0][1]),Vector2(stairs[1][0]-stairs[0][0],stairs[1][1]-stairs[0][1])).has_point(at):return "wood"
	if world.moon!=null and world.standard.ready("moon.lookout") and world.moon.config.has("platform_surface") and Geometry2D.is_point_in_polygon(at,Layout.points(world.moon.config.platform_surface)):return "wood"
	# Reuse the topmost actual cached continuous material polygon, including road wear.
	if view.get("terrain")!=null:
		var commands:Array=view.terrain.commands
		for i in range(commands.size()-1,-1,-1):
			var command:Dictionary=commands[i]
			if command.kind!="surface" or not Geometry2D.is_point_in_polygon(at*32,command.shape):continue
			var material:String=command.material
			if material.begins_with("slab") or material=="stone":return "stone"
			if material.begins_with("grass"):return "grass"
			if material.begins_with("sand") or material.begins_with("soil"):return "sand"
	return "grass"
func coast_distance(at:Vector2)->float:
	var nearest:=10000.0
	for polygon in coast_shapes:
		for i in range(polygon.size()):nearest=minf(nearest,at.distance_to(Geometry2D.get_closest_point_to_segment(at,polygon[i],polygon[(i+1)%polygon.size()])))
	return nearest
func wind_gain(base:float,peak:float)->float:
	var config:Dictionary=audio.tuning.get("wind",{})
	if audio.clock>=next_gust:
		gust_started=audio.clock;gust_until=audio.clock+audio.rng.randf_range(float(config.get("duration_min",4)),float(config.get("duration_max",6)));next_gust=gust_started+audio.rng.randf_range(float(config.get("interval_min",25)),float(config.get("interval_max",60)))
		if world.scene_speech!=null and world.actors.human.region_id in ["home","dark"]:
			var h:Dictionary=world.actors.human
			world.scene_speech.emit_at("wind_dark" if h.region_id!="home" else "wind_south" if world.home_island.here() else "wind_home",h.region_id,world.point(h))
	if audio.clock>=gust_until:return base
	var p:float=(audio.clock-gust_started)/(gust_until-gust_started)
	return lerpf(base,peak,smoothstep(0.0,0.25,p)*(1.0-smoothstep(0.75,1.0,p)))
func environment()->void:
	for item in audio.active:
		if item.loop and not str(item.key).begins_with("sound-test:"):item.target=0.0
	if not view.is_visible_in_tree():return
	var home:bool=audio.region_id=="home";var moon:bool=home and world.moon!=null and world.moon.contains(audio.listener)
	var phase:String=world.days.phase().id;var rain:bool=world.weather.current().id=="rain"
	var dining:=false
	for id in world.barbecues:
		var life:RefCounted=world.barbecues[id];var at:Vector2=world.point(life.station);var nearby:bool=life.station.region_id==audio.region_id
		if nearby:
			audio.loop_event("fire:"+id,"ambience.fire",1.0 if life.fireside.burning() else 0.0,at,life.station.region_id)
			var food:Dictionary=life.fireside.state.get("current",{})
			audio.loop_event("sizzle:"+id,"ambience.sizzle",1.0 if life.fireside.burning() and not food.is_empty() and not food.get("ready",false) else 0.0,at,life.station.region_id)
		if life.fireside.jobs.has("human") and world.work.jobs.get("human",{}).get("phase") in ["fire_sit","fire_eat"]:dining=true
	if home:
		var wind:Dictionary=audio.tuning.get("wind",{})
		var gust:float=wind_gain(float(wind.get("home_base",.3)),float(wind.get("home_peak",.6)))
		var ocean:Dictionary=audio.catalog.events.get("ambience.waves",{})
		var distance:float=coast_distance(audio.listener)
		var near_ocean:bool=not ocean.is_empty() and distance<=float(ocean.near_tiles)
		if phase!="night" and audio.clock>=next_bird:
			var nature:Dictionary=audio.tuning.get("nature",{})
			next_bird=audio.clock+audio.rng.randf_range(float(nature.get("bird_interval_min",35)),float(nature.get("bird_interval_max",65)))
			audio.play_event("ambience.birds",Vector2.ZERO,"","",1,1,"birds")
		audio.loop_event("insects","ambience.insects",1.0 if phase=="night" else 0.0)
		if not near_ocean:
			audio.loop_event("rain","ambience.rain",1.0 if rain else 0.0)
			audio.loop_event("wind","ambience.wind",gust)
		if not ocean.is_empty():audio.loop_event("ocean","ambience.waves",(1-smoothstep(float(ocean.near_tiles),float(ocean.far_tiles),distance))*float(audio.tuning.moon_waves_gain if moon else audio.tuning.main_waves_gain))
		if near_ocean:
			audio.loop_event("rain","ambience.rain",1.0 if rain else 0.0)
			audio.loop_event("wind","ambience.wind",gust)
	if audio.region_id=="dark":
		# A region transition must never carry the main-island birds into the dark island.
		for i in range(audio.active.size()-1,-1,-1):
			if audio.active[i].event=="ambience.birds":audio.recycle(audio.active[i].player);audio.active.remove_at(i)
		var dark:RefCounted=world.get("dark")
		var levels:Dictionary=dark.config.get("audio",{}) if dark!=null else {}
		var gust_gain:float=wind_gain(float(levels.get("wind_gain",.22)),float(levels.get("wind_gust_gain",.4)))
		audio.loop_event("dark:wind","ambience.wind",gust_gain)
		audio.loop_event("dark:waves","ambience.waves",float(levels.get("waves_gain",.35)))
		audio.loop_event("dark:insects","ambience.insects",float(levels.get("insects_gain",.45)))
	var their:bool=home and world.home_island.contains(audio.listener)
	var music:String="fireside" if dining else "dark" if audio.region_id=="dark" else "their" if their else "moon" if moon else "rain" if rain else "night" if phase=="night" else "dusk" if phase=="dusk" else "day"
	audio.loop_event("music:"+music,"music."+music,0.0 if audio.music_preview_active else 1.0)
func bind(node:Node,signal_name:String,callback:Callable)->void:
	if disposed:return
	var id:int=node.get_instance_id()
	if not connections.has(id):connections[id]=[]
	node.connect(signal_name,callback);connections[id].append([signal_name,callback])
func drop(id:int)->void:
	var n:Node=watched[id].get_ref() if watched.has(id) else null
	for entry in connections.get(id,[]):
		if n!=null and n.is_connected(entry[0],entry[1]):n.disconnect(entry[0],entry[1])
	connections.erase(id);watched.erase(id)
func dispose()->void:
	if disposed:return
	disposed=true
	if is_instance_valid(audio) and audio.is_inside_tree() and audio.get_tree().node_added.is_connected(watch_deferred):audio.get_tree().node_added.disconnect(watch_deferred)
	for id in watched.keys():drop(id)

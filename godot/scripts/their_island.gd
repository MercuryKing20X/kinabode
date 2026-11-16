extends RefCounted
## A proposal never grants work. Only an exact host card acceptance grants one job.
const Text=preload("res://scripts/localization.gd")
var owner:WeakRef
var world:RefCounted:
	get:return owner.get_ref()
var pending:Dictionary={}
var grants:Dictionary={}
var running:Dictionary={}
var cooldown:Dictionary={}
var completed:Dictionary={}
var finished_lines:Dictionary={}
var serial:=0
var elapsed:=0.0
var selection:Dictionary={}
var config:Dictionary
func _init(w:RefCounted)->void:
	owner=weakref(w)
	config=JSON.parse_string(FileAccess.get_file_as_string("res://content/their-island.json"))
func eligible(id:String,model:bool=false)->bool:
	return world.director.routines.has(id) and world.director.routines[id].enabled and (not world.director.routines[id].held or model) and world.director.routines[id].time>=world.director.routines[id].visual_quiet_until and config.presets.has(id) and world.actors.has(id) and world.hunger.rank(id)<3 and not world.actors[id].has("furniture_id") and world.fishing.held(id).is_empty() and not world.work.jobs.has(id) and not world._routes.has(id) and not (world.deliveries!=null and world.deliveries.active(id)) and not world.projects.active(id) and not world.farms.active(id) and not world.homestead.active(id) and not world.shared_activity.holds(id) and not world.activities.members.has(id) and world.director.state(id).effective in (["idle","local_rules","following","conversation"] if model else ["idle","local_rules","following"])
func ready()->bool:
	return unlocked or world.opening_id=="showcase" or world.memories.records.filter(func(e):return e.kind=="shared_barbecue" and e.facts.get("version")==2 and "human" in e.participants and e.participants.any(func(id):return id in config.presets)).size()>=int(world.home_island.config.get("their_island",{}).get("meal_threshold",3))
func within(id:String,at:Vector2,template:String)->bool:
	var production:Dictionary={"produce-flowerhouse":{"owner":"codex","at":Vector2(33,226)},"produce-herbgarden":{"owner":"npc.mira","at":Vector2(105,226)},"produce-stargarden":{"owner":"npc.nora","at":Vector2(129,226)}}
	if production.has(template) and (id!=production[template].owner or at.distance_to(production[template].at)>.01):return false
	var work:Dictionary=world.library.artworks.get(template,{})
	if not preload("res://scripts/leisure_rules.gd").valid(work.get("recreation")):return false
	var size:=Vector2(work.recreation.width,work.recreation.depth)
	for corner in [at-size/2,at+size/2,at+Vector2(size.x,-size.y)/2,at+Vector2(-size.x,size.y)/2]:
		if world.home_island.territory_at(corner)!=id:return false
	return true
func propose(id:String,args:Dictionary,local:bool=false,authorized_plan:bool=false)->Dictionary:
	if authorized_plan and not world.director.model_controlled(id):return world._error("model_required")
	if not authorized_plan and world.resort!=null and world.resort.enabled():return world._error("vacation_activity_only")
	if not ready() or not eligible(id,not local or authorized_plan):return world._error("island_not_ready")
	if pending.has(id) or running.has(id):return world._error("island_proposal_pending")
	if world.forest.clock<float(cooldown.get(id,0)):return world._error("island_proposal_cooldown")
	if args.keys().any(func(k):return k not in ["intent","template_id","x","y","name","reason"]):return world._error("invalid_island_proposal")
	for key in ["name","reason"]:
		if not args.get(key) is String or args[key].strip_edges().is_empty() or args[key].length()>(40 if key=="name" else 128) or "\n" in args[key] or "\r" in args[key]:return world._error("invalid_island_text")
	for key in ["x","y"]:
		if not (args.get(key) is float or args.get(key) is int) or not is_finite(args[key]):return world._error("invalid_position")
	var template:String=str(args.get("template_id",""))
	if not config.templates.has(template):return world._error("unknown_template")
	var at:=Vector2(args.x,args.y)
	if not within(id,at,template):return world._error("outside_own_territory")
	# Conservative provenance: model reasons are exactly an offered true memory summary.
	if not local and args.reason not in memory_reasons(id):return world._error("unverified_island_memory")
	var validation:Dictionary=placement(template,at,id if authorized_plan else "")
	if not validation.ok:return validation
	serial+=1
	pending[id]={"id":"island-"+Crypto.new().generate_random_bytes(12).hex_encode(),"actor_id":id,"template_id":template,"position":[at.x,at.y],"name":args.name,"reason":args.reason,"local":local}
	if local:world.director.say_local(id,args.reason,"island_proposal",30,8)
	world.revision+=1
	return {"ok":true,"status":"proposed","proposal_id":pending[id].id}
func memory_reasons(id:String)->Array:
	var result:Array=[]
	for entry in world.memories.records:
		if id in entry.participants and "human" in entry.participants:
			var summary:Dictionary=world.memories._describe(entry)
			var text:String=str(summary.get("summary",""))
			if not text.is_empty() and text.length()<=128:result.append(text)
	return result.slice(-3)
func decide(id:String,card_id:String,decision:String,authorized_plan:bool=false)->Dictionary:
	if not pending.has(id) or pending[id].id!=card_id:return world._error("stale_island_card")
	if decision not in ["accept","later","change"]:return world._error("invalid_decision")
	if decision!="accept":
		if decision=="change":selection[id]=int(selection.get(id,0))+1
		pending.erase(id);cooldown[id]=world.forest.clock+(0 if decision=="change" else world.home_island.config.their_island.retry_seconds)
		return {"ok":true}
	if not eligible(id,authorized_plan):return world._error("busy_or_hungry")
	var p:Dictionary=pending[id]
	if p.has("activity_id"):
		var result:Dictionary=world.resort.begin(p.activity_id,["human",id])
		if result.ok:pending.erase(id);cooldown[id]=world.forest.clock+world.home_island.config.their_island.retry_seconds
		return result
	var at:=Vector2(p.position[0],p.position[1])
	if not within(id,at,p.template_id):return world._error("outside_own_territory")
	var validation:Dictionary=placement(p.template_id,at,id if authorized_plan else "")
	if not validation.ok:return validation
	var cost:int=preload("res://scripts/leisure_rules.gd").cost(world.library.artworks[p.template_id].recreation)
	if world.storage.count("wood")<cost:return world._error("insufficient_wood")
	var placed:Dictionary=world.leisure.place(p.template_id,at,id if authorized_plan else "")
	if not placed.ok:return placed
	world.activities.release_follow(id)
	grants[id]=placed.site_id
	var result:Dictionary=world.leisure.command(id,{"intent":"build_facility","target_id":placed.site_id})
	grants.erase(id)
	if not result.ok:
		world.leisure.sites.erase(placed.site_id);return result
	var paid:Dictionary=world.storage.take({"wood":cost})
	if not paid.ok:
		if world.work.jobs.get(id,{}).get("id")==result.job_id:world.work.stop(id,false)
		world.leisure.sites.erase(placed.site_id);return paid
	world.leisure.sites[placed.site_id].invested=cost
	world.leisure.sites[placed.site_id].name=p.name
	running[id]={"proposal":p.duplicate(true),"site_id":placed.site_id,"job_id":result.job_id}
	pending.erase(id)
	return result
func advance(delta:float)->void:
	if delta<=0 or world.library==null:return
	elapsed+=delta
	if elapsed<2:return
	elapsed=0
	if ready():unlocked=true
	for id in pending.keys():
		if not pending[id].local and not world.director.model_controlled(id):pending.erase(id);world.revision+=1
	for id in running.keys():
		if world.work.jobs.get(id,{}).get("id")!=running[id].job_id:running.erase(id)
	if not world.home_island.here() or not ready():return
	if world.resort!=null and world.resort.enabled():
		for id in config.presets:
			if not eligible(id) or pending.has(id) or not world.resort.vacation(id) or world.forest.clock<float(cooldown.get(id,0)):continue
			var choices:Array=world.resort.activities.values().filter(func(item):return item.kind in ["pool","lounge","swing","hammock"])
			choices.sort_custom(func(a,b):return world.point(a).distance_squared_to(world.point(world.actors[id]))<world.point(b).distance_squared_to(world.point(world.actors[id])))
			if choices.is_empty():continue
			var activity:Dictionary=choices[posmod(int(selection.get(id,0)),mini(3,choices.size()))]
			var english:bool=TranslationServer.get_locale().begins_with("en")
			var name:String=({"pool":preload("res://scripts/localization.gd").source("content.health_20261107.432ab927a039"),"lounge":preload("res://scripts/localization.gd").source("content.health_20261107.827725a4226f"),"swing":preload("res://scripts/localization.gd").source("content.health_20261107.07ada42bcdd1"),"hammock":preload("res://scripts/localization.gd").source("content.health_20261107.ac382de9d641")} if not english else {"pool":"Let us play in the pool","lounge":"Let us relax in the sun","swing":"Let us use the swings","hammock":"Let us rest in hammocks"}).get(activity.kind,"")
			pending[id]={"id":"vacation-"+Crypto.new().generate_random_bytes(12).hex_encode(),"actor_id":id,"activity_id":activity.id,"template_id":"play-swing","position":activity.position.duplicate(),"name":name,"reason":name,"local":true}
			world.revision+=1
		return

func clear_session()->void:
	pending.clear();grants.clear();running.clear();cooldown.clear();selection.clear();finished_lines.clear()

var unlocked:=false
var introduced:=false
var arrivals:Array=[]
var intro_actor:=""
var story_started:Dictionary={}
func saved()->Dictionary:return {"unlocked":unlocked,"introduced":introduced,"arrivals":arrivals.duplicate()}
func valid_saved(data:Variant)->bool:
	return data is Dictionary and data.size()==3 and data.get("unlocked") is bool and data.get("introduced") is bool and (not data.introduced or data.unlocked) and data.get("arrivals") is Array and data.arrivals.size()<=4 and data.arrivals.all(func(id):return id is String and config.presets.has(id) and data.arrivals.count(id)==1)
func restore(data:Dictionary)->void:
	clear_session();unlocked=bool(data.get("unlocked",false));introduced=bool(data.get("introduced",false));arrivals=data.get("arrivals",[]).duplicate();intro_actor="";story_started.clear()
func story_busy(r:RefCounted)->bool:
	var id:String=r.ID
	return not r.enabled or not r.chatter or r.held or r.time<r.visual_quiet_until or world.hunger.rank(id)>=2 or world.activities.blocked(id,false) or (world.deliveries!=null and world.deliveries.active(id)) or world.work.jobs.has(id) or world.projects.active(id) or world.farms.active(id) or world.homestead.active(id) or r.transporting() or not world.fishing.held(id).is_empty() or (world._routes.has(id) and not r.owns_route and not world.hunger.owned_routes.has(id))
func story_tick(_r:RefCounted,_delta:float)->bool:
	return false
func _retired_story_tick(r:RefCounted,delta:float)->bool:
	var id:String=r.ID
	if delta<=0 or not config.presets.has(id) or world.actors[id].region_id!="home":return false
	if world.actors.human.region_id!="home":
		if r.kind in ["island_intro","island_arrival"]:r.interrupt(8)
		return false
	var own_story:bool=r.kind in ["island_intro","island_arrival"]
	if story_busy(r):
		if intro_actor==id:intro_actor=""
		if own_story:r.interrupt(8)
		return false
	if not unlocked and world.opening_id!="showcase":return false
	var first:bool=world.home_island.here() and world.home_island.contains(world.point(world.actors[id])) and id not in arrivals
	var intro:bool=world.opening_id=="standard" and not introduced and not world.home_island.here()
	if not own_story:
		if world.forest.clock-float(story_started.get(id,-INF))<8:return false
		if not first and not intro:return false
		if intro:
			if intro_actor.is_empty():
				var nearest:="";var distance:=INF
				for who in config.presets:
					if not world.director.routines.has(who) or story_busy(world.director.routines[who]) or world.actors[who].region_id!="home":continue
					var d:float=world.point(world.actors[who]).distance_to(world.point(world.actors.human))
					if d<=12 and d<distance:nearest=who;distance=d
				intro_actor=nearest
			if id!=intro_actor:return false
		if world._routes.has(id) and not world.hunger.owned_routes.has(id):return false
		story_started[id]=world.forest.clock
		var following:bool=world.activities.following.has(id)
		if not following:world.hunger.clear_follow(id)
		r.interrupt(8)
		var destination:Vector2=world.point(world.actors.human)+Vector2(1.5,0)
		if first:
			for t in world.home_island.config.their_island.territories:
				if t.owner_id==id:
					for villa in world.resort.config.villas:
						if villa.owner_id==id:destination=Vector2(villa.gate[0],villa.gate[1])
		# A host-follow command owns its existing route. Story speech waits for
		# its natural arrival; only free residents take the original World route.
		if not following:
			world.activities.follow_issuing=true
			var moved:bool=r._move_to(destination)
			world.activities.follow_issuing=false
			if not moved:return false
		r.kind="island_arrival" if first else "island_intro";r.elapsed=0;r.duration=120;story_started[id]=world.forest.clock
		return true
	if world.forest.clock-float(story_started.get(id,world.forest.clock))>120:
		story_started[id]=world.forest.clock;r.interrupt(8);return false
	if world._routes.has(id):return true
	r.owns_route=false;r.elapsed+=delta
	if r.elapsed<.3:return true
	world.actors[id].facing="down";world.actors[id].activity="local_look"
	var key:String="theirs.arrival."+id if r.kind=="island_arrival" else "theirs.intro."+id
	if world.director.say_local(id,Text.text(key),r.kind,30,8):
		if r.kind=="island_arrival":
			if world.memories.record_event("island_arrival",id,["human",id],{"resident_id":id}):arrivals.append(id)
		else:introduced=true
		world.revision+=1;r.interrupt(8)
	return true

func placement(template:String,at:Vector2,authorized_owner:String="")->Dictionary:
	var result:Dictionary=world.leisure.validate_place(template,at,authorized_owner)
	if not result.ok:return result
	var cfg:Dictionary=world.library.artworks[template].recreation
	var area:=Rect2(at-Vector2(cfg.width,cfg.depth)/2,Vector2(cfg.width,cfg.depth)).grow(1)
	var corners:Array=[area.position,Vector2(area.end.x,area.position.y),area.end,Vector2(area.position.x,area.end.y)]
	for id in world._routes:
		if world.actors[id].region_id!="home":continue
		var previous:Vector2=world.point(world.actors[id])
		for next in world._routes[id]:
			if area.has_point(previous) or area.has_point(next):return world._error("route_occupied")
			for i in range(4):
				if Geometry2D.segment_intersects_segment(previous,next,corners[i],corners[(i+1)%4])!=null:return world._error("route_occupied")
			previous=next
	return {"ok":true}

func try_finish_speech(r:RefCounted)->bool:
	if not r.enabled or not r.chatter or r.held or r.time<r.visual_quiet_until or world.fishing.life.time<float(world.fishing.life.quiet_until.get(r.ID,0)):return false
	if not finished_lines.has(r.ID):return false
	var line:Dictionary=finished_lines[r.ID]
	if world.forest.clock>float(line.expires):finished_lines.erase(r.ID);return false
	if world.director.say_local(r.ID,Text.text("theirs.finished")%line.name,"island_finished",30,8):
		finished_lines.erase(r.ID);return true
	return false

func construction_completed(id:String,site_id:String)->void:
	var r:Dictionary=running.get(id,{})
	if r.is_empty() or r.site_id!=site_id or world.work.jobs.get(id,{}).get("id")!=r.job_id:return
	var site:Dictionary=world.leisure.sites.get(site_id,{})
	if not site.get("complete",false):return
	completed[site_id]={"actor_id":id,"name":r.proposal.name,"template_id":r.proposal.template_id}
	world.memories.record_event("island_build",site_id,["human",id],{"resident_id":id,"site_id":site_id,"name":r.proposal.name})
	finished_lines[id]={"name":r.proposal.name,"expires":world.forest.clock+90}
	running.erase(id);cooldown[id]=world.forest.clock+world.home_island.config.their_island.retry_seconds

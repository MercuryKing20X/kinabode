extends RefCounted
## Real warehouse roses. Routes belong exclusively to World; drafts never own items.
const ACTIONS=["place_flower","arrange_flowers","pick_flower","gift_flower","trade_flowers"]
const PALETTE={"red":"d84e67","white":"fff3dd","yellow":"f3c655","pink":"f49db5"}
var owner:WeakRef
var world:RefCounted:
	get:return owner.get_ref()
var config:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/flower-creation.json"))
var glyphs:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/flower-glyphs.json"))
var flowers:Dictionary={}
var jobs:Dictionary={}
var gifts:Dictionary={}
var first_received:=false
var serial:=0
var next_auto:=0.0
var creations: RefCounted
func _init(w:RefCounted)->void:
	owner=weakref(w)
	creations=preload("res://scripts/world_creations.gd").new(self)
func item(color:String)->String:return "rose_"+color
func active(id:String)->bool:return jobs.has(id)
func fail(reason:String)->Dictionary:
	var en:bool=TranslationServer.get_locale().begins_with("en")
	var messages:Dictionary={"very_hungry":["太饿了，先吃饱再摆花、送花吧。","I'm too hungry. Let's eat before arranging flowers."],"busy":["等我忙完再来摆花吧。","Let me finish what I'm doing first."],"insufficient_materials":["仓库里的材料不够。","There aren't enough materials in storage."],"blocked_position":["这里放不下，换一块空地吧。","There isn't room here. Try an open patch."],"daily_limit":["今天已经送过花啦。","I've already given you a flower today."]}
	return {"ok":false,"error":reason,"message":str(messages.get(reason,[reason,reason])[1 if en else 0])}
func preflight(id:String)->Dictionary:
	if not world.actors.has(id):return fail("unknown_resident")
	var r:RefCounted=world.director.routines.get(id)
	if active(id) or world.shared_activity.contains(id) or world.work.jobs.has(id) or world.farms.active(id) or world.projects.active(id) or world.homestead.active(id) or not world.fishing.held(id).is_empty() or world.activities.members.has(id) or world.activities.held.get(id,false) or (r!=null and r.held):return fail("busy")
	return {"ok":true}
func point(args:Dictionary)->Vector2:
	var pos:Variant=args.get("position",[args.get("x"),args.get("y")])
	if not pos is Array or pos.size()!=2 or not pos.all(func(n):return (n is float or n is int) and is_finite(n)):return Vector2(INF,INF)
	return Vector2(roundf(pos[0]),roundf(pos[1]))
func key(region:String,p:Vector2)->String:return region+":"+str(int(p.x))+":"+str(int(p.y))
func space(region:String,p:Vector2)->bool:
	if not is_finite(p.x) or not is_finite(p.y) or not world.walkable(region,p) or flowers.has(key(region,p)) or creations.pieces.has(key(region,p)):return false
	for job in jobs.values():
		if job.region==region and job.points.has(p):return false
	if region=="home":
		if world.Layout.near_road(world.catalog.regions.home.layout,p,.5):return false
		if world.resort!=null and world.resort.enabled():
			for bed in preload("res://scripts/resort_renderer.gd").BEDS:
				if bed.has_point(p):return false
		for farm in world.farms.farms.values():
			if world.farms.bounds(farm).grow(.5).has_point(p):return false
	for obj in world.objects.values():
		if obj.region_id!=region:continue
		if obj.kind=="construction_site" and Rect2(world.point(obj)-world.site_size(obj)/2,world.site_size(obj)).grow(.6).has_point(p):return false
		if obj.kind in ["tree","chest"] and world.point(obj).distance_to(p)<1.3:return false
	for site in world.leisure.sites.values():
		if site.region_id==region and world.point(site).distance_to(p)<2:return false
	return true
func pixels(args:Dictionary)->Array:
	var rows:Array=[];var text:String=str(args.get("text","")).to_upper()
	if not text.is_empty():
		if text.length()>6:return []
		for c in text:
			if not glyphs.font.has(c):return []
		for y in range(7):
			var row:String=""
			for c in text:row+=str(glyphs.font[c]).split("/")[y]+"0"
			rows.append(row)
	else:
		var pattern:String=str(args.get("pattern","single"))
		if not glyphs.patterns.has(pattern):return []
		rows=Array(str(glyphs.patterns[pattern]).split("/"))
	var result:Array=[]
	for y in range(rows.size()):
		for x in range(str(rows[y]).length()):
			if str(rows[y])[x]=="1":result.append(Vector2(x,y))
	return result
func execute(id:String,args:Dictionary)->Dictionary:
	var check:Dictionary=preflight(id)
	if not check.ok:return check
	if args.keys().any(func(k):return k not in ["intent","color","quantity","text","pattern","position","x","y","region_id"]):return fail("invalid_arguments")
	var action:String=str(args.get("intent",""));var color:String=str(args.get("color","red"))
	if action not in ACTIONS or color not in config.colors:return fail("invalid_flower")
	if action=="trade_flowers":
		var q:Variant=args.get("quantity",2)
		if not world._integer(q) or q<=0 or q>int(config.world_limit) or int(q)%int(config.roses_per_wood)!=0:return fail("invalid_quantity")
		var wood:int=int(q)/int(config.roses_per_wood)
		if id!="human":
			if not trade_authority.is_valid() or not trade_authority.call(id):return fail("host_authority_required")
			if world.storage.count("wood")-wood<int(config.manager_wood_floor):return fail("wood_floor")
		elif world.actors.human.region_id!="home" or world.point(world.actors.human).distance_to(Vector2(43,208))>5:return fail("too_far")
		if not world.storage.has({"wood":wood}):return fail("insufficient_materials")
		if world.storage.count(item(color))>9007199254740991-int(q):return fail("invalid_quantity")
		world.storage.take({"wood":wood});world.storage.add({item(color):int(q)});world.revision+=1
		return {"ok":true,"status":"completed","wood":wood,"quantity":int(q)}
	var region:String=str(args.get("region_id",world.actors[id].region_id));var p:Vector2=point(args)
	if (args.has("position") or args.has("x") or args.has("y")) and not p.is_finite():return fail("invalid_position")
	if region!=world.actors[id].region_id:return fail("different_region")
	if action=="gift_flower":
		return begin_gift(id,"human",color,false)
	if action=="pick_flower":
		if not flowers.has(key(region,p)):return fail("no_flower")
		return begin(id,{"action":action,"region":region,"points":[],"color":color,"target":p,"elapsed":0.0})
	if not args.has("pattern") and not args.has("text") and action=="arrange_flowers":
		args=args.duplicate(true)
		args["pattern"]={"lively":"heart","gentle":"ring","laborious":"row","quiet":"single"}.get(world.intelligence.tag(id),"heart")
		if world.intelligence.tag(id)=="gentle" and not args.has("color"):color="white"
	var offsets:Array=[Vector2.ZERO] if action=="place_flower" else pixels(args)
	if offsets.is_empty():return fail("invalid_pattern")
	var pending:int=0
	for j in jobs.values():pending+=j.points.size()
	if flowers.size()+pending+offsets.size()>int(config.world_limit):return fail("world_limit")
	if not p.is_finite() and id!="human" and world.intelligence.tag(id)=="quiet" and offsets.size()==1:
		var trees:Array=world.objects.values().filter(func(obj):return obj.kind=="tree" and obj.region_id==region and obj.status=="mature")
		trees.sort_custom(func(a,b):return world.point(a).distance_squared_to(world.point(world.actors[id]))<world.point(b).distance_squared_to(world.point(world.actors[id])))
		for tree in trees.slice(0,8):
			var at:Vector2=(world.point(tree)+Vector2(0,2)).round()
			if space(region,at):p=at;break
	if not is_finite(p.x):
		var origin:Vector2=world.point(world.actors[id]).round();var found:=false
		for radius in range(2,62,3):
			for x in range(-radius,radius+1,3):
				for y in [-radius,radius]:
					var at:Vector2=origin+Vector2(x,y)
					if offsets.all(func(offset):return space(region,at+offset)):
						p=at;found=true;break
				if found:break
			if found:break
		if not found:return fail("blocked_position")
	var points:Array=[]
	for offset in offsets:
		if not space(region,p+offset):return fail("blocked_position")
		points.append(p+offset)
	if not world.storage.has({item(color):points.size()}):return fail("insufficient_materials")
	if id=="human" and world.point(world.actors[id]).distance_to(p)>40:return fail("too_far")
	serial+=1
	return begin(id,{"action":action,"region":region,"points":points,"color":color,"target":points[0],"elapsed":0.0,"pattern_id":"arrangement-"+str(serial),"label":str(args.get("text",args.get("pattern","single")))})
var trade_authority:Callable
func begin_gift(id:String,recipient:String,color:String,heart_project:bool)->Dictionary:
	var check:Dictionary=preflight(id)
	if not check.ok:return check
	if id=="human" or id==recipient or not world.actors.has(recipient) or color not in config.colors:return fail("resident_only")
	if not heart_project and int(gifts.get(id,{}).get("day",0))==world.days.day() and int(gifts[id].count)>=int(config.gifts_per_day):return fail("daily_limit")
	if not world.storage.has({item(color):1}):return fail("insufficient_materials")
	var region:String=world.actors[id].region_id
	if world.actors[recipient].region_id!=region:return fail("different_region")
	var at:Vector2=world.nearest_walkable(region,world.point(world.actors[recipient])+Vector2(0,1.5))
	return begin(id,{"action":"gift_flower","region":region,"points":[],"color":color,"target":at,"elapsed":0.0,"offered":false,"recipient":recipient,"heart_project":heart_project})
func begin(id:String,job:Dictionary)->Dictionary:
	if not world.route_to(id,job.target):return fail("unreachable")
	if job.action=="gift_flower":
		if not world.storage.take({item(job.color):1}).ok:
			world._routes.erase(id);return fail("insufficient_materials")
		job.offered=true
	job["route"]=world._routes.get(id);job["age"]=0.0;job["returning"]=false
	jobs[id]=job
	return {"ok":true,"status":"accepted"}
func cancel(id:String)->void:
	if not jobs.has(id):return
	var job:Dictionary=jobs[id]
	if job.get("offered",false):world.storage.add({item(job.color):1})
	if is_same(world._routes.get(id),job.get("route")):world._routes.erase(id)
	jobs.erase(id);world.actors[id].activity="idle"
func pick(k:String)->void:
	var f:Dictionary=flowers[k]
	if not world.storage.add({item(f.color):1}):return
	flowers.erase(k);world.revision+=1
func place_carried(id:String,item_id:String)->String:
	var actor:Dictionary=world.actors[id]
	var check:Dictionary=preflight(id)
	if not check.ok:return check.error
	var color:String=item_id.trim_prefix("rose_")
	var p:Vector2=world.point(actor).round()+Vector2(0,1)
	if item(color)!=item_id or color not in config.colors or int(actor.carry.get(item_id,0))<1:return "insufficient_owned_items"
	if flowers.size()>=int(config.world_limit) or not space(actor.region_id,p):return "blocked_position"
	preload("res://scripts/carry_retention.gd").consume(actor,item_id,1)
	actor.carry[item_id]=int(actor.carry.get(item_id,0))-1
	if actor.carry[item_id]==0:actor.carry.erase(item_id)
	serial+=1
	flowers[key(actor.region_id,p)]={"position":[int(p.x),int(p.y)],"region_id":actor.region_id,"color":color,"actor_id":id,"pattern_id":"arrangement-"+str(serial),"label":"single"}
	world.revision+=1
	return ""
func finish(id:String)->void:
	var job:Dictionary=jobs[id]
	if id!="human" and world.actors.human.region_id==job.region and world.route_to(id,world.nearest_walkable(job.region,world.point(world.actors.human)+Vector2(1.5,0))):
		job.returning=true;job.route=world._routes.get(id);return
	jobs.erase(id)
func advance(delta:float)->void:
	for id in jobs.keys():
		var job:Dictionary=jobs[id];job.age+=delta
		var r:RefCounted=world.director.routines.get(id)
		if world.work.jobs.has(id) or world.farms.active(id) or world.projects.active(id) or world.activities.blocked(id,false) or job.age>float(config.timeout_seconds) or world.actors[id].region_id!=job.region or (r!=null and r.held):cancel(id);continue
		if world._routes.has(id):
			if not is_same(job.route,world._routes[id]):cancel(id)
			continue
		if job.returning:jobs.erase(id);continue
		if world.point(world.actors[id]).distance_to(job.target)>.65:cancel(id);continue
		job.elapsed+=delta
		if job.action=="gift_flower":
			var recipient:String=job.get("recipient","human")
			if world.actors[recipient].region_id!=job.region or world.point(world.actors[recipient]).distance_to(world.point(world.actors[id]))>2.8:cancel(id);continue
			world.actors[id].activity="local_offer_flower"
			if job.elapsed<1.5:continue
			# The rose is received into the shared warehouse, never destroyed or copied.
			world.storage.add({item(job.color):1});job.offered=false
			var count:int=int(gifts.get(id,{}).get("count",0)) if int(gifts.get(id,{}).get("day",0))==world.days.day() else 0
			gifts[id]={"day":world.days.day(),"count":count+1}
			record(id,"gift_flower",job.color,not first_received and recipient=="human")
			if recipient=="human":first_received=true
			job["committed"]=true
			var line:String="这朵玫瑰送给你。" if not TranslationServer.get_locale().begins_with("en") else "This rose is for you."
			world.director.say_local(id,line,"flower_creation",30,14)
			finish(id);continue
		if job.action=="pick_flower":
			var k:String=key(job.region,job.target)
			if flowers.has(k):pick(k)
			finish(id);continue
		if job.elapsed<float(config.step_seconds):continue
		job.elapsed=0
		var p:Vector2=job.points.pop_front()
		# Remove the reservation for this cell before checking live geometry again.
		if not space(job.region,p) or not world.storage.take({item(job.color):1}).ok:cancel(id);continue
		flowers[key(job.region,p)]={"position":[int(p.x),int(p.y)],"region_id":job.region,"color":job.color,"actor_id":id,"pattern_id":job.pattern_id,"label":job.label}
		world.revision+=1
		if job.points.is_empty():job["committed"]=true;record(id,"flower_arrangement",job.label,false);finish(id)
		else:
			job.target=job.points[0]
			if not world.route_to(id,job.target):cancel(id)
			else:job.route=world._routes.get(id)
	if world.forest.clock>=next_auto:
		next_auto=world.forest.clock+30
		for id in world.director.routines:
			var r:RefCounted=world.director.routines[id]
			if world.director.brains.has(id) and world.director.brains[id].current.has("basic_plan"):continue
			if r.blocked() or not r.enabled or r.held or r.time<r.visual_quiet_until or world.director.model_controlled(id) or world._routes.has(id) or world.point(world.actors[id]).distance_to(world.point(world.actors.human))>6:continue
			if int(gifts.get(id,{}).get("day",0))==world.days.day() or not preflight(id).ok:continue
			for color in config.colors:
				if world.storage.count(item(color))>0:
					world.command(id,{"intent":"gift_flower","color":color});break
func record(id:String,kind:String,label:String,first:bool)->void:
	var job:Dictionary=jobs.get(id,{})
	if world.get("hearts")!=null:
		world.hearts.change(id,{"joy":10,"safe":8},"shared")
	var book:RefCounted=world.memories.notebook
	if book==null:return
	var event:String="flowers:%s:%s:%s"%[id,world.days.day(),world.revision]
	var zh:String="收到她送来的一朵%s玫瑰。"%label if kind=="gift_flower" else "摆好了玫瑰图案：%s。"%label
	var en:String="Received her %s rose."%label if kind=="gift_flower" else "Arranged roses: %s."%label
	book.add(id,world.world_id,event,"facts","memory.localized_fact",{"localized":{"zh":zh,"en":en},"legacy":{"kind":kind,"actor_id":id,"color":label,"first":first}},world.days.day(),"game",[id,job.get("recipient","human")] if kind=="gift_flower" else [id],world.forest.clock)
func summary(id:String)->Dictionary:
	var roses:Dictionary={}
	for color in config.colors:roses[color]=world.storage.count(item(color))
	var near:Array=[];var region:String=world.actors[id].region_id;var origin:Vector2=world.point(world.actors[id])
	for x in range(-12,13,4):
		for y in range(-12,13,4):
			var p:Vector2=(origin+Vector2(x,y)).round()
			if space(region,p):near.append({"position":[p.x,p.y],"region_id":region})
	return {"roses":roses,"candidates":near.slice(0,12),"arrangements":flowers.values().filter(func(f):return f.actor_id==id).slice(-24).duplicate(true),"patterns":glyphs.patterns.keys(),"text_max":6,"remaining":int(config.world_limit)-flowers.size()}
func saved()->Dictionary:
	# In-flight offerings return to warehouse in the encoded snapshot only.
	return {"version":1,"flowers":flowers.duplicate(true),"gifts":gifts.duplicate(true),"serial":serial,"first_received":first_received}
func valid_saved(v:Variant,actors:Dictionary)->bool:
	if not v is Dictionary or v.get("version")!=1 or not v.get("flowers") is Dictionary or v.flowers.size()>int(config.world_limit) or not v.get("gifts") is Dictionary or not world._integer(v.get("serial")) or v.serial<0 or not v.get("first_received") is bool:return false
	for k in v.flowers:
		var f:Variant=v.flowers[k]
		if not f is Dictionary or f.get("color") not in config.colors or not actors.has(f.get("actor_id","")) or not world.catalog._pair(f.get("position")) or not f.get("pattern_id") is String or not f.get("label") is String or f.label.length()>32 or not world.catalog.regions.has(f.get("region_id","")):return false
		var p:Vector2=Vector2(f.position[0],f.position[1])
		if p!=p.round() or k!=key(f.region_id,p):return false
	for id in v.gifts:
		var g:Variant=v.gifts[id]
		if not actors.has(id) or not g is Dictionary or not world._integer(g.get("day")) or g.day<1 or not world._integer(g.get("count")) or g.count<0 or g.count>int(config.gifts_per_day):return false
	return true
func restore(v:Dictionary)->void:
	for id in jobs.keys():cancel(id)
	flowers=v.get("flowers",{}).duplicate(true);gifts=v.get("gifts",{}).duplicate(true);serial=int(v.get("serial",0));first_received=bool(v.get("first_received",false))

# Explicit host-only group placement: one design, disjoint real cells, one debit
# per arrival. This helper is intentionally absent from the model action contract.
func arrange_group(ids:Array,args:Dictionary)->Dictionary:
	var eligible:Array=ids.filter(func(id):return id is String and id!="human" and preflight(id).ok)
	if eligible.is_empty():return fail("busy")
	var result:Dictionary=world.host_command(eligible[0],args)
	if not result.get("ok",false) or not jobs.has(eligible[0]):return result
	var first:Dictionary=jobs[eligible[0]]
	var cells:Array=first.points.duplicate()
	var groups:Array=[]
	for i in range(mini(eligible.size(),cells.size())):groups.append([])
	for i in range(cells.size()):groups[i%groups.size()].append(cells[i])
	first.points=groups[0]
	for i in range(1,groups.size()):
		var who:String=eligible[i]
		var job:Dictionary=first.duplicate(true);job.points=groups[i];job.target=groups[i][0]
		var started:Dictionary=world.director.brains[who].mandate("command","arrange_flowers",func():return begin(who,job))
		if not started.get("ok",false):first.points.append_array(groups[i])
	return result

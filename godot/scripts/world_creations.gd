extends RefCounted

static var Catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/world-pieces.json"))
const LIMIT := 800
const CHANGE_LIMIT := 200
var flowers_ref: WeakRef
var flowers: RefCounted:
	get: return flowers_ref.get_ref()
var pieces := {}
var solids:Dictionary={}
var pending_reactions:Dictionary={}
var last_refusal:Dictionary={}
const RemovalLines={
	"gentle":[["已经拆掉啦？那片空地也很好看。","Oh, it's gone. I rather like the space it left."],["我摆的那件不在了。下回一起挑地方吧。","The piece I put there is gone. Shall we choose a spot together next time?"],["这样也好，路边宽敞多啦。","A little more breathing room by the path. That's nice, too."]],
	"lively":[["咦，你把我那件拆啦！这下能换个摆法了。","You took mine down! Ooh, now we can try a different layout."],["少了一件！我刚刚还以为自己走错了。","One piece missing! For a second I thought I was on the wrong path."],["这里腾出来啦！让我想想还能摆什么。","Look at all that room! What could go there next?"]],
	"quiet":[["拆了啊。我看见了。","You took it down. I noticed."],["留空也行。","We can leave it empty."],["嗯，那里清出来了。","Right. That spot's clear now."]],
	"laborious":[["拆下来的料回仓就好，还能再用。","Good, the reclaimed wood can go back into stock."],["少了那件，正好把这块地理一理。","With that piece out, we can tidy this patch."],["我摆的那件拆了？行，腾出地方就有用。","My piece came down? Fair enough. We've gained some room."]]
}
var changes := []
var summaries := {}
var projects := {}
var diary_writer: Callable
var sequence := 0
var seen := 0
signal removed(owner: String, change: Dictionary)

func _init(owner: RefCounted) -> void:
	flowers_ref = weakref(owner)

func catalog() -> Dictionary:
	var result := Catalog.duplicate(true)
	for id in result:
		result[id].erase("texture")
	return result

static func phrase(zh:String,en:String)->String:
	return en if TranslationServer.get_locale().begins_with("en") else zh

func blocked(region:String,p:Vector2)->bool:
	return region=="home" and not solids.is_empty() and solids.has(Vector2i((p+Vector2(.5,.5)).floor()))

func tick_reactions()->void:
	if pending_reactions.is_empty():return
	var w:RefCounted=flowers.world
	for id in pending_reactions.keys():
		var pending:Dictionary=pending_reactions[id]
		if w.forest.clock>pending.until or w.director.model_controlled(id) or w.actors[id].has("world_door_client"):
			pending_reactions.erase(id);continue
		var lines:Array=RemovalLines.get(w.intelligence.tag(id),RemovalLines.gentle)
		var pair:Array=lines[int(pending.serial)%lines.size()]
		if w.director.say_local(id,phrase(pair[0],pair[1]),"piece_removed",12,8):pending_reactions.erase(id)

func box(p:Vector2)->Rect2:
	return Rect2(p-Vector2(.5,.5),Vector2.ONE)

func crosses(area:Rect2,start:Vector2,finish:Vector2)->bool:
	if not area.intersects(Rect2(start,Vector2.ZERO).expand(finish).grow(.0001)):return false
	if area.has_point(start) or area.has_point(finish):return true
	var corners:Array[Vector2]=[area.position,Vector2(area.end.x,area.position.y),area.end,Vector2(area.position.x,area.end.y)]
	for i in 4:
		if Geometry2D.segment_intersects_segment(start,finish,corners[i],corners[(i+1)%4])!=null:return true
	return false

func route_crosses(area:Rect2,start:Vector2,route:Array)->bool:
	for finish:Vector2 in route:
		if crosses(area,start,finish):return true
		start=finish
	return false

func mark_grid(region:String,grid:AStarGrid2D)->void:
	if region!="home":return
	for slot:Vector2i in solids:
		var cell:=slot-Vector2i.ONE
		if grid.region.has_point(cell):grid.set_point_solid(cell,true)

func key_points()->Dictionary:
	var w:RefCounted=flowers.world
	var result:Dictionary={}
	var storage:Dictionary=w.objects.get("home.storage",{})
	if not storage.is_empty():result[phrase("仓库","Warehouse")]=w.point(storage)
	elif w.catalog.regions.home.get("layout",{}).get("anchors",{}).has("logging.entry"):
		var entry:Array=w.map_anchor("logging.entry")
		result[phrase("仓库","Warehouse")]=Vector2(entry[0],entry[1])
	for site in w.objects.values():
		if site.kind=="construction_site" and site.region_id=="home" and int(site.get("stage_index",0))==5:
			var door:Vector2=w.interior.outside(w.interior.room_for(site.id))
			result[phrase("%s门口","%s door")%preload("res://scripts/localization.gd").resident(w,site.get("owner_id","human"))]=door
	for fire in w.barbecues.values():
		if fire.station.region_id=="home" and w.standard.ready(fire.station.id):
			result[phrase("月牙岛营火","Crescent campfire") if fire.station.id=="moon.barbecue" else phrase("主岛营火","Main island campfire")]=w.point(fire.station)
	var anchors:Dictionary={
		"dock.south.entry":phrase("南码头入口","South pier entrance"),
		"dock.south.end":phrase("南码头尽头","South pier end"),
		"dock.west.entry":phrase("西码头入口","West pier entrance"),
		"dock.west.end":phrase("西码头尽头","West pier end"),
		"moon.bridge.east":phrase("桥东端","East bridge end"),
		"moon.bridge.west":phrase("桥西端","West bridge end"),
		"moon.lookout":phrase("月牙岛观景台","Crescent lookout")}
	var w_layout:Dictionary=w.catalog.regions.home.get("layout",{})
	for key in anchors:
		if w_layout.get("anchors",{}).has(key):
			var p:Array=w.map_anchor(key)
			if p.size()==2:result[anchors[key]]=Vector2(p[0],p[1])
	return result

func rejection(first:String,second:String)->Dictionary:
	return {"error":"blocks_access","message":phrase("会堵住「%s」到「%s」的路。","This would block the way from %s to %s.")%[first,second]}

func protection(p:Vector2)->Dictionary:
	var points:=key_points()
	var names:=points.keys()
	for name in names:
		if box(p).has_point(points[name]):
			var other:String=phrase("岛上道路","the island paths")
			for available in names:
				if available!=name:other=available;break
			return rejection(other,name)
	return {}

func structure_check(target:String)->Dictionary:
	var w:RefCounted=flowers.world
	if w.barbecues.has(target):
		var camp:RefCounted=w.barbecues[target]
		if w.standard.site_for(target).is_empty() or camp.station.region_id!="home":return {"error":"protected_structure"}
		if not w.standard.ready(target):return {"error":"structure_missing"}
		if camp.fireside.active() or not camp.fireside.jobs.is_empty():return {"error":"structure_in_use"}
		if not w.barbecues.keys().any(func(other):return other!=target and w.barbecues[other].station.region_id=="home" and w.standard.ready(other) and not w.route_between("home",w.nearest_walkable("home",w.point(camp.station)),w.nearest_walkable("home",w.point(w.barbecues[other].station))).is_empty()):
			return {"error":"last_camp"}
		return {}
	var site:Dictionary=w.leisure.sites.get(target,{})
	if site.is_empty():return {"error":"protected_structure"}
	if not site.complete:return {"error":"structure_missing"}
	if w.standard.sites.has(target) or w.leisure.art(site).get("recreation",{}).get("game","")!="":
		return {"error":"dependent_facility"}
	for job in w.work.jobs.values():
		if job.get("target_id")==target:return {"error":"structure_in_use"}
	return {}

func remove_structure(id:String,target:String,reason:String)->String:
	var problem:=structure_check(target)
	if not problem.is_empty():return problem.error
	var w:RefCounted=flowers.world
	if w.barbecues.has(target):
		var station:Dictionary=w.barbecues[target].station
		if w.actors[id].region_id!="home" or w.point(w.actors[id]).distance_to(w.point(station))>4:return "too_far"
		w.standard.install_sites(w.library)
		var plan:Dictionary=w.leisure.sites[w.standard.site_for(target)]
		var refund:=floori(float(plan.invested)/2)
		if refund>0 and not w.storage.add({"wood":refund}):return "storage_full"
		plan.world_camp_rebuild=true
		plan.complete=false
		plan.invested=0
		plan.position=station.position.duplicate()
		var name:String=preload("res://scripts/localization.gd").content(station.get("name",phrase("营火","Campfire")))
		record(id,"structure_removed",target,"home",w.point(station),reason,name)
		return ""
	var site:Dictionary=w.leisure.sites[target]
	if w.actors[id].region_id!="home" or w.point(w.actors[id]).distance_to(w.point(site))>4:return "too_far"
	# Removing Leisure geometry opens paths; the plot and original template stay.
	# Opening presets carry no paid receipt and therefore grant no material.
	var refund:=floori(float(site.invested)/2)
	if refund>0 and not w.storage.add({"wood":refund}):return "storage_full"
	site.complete=false
	site.invested=0
	site.erase("preset_origin")
	site.erase("host_completed")
	w._grids.erase("home")
	w._terrain_solids.erase("home")
	record(id,"structure_removed",target,"home",w.point(site),reason,preload("res://scripts/localization.gd").content(site.name))
	return ""

func relocate_camp(id:String,target:String,step:Dictionary)->String:
	var w:RefCounted=flowers.world
	if not w.barbecues.has(target):return "protected_structure"
	var plan:Dictionary=w.leisure.sites.get(w.standard.site_for(target),{})
	if not plan.get("world_camp_rebuild",false) or plan.complete or plan.invested!=0:return "structure_in_use"
	if w.work.claims.has(plan.id):return "structure_in_use"
	var p:Vector2=flowers.point(step)
	if not p.is_finite() or w.actors[id].region_id!="home":return "not_land"
	if not check(id,"place_piece",{"item":"fence","position":[p.x,p.y]},true).is_empty():
		return "occupied_or_blocked"
	for offset in w.barbecues[target].activity_rules.seat_offsets:
		if not w.walkable("home",p+Vector2(offset[0],offset[1])):return "occupied_or_blocked"
	if not w.walkable("home",p+Vector2(0,1.5)):return "unreachable"
	plan.position=[p.x,p.y]
	w.revision+=1
	return ""

func connectivity(p:Vector2)->Dictionary:
	var protected:=protection(p)
	if not protected.is_empty():return protected
	var w:RefCounted=flowers.world
	var points:=key_points()
	var names:=points.keys()
	for name in names:
		if not w.walkable("home",points[name]):
			points[name]=w.nearest_walkable("home",points[name])
	# Preserve existing connections, including endpoints on either side of the bridge.
	# Use the usual World solver with a tentative obstacle and restore its previous grid.
	var pairs:Array=[]
	var affected:Array=[]
	var area:=box(p)
	if not names.is_empty():
		var start:String=names[0]
		for name in names.slice(1):
			var route:Array[Vector2]=w.route_between("home",points[start],points[name])
			if not route.is_empty():
				pairs.append([start,name])
				if route_crosses(area,points[start],route):affected.append([start,name])
		# Some old layouts already split access groups. Preserve those groups too.
		var checked:Dictionary={start:true}
		for pair in pairs:checked[pair[1]]=true
		for i in range(1,names.size()):
			if checked.has(names[i]):continue
			for j in range(i+1,names.size()):
				var route:Array[Vector2]=w.route_between("home",points[names[i]],points[names[j]])
				if not route.is_empty():
					pairs.append([names[i],names[j]])
					checked[names[j]]=true
					if route_crosses(area,points[names[i]],route):affected.append([names[i],names[j]])
	if affected.is_empty():return {}
	var previous:AStarGrid2D=w._grids.get("home")
	var cell:=Vector2i(p)-Vector2i.ONE
	var can_mark:=previous!=null and previous.region.has_point(cell)
	var old_solid:=can_mark and previous.is_point_solid(cell)
	if can_mark:previous.set_point_solid(cell,true)
	solids[Vector2i(p)]=true
	for pair in affected:
		if w.route_between("home",points[pair[0]],points[pair[1]]).is_empty():
			protected=rejection(pair[0],pair[1]);break
	solids.erase(Vector2i(p))
	if can_mark:previous.set_point_solid(cell,old_solid)
	if previous==null:w._grids.erase("home")
	return protected

func check(id:String,action:String,step:Dictionary,full:bool=false)->Dictionary:
	var w:RefCounted=flowers.world
	var region:String=w.actors[id].region_id
	var p:Vector2=flowers.point(step)
	var k:String=flowers.key(region,p) if p.is_finite() else ""
	if region!="home" or not p.is_finite() or not w.terrain_surface(region,p):return {"error":"not_land"}
	if action=="remove_piece":return {} if pieces.has(k) else {"error":"protected_or_missing"}
	if action=="name_place":return {} if pieces.has(k) else {"error":"protected_or_missing"}
	if not Catalog.has(step.get("item")):return {"error":"unknown_piece"}
	if pieces.size()>=LIMIT:return {"error":"placement_limit"}
	var shape:Dictionary=Catalog[step.item]
	if not shape.walkable:
		var reserved:=protection(p)
		if not reserved.is_empty():return reserved
	if pieces.has(k) or flowers.flowers.has(k) or not w.walkable(region,p):return {"error":"occupied_or_blocked"}
	for object in w.objects.values():
		if object.region_id!=region or object.kind not in ["tree","construction_site"]:continue
		var extent:Vector2=w.site_size(object) if object.kind=="construction_site" else Vector2.ONE
		if box(p).intersects(Rect2(w.point(object)-extent/2,extent)):return {"error":"occupied_or_blocked"}
	if not w.storage.has(shape.material):return {"error":"insufficient_materials"}
	if shape.walkable:return {}
	var area:=box(p)
	for actor in w.actors.values():
		if actor.region_id!=region:continue
		var at:Vector2=w.point(actor)
		if area.has_point(at):return {"error":"occupied_or_blocked"}
		if route_crosses(area,at,w._routes.get(actor.id,[])):return {"error":"active_route"}
	for drop in w.drops.values():
		if drop.region_id==region and area.has_point(w.point(drop)):return {"error":"occupied_or_blocked"}
	return connectivity(p) if full else {}

func approach(id:String,p:Vector2)->Array[Vector2]:
	var w:RefCounted=flowers.world
	var start:Vector2=w.point(w.actors[id])
	var stops:Array=[p+Vector2(1,0),p+Vector2(-1,0),p+Vector2(0,1),p+Vector2(0,-1)]
	stops.sort_custom(func(a,b):return a.distance_squared_to(start)<b.distance_squared_to(start))
	for at in stops:
		var route:Array[Vector2]=w.route_between("home",start,at)
		if not route.is_empty():return route
	return []

func local_piece(id:String)->Dictionary:
	var w:RefCounted=flowers.world
	if not w.open_life or w.actors[id].region_id!="home" or w.storage.count("wood")<8:return {}
	# Keep the fallback modest and leave shared stock for the player's first builds.
	if pieces.values().any(func(piece):return piece.owner==id):return {}
	var item:String={"gentle":"lamp","quiet":"bench","lively":"sign","laborious":"fence"}.get(w.intelligence.tag(id),"sign")
	var origin:Vector2=w.point(w.actors[id]).round()
	for offset in [Vector2(0,3),Vector2(3,0),Vector2(-3,0),Vector2(0,-3)]:
		var p:Vector2=origin+offset
		var step:Dictionary={"action":"place_piece","item":item,"position":[p.x,p.y]}
		if check(id,"place_piece",step).is_empty():return step
	return {}

func write_diary(id:String, text:String, reason:String)->String:
	var w:RefCounted=flowers.world
	var actor:Dictionary=w.actors[id]
	if actor.region_id!="home" or not diary_writer.is_valid():return "diary_unavailable"
	if not diary_writer.call(id,text,sequence+1):return "diary_write_failed"
	record(id,"diary","",actor.region_id,w.point(actor),reason)
	return ""

func record(id: String, kind: String, item: String, region: String, p: Vector2, reason: String, description: String = "") -> Dictionary:
	var w: RefCounted = flowers.world
	var actor: Dictionary = w.actors[id]
	var brain:RefCounted=w.director.brains.get(id)
	var background:bool=brain!=null and brain.current.get("origin")=="island_ai"
	sequence += 1
	var row := {"id":sequence,"actor":id,"controller":actor.get("world_door_client","player" if id=="human" else "native" if background or actor.get("controller")=="model" else "local"),"day":w.days.day(),"minute":int(1440.0*w.days.within_day()/w.days.day_seconds),"action":kind,"item":item,"region":region,"position":[p.x,p.y],"reason":reason,"description":description}
	changes.append(row)
	while changes.size() > CHANGE_LIMIT and int(changes[0].id) <= seen:
		var old: Dictionary = changes.pop_front()
		var day := str(int(old.day))
		summaries[day] = int(summaries.get(day,0))+1
		if summaries.size() > 90: summaries.erase(summaries.keys()[0])
	if changes.size() > 1200: changes.pop_front()
	w.revision += 1
	return row

func commit(id: String, action: String, step: Dictionary, reason: String) -> String:
	var w: RefCounted = flowers.world
	var actor: Dictionary = w.actors[id]
	var region: String = actor.region_id
	last_refusal.erase(id)
	var problem:=check(id,action,step,true)
	if not problem.is_empty():
		last_refusal[id]=problem
		return problem.error
	var p: Vector2 = flowers.point(step)
	if w.point(actor).distance_to(p)>2:return "too_far"
	var key: String = flowers.key(region,p)
	if action=="remove_piece":
		if not pieces.has(key):return "protected_or_missing"
		var piece: Dictionary=pieces[key]
		var refund:Dictionary={}
		for material in Catalog[piece.item].material:
			var quantity:=floori(float(Catalog[piece.item].material[material])/2)
			if quantity>0:refund[material]=quantity
		if not refund.is_empty() and not w.storage.add(refund):return "storage_full"
		pieces.erase(key)
		if solids.erase(Vector2i(p)):w._grids.erase(region)
		var row := record(id,"removed",piece.item,region,p,reason,piece.label)
		if piece.owner!=id:
			removed.emit(piece.owner,row)
			if id=="human" and not w.actors[piece.owner].has("world_door_client") and not w.director.model_controlled(piece.owner):
				pending_reactions[piece.owner]={"serial":row.id,"until":w.forest.clock+90}
		return ""
	if action=="name_place":
		var piece: Dictionary = pieces.get(key,{})
		if not valid_label(step.get("label")):return "invalid_label"
		piece.label=step.label
		record(id,"named",piece.item,region,p,reason,step.label)
		return ""
	if not w.storage.take(Catalog[step.item].material).ok:return "insufficient_materials"
	var row := record(id,"placed",step.item,region,p,reason)
	pieces[key]={"item":step.item,"owner":id,"region":region,"position":[p.x,p.y],"label":"","created":row.id}
	if step.item=="sign":pieces[key].author=row.controller
	if not Catalog[step.item].walkable:
		solids[Vector2i(p)]=true
		w._grids.erase(region)
	return ""

func saved() -> Dictionary:
	return {"pieces":pieces,"changes":changes,"summaries":summaries,"sequence":sequence,"seen":seen,"projects":projects}

func valid(data: Variant, actors: Dictionary) -> bool:
	if not data is Dictionary or not data.get("pieces") is Dictionary or data.pieces.size()>LIMIT or not data.get("changes") is Array or data.changes.size()>1200 or not data.get("summaries") is Dictionary or data.summaries.size()>90:return false
	if not whole(data.get("sequence"),9007199254740991) or not whole(data.get("seen"),data.sequence):return false
	if not data.get("projects",{}) is Dictionary:return false
	for id in data.get("projects",{}):
		if not actors.has(id) or not valid_label(data.projects[id],true):return false
	for key in data.pieces:
		var piece: Variant=data.pieces[key]
		if not piece is Dictionary or not Catalog.has(piece.get("item")) or not actors.has(piece.get("owner")) or piece.get("region")!="home" or not whole(piece.get("created"),data.sequence) or not valid_label(piece.get("label"),true):return false
		if piece.has("author") and (piece.item!="sign" or not piece.author is String or piece.author.length()>32):return false
		var p:Vector2=flowers.point(piece)
		if not p.is_finite() or not flowers.world.terrain_surface("home",p) or key!=flowers.key("home",p):return false
	var prev := 0
	for row in data.changes:
		if not row is Dictionary or not whole(row.get("id"),data.sequence) or row.id<=prev or not actors.has(row.get("actor")) or not row.get("controller") is String or row.controller.length()>32 or not whole(row.get("day"),1000000) or not whole(row.get("minute"),1439) or row.get("region")!="home" or row.get("action") not in ["placed","removed","named","note","diary","structure_removed"] or not row.get("item") is String or not row.get("reason") is String or row.reason.length()>160 or not valid_label(row.get("description"),true):return false
		if not flowers.point(row).is_finite():return false
		prev=int(row.id)
	for day in data.summaries:
		if not str(day).is_valid_int() or not whole(data.summaries[day],data.sequence):return false
	return true

static func whole(value: Variant, max_value: int) -> bool:
	return (value is int or value is float) and is_finite(value) and float(value)==floorf(value) and value>=0 and value<=max_value

static func valid_label(value: Variant, allow_empty: bool = false) -> bool:
	return (allow_empty and value=="") or preload("res://scripts/island_notes.gd").valid_text(value)

func restore(data: Dictionary) -> void:
	pieces=data.get("pieces",{}).duplicate(true)
	solids.clear()
	pending_reactions.clear()
	last_refusal.clear()
	var sign_authors:Dictionary={}
	for row in data.get("changes",[]):
		if row.action=="placed" and row.item=="sign":sign_authors[int(row.id)]=row.controller
	for piece in pieces.values():
		if not Catalog[piece.item].walkable:solids[Vector2i(flowers.point(piece))]=true
		if piece.item=="sign" and not piece.has("author") and sign_authors.has(int(piece.created)):
			piece.author=sign_authors[int(piece.created)]
	changes=data.get("changes",[]).duplicate(true)
	summaries=data.get("summaries",{}).duplicate(true)
	projects=data.get("projects",{}).duplicate(true)
	sequence=int(data.get("sequence",0))
	seen=int(data.get("seen",0))

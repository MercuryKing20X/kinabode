extends RefCounted
## Host-authorized leisure only. World remains the sole movement owner.
const EXTENSION=[[25,165],[55,162],[81,170],[108,162],[137,165],[148,192],[143,229],[119,250],[81,254],[43,250],[19,229],[14,192]]
const WORK=["fish","chop","gather_wood","forage","plant","water","harvest","manage_farm","build","build_house","build_facility","deliver_wood","homestead_start"]
var owner:WeakRef
var world:RefCounted:
	get:return owner.get_ref()
var config:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/migrations/flower-predecessor/resort-villas.json"))
var speech:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/companions/vacation-speech.json"))
var activities:Dictionary={}
var wet:Dictionary={}
var furnished:=false
var migrated:=false
var migration:Dictionary={}
func _init(w:RefCounted)->void:
	owner=weakref(w)
	for villa in config.villas:
		for activity in villa.activities:activities[activity.id]=activity
		for kind in ["sea","stars"]:
			var at:=Vector2(villa.position[0],villa.position[1])+Vector2(0,20)
			var slots:Array=[]
			for i in 5:slots.append([at.x+(i-2)*2,at.y])
			var id:String="resort."+villa.key+"."+kind
			activities[id]={"id":id,"kind":kind,"position":[at.x,at.y],"slots":slots,"size":[10,2]}
static func install(catalog:RefCounted)->void:
	if catalog.manifest.get("template_id")!="home-v3" or not catalog.regions.get("home",{}).get("layout",{}).has("homelands"):return
	var region:Dictionary=catalog.regions.home
	region.size[1]=330
	region.zones.append({"id":"resort","name":preload("res://scripts/localization.gd").text("content.health_20261107.ead88ddab5c6"),"rect":[14,162,134,92]})
	region.land_extensions[int(region.layout.homelands.land_index)]=EXTENSION.duplicate(true);catalog._compiled_geometry.clear()
	for id in catalog.objects.keys():
		if str(id).begins_with("homelands.house.") or str(id).begins_with("homelands.free."):catalog.objects.erase(id)
	for v in JSON.parse_string(FileAccess.get_file_as_string("res://content/migrations/flower-predecessor/resort-villas.json")).villas:
		catalog.objects[v.id]={"id":v.id,"name":v.name,"kind":"construction_site","region_id":"home","zone_id":"resort","position":v.position.duplicate(),"footprint":v.footprint.duplicate(),"owner_id":v.owner_id,"stage_index":5,"stage":"complete","status":"complete","invested":0,"delivered":{},"introduced_in":999}
func enabled()->bool:return world.locations.v3() and world.catalog.regions.get("home",{}).get("layout",{}).has("homelands")
func contains(at:Vector2)->bool:
	if at.y<150:return false
	return enabled() and world.home_island.contains(at)
func vacation(id:String)->bool:return enabled() and world.actors.has(id) and world.actors[id].region_id=="home" and contains(world.point(world.actors[id]))
func line()->String:return preload("res://scripts/localization.gd").source("content.health_20261107.d726a7d5decf") if not TranslationServer.get_locale().begins_with("en") else "We are on holiday here. Let us work back on the main island!"
func villa(id:String)->Dictionary:
	for v in config.villas:
		if v.id==id:return v
	return {}
func retired(target:Dictionary)->bool:return target.get("region_id","home")=="home" and contains(world.point(target)) and not str(target.get("id","")).begins_with("resort.villa.")
func migrate()->void:
	if migrated or not enabled():return
	var refund:Dictionary={};var crops:Dictionary={}
	for site in world.objects.values():
		if site.kind!="construction_site" or not retired(site) or int(site.get("stage_index",0))==5:continue
		var amount:int=int(site.get("invested",0))+int(site.get("delivered",{}).get("wood",0))
		refund[site.id]=amount
	for site in world.leisure.sites.values():
		if retired(site) and not site.complete:refund[site.id]=int(site.invested)
	for plot in world.farms.plots.values():
		if not retired(plot) or str(plot.crop_id).is_empty():continue
		var crop:String=plot.crop_id
		var items:Dictionary={"seed."+crop:1}
		if world.farms.stage(plot)=="mature":items[crop]=int(world.farms.crops[crop].yield)
		crops[plot.id]=items
	var items:Dictionary={"wood":0}
	for n in refund.values():items.wood+=int(n)
	for batch in crops.values():
		for key in batch:items[key]=int(items.get(key,0))+int(batch[key])
	if not world.storage.add(items):return
	for id in refund:
		if world.objects.has(id):
			var site:Dictionary=world.objects[id];site.invested=0;site.delivered={};site.stage_index=0;site.status="unstarted";site.stage="unstarted";site.erase("contributions");site.erase("blueprint")
		else:world.leisure.sites[id].invested=0
	for actor in world.projects.plans.keys():
		if refund.has(str(world.projects.plans[actor].get("site_id",""))):world.projects.plans.erase(actor)
	for id in crops:
		var p:Dictionary=world.farms.plots[id];p.crop_id="";p.watered=false;p.planted_at=0.0
	world.farms._stages.clear();world._grids.clear();world._terrain_solids.clear()
	migration={"refunds":refund,"crops":crops,"added":items};migrated=true
func ready()->void:
	migrate();furnish()
func begin(target_id:String,ids:Array)->Dictionary:
	if not activities.has(target_id):return world._error("unknown_resort_activity")
	var activity:Dictionary=activities[target_id];var accepted:Array=[];var rejected:Dictionary={}
	for id in ids:
		if not world.actors.has(id) or id in accepted:continue
		if not vacation(id):rejected[id]="not_on_island";continue
		if world.director.brains.has(id) and world.director.brains[id].active():world.director.brains[id].begin_external("command","resort")
		if id!="human" and world.hunger.rank(id)>=3:rejected[id]="very_hungry";continue
		if world.work.jobs.has(id) or world.farms.active(id) or world.projects.active(id) or world.shared_activity.holds(id) or world.loaded(id):rejected[id]="busy";continue
		var slot:=-1
		for i in activity.slots.size():
			if not world.work.claims.has(target_id+":"+str(i)):slot=i;break
		if slot<0:rejected[id]="full";continue
		var at:Vector2=Vector2(activity.slots[slot][0],activity.slots[slot][1])
		var route:Array[Vector2]=world.find_route(id,at)
		if route.is_empty() and world.point(world.actors[id]).distance_to(at)>.3:rejected[id]="unreachable";continue
		world.activities.pause_follow(id);world.director.command_received(id,"resort")
		world.work.serial+=1
		world.work.jobs[id]={"id":"job-%s"%world.work.serial,"intent":"resort","phase":"resort_work","target_id":target_id,"slot":slot,"time":0.0,"step":"arriving"}
		world.work.claims[target_id+":"+str(slot)]=id
		world._routes[id]=route
		accepted.append(id)
	return {"ok":not accepted.is_empty(),"accepted":accepted,"rejected":rejected}
func tick(id:String,job:Dictionary,delta:float)->void:
	var a:Dictionary=activities.get(job.target_id,{})
	if a.is_empty():world.work.stop(id,false);return
	job.step="using";job.time+=delta
	world.actors[id].activity="resort_"+a.kind;world.actors[id].facing="down"
	if a.kind=="pool":wet[id]=world.forest.clock+8
	if id!="human" and world.director.routines.has(id) and world.director.time>=float(job.get("speech_after",0)):
		var r:RefCounted=world.director.routines[id]
		if world.director.time<r.visual_quiet_until or world.fishing.life.time<float(world.fishing.life.quiet_until.get(id,0)) or world.activities.blocked(id,false):return
		var tag:String=world.intelligence.tag(id)
		var lang:String="en" if TranslationServer.get_locale().begins_with("en") else "zh"
		var lines:Array=speech[a.kind].get(tag,speech[a.kind].gentle)[lang]
		var count:int=int(job.get("lines",0))
		if world.director.say_local(id,lines[count%lines.size()],"vacation_"+a.kind,float(r.config.speech_interval[0]),float(world.hunger.config.village_gap)):job.lines=count+1
		job.speech_after=maxf(world.director.time+8,r.next_speech)
func using(id:String)->String:
	var j:Dictionary=world.work.jobs.get(id,{})
	return str(activities.get(j.get("target_id",""),{}).get("kind","")) if j.get("intent")=="resort" and j.get("step")=="using" and not world._routes.has(id) else ""
func nearest(kind:String)->String:
	var best:="";var distance:=INF
	for a in activities.values():
		if a.kind!=kind:continue
		var d:float=world.point(a).distance_squared_to(world.point(world.actors.human))
		if d<distance:distance=d;best=a.id
	return best
const ROOM_FURNITURE=[{"recipe":"rug","at":[13,4]},{"recipe":"table","at":[13,4]},{"recipe":"chair","at":[10,5]},{"recipe":"chair","at":[16,5]},{"recipe":"lamp","at":[21,2]}]
func furnish()->void:
	if furnished or not enabled() or world.library==null:return
	for index in config.villas.size():
		var v:Dictionary=config.villas[index]
		for i in ROOM_FURNITURE.size():
			var serial:int=9000001+int({"white":0,"blue":1,"human":2,"orange":3,"black":4}[v.key])*5+i;var id:String="furniture."+str(serial)
			if world.interior.furniture.has(id):continue
			if world.interior.furniture.size()>=64:continue
			var spec:Dictionary=ROOM_FURNITURE[i];var recipe:Dictionary=world.interior.RECIPES[spec.recipe]
			if not world.library.artworks.has("furniture-"+spec.recipe):continue
			world.interior.furniture[id]={"id":id,"kind":"furniture","recipe_id":spec.recipe,"name":recipe.name,"region_id":"room."+str(v.id),"position":spec.at.duplicate(),"facing":"down","holder_id":"","invested":0,"items":{},"capacity":0,"artwork":world.library.artworks["furniture-"+spec.recipe].duplicate(true),"preset_origin":"resort"}
			world.interior.serial=maxi(world.interior.serial,serial)
	furnished=true
static func valid_furniture(item:Dictionary)->bool:
	var id:String=str(item.get("id",""));var number:String=id.trim_prefix("furniture.")
	if not id.begins_with("furniture.") or not number.is_valid_int():return false
	var index:int=int(number)-9000001
	if index<0 or index>=25:return false
	return item.get("preset_origin")=="resort" and item.get("invested")==0 and item.get("recipe_id")==ROOM_FURNITURE[index%5].recipe

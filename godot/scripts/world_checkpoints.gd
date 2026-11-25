extends RefCounted

const Save=preload("res://scripts/save_store.gd")
const LIMIT:=24*1024*1024
const KEEP:=7
const PARTS:=["objects","outdoor_plots","drops","leisure","storage","farming","flower_creation"]
const INVENTORY:=["carry","retained_carry","pocketed","furniture_id"]
const REACTIONS:={
	"gentle":["岛变回去了。我还记得我们一起摆过什么。","The island is back the way it was. I still remember what we made together."],
	"lively":["咦，岛变回去了！昨天那阵忙活我可没忘。","Whoa, the island went back! I still remember all the fuss we made yesterday."],
	"quiet":["岛变回去了。我记得。","The island's back. I remember."],
	"laborious":["岛变回去了。昨天做过的活，我还记得。","The island's back in its old shape. I remember the work we put in."]
}
var directory:String
var world:RefCounted
var last_day:=0
var notice_day:=0
var reactions:Array[String]=[]
var diary_after:=0.0

func _init(w:RefCounted, data_dir:String)->void:
	world=w
	directory=data_dir.path_join("world-checkpoints").path_join(w.world_id.sha256_text())
	for row in entries():
		if row.key!="undo":last_day=maxi(last_day,int(row.day))

func read(key:String)->Dictionary:
	if key!="undo" and (not key.is_valid_int() or str(key.to_int())!=key or key.to_int()<1):return {}
	var file:=FileAccess.open(directory.path_join(key+".json"),FileAccess.READ)
	if file==null or file.get_length()>=LIMIT:return {}
	var parsed:Variant=JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or parsed.get("world")!=world.world_id or parsed.get("opening")!=world.opening_id or not parsed.get("state") is Dictionary:return {}
	if not parsed.get("day") is float or parsed.day<1 or parsed.day!=floorf(parsed.day):return {}
	if key!="undo" and key.to_int()!=int(parsed.day):return {}
	for part in PARTS+["pieces","furniture"]:
		if not parsed.state.get(part) is Dictionary:return {}
	return parsed

func entries()->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	if not DirAccess.dir_exists_absolute(directory):return result
	for file in DirAccess.get_files_at(directory):
		if not file.ends_with(".json"):continue
		var key:=file.trim_suffix(".json")
		var row:=read(key)
		if not row.is_empty():
			row.erase("state")
			row.key=key
			result.append(row)
	result.sort_custom(func(a,b):return (a.key=="undo" and b.key!="undo") or (a.key!="undo" and b.key!="undo" and a.day>b.day))
	return result

func capture(key:String, thumbnail:String="")->bool:
	var current:=Save.encode_world(world)
	var state:Dictionary={}
	for part in PARTS:state[part]=current[part]
	state.pieces=current.world_creations.pieces
	state.furniture=current.interior.furniture
	state.inventory={}
	for id in current.actors:
		var held:Dictionary={}
		for field in INVENTORY:
			if current.actors[id].has(field):held[field]=current.actors[id][field]
		state.inventory[id]=held
	var day:int=world.days.day()
	var changes:int=int(current.world_creations.summaries.get(str(day),0))
	for row in current.world_creations.changes:
		if int(row.day)==day:changes+=1
	return Save.write_data(directory.path_join(key+".json"),{"world":world.world_id,"opening":world.opening_id,"day":day,"changes":changes,"thumbnail":thumbnail,"state":state},LIMIT)

func tick(thumbnail:Callable)->void:
	var day:int=world.days.day()
	if day<=last_day:return
	if not capture(str(day),str(thumbnail.call())):return
	last_day=day
	var retained:=0
	for row in entries():
		if row.key=="undo":continue
		retained+=1
		if retained>KEEP:DirAccess.remove_absolute(directory.path_join(row.key+".json"))

func working()->bool:
	if not world.flower_creation.jobs.is_empty() or not world.deliveries.pending.is_empty() or world.shared_activity.active():return true
	if world.work.jobs.values().any(func(job):return job.get("intent")!="use_facility"):return true
	return world.actors.keys().any(func(id):return world.farms.active(id) or world.projects.active(id))

func stop_work()->void:
	if world.shared_activity.active():world.shared_activity.cancel()
	for id in world.actors:
		if world.work.jobs.has(id) or world.flower_creation.jobs.has(id) or world.deliveries.active(id) or world.farms.active(id) or world.projects.active(id) or world.shared_activity.holds(id):
			world.command(id,{"intent":"stop"})

func restore(key:String, live_path:String, stop_confirmed:bool=false)->String:
	var row:=read(key)
	if row.is_empty():return "missing"
	if working() and not stop_confirmed:return "busy"
	var prepared:=prepare(row)
	if not prepared.error.is_empty():return prepared.error
	if stop_confirmed and working():
		stop_work()
		if working():return "busy"
		prepared=prepare(row)
		if not prepared.error.is_empty():return prepared.error
	var next:Dictionary=prepared.data
	if key!="undo" and not capture("undo"):return "write_failed"
	if not Save.write_data(live_path,next,Save.MAX_SAVE_BYTES):return "write_failed"
	apply_state(next,key,int(row.day))
	return ""

func prepare(row:Dictionary)->Dictionary:
	var next:=Save.encode_world(world).duplicate(true)
	var incompatible:={"error":"incompatible"}
	if not preload("res://scripts/outdoor_building.gd").equivalent(next.outdoor_plots,row.state.outdoor_plots):return incompatible
	for part in PARTS:
		next[part]=row.state[part]
	next.world_creations.pieces=row.state.pieces
	next.interior.furniture=row.state.furniture
	if row.state.has("inventory"):
		var inventory:Variant=row.state.inventory
		if not inventory is Dictionary or inventory.size()!=next.actors.size():return incompatible
		for id in next.actors:
			if not inventory.get(id) is Dictionary or not inventory[id].has("carry"):return incompatible
			for field in INVENTORY:
				next.actors[id].erase(field)
				if inventory[id].has(field):next.actors[id][field]=inventory[id][field]
	elif next.actors.values().any(func(actor):return not actor.carry.is_empty() or actor.has("furniture_id")):
		# Older snapshots cannot say which carried materials already exist in the snapshot.
		return incompatible
	for fid in next.interior.furniture:
		next.interior.serial=maxi(int(next.interior.serial),str(fid).get_slice(".",1).to_int())
	# A rollback is a world change, not a rewind of the island's social clock.
	next.farming.memories=world.farms.memories
	next.farming.orders={}
	next.projects.plans={}
	next.flower_creation.gifts=world.flower_creation.gifts
	next.flower_creation.first_received=world.flower_creation.first_received
	next.flower_creation.serial=maxf(float(next.flower_creation.serial),float(world.flower_creation.serial))
	for id in world.barbecues:
		var state:Dictionary=next.shared_life if id=="home.barbecue" else next.extra_barbecues[id]
		var old:Vector2=world.point(state.station)
		var position:Array=world.standard.camp_position(id,next.leisure.sites)
		var plan:Dictionary=next.leisure.sites.get(world.standard.site_for(id),{})
		if (old!=Vector2(position[0],position[1]) or plan.get("world_camp_rebuild",false) and not plan.complete) and world.barbecues[id].fireside.active():return {"error":"busy"}
		state.station.position=position
	if not world.flower_creation.valid_saved(next.flower_creation,next.actors):return incompatible
	if not world.flower_creation.creations.valid(next.world_creations,next.actors):return incompatible
	if not Save._valid(world,next):return incompatible
	return {"error":"","data":next}

func apply_state(next:Dictionary,key:String,day:int)->void:
	for id in world.work.jobs.keys():world.work.stop(id,false)
	for brain in world.director.brains.values():brain.finish("interrupted","world_restored")
	world.director.interrupt_all()
	world._routes.clear()
	world._forced_runs.clear()
	world._grids.clear()
	world._terrain_solids.clear()
	world.objects=next.objects
	world.drops=next.drops
	world.storage.restore(next.storage)
	for id in world.actors:
		for field in INVENTORY:
			world.actors[id].erase(field)
			if next.actors[id].has(field):world.actors[id][field]=next.actors[id][field]
	world.interior.serial=int(next.interior.serial)
	world.interior.furniture=next.interior.furniture
	world.leisure.restore(next.leisure)
	world.standard.sync_camps()
	world.farms.restore(next.farming)
	world.projects.restore(next.projects)
	world.flower_creation.restore(next.flower_creation)
	world.flower_creation.creations.restore(next.world_creations)
	world.rescue_obstructed()
	world.revision+=1
	if key=="undo":DirAccess.remove_absolute(directory.path_join("undo.json"))
	notice_day=day
	# Stopping a job also defers local speech. Give the reaction a window
	# after that gate reopens before falling back to the diary.
	diary_after=world.forest.clock+35.0
	reactions.assign(world.director.brains.keys().filter(func(id):return not world.director.model_controlled(id) and not world.actors[id].has("world_door_client")))

func speak()->void:
	for id in reactions:
		var lines:Array=REACTIONS.get(world.intelligence.tag(id),REACTIONS.gentle)
		if world.director.say_local(id,preload("res://scripts/world_creations.gd").phrase(lines[0],lines[1]),"world_restored",12,8):
			reactions.erase(id)
			return
		if world.forest.clock>=diary_after:
			var creation:RefCounted=world.flower_creation.creations
			if creation.write_diary(id,preload("res://scripts/world_creations.gd").phrase(lines[0],lines[1]),"")=="":reactions.erase(id)
			return

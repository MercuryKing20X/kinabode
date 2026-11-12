extends RefCounted
## A local handling-rate projection, never routes, jobs, claims or material credit.
var _owner: WeakRef
var world: RefCounted:
	get:return _owner.get_ref()
var config: Dictionary={}
func _init(source: RefCounted) -> void:
	_owner=weakref(source);config=JSON.parse_string(FileAccess.get_file_as_string("res://content/cooperation.json"))
func target(job: Dictionary) -> Dictionary:
	var id: String=str(job.get("target_id",""))
	if world.objects.get(id,{}).get("kind")=="construction_site":return world.objects[id]
	if id==world.homestead.config.site.id:return world.homestead.target()
	return {}
func delivering(job: Dictionary) -> bool:
	return job.get("phase") in config.delivery_phases or (job.get("intent")=="homestead" and job.get("step")=="deliver")
func participating(job: Dictionary) -> bool:
	return job.get("intent") in config.site_intents and (delivering(job) or job.get("phase")=="building" or (job.get("intent")=="homestead" and job.get("step")=="build"))
func present(id: String,site: Dictionary) -> bool:
	if world._routes.has(id) or world.actors[id].region_id!=site.region_id:return false
	var half: Vector2=world.site_size(site)/2 if site.kind=="construction_site" else world.homestead.area().size/2
	return world.point(world.actors[id]).distance_to(world.point(site))<=half.length()+float(config.extra_site_range)
func active(id: String) -> bool:
	if not config.enabled or not world.actors.has(id):return false
	var job: Dictionary=world.work.jobs.get(id,{})
	if not delivering(job):return false
	var site:=target(job)
	if site.is_empty() or not present(id,site):return false
	for other in world.work.jobs:
		var mate: Dictionary=world.work.jobs[other]
		if other!=id and mate.get("target_id")==site.id and participating(mate) and present(other,site):return true
	return false
func factor(id: String,job: Dictionary,site: Dictionary,activity: String) -> float:
	if activity!="putting_down" or not delivering(job) or target(job).get("id")!=site.get("id"):return 1.0
	return float(config.delivery_factor) if active(id) else 1.0

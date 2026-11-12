extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
## Reads actual Leisure seats. Does not create jobs, move people, consume items or infer.
var _owner:WeakRef
var world:RefCounted:
	get:return _owner.get_ref()
var config:Dictionary={}
var last_viewing_day:=0
var elapsed:=0.0
func _init(source:RefCounted)->void:
	_owner=weakref(source)
	config=world.catalog.regions.home.get("layout",{}).get("moon",{}).duplicate(true)
	if not config.is_empty() and (config.get("phase_days")!=8 or not config.get("platform_sites") is Array or config.platform_sites.size()!=3 or not config.platform_sites.all(func(id):return world.leisure.sites.has(id))):world.error=LocalText.text("system.moon_island.the_crescent_island_moon_viewing_settings_are_invalid")
func phase()->int:return posmod(world.days.day()-1,int(config.get("phase_days",8)))
func summary()->Dictionary:
	return {"id":config.get("id",""),"access":"walking_bridge","platform_id":config.get("platform_id",""),"moon_phase":phase(),"day":world.days.day()}
func advance(delta:float)->void:
	if config.is_empty() or delta<=0:return
	elapsed+=delta
	if elapsed<.25:return
	elapsed=0
	if world.days.phase().id!="night" or last_viewing_day==world.days.day() or world.weather.current().id in ["rain","fog"]:return
	var seated:Array=[];var first_site:=""
	for id in world.work.jobs:
		var job:Dictionary=world.work.jobs[id]
		if job.get("intent")=="use_facility" and job.get("target_id") in config.platform_sites and job.get("step")=="using" and world.actors[id].activity=="seated" and world.actors[id].region_id=="home" and not world._routes.has(id):
			seated.append(id);first_site=job.target_id
	if seated.size()<2 or "human" not in seated:return
	var facts:Dictionary={"place_id":config.id,"site_id":first_site,"day":world.days.day(),"phase":"night","moon_phase":phase(),"weather":world.weather.current().id}
	if world.memories.record_event("moon_viewing","moon-night-"+str(world.days.day()),seated,facts):last_viewing_day=world.days.day()

func contains(point:Vector2)->bool:
	return not config.is_empty() and world.catalog.rectangle(config.bounds).has_point(point)

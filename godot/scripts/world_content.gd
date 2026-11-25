extends RefCounted
## Per-world copied content projection. Canonical coordinates stay in the chosen map pack.
var _owner:WeakRef
var world:RefCounted:
	get:return _owner.get_ref()
var cache:Dictionary={}
func _init(source:RefCounted)->void:_owner=weakref(source)
func v3()->bool:return world.catalog.manifest.get("template_id","")=="home-v3"
func read(name:String)->Dictionary:
	if cache.has(name):return cache[name].duplicate(true)
	var value:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/"+name+".json"))
	if v3():
		var layout:Dictionary=world.catalog.regions.home.layout
		match name:
			"recipes":value.station.position=world.map_anchor("camp.stove")
			"homestead":value.site.rect=layout.homestead.rect.duplicate();value.site.entry=world.map_anchor(str(layout.homestead.entry_anchor))
			"shared-activities":value.barbecue.seat_offsets=layout.camp_seat_offsets.duplicate(true)
			"farms":
				for farm in value.farms:
					for authored in layout.farms:
						if farm.id==authored.id:farm.merge(authored,true)
					farm.seed_at=world.map_anchor("tools.seed");farm.harvest_at=world.map_anchor("tools.harvest");farm.meeting_at=farm.entrance.duplicate();farm.road=[farm.entrance.duplicate(),[farm.entrance[0],farm.rect[1]+1]]
			"schedules":
				for phase in layout.schedule_phases:value.phases[phase]=layout.schedule_phases[phase].duplicate(true)
			"fishing":
				value.pens=[]
				for pen in layout.fisheries:
					var copy:Dictionary=pen.duplicate(true);copy.erase("capacity");copy["region_id"]="home";value.pens.append(copy)
				for sea in value.seas:
					sea.anchor=layout.water_anchors[str(sea.id).get_slice(".",2)].duplicate();sea.legacy_spots=[]
			"map-locations":
				value.leisure=[]
				for facility in layout.facilities:
					value.leisure.append({"id":facility.id,"name":facility.name,"template_id":facility.template_id,"position":world.map_anchor(facility.anchor),"facing":facility.get("facing","down")})
				value.mushrooms=layout.forage.duplicate(true)
				value.points.p_24_45={"file":"recipes.json","path":["station","position"]}
				value.points.p_21_47=world.map_anchor("picnic");value.points.p_49_48=world.map_anchor("spawn")
	cache[name]=value.duplicate(true);return value.duplicate(true)
func section(key:String)->Variant:return read("map-locations")[key]
func pair(key:String)->Array:
	var value:Variant=read("map-locations").points[key]
	if value is Array:return value.duplicate()
	var result:Variant=read(str(value.file).trim_suffix(".json"))
	for segment in value.path:result=result[segment]
	return result.duplicate()
func point(key:String)->Vector2:
	var value:=pair(key);return Vector2(value[0],value[1])

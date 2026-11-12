extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
## Cosmetic daily projection: own seeded RNG, same DayCycle; no simulation values.
var _owner: WeakRef
var world: RefCounted:
	get:return _owner.get_ref()
var config: Dictionary={}
var weather_seed:=0
var marked_day:=0
func _init(source: RefCounted) -> void:
	_owner=weakref(source)
	var data: Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/weather.json"))
	if not valid_config(data):world.error=LocalText.text("system.weather_system.the_weather_settings_are_invalid");return
	config=data;weather_seed=abs((world.world_id+Crypto.new().generate_random_bytes(8).hex_encode()).hash())
func valid_config(data: Variant) -> bool:
	if not data is Dictionary or data.get("version")!=1 or not data.get("states") is Array or data.states.size()!=4:return false
	var ids: Array=[]
	for item in data.states:
		if not item is Dictionary or item.get("id") not in ["sunny","cloudy","rain","fog"] or item.id in ids or not item.get("name") is String or item.name.is_empty() or item.name.length()>8:return false
		for key in ["weight","tint","rain","fog"]:
			if not world.catalog._number(item.get(key)) or item[key]<0:return false
		if item.weight<1 or item.weight>100 or item.tint>.25 or item.fog>.35 or item.rain>100 or item.rain!=floor(item.rain) or not item.get("lines") is Array or item.lines.size()<4 or not item.lines.all(func(line):return line is String and not line.is_empty() and line.length()<=60):return false
		ids.append(item.id)
	return true
func for_day(day: int) -> Dictionary:
	var rng:=RandomNumberGenerator.new();rng.seed=abs((str(weather_seed)+":"+str(day)).hash())
	var total: float=config.states.reduce(func(sum,item):return sum+float(item.weight),0.0)
	var roll:=rng.randf()*total
	for item in config.states:
		roll-=float(item.weight)
		if roll<=0:return item.duplicate(true)
	return config.states[-1].duplicate(true)
func current() -> Dictionary:return for_day(world.days.day())
func summary() -> Dictionary:
	var item:=current();return {"id":item.id,"name":item.name,"day":world.days.day(),"source":"local_rules","cosmetic_only":true}
func advance() -> void:
	if marked_day!=world.days.day():marked_day=world.days.day();world.revision+=1
func saved() -> Dictionary:return {"version":1,"seed":weather_seed}
func valid_saved(data: Variant) -> bool:return data is Dictionary and data.size()==2 and data.get("version")==1 and world.relationships.integer(data.get("seed"),4294967295)
func restore(data: Dictionary) -> void:
	if not data.is_empty():weather_seed=int(data.seed)
	marked_day=world.days.day()

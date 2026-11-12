extends RefCounted
## Daily play defaults. Manual zoom remains under the view's existing controls.
const DEFAULTS={"version":1,"home":1.5625,"moon":1.6875,"dark":1.5625,"room":1.4375,"fishing":1.5625}
var distance_factor:float=1.0
var preference_path:String=""
func configure(directory:String)->void:
	preference_path=directory.path_join("local-life.cfg")
	var prefs:=ConfigFile.new();prefs.load(preference_path)
	distance_factor=clampf(float(prefs.get_value("camera","distance_factor",1.0)),.8,1.0)
func set_distance(value:float)->void:
	distance_factor=clampf(value,.8,1.0)
	if preference_path.is_empty():return
	var prefs:=ConfigFile.new();prefs.load(preference_path);prefs.set_value("camera","distance_factor",distance_factor);prefs.save(preference_path)
var config:Dictionary=DEFAULTS.duplicate()
func _init()->void:
	var value:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://content/camera.json"))
	if valid(value):config=value
static func valid(value:Variant)->bool:
	if not value is Dictionary or value.size()!=DEFAULTS.size() or value.get("version")!=1:return false
	for key in ["home","moon","dark","room","fishing"]:
		var n:Variant=value.get(key)
		if not (n is float or n is int) or not is_finite(n) or n<.42 or n>2:return false
	return true
func at(world:RefCounted,region:String,point:Vector2)->float:
	if region=="home":return distance_factor*float(config.moon if world.moon!=null and world.moon.contains(point) else config.home)
	return distance_factor*float(config.dark if region=="dark" else config.room)

class_name MapLocations
extends RefCounted
## Authored legacy map anchors. Values are copied; no world/save mutation or executable content.
static var _cache: Dictionary={}
static func data() -> Dictionary:
	if _cache.is_empty():_cache=JSON.parse_string(FileAccess.get_file_as_string("res://content/map-locations.json"))
	return _cache.duplicate(true)
static func section(key: String) -> Variant:return data()[key]
static func pair(key: String) -> Array:
	var entry:Variant=data().points[key]
	if entry is Array:return entry.duplicate()
	var value:Variant=data() if entry.file=="map-locations.json" else JSON.parse_string(FileAccess.get_file_as_string("res://content/"+entry.file))
	for part in entry.path:value=value[part]
	return value.duplicate()
static func point(key: String) -> Vector2:
	var v:=pair(key);return Vector2(v[0],v[1])

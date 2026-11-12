class_name WorldCatalog
extends RefCounted
const LocalText=preload("res://scripts/localization.gd")

var manifest: Dictionary = {}
var regions: Dictionary = {}
var objects: Dictionary = {}
var region_packs: Dictionary = {}
var error := ""
# Compiled source geometry only; no route, obstacle or walkability decisions.
var _compiled_geometry: Dictionary = {}

func load_world(path: String = "res://content/world.json") -> bool:
	manifest = _json(path)
	regions.clear()
	_compiled_geometry.clear()
	objects.clear()
	region_packs.clear()
	if manifest.get("schema_version") != 1 or not _rect(manifest.get("bounds")):
		error = LocalText.text("system.world_catalog.invalid_world_manifest")
		return false
	if not manifest.get("active_packs") is Array or manifest.active_packs.is_empty():
		error = LocalText.text("system.world_catalog.the_world_has_no_enabled_content_packs")
		return false
	if not manifest.get("pack_regions",{}) is Dictionary:error=LocalText.text("system.world_catalog.invalid_content_pack_region_selection");return false
	for pack_path in manifest.active_packs:
		var pack := _json(str(pack_path))
		var selection:Variant=manifest.get("pack_regions",{}).get(str(pack_path),null)
		if selection!=null:
			if not selection is Array or selection.is_empty() or not selection.all(func(id):return id is String) or not pack.get("regions") is Array:
				error=LocalText.text("system.world_catalog.invalid_content_pack_region_selection");return false
			pack.regions=pack.regions.filter(func(region):return region is Dictionary and region.get("id","") in selection)
			if pack.regions.size()!=selection.size():error=LocalText.text("system.world_catalog.a_selected_region_is_missing_or_duplicated");return false
		var issues := validate_pack(pack)
		if not issues.is_empty():
			error = "; ".join(issues)
			return false
		for region in pack.regions:
			region_packs[region.id]={"id":pack.id,"version":pack.get("version",1),"name":pack.get("name",pack.id)}
			regions[region.id] = region.duplicate(true)
			# Optional content references keep farm bounds in the validated zone once.
			for farm in regions[region.id].get("layout",{}).get("farms",[]):
				if not farm.get("geometry_from_zone",false):continue
				var source:Array=region.zones.filter(func(zone):return zone.id==farm.get("zone_id",""))
				if source.size()!=1 or not _pair(farm.get("first_offset")) or not _number(farm.get("entrance_offset_y")) or not _number(farm.get("gate",{}).get("offset")):
					error=LocalText.text("system.world_catalog.invalid_farm_location_reference");return false
				farm["rect"]=source[0].rect.duplicate()
				farm["first"]=[farm.rect[0]+farm.first_offset[0],farm.rect[1]+farm.first_offset[1]]
				farm["entrance"]=[farm.rect[0]+farm.gate.offset,farm.rect[1]+farm.entrance_offset_y]
			for object in region.objects:
				var entry: Dictionary = object.duplicate(true)
				entry["region_id"] = region.id
				objects[object.id] = entry
	if regions.is_empty(): error = LocalText.text("system.world_catalog.the_content_pack_has_no_region")
	return not regions.is_empty()

func _json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

func _pair(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _number(value[0]) and _number(value[1])

func _number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

func _rect(value: Variant) -> bool:
	return value is Array and value.size() == 4 and _number(value[0]) and _number(value[1]) and _number(value[2]) and _number(value[3]) and value[2] > 0 and value[3] > 0

func rectangle(value: Array) -> Rect2:
	return Rect2(value[0], value[1], value[2], value[3])

func local_origin(region:Dictionary)->Vector2:
	var at:Array=region.get("local_origin",[0,0])
	return Vector2(at[0],at[1])

func polygon(region: Dictionary) -> PackedVector2Array:
	var points := PackedVector2Array()
	for point in region.land:
		points.append(Vector2(point[0], point[1]))
	return points

func validate_pack(pack: Dictionary) -> Array[String]:
	var issues: Array[String] = []
	if pack.get("schema_version") != 1 or not pack.get("id") is String or not pack.get("regions") is Array:
		return [LocalText.text("system.world_catalog.invalid_content_pack_format")]
	var ids: Dictionary = {}
	var occupied: Array[Rect2] = []
	var occupied_regions:Array=[]
	for existing in regions.values():
		occupied.append(Rect2(Vector2(existing.origin[0], existing.origin[1])+local_origin(existing), Vector2(existing.size[0], existing.size[1])))
		occupied_regions.append(existing)
	for region in pack.regions:
		if not region is Dictionary or not region.get("name") is String or not region.get("id") is String or not _pair(region.get("origin")) or not _pair(region.get("size")):
			return [LocalText.text("system.world_catalog.invalid_region_coordinates_or_identity")]
		if region.has("local_origin") and not _pair(region.local_origin):return [LocalText.text("system.world_catalog.invalid_region_local_origin")]
		if region.size[0] <= 0 or region.size[1] <= 0 or region.size[0] > 512 or region.size[1] > 512:
			return [LocalText.text("system.world_catalog.region_dimensions_must_be_within_1_512")]
		if ids.has(region.id) or regions.has(region.id):
			issues.append(LocalText.text("system.world_catalog.duplicate_region_id") + region.id)
		ids[region.id] = true
		var bounds := Rect2(Vector2(region.origin[0], region.origin[1])+local_origin(region), Vector2(region.size[0], region.size[1]))
		if not rectangle(manifest.bounds).encloses(bounds): issues.append(LocalText.text("system.world_catalog.a_region_extends_beyond_the_world_bounds"))
		for index in range(occupied.size()):
			if bounds.intersects(occupied[index]):
				var other_region:Dictionary=occupied_regions[index]
				if not (region.get("layout",{}).has("homelands") or other_region.get("layout",{}).has("homelands")) or land_overlaps(region,other_region):issues.append(LocalText.text("system.world_catalog.region_footprints_overlap"))
		occupied.append(bounds);occupied_regions.append(region)
		if not region.get("land") is Array or region.land.size() < 3 or region.land.size() > 2048:
			return [LocalText.text("system.world_catalog.invalid_island_outline")]
		var local_bounds := Rect2(local_origin(region), bounds.size)
		for extension in region.get("land_extensions",[]):
			if not extension is Array or extension.size()<3 or extension.size()>2048:return [LocalText.text("system.world_catalog.invalid_land_extension_outline")]
			var polygon_points:=PackedVector2Array()
			for p in extension:
				if not _pair(p) or not local_bounds.has_point(Vector2(p[0],p[1])):return [LocalText.text("system.world_catalog.a_land_extension_exceeds_bounds")]
				polygon_points.append(Vector2(p[0],p[1]))
			if Geometry2D.triangulate_polygon(polygon_points).is_empty():return [LocalText.text("system.world_catalog.a_land_extension_cannot_be_triangulated")]
		for point in region.land:
			if not _pair(point) or not local_bounds.has_point(Vector2(point[0], point[1])): return [LocalText.text("system.world_catalog.an_island_vertex_exceeds_bounds")]
		if Geometry2D.triangulate_polygon(polygon(region)).is_empty(): return [LocalText.text("system.world_catalog.the_island_outline_cannot_be_triangulated")]
		if not region.get("zones") is Array or not region.get("objects") is Array: return [LocalText.text("system.world_catalog.a_region_is_missing_zones_objects")]
		var zone_ids: Dictionary = {}
		var zone_bounds: Array[Rect2] = []
		for zone in region.zones:
			if not zone is Dictionary or not zone.get("name") is String or not zone.get("purpose") is String or not zone.get("id") is String or not _rect(zone.get("rect")): return [LocalText.text("system.world_catalog.invalid_zone_format")]
			if ids.has(zone.id): issues.append(LocalText.text("system.world_catalog.duplicate_zone_id"))
			ids[zone.id] = true
			zone_ids[zone.id] = zone
			var area := rectangle(zone.rect)
			if not local_bounds.encloses(area): issues.append(LocalText.text("system.world_catalog.a_zone_exceeds_bounds"))
			for point in [area.position, area.position + Vector2(area.size.x, 0), area.end, area.position + Vector2(0, area.size.y)]:
				if not on_land(region,point): issues.append(LocalText.text("system.world_catalog.a_zone_is_outside_the_land"))
			for previous in zone_bounds:
				if area.intersects(previous): issues.append(LocalText.text("system.world_catalog.usage_zones_overlap"))
			zone_bounds.append(area)
		for object in region.objects:
			if not object is Dictionary or not object.get("name") is String or object.get("kind") not in ["tree", "farm_plot", "construction_site"] or not object.get("id") is String or not _pair(object.get("position")) or not zone_ids.has(object.get("zone_id", "")): return [LocalText.text("system.world_catalog.invalid_object_identity_coordinates_or_zone")]
			if ids.has(object.id) or objects.has(object.id): issues.append(LocalText.text("system.world_catalog.duplicate_object_id"))
			ids[object.id] = true
			var point := Vector2(object.position[0], object.position[1])
			if not rectangle(zone_ids[object.zone_id].rect).has_point(point): issues.append(LocalText.text("system.world_catalog.an_object_is_outside_its_zone"))
			if not on_land(region,point): issues.append(LocalText.text("system.world_catalog.an_object_is_outside_the_land"))
	return issues

func zone_at(region_id: String, point: Vector2) -> String:
	for zone in regions[region_id].zones:
		if rectangle(zone.rect).has_point(point): return zone.id
	return ""

func walkable(region_id: String, point: Vector2) -> bool:
	if not regions.has(region_id): return false
	if not on_land(regions[region_id],point): return false
	for object in regions[region_id].objects:
		if object.kind=="tree" and point.distance_to(Vector2(object.position[0], object.position[1])) < 0.7:
			return false
	return true

func on_land(region:Dictionary,point:Vector2)->bool:
	for shape in _geometry(region,"land"):
		if _shape_contains(shape,point):return true
	return false

func on_dock(region:Dictionary,point:Vector2)->bool:
	for shape in _geometry(region,"docks"):
		if _shape_contains(shape,point):return true
	return false

func _geometry(region:Dictionary,kind:String)->Array:
	var id:String=str(region.get("id",""))
	# Imported/validation fixtures may reuse a live ID with different geometry.
	# Only the exact catalog-owned region dictionary can use the retained cache.
	if regions.has(id) and is_same(regions[id],region):
		var key:String=id+":"+kind
		if not _compiled_geometry.has(key):_compiled_geometry[key]=_compile_geometry(region,kind)
		return _compiled_geometry[key]
	return _compile_geometry(region,kind)

func _compile_geometry(region:Dictionary,kind:String)->Array:
	var result:Array=[]
	if kind=="land":
		result.append(_compile_shape(region.land))
		for extension in region.get("land_extensions",[]):result.append(_compile_shape(extension))
	else:
		for dock in region.get("layout",{}).get("dock_surfaces",[]):result.append(_compile_shape(dock.polygon))
	return result

func _compile_shape(points:Array)->Dictionary:
	var shape:=PackedVector2Array()
	for at in points:shape.append(Vector2(at[0],at[1]))
	var low:Vector2=shape[0];var high:Vector2=shape[0]
	for at in shape:
		low=Vector2(minf(low.x,at.x),minf(low.y,at.y))
		high=Vector2(maxf(high.x,at.x),maxf(high.y,at.y))
	return {"points":shape,"bounds":Rect2(low,high-low)}

func _shape_contains(shape:Dictionary,point:Vector2)->bool:
	var bounds:Rect2=shape.bounds
	# Inclusive coarse bounds keep polygon-edge behavior exactly as before.
	if point.x<bounds.position.x or point.y<bounds.position.y or point.x>bounds.end.x or point.y>bounds.end.y:return false
	if Geometry2D.is_point_in_polygon(point,shape.points):return true
	# The engine's ray predicate can return false at isolated interior points
	# (e.g. core land at 39.6329803467,48.0688629150). Verify negative results
	# with scalar-double horizontal crossings; no tolerance or coastal padding.
	var inside:=false
	var polygon:PackedVector2Array=shape.points
	var px:float=point.x;var py:float=point.y
	var previous:int=polygon.size()-1
	for index in polygon.size():
		var ax:float=polygon[previous].x;var ay:float=polygon[previous].y
		var bx:float=polygon[index].x;var by:float=polygon[index].y
		var cross:float=(bx-ax)*(py-ay)-(by-ay)*(px-ax)
		if cross==0 and px>=minf(ax,bx) and px<=maxf(ax,bx) and py>=minf(ay,by) and py<=maxf(ay,by):return true
		if (ay>py)!=(by>py) and px<ax+(py-ay)*(bx-ax)/(by-ay):inside=not inside
		previous=index
	return inside

# A merged archipelago's empty bounding-box sea is not occupied terrain.
func land_overlaps(a:Dictionary,b:Dictionary)->bool:
	for left in [a.land]+a.get("land_extensions",[]):
		var p:=PackedVector2Array()
		for at in left:p.append(Vector2(at[0]+a.origin[0],at[1]+a.origin[1]))
		for right in [b.land]+b.get("land_extensions",[]):
			var q:=PackedVector2Array()
			for at in right:q.append(Vector2(at[0]+b.origin[0],at[1]+b.origin[1]))
			if not Geometry2D.intersect_polygons(p,q).is_empty():return true
	return false

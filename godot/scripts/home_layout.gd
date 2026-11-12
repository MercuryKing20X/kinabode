class_name HomeLayout
extends RefCounted

static func points(values: Array) -> PackedVector2Array:
	var result := PackedVector2Array()
	for value in values: result.append(Vector2(value[0], value[1]))
	return result

static func near_road(layout: Dictionary, point: Vector2, padding: float = 0.0) -> bool:
	for road in layout.get("roads", []):
		var path := points(road.points)
		for i in range(path.size() - 1):
			if point.distance_to(Geometry2D.get_closest_point_to_segment(point, path[i], path[i + 1])) < float(road.width) + padding: return true
	return false

static func blocked(layout: Dictionary, point: Vector2) -> bool:
	for fence in layout.garden.fences:
		var start := Vector2(fence[0][0], fence[0][1])
		var end := Vector2(fence[1][0], fence[1][1])
		if point.distance_to(Geometry2D.get_closest_point_to_segment(point, start, end)) < .38: return true
	for prop in layout.get("solid_props",[]):
		var at:Array=layout.anchors[prop.anchor]
		if Rect2(Vector2(at[0]+prop.offset[0],at[1]+prop.offset[1]),Vector2(prop.size[0],prop.size[1])).has_point(point):return true
	for cliff in layout.get("cliffs",[]):
		if Geometry2D.is_point_in_polygon(point,points(cliff.polygon)):
			var steps:Rect2=Rect2(Vector2(cliff.stairs[0][0],cliff.stairs[0][1]),Vector2(cliff.stairs[1][0]-cliff.stairs[0][0],cliff.stairs[1][1]-cliff.stairs[0][1]))
			if not steps.has_point(point):return true
	for pond in layout.get("ponds", []):
		if pond.has("crossing_anchor"):
			var at:Array=layout.anchors[pond.crossing_anchor];var span:Vector2=Vector2(pond.crossing_size[0],pond.crossing_size[1])
			if Rect2(Vector2(at[0],at[1])-span/2,span).has_point(point):continue
		var local := (point - Vector2(pond.center[0], pond.center[1])) / Vector2(pond.radius[0], pond.radius[1])
		if local.length_squared() < 1.25 and Geometry2D.is_point_in_polygon(point, pond_shape(pond)): return true
	return false

static func ellipse(center: Vector2, radius: Vector2) -> PackedVector2Array:
	var result := PackedVector2Array()
	for i in range(48): result.append(center + Vector2(cos(i * TAU / 48), sin(i * TAU / 48)) * radius)
	return result

static func rectangle(rect: Rect2, corner: float = .0) -> PackedVector2Array:
	var r := minf(corner, minf(rect.size.x, rect.size.y) / 2)
	return PackedVector2Array([rect.position + Vector2(r, 0), Vector2(rect.end.x - r, rect.position.y), Vector2(rect.end.x, rect.position.y + r), rect.end - Vector2(0, r), rect.end - Vector2(r, 0), Vector2(rect.position.x + r, rect.end.y), Vector2(rect.position.x, rect.end.y - r), rect.position + Vector2(0, r)])

static func pond_shape(pond: Dictionary) -> PackedVector2Array:
	var result := PackedVector2Array()
	var center := Vector2(pond.center[0], pond.center[1])
	var radius := Vector2(pond.radius[0], pond.radius[1])
	for i in range(64):
		var angle := i * TAU / 64
		var ripple := 1.0 + sin(angle * 3 + .7) * .06 + cos(angle * 5) * .035
		result.append(center + Vector2(cos(angle), sin(angle)) * radius * ripple)
	return result

static func yard_fences(point: Vector2, half: Vector2) -> Array:
	return [[point + Vector2(-half.x - 1.5, half.y + 3.4), point + Vector2(-1.7, half.y + 3.4)], [point + Vector2(1.7, half.y + 3.4), point + Vector2(half.x + 1.5, half.y + 3.4)]]

static func plaza_shape(layout:Dictionary)->PackedVector2Array:
	var value:Array=layout.plaza
	var rect:=Rect2(Vector2(value[0],value[1]),Vector2(value[2],value[3]))
	return PackedVector2Array([rect.position,Vector2(rect.end.x,rect.position.y),rect.end,Vector2(rect.position.x,rect.end.y)])

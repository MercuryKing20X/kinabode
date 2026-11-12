class_name BlueprintRules
extends RefCounted

static func valid_structure(value: Variant) -> bool:
	if not value is Dictionary: return false
	for key in ["width", "depth", "floors", "porch"]:
		if not value.has(key) or not (value[key] is int or value[key] is float) or not is_finite(float(value[key])) or value[key] != floor(float(value[key])): return false
	return value.width >= 4 and value.width <= 10 and value.depth >= 4 and value.depth <= 8 and value.floors >= 1 and value.floors <= 2 and value.porch >= 0 and value.porch <= 2

static func quote(structure: Dictionary) -> Dictionary:
	if not valid_structure(structure): return {"ok": false, "error": "invalid_structure"}
	var floor_cost := ceili(float(structure.width * structure.depth * structure.floors) / 4.0)
	var wall_cost := ceili(float(2 * (structure.width + structure.depth) * structure.floors) / 3.0)
	var roof_cost := ceili(float(structure.width * structure.depth) / 4.0)
	var porch_cost := int(structure.width * structure.porch)
	var stages := [floor_cost, wall_cost, wall_cost + 4, roof_cost, 8 + porch_cost]
	var total := 0
	for amount in stages: total += amount
	return {"ok": true, "wood": total, "stages": stages, "breakdown": {"floor": floor_cost, "frame": wall_cost, "walls": wall_cost + 4, "roof": roof_cost, "finish": 8, "porch": porch_cost}}

static func footprint(structure: Dictionary) -> Vector2:
	return Vector2(structure.width, structure.depth + structure.porch)

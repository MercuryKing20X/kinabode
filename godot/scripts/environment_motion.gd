class_name EnvironmentMotion
extends RefCounted

# Shared breeze for plants and smoke; entirely presentation, no world writes.
static func wind(time: float, point: Vector2) -> float:
	return sin(time * .72 + point.x * .13 + point.y * .09) * .65 + sin(time * 1.31 + point.y * .21) * .35

static func heat(state: String) -> float:
	if state in ["cooking", "needs_turn"]: return 1.0
	if state in ["ready", "eating"]: return .28
	if state == "embers": return .12
	return 0.0

static func smoke(time: float, index: int, point: Vector2, heat_value: float) -> Dictionary:
	var life := fposmod(time * .28 + index * .173, 1.0)
	return {"offset": Vector2(wind(time - life, point) * life * 24 + life * 18, -75 - life * 95), "size": 22 + life * 38, "alpha": sin(life * PI) * .28 * heat_value}

extends "res://scripts/island_v3_view.gd"
## Render-only copy of existing drawers into an immutable viewport texture.
var mode:="terrain"
var bake_origin:=Vector2.ZERO
func _ready()->void:pass
func _process(_delta:float)->void:pass
func screen(point:Vector2)->Vector2:return ((point-bake_origin)*32).round()
func _draw()->void:
	if mode=="terrain":super._draw_ground(get_viewport_rect())
	elif mode=="farms":farm_renderer.ground(self)
	else:
		for prop in world.catalog.regions.home.layout.art_props:
			if not decor_dynamic(prop):_draw_extra_entry({"type":"v3_prop","value":prop,"y":prop_point(prop).y})
func use_cached_farm_ground()->bool:return false

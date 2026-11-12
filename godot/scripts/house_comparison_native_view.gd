extends "res://scripts/island_view.gd"
## Screenshot-only scale normalization. Original live renderer is never changed.
func _house_size(site:Dictionary)->Vector2:
	if site.has("blueprint"):
		var art:Dictionary=site.blueprint.artwork
		return Vector2(art.width,art.height)
	return Vector2(240,252)

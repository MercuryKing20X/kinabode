extends Node2D
## Child emission pass is unaffected by the parent's self_modulate or weather overlay.
var view_ref:WeakRef
func _draw()->void:
	var view:Node2D=view_ref.get_ref() if view_ref!=null else null
	if view!=null and view.ambience_enabled and view.region_id=="home":view.atmosphere.draw_lights(view,self)

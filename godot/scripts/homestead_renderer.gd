extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
var completed_texture: Texture2D=preload("res://assets/island/homestead-flowerbed.png")
var foundation_texture: Texture2D=preload("res://assets/island/homestead-foundation.png")
func draw(view: Node2D) -> void:
	var system: RefCounted=view.world.homestead
	var rect: Rect2=system.area()
	var screen_rect:=Rect2(view.screen(rect.position),rect.size*32*view.zoom)
	if system.site.progress==0 and not system.completed():
		if system.site.state=="unstarted" and not system.occupancy().is_empty():return
		view.draw_rect(screen_rect,Color("dcd1a477"),false,1.5)
	else:view.draw_texture_rect(preload("res://scripts/flowerbed_visual.gd").texture(not view.world.locations.v3()) if system.completed() else foundation_texture,screen_rect,false)
	var text: String=LocalText.content(system.config.site.name)+" · "+{"unstarted":LocalText.text("ui.homestead_renderer.not_started"),"funding":LocalText.text("ui.homestead_renderer.gathering_materials"),"ready":LocalText.text("ui.homestead_renderer.ready_to_build"),"building":LocalText.text("ui.homestead_renderer.building"),"completed":LocalText.text("ui.homestead_renderer.complete")}[system.site.state]
	if view.has_method("map_label"):
		view.map_label(text,rect.get_center()+Vector2(0,rect.size.y/2+.9));return
	var at: Vector2=view.screen(rect.get_center()+Vector2(0,rect.size.y/2+.8));at.x-=view.font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x/2
	view.draw_string_outline(view.font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,14,3,Color("263e32"))
	view.draw_string(view.font,at,text,HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("fff0cb"))

extends RefCounted

static func position_person_card(g:Node,panel:PanelContainer,id:String,remaining:float,near_player:bool=false)->void:
	var viewport:Vector2=g.get_viewport_rect().size
	var anchor:Vector2=g.view.screen(g.world.point(g.world.actors[id]))
	if near_player:
		var human:Vector2=g.view.screen(g.world.point(g.world.actors.human))
		if g.world.actors.human.region_id==g.world.actors[id].region_id and Rect2(Vector2.ZERO,viewport).has_point(human):anchor=anchor.lerp(human,.45)
	var timer:Label=panel.get_meta("person_timer",null)
	if not is_instance_valid(timer):return
	var outside:bool=not Rect2(Vector2.ZERO,viewport).has_point(anchor)
	timer.text=("◀ " if anchor.x<0 else "▶ " if anchor.x>viewport.x else "↑ " if anchor.y<0 else "↓ " if outside else "")+str(maxi(0,ceili(remaining-g.world.forest.clock)))+" s"
	var bottom:float=viewport.y-12
	if is_instance_valid(g.island_hud.primary_actions) and g.island_hud.primary_actions.is_visible_in_tree():
		bottom=minf(bottom,g.island_hud.primary_actions.global_position.y-12)
	var maximum:=Vector2(maxf(12,viewport.x-panel.size.x-12),maxf(12,bottom-panel.size.y))
	panel.position=(anchor-Vector2(panel.size.x/2,panel.size.y+100*g.view.zoom)).clamp(Vector2(12,12),maximum)
static func announce_person_card(g:Node,panel:PanelContainer,id:String)->void:
	panel.pivot_offset=Vector2(panel.get_combined_minimum_size().x*.5,panel.get_combined_minimum_size().y)
	panel.scale=Vector2(.96,.96)
	var tween:=panel.create_tween()
	tween.tween_property(panel,"scale",Vector2(1.025,1.025),.14).set_trans(Tween.TRANS_SINE)
	tween.tween_property(panel,"scale",Vector2.ONE,.19).set_trans(Tween.TRANS_SINE)
	if is_instance_valid(g.game_audio):g.game_audio.play_event("ui.invite",Vector2.ZERO,"",id,1,.55)

static func style_card(panel:PanelContainer)->void:
	var body:VBoxContainer
	for child in panel.get_children():
		if child is VBoxContainer:body=child;break
	if body==null:return
	body.name="body"
	for child in body.get_children():
		child.set_meta("ui_font_base",24)
		child.add_theme_font_size_override("font_size",preload("res://scripts/ui_scale.gd").pixels(24))
		if child is Button:child.set_meta("ui_scale_min",Vector2(0,45));child.custom_minimum_size.y=preload("res://scripts/ui_scale.gd").pixels(45)
	var timer:=Label.new();timer.name="countdown";timer.set_meta("ui_font_base",24);body.add_child(timer)
	timer.add_theme_color_override("font_color",Color("ffdda3"));timer.add_theme_font_size_override("font_size",preload("res://scripts/ui_scale.gd").pixels(24))
	panel.set_meta("person_timer",timer)

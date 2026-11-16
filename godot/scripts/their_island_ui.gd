extends Node
## Presentation and exact-card host decisions only; World owns routes and building.
const Text=preload("res://scripts/localization.gd")
class PlacementPreview extends Control:
	var world:RefCounted
	var proposal:Dictionary
	func _draw()->void:
		if world==null or proposal.is_empty():return
		var scale_value:float=minf((size.x-24)/210.0,(size.y-24)/180.0)
		var origin:Vector2=(size-Vector2(210,180)*scale_value)/2-Vector2(-19,150)*scale_value
		draw_style_box(_background(),Rect2(Vector2.ZERO,size))
		var cfg:Dictionary=world.catalog.regions.home.layout.homelands
		var land:Array=world.catalog.regions.home.land_extensions[int(cfg.land_index)]
		var points:=PackedVector2Array()
		for p in land:points.append(origin+Vector2(p[0],p[1])*scale_value)
		draw_colored_polygon(points,Color("9aaf87"))
		for object in world.objects.values():
			if object.kind=="construction_site" and world.home_island.contains(world.point(object)):
				draw_rect(Rect2(origin+world.point(object)*scale_value-Vector2(3,3),Vector2(6,6)),Color("82644a"))
		var at:=Vector2(proposal.position[0],proposal.position[1]);var center:Vector2=origin+at*scale_value
		draw_circle(center,8,Color("ffe8a0"));draw_arc(center,11,0,TAU,24,Color("463923"),2)
		draw_line(center-Vector2(15,0),center+Vector2(15,0),Color("463923"),2)
		draw_line(center-Vector2(0,15),center+Vector2(0,15),Color("463923"),2)
	func _background()->StyleBoxFlat:
		var style:=StyleBoxFlat.new();style.bg_color=Color("314e57");style.set_corner_radius_all(8);return style
var game:Node
var button:Button
var card:AcceptDialog
var change_button:Button
var later_button:Button
var material:Label
var error_label:Label
var selected:Dictionary={}
var preferred_actor:=""
func setup(host:Node)->void:
	game=host
	var layer:=CanvasLayer.new();layer.layer=4;add_child(layer)
	button=Button.new();button.position=Vector2(18,318);button.custom_minimum_size=Vector2(150,38);button.add_theme_font_override("font",game.view.font);layer.add_child(button)
	button.pressed.connect(show_next)
func _process(_delta:float)->void:
	if game==null:return
	# Flower Isle retired holiday invitations and courtyard construction.
	if game.world.resort!=null and game.world.resort.enabled():
		button.hide()
		if is_instance_valid(card):_close()
		return
	button.visible=game.world.their_island.ready() and (game.world.home_island.here() or not game.world.their_island.pending.is_empty())
	button.text=(preload("res://scripts/localization.gd").source("content.health_20261107.eafae6117cde") if not TranslationServer.get_locale().begins_with("en") else "Holiday invitations")+" (%s)"%game.world.their_island.pending.size()
	if is_instance_valid(card) and card.visible:_refresh_material()
func _label(parent:Node,value:String)->Label:
	var label:=Label.new();label.text=value;label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;label.add_theme_font_size_override("font_size",16);label.size_flags_horizontal=Control.SIZE_EXPAND_FILL;parent.add_child(label);return label
func _close()->void:
	if is_instance_valid(card):card.queue_free()
	card=null;selected={}
func _refresh_material()->void:
	var id:String=selected.actor_id
	var current:Dictionary=game.world.their_island.pending.get(id,{})
	if current.get("id")!=selected.id:
		card.get_ok_button().disabled=true;error_label.text=Text.text("theirs_ui.stale");return
	if selected.has("activity_id"):
		material.text=preload("res://scripts/localization.gd").source("content.health_20261107.0a3665886fbd") if not TranslationServer.get_locale().begins_with("en") else "Holiday activity · no materials needed"
		return
	var cost:int=preload("res://scripts/leisure_rules.gd").cost(game.world.library.artworks[selected.template_id].recreation)
	var warehouse:int=game.world.storage.count("wood")
	var missing:int=maxi(0,cost-warehouse)
	material.text=Text.text("theirs_ui.materials")%[cost,warehouse]
	if missing>0:material.text+="\n"+Text.text("theirs_ui.missing")%missing
	else:material.text+="\n"+Text.text("theirs_ui.enough")
func show_next()->void:
	if game.world.resort!=null and game.world.resort.enabled():return
	if is_instance_valid(card):card.popup_centered();return
	var system:RefCounted=game.world.their_island
	if system.pending.is_empty():return
	var id:String=preferred_actor if system.pending.has(preferred_actor) else str(system.pending.keys()[0]);selected=system.pending[id].duplicate(true)
	card=AcceptDialog.new();card.title=Text.resident(game.world,id)+" · "+Text.text("theirs.card");card.ok_button_text=Text.text("theirs.accept");card.dialog_hide_on_ok=false;card.min_size=Vector2i(500,460);card.add_theme_font_override("font",game.view.font);game.add_child(card)
	var scroll:=ScrollContainer.new();scroll.custom_minimum_size=Vector2(480,380);scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;card.add_child(scroll)
	var col:=VBoxContainer.new();col.custom_minimum_size.x=480;col.size_flags_horizontal=Control.SIZE_EXPAND_FILL;col.add_theme_constant_override("separation",8);scroll.add_child(col)
	var picker:=OptionButton.new();picker.focus_mode=Control.FOCUS_NONE;col.add_child(picker)
	for actor_id in system.pending:
		picker.add_item(Text.resident(game.world,actor_id));picker.set_item_metadata(picker.item_count-1,actor_id)
		if actor_id==id:picker.select(picker.item_count-1)
	picker.item_selected.connect(func(index):
		preferred_actor=str(picker.get_item_metadata(index));_close();call_deferred("show_next"))
	var row:=HBoxContainer.new();row.add_theme_constant_override("separation",16);col.add_child(row)
	var portrait:=TextureRect.new();portrait.custom_minimum_size=Vector2(80,100);portrait.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;portrait.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture=game.world.library.texture(game.world.actors[id].appearance_id,"down_0");row.add_child(portrait)
	var words:=VBoxContainer.new();words.size_flags_horizontal=Control.SIZE_EXPAND_FILL;row.add_child(words)
	var title:=_label(words,selected.name);title.add_theme_font_size_override("font_size",20)
	_label(words,selected.reason)
	material=_label(col,"");error_label=_label(col,"");error_label.add_theme_color_override("font_color",Color("ba633d"))
	var preview:=PlacementPreview.new();preview.world=game.world;preview.proposal=selected.duplicate(true);preview.custom_minimum_size=Vector2(450,174);col.add_child(preview)
	_label(col,Text.text("theirs_ui.preview")%selected.position)
	later_button=card.add_button(Text.text("theirs.later"),false,"later");change_button=card.add_button(Text.text("theirs.change"),false,"change")
	var bound_id:String=selected.id
	card.confirmed.connect(func():
		var result:Dictionary=system.decide(id,bound_id,"accept")
		if result.ok:_close()
		else:
			error_label.text=Text.text({"insufficient_wood":"theirs_ui.shortage","busy_or_hungry":"theirs_ui.busy","occupied":"theirs_ui.occupied","stale_island_card":"theirs_ui.stale"}.get(str(result.get("error","")),"theirs.rejected"));_refresh_material())
	card.custom_action.connect(func(action):
		var result:Dictionary=system.decide(id,bound_id,action)
		if result.ok:_close()
		else:error_label.text=Text.text("theirs_ui.stale"))
	# Closing only hides this view; the pending proposal remains available.
	card.canceled.connect(_close)
	_refresh_material();card.popup_centered(Vector2i(540,520));card.get_ok_button().grab_focus()

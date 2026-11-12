extends Node
const LocalText=preload("res://scripts/localization.gd")
## Explicit host UI only; no model/action adapter entry points.
var game:Node
var menu:AcceptDialog
var fire_button:Button
var entry_button:Button
var return_button:Button
var hint:Label
var boat_pending:=false
var selected:Array=[]
var walking_party:Array=[]
var crossing_after:=0.0
var last_human:=Vector2.INF
var last_region:=""
var arrival_goal:=Vector2.INF
func setup(host:Node)->void:
	game=host
	LocalText.events.changed.connect(refresh_locale)
	var layer:=CanvasLayer.new();layer.layer=3;add_child(layer)
	fire_button=Button.new();fire_button.set_meta("audio_primary",true);fire_button.text=T("ui.dark.light_button");fire_button.tooltip_text=T("ui.dark.torch_tooltip");fire_button.custom_minimum_size=Vector2(104,40);fire_button.add_theme_font_override("font",game.view.font)
	if game.island_hud!=null:game.island_hud.primary_actions.add_child(fire_button)
	else:layer.add_child(fire_button)
	fire_button.pressed.connect(func():show_result(game.world.dark.light_portable_torch()))
	entry_button=Button.new();entry_button.add_theme_font_override("font",game.view.font);entry_button.text=T("ui.dark.bridge_entry")
	if game.island_hud!=null:game.island_hud.upper_status.add_child(entry_button)
	else:entry_button.position=Vector2(18,98);layer.add_child(entry_button)
	entry_button.pressed.connect(boat_dialog)
	return_button=Button.new();return_button.add_theme_font_override("font",game.view.font);return_button.text=T("ui.dark.return_to_light");return_button.position=Vector2(18,150);layer.add_child(return_button)
	return_button.pressed.connect(func():
		var at:Vector2=game.world.dark.nearest_light()
		if at.is_finite():game.world.command("human",{"intent":"move","x":at.x,"y":at.y}))
	hint=Label.new();hint.add_theme_font_override("font",game.view.font);hint.position=Vector2(18,195);hint.add_theme_color_override("font_color",Color("ffe6a1"));layer.add_child(hint)
func close_menu()->void:
	if is_instance_valid(menu):menu.hide();menu.queue_free()
func panel(title_text:String)->VBoxContainer:
	close_menu();menu=AcceptDialog.new();menu.title=title_text;menu.ok_button_text=T("ui.dark.close");game.add_child(menu)
	preload("res://scripts/invitation_common.gd").style_dialog(menu,game.view.font,game.island_hud.pixel_style() if game.island_hud!=null else null,false)
	var body:=VBoxContainer.new();body.custom_minimum_size.x=280;body.add_theme_constant_override("separation",8);menu.add_child(body)
	menu.close_requested.connect(menu.queue_free);menu.confirmed.connect(menu.queue_free)
	return body
func button(body:Control,text:String,fn:Callable)->void:
	var b:=Button.new();b.focus_mode=Control.FOCUS_NONE;b.text=text;b.custom_minimum_size.y=38;body.add_child(b);b.pressed.connect(fn)
func boat_dialog()->void:
	arrival_goal=Vector2.INF
	var dark:RefCounted=game.world.dark
	var body:=panel(T("ui.dark.return_question") if dark.here() else T("ui.dark.depart_question"))
	var names:=Label.new();names.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;names.custom_minimum_size.x=280
	var checked:Dictionary=dark.allowed_party(selected)
	names.text=T("ui.dark.party")%", ".join(checked.ids.map(func(id):return LocalText.resident(game.world,id))) if not checked.ids.is_empty() else T("ui.dark.bridge_note")
	names.set_meta("party_ids",checked.ids);body.add_child(names)
	if not dark.here():button(body,T("ui.dark.invite"),invite)
	button(body,T("ui.dark.return_home") if dark.here() else T("ui.dark.depart"),func():close_menu();boat_pending=true;approach_boat())
	menu.popup_centered()
func invite()->void:
	var body:=panel(T("ui.dark.invite"))
	var common:Script=preload("res://scripts/invitation_common.gd")
	var all_box:CheckBox=common.add_all(body);var checks:Dictionary={}
	for id in game.world.actors:
		if id=="human" or game.world.actors[id].region_id!="home":continue
		var box:=CheckBox.new();box.focus_mode=Control.FOCUS_NONE;box.text=LocalText.resident(game.world,id);box.set_meta("resident_id",id);box.button_pressed=id in selected;body.add_child(box);checks[id]=box
	common.bind_all(all_box,checks.values())
	button(body,T("ui.dark.confirm_party"),func():
		var checked:Dictionary=game.world.dark.allowed_party(checks.keys().filter(func(id):return checks[id].button_pressed))
		selected=checked.ids;game.status.text=checked.message;boat_dialog())
	menu.popup_centered()
func approach_boat()->void:
	var dark:RefCounted=game.world.dark
	var at:Vector2=dark.p(dark.config.walking_connection.dark_end if dark.here() else dark.config.walking_connection.home_end)
	walking_party=game.world.actors.keys().filter(func(id):return id!="human" and game.world.actors[id].region_id=="dark") if dark.here() else dark.allowed_party(Array(selected)+game.world.activities.following.keys()).ids
	for who in walking_party:game.world.hunger.follow_after[who]=game.world.director.time+600
	game.world.activities.follow_issuing=true
	for index in range(walking_party.size()):
		var id:String=walking_party[index]
		if game.world.director.routines[id].owns_job():game.world.work.stop(id,false)
		game.world.hunger.clear_follow(id)
		game.world.command(id,{"intent":"move","x":at.x+float(index)-1.5,"y":at.y})
	game.world.activities.follow_issuing=false
	var dest:Vector2=at
	var result:Dictionary=game.world.command("human",{"intent":"move","x":dest.x,"y":dest.y})
	if result.ok:game.view.follow_player=true
	else:boat_pending=false;game.status.text=str(result.get("message",result.get("error",T("ui.dark.bridge_unreachable"))))
func sail()->void:
	boat_pending=false
	for who in walking_party:game.world.hunger.follow_after.erase(who)
	crossing_after=game.world.forest.clock+3
	var result:Dictionary=game.world.dark.travel(selected,true)
	if result.ok:
		game.view.show_region(result.region_id);game.view.follow_player=true
		var at:Vector2=arrival_goal if arrival_goal.is_finite() else game.world.dark.p(game.world.dark.config.home_arrival if result.region_id=="home" else game.world.dark.config.arrival)
		arrival_goal=Vector2.INF
		game.world.command("human",{"intent":"move","x":at.x,"y":at.y})
	else:game.status.text=str(result.get("message",result.get("error",T("ui.dark.crossing_unavailable"))))
func handle(id:String,at:Vector2)->bool:
	if not game.world.dark.enabled():return false
	var dark:RefCounted=game.world.dark
	var region:String=game.world.actors.human.region_id
	if game.view.region_id==region and region in ["home","dark"]:
		var other:String="home" if region=="dark" else "dark"
		var current_origin:Array=game.world.catalog.regions[region].origin
		var other_origin:Array=game.world.catalog.regions[other].origin
		var target:Vector2=at+Vector2(current_origin[0]-other_origin[0],current_origin[1]-other_origin[1])
		var beyond:bool=at.y>127.4 if region=="dark" else at.y<1.6
		if beyond and game.world.walkable(other,target):
			arrival_goal=target;close_menu();boat_pending=true;approach_boat();game.view.follow_player=true;return true
	if id!="dark.boat":boat_pending=false;arrival_goal=Vector2.INF
	if id=="dark.boat":game.world.dark.cancel();boat_dialog();return true
	if not game.world.dark.here():return false
	if game.view.region_id!="dark":return false
	boat_pending=false;game.world.dark.cancel()
	if id.begins_with("relic:"):
		var item:Dictionary=game.world.dark.discoveries.config.objects.filter(func(i):return i.id==id.trim_prefix("relic:"))[0]
		show_result(game.world.dark.discoveries.begin(item.id,game.world.dark.p(item.position)));return true
	if id.begins_with("fly-"):
		var flies:Array=game.world.dark.discoveries.fireflies().filter(func(i):return i.id==id)
		if not flies.is_empty():show_result(game.world.dark.discoveries.begin(id,game.world.dark.p(flies[0].position)))
		return true
	if id=="star-seat":
		var body:=panel(T("ui.dark.star_cliff"))
		button(body,T("ui.dark.watch_stars"),func():close_menu();show_result(game.world.dark.discoveries.begin("stars",game.world.dark.p(game.world.dark.discoveries.config.star_seat))))
		menu.popup_centered();return true
	game.world.dark.discoveries.stop_stars()
	if id=="human":game._return_to_player();return true
	if game.world.barbecues.has(id):
		var body:=panel(T("ui.dark.campfire"))
		button(body,T("ui.dark.fireside"),func():close_menu();game._camp_action(id,"panel",at))
		button(body,T("ui.dark.light_torch"),func():close_menu();show_result(game.world.dark.start("torch",game.world.dark.p(game.world.dark.config.camp))))
		menu.popup_centered();return true
	if id.begins_with("dark.beacon."):
		var area:Dictionary=game.world.dark.config.areas.filter(func(a):return a.id==id.trim_prefix("dark.beacon."))[0]
		var body:=panel(T("ui.dark.beacon_title")%LocalText.content(area.name));menu.set_meta("beacon_name",area.name)
		button(body,T("ui.dark.light_beacon"),func():close_menu();show_result(game.world.dark.start("beacon",game.world.dark.p(area.beacon))))
		if area.id in game.world.dark.beacons:button(body,T("ui.dark.light_torch"),func():close_menu();show_result(game.world.dark.start("torch",game.world.dark.p(area.beacon))))
		menu.popup_centered();return true
	if id.begins_with("dark.fire."):
		var fire:Dictionary=game.world.dark.fires[int(id.get_slice(".",2))]
		var body:=panel(T("ui.dark.small_fire"));button(body,T("ui.dark.light_torch"),func():close_menu();show_result(game.world.dark.start("torch",game.world.dark.p(fire.position))));menu.popup_centered();return true
	if game.world.objects.has(id) or game.world.all_mushrooms().has(id) or game.world.drops.has(id):
		var intent:String="forage" if game.world.all_mushrooms().has(id) else "collect" if game.world.drops.has(id) else "chop" if game.world.objects[id].kind=="tree" else "store" if game.world.loaded("human") else "take"
		show_result(game.world.command("human",{"intent":intent,"target_id":id}));return true
	if not game.world.walkable("dark",at):game.status.text=T("ui.dark.blocked");return true
	close_menu();game.world.command("human",{"intent":"stop"})
	var result:Dictionary=game.world.command("human",{"intent":"move","x":at.x,"y":at.y})
	if result.ok and game.view.run_click:game.world.force_human_run()
	show_result(result)
	return true
func relics()->void:
	var body:=panel(T("ui.dark.relics"))
	for item in game.world.dark.discoveries.config.objects:
		if item.id in game.world.dark.discoveries.found:
			var line:=Label.new();line.set_meta("relic_id",item.id);line.text=LocalText.content(item.name)+"\n"+LocalText.content(item.text);line.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;line.custom_minimum_size.x=350;body.add_child(line)
	menu.popup_centered(Vector2i(390,400))
func show_result(result:Dictionary)->void:game.status.text=str(result.get("message",result.get("error","")))
func _process(_delta:float)->void:
	if game==null:return
	var dark:RefCounted=game.world.dark
	var human_at:Vector2=game.world.point(game.world.actors.human)
	var human_region:String=game.world.actors.human.region_id
	var just_walked:bool=last_region==human_region and last_human.is_finite() and human_at.distance_to(last_human)>.0001
	last_human=human_at;last_region=human_region
	var chess_overlay:bool=(game.jieqi_panel!=null and game.jieqi_panel.visible) or (game.gomoku_panel!=null and game.gomoku_panel.card.visible)
	fire_button.visible=not chess_overlay and dark.here() and game.view.visible and game.view.region_id=="dark"
	if game.island_hud!=null:
		game.island_hud.layout_primary_actions()
	var cards_visible:bool=game.island_hud!=null and game.island_hud.notifications.is_visible_in_tree()
	var english_overlay:bool=LocalText.revision().begins_with("en") and [game.journal_panel,game.memory_panel,game.resident_connections,game.fishing_panel,game.island_hud.wardrobe if game.island_hud!=null else null].any(func(panel_node):return panel_node!=null and panel_node.visible)
	var interface_modal:bool=game.island_hud!=null and game.island_hud.scale_manager()!=null and game.island_hud.scale_manager().modal_open()
	entry_button.visible=not interface_modal and not chess_overlay and dark.enabled() and human_region=="home" and game.view.visible and not english_overlay
	return_button.visible=not interface_modal and not chess_overlay and not english_overlay and dark.here() and not dark.permanent(game.world.point(game.world.actors.human)) and not cards_visible
	hint.visible=not interface_modal and not chess_overlay and not english_overlay and dark.here() and dark.torch.remaining>0 and dark.torch.remaining<=float(dark.config.torch_warning_seconds)
	hint.text=T("ui.dark.torch_warning")
	if dark.enabled() and game.world.actors.human.region_id in ["home","dark"] and not boat_pending and just_walked and game.world.forest.clock>=crossing_after:
		var edge:Vector2=dark.p(dark.config.walking_connection.dark_end if dark.here() else dark.config.walking_connection.home_end)
		if game.world.point(game.world.actors.human).distance_to(edge)<.6 and not game.world._routes.has("human"):
			boat_pending=true;approach_boat()
	if boat_pending and not game.world._routes.has("human"):
		var end:Vector2=dark.p(dark.config.walking_connection.dark_end if dark.here() else dark.config.walking_connection.home_end)
		if game.world.point(game.world.actors.human).distance_to(end)>2:boat_pending=false;return
		if walking_party.any(func(id):return game.world._routes.has(id)):return
		if walking_party.any(func(id):return game.world.point(game.world.actors[id]).distance_to(end)>4):boat_pending=false;game.status.text=T("ui.dark.wait_for_party");return
		sail()

var locale_bindings:Dictionary={}
func T(key:String)->String:
	locale_bindings[LocalText.source(key)]=key
	var translated:=LocalText.text(key);locale_bindings[translated]=key;locale_bindings[LocalText.source(key)]=key;locale_bindings[str(LocalText.entries.get(key,{}).get("en",translated))]=key
	return translated
func refresh_locale()->void:
	fire_button.text=T("ui.dark.light_button");fire_button.tooltip_text=T("ui.dark.torch_tooltip")
	entry_button.text=T("ui.dark.bridge_entry")
	_refresh_locale_nodes(self)
	if is_instance_valid(menu):_refresh_locale_nodes(menu)
func _refresh_locale_nodes(node:Node)->void:
	for property in ["text","title","dialog_text","tooltip_text","ok_button_text"]:
		var value:Variant=node.get(property) if node.get_property_list().any(func(p):return p.name==property) else null
		if value is String and locale_bindings.has(value):node.set(property,LocalText.text(locale_bindings[value]))
	if node is Label and node.has_meta("relic_id"):
		for item in game.world.dark.discoveries.config.objects:
			if item.id==node.get_meta("relic_id"):node.text=LocalText.content(item.name)+"\n"+LocalText.content(item.text)
	if node is Label and node.has_meta("party_ids"):
		var ids:Array=node.get_meta("party_ids")
		node.text=T("ui.dark.party")%", ".join(ids.map(func(id):return LocalText.resident(game.world,id))) if not ids.is_empty() else T("ui.dark.bridge_note")
	if node is Button and node.has_meta("resident_id"):node.text=LocalText.resident(game.world,str(node.get_meta("resident_id")))
	if node is Window and node.has_meta("beacon_name"):node.title=T("ui.dark.beacon_title")%LocalText.content(str(node.get_meta("beacon_name")))
	for child in node.get_children():_refresh_locale_nodes(child)

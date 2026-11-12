# DIRECTION 2026-11-07: 烤蘑菇永久无限供应，不扣任何食材；其它食材守恒断言保留。
extends SceneTree
## Integration/UI — production/evidence/barbecue-v4 — BLOCKING binding/input guards.
const CampPanel=preload("res://scripts/fireside_panel.gd")
const Menu=preload("res://scripts/fireside_menu.gd")
const Invitation=preload("res://scripts/fireside_invitation.gd")
var game:Node
var w:RefCounted
var checks:=0
var failed:=false
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failed=true;push_error(message)
func _initialize()->void:call_deferred("run")
func descendants(node:Node)->Array:
	var result:Array=[]
	for child in node.get_children():result.append(child);result.append_array(descendants(child))
	return result
func shown_script(script:Script)->Node:
	for node in game.get_children():
		if node.get_script()==script and not node.is_queued_for_deletion() and node.visible:return node
	return null
func button_named(node:Node,prefix:String)->Button:
	for child in descendants(node):
		if child is Button and child.text.begins_with(prefix) and child.is_visible_in_tree():return child
	return null
func mouse(viewport:Viewport,at:Vector2,pressed:bool)->void:
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=pressed;event.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0;event.position=at;event.global_position=at
	viewport.push_input(event,true)
func click_button(button:Button)->bool:
	if button==null:return false
	await process_frame;await process_frame
	var signal_count:Dictionary={"pressed":0}
	button.pressed.connect(func():signal_count.pressed+=1,CONNECT_ONE_SHOT)
	var at:Vector2=button.get_global_rect().get_center();var viewport:Viewport=button.get_viewport()
	if viewport is Window and viewport.is_embedded():at+=Vector2(viewport.position);viewport=root
	var motion:=InputEventMouseMotion.new();motion.position=at;motion.global_position=at;viewport.push_input(motion,true)
	mouse(viewport,at,true);await process_frame;mouse(viewport,at,false);await process_frame
	if signal_count.pressed!=1:print("B UI input rejected: ",button.text," button_rect=",button.get_global_rect()," viewport=",viewport," size=",viewport.get_visible_rect())
	return signal_count.pressed==1
func map_click(position:Vector2)->void:
	var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=true;event.position=game.view.screen(position);event.global_position=event.position
	game.view._unhandled_input(event)
func step(delta:float=.1)->void:
	w.advance(delta);game.view._process(delta)
func walk_to_camp(life:RefCounted)->bool:
	game.view.follow_player=false;game.view.zoom=1;game.view.center=w.point(life.station)
	var destination:=Vector2.INF
	for angle in range(48):
		var p:Vector2=w.point(life.station)+Vector2.from_angle(angle*TAU/48)*2.9
		if w.walkable("home",p) and game.view.hit(game.view.screen(p)).is_empty():destination=p;break
	if not destination.is_finite():return false
	var before:Vector2=w.point(w.actors.human);map_click(destination)
	if not w._routes.has("human"):print("B map click did not create route: ",destination," hit=",game.view.hit(game.view.screen(destination))," status=",game.status.text);return false
	var safe:=true
	for tick in range(5000):
		step();safe=safe and w.walkable(w.actors.human.region_id,w.point(w.actors.human))
		if not w._routes.has("human"):break
	return safe and w.point(w.actors.human)!=before and w.point(w.actors.human).distance_to(destination)<.01 and life.fireside.near("human",3)
func physical(life:RefCounted)->Dictionary:
	return {"fuel":life.station.fuel_used,"eaten":life.station.meals_eaten,"portions":life.station.portions,"supplies":life.station.supplies.duplicate(true),"current":life.fireside.state.get("current",{}).duplicate(true)}
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"));OS.set_environment("HABITAT_OPENING","legacy")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.view.sound_enabled=false;game.island_hud.set_process(false);w=game.world;w.director.set_all_enabled(false);game.chat.hide()
	await process_frame;await process_frame
	for station_id in ["moon.barbecue","home.barbecue"]:
		var life:RefCounted=w.barbecues[station_id];var other:RefCounted=w.barbecues["home.barbecue" if station_id=="moon.barbecue" else "moon.barbecue"]
		check(walk_to_camp(life),station_id+" actual mouse map input walks host by World route, every frame walkable")
		check(w.nearest_barbecue("human").station.id==station_id,station_id+" nearest-camp resolution follows actual host position")
		var untouched:Dictionary=other.station.duplicate(true);var stock:Dictionary=life.fireside.available();var wood_before:int=int(stock.get("wood",0))
		map_click(w.point(life.station));await process_frame;await process_frame
		var panel:Node=shown_script(CampPanel)
		check(panel!=null and panel.life.station.id==station_id,station_id+" camp map click opens exact station UI")
		if panel==null:continue
		check(await click_button(button_named(panel,"生火")),station_id+" native viewport mouse click emits actual light-button pressed")
		check(life.fireside.burning() and life.station.fuel_used==2 and int(life.fireside.available().get("wood",0))==wood_before-2,station_id+" UI lights this fire and debits two actual wood")
		check(other.station==untouched,station_id+" lighting leaves other station byte-for-byte unchanged without advancing game time")
		var first:Dictionary=game.view.fire_visual(station_id);var revision:int=w.revision;game.view._process(.17);var second:Dictionary=game.view.fire_visual(station_id)
		check(first.burning and second.burning and first.frame!=second.frame and w.revision==revision,station_id+" actual shared renderer state animates flames without world writes")
		step(.7);check(game.view.fire_visual(station_id).ignition==1,station_id+" real point-light ignition advances to full flame")
		var old_physical:Dictionary=physical(other);var mushrooms:int=int(life.fireside.available().get("mushroom",0))
		check(await click_button(button_named(panel,"烧烤")),station_id+" native viewport click opens barbecue menu")
		var invitation:Node=shown_script(Invitation)
		check(invitation!=null and invitation.life.station.id==station_id and invitation.all_box.text=="所有人",station_id+" exact invitation page includes All")
		if invitation==null:continue
		check(await click_button(invitation.all_box) and invitation.selected_ids().size()==4,station_id+" native All input selects all four companions")
		check(await click_button(invitation.get_ok_button()),station_id+" native Next input opens selected fire menu")
		var menu:Node=shown_script(Menu)
		check(menu!=null and menu.life.station.id==station_id,station_id+" menu binds the same station")
		if menu==null:continue
		check(menu.choices[menu.selected].id=="single:mushroom" and not menu.get_property_list().any(func(p):return p.name=="amount"),station_id+" real menu starts with mushroom and no quantity control")
		check(await click_button(menu.start_button),station_id+" native viewport click opens real roasting batch")
		for tick in range(3000):
			step()
			if life.fireside.state.current.get("eaten",0)>=5:break
		check(life.fireside.state.current.get("eaten",0)==5 and life.fireside.state.current.eaters.has("human") and life.station.meals_eaten==5,station_id+" actual cooked food reaches host through real auto-eat jobs")
		check(int(life.fireside.available().get("mushroom",0))==mushrooms and life.fireside.state.current.receipt.is_empty(),station_id+" five mushroom diners consume zero ingredients and grant no inventory")
		check(physical(other)==old_physical,station_id+" other fire keeps its own physical food, receipts, fuel and eater counters")
		life.fireside.end_circle("host ends native UI verification")
	for link in game.links.values():check(link._pid<=0,"UI playthrough launches no model process")
	game.queue_free();await process_frame;print("Camp binding v4: ",checks," checks, failed=",failed);quit(1 if failed else 0)

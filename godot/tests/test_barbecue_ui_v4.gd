extends SceneTree
## Native controller and layout checks for the simplified two-action host flow.
const CampPanel=preload("res://scripts/fireside_panel.gd")
const Invitation=preload("res://scripts/fireside_invitation.gd")
const Menu=preload("res://scripts/fireside_menu.gd")
var game:Node
var w:RefCounted
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func descendants(node:Node)->Array:
	var result:Array=[]
	for child in node.get_children():result.append(child);result.append_array(descendants(child))
	return result
func shown(script:Script)->Node:
	for child in game.get_children():
		if child.get_script()==script and not child.is_queued_for_deletion() and child.visible:return child
	return null
func click(button:Button)->bool:
	if button==null:return false
	await process_frame;await process_frame
	var count:Dictionary={"pressed":0};button.pressed.connect(func():count.pressed+=1,CONNECT_ONE_SHOT)
	var at:Vector2=button.get_global_rect().get_center();var viewport:Viewport=button.get_viewport()
	if viewport is Window and viewport.is_embedded():at+=Vector2(viewport.position);viewport=root
	var motion:=InputEventMouseMotion.new();motion.position=at;motion.global_position=at;viewport.push_input(motion,true)
	for pressed in [true,false]:
		var input:=InputEventMouseButton.new();input.button_index=MOUSE_BUTTON_LEFT;input.pressed=pressed;input.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0;input.position=at;input.global_position=at;viewport.push_input(input,true);await process_frame
	return count.pressed==1
func inventory()->Dictionary:
	return {"actors":w.actors.duplicate(true),"stock":w.life.fireside.available().duplicate(true),"jobs":w.work.jobs.duplicate(true),"routes":w._routes.duplicate(true)}
func visible_text(node:Node)->String:
	var lines:Array=[]
	for child in descendants(node):
		if child is Label or child is Button:lines.append(child.text)
	return "\n".join(lines)
func walk(life:RefCounted)->bool:
	for offset in [Vector2(2.5,0),Vector2(0,2.5),Vector2(-2.5,0),Vector2(0,-2.5)]:
		var p:Vector2=w.point(life.station)+offset
		if not w.walkable("home",p):continue
		if not w.command("human",{"intent":"move","x":p.x,"y":p.y}).ok:continue
		for i in range(4000):
			w.advance(.1)
			if not w._routes.has("human"):return life.fireside.near("human",3)
	return false
func close_windows()->void:
	for child in game.get_children():
		if child.get_script() in [CampPanel,Invitation,Menu]:child.queue_free()
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"));OS.set_environment("HABITAT_OPENING","legacy")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.view.sound_enabled=false;game.island_hud.set_process(false);w=game.world;w.director.set_all_enabled(false)
	await process_frame;await process_frame
	check(not FileAccess.file_exists("res://scripts/cooking_panel.gd") and not FileAccess.file_exists("res://scripts/shared_activity_panel.gd"),"removed panels are physically gone, no hidden legacy instances")
	check(not game.get_property_list().any(func(p):return p.name in ["cooking_panel","shared_activity_panel"]),"Main has no removed panel references")
	check(not visible_text(game.island_hud.resident_card).contains("喂她") and not visible_text(game.action_dock.menu).contains("做菜"),"feeding and independent cooking entries absent")
	for station_id in ["home.barbecue","moon.barbecue"]:
		var life:RefCounted=w.barbecues[station_id]
		check(walk(life),"host uses original World route to "+station_id)
		game._show_barbecue_menu(station_id);await process_frame;await process_frame
		var panel:Node=shown(CampPanel)
		check(panel!=null and panel.life.station.id==station_id,"two-action panel binds exact fire")
		game.island_hud.context_signature="";game.island_hud.refresh_context()
		check(not descendants(game.island_hud.context).any(func(n):return n is Button and n.text in ["营火灶台","月牙营火"]),"built camp construction aliases do not duplicate a third camp button")
		var buttons:Array=descendants(panel.body).filter(func(n):return n is Button)
		check(buttons.size()==2 and panel.roast_button.text=="烧烤" and panel.light_button.text.begins_with("生火"),"camp has only light and barbecue actions")
		var wood_before:int=int(life.fireside.available().get("wood",0))
		check(await click(panel.light_button),"native mouse light input reaches correct controller")
		check(life.fireside.burning() and int(life.fireside.available().get("wood",0))==wood_before-2 and panel.light_button.text.begins_with("续火"),"light changes to renew and debits actual stock")
		var before:Dictionary=inventory()
		check(await click(panel.roast_button),"native barbecue opens invite first")
		var invitation:Node=shown(Invitation)
		check(invitation!=null and invitation.all_box.text=="所有人" and invitation.checks.size()==w.actors.size()-1,"All is above dynamic companion checkboxes")
		check(await click(invitation.all_box) and invitation.selected_ids().size()==invitation.checks.size(),"native All selects every current companion")
		check(inventory()==before,"selection does not move anyone, start jobs or take resources")
		check(await click(invitation.get_ok_button()),"native Next opens restaurant menu")
		var menu:Node=shown(Menu)
		check(menu!=null and menu.life.station.id==station_id,"menu inherits the chosen fire")
		check(inventory()==before,"opening menu after invitation preserves actors and stock")
		var words:String=visible_text(menu)
		check(words.contains("基础烤物") and words.contains("料理") and words.contains("烤蘑菇"),"both restaurant sections retain mushroom first")
		check(not words.contains("份") and not words.contains("打包") and not words.contains("做菜") and not words.contains("喂她") and not descendants(menu).any(func(n):return n is SpinBox),"no serving numbers, spinner, pack, cook or feed controls")
		close_windows();await process_frame
	for dimensions in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=dimensions
		for mode in ["小","标准","大"]:
			game.island_hud.set_interface_size(mode,false)
			var before:Dictionary=inventory()
			game._invite_barbecue("moon.barbecue");await process_frame;await process_frame
			var invitation:Node=shown(Invitation)
			check(invitation.position.x>=0 and invitation.position.y>=0 and invitation.position.x+invitation.size.x<=dimensions.x and invitation.position.y+invitation.size.y<=dimensions.y,"invitation fits "+mode+str(dimensions))
			check(await click(invitation.all_box) and await click(invitation.get_ok_button()),"All and Next remain clickable "+mode+str(dimensions))
			var menu:Node=shown(Menu)
			check(menu!=null and menu.position.x>=0 and menu.position.y>=0 and menu.position.x+menu.size.x<=dimensions.x and menu.position.y+menu.size.y<=dimensions.y,"menu stays inside "+mode+str(dimensions))
			check(menu.scroll.get_v_scroll_bar().max_value>menu.scroll.size.y and menu.start_button.size.x>=180 and menu.start_button.size.y>=42,"scroll and wide roast button remain reachable")
			check(menu.cards.all(func(c):return c.size.x>180 and c.size.x<=menu.scroll.size.x),"grid cards fit available content width")
			check(inventory()==before,"six layout combinations preserve people and inventory")
			close_windows();await process_frame
	var standard=preload("res://tests/standard_fixture.gd").new();standard.start(OS.get_environment("HABITAT_DATA_DIR").path_join("context"))
	var old_world:RefCounted=game.world;game.world=standard.w
	for station_id in ["home.barbecue","moon.barbecue"]:
		# This presentation-only context assertion models an already built config site.
		game.world.leisure.sites[game.world.standard.site_for(station_id)].complete=true
		game.world.actors.human.position=game.world.barbecues[station_id].station.position.duplicate();game.island_hud.context_signature="";game.island_hud.refresh_context()
		var camp_buttons:Array=descendants(game.island_hud.context).filter(func(n):return n is Button)
		check(camp_buttons.size()==2 and camp_buttons.all(func(n):return n.text in ["生火","续火","烧烤"]),"standard built camp has exactly the two fire actions without construction alias")
		for seat in game.world.barbecues[station_id].seats():
			game.world.actors.human.position=seat.position.duplicate();game.island_hud.context_signature="";game.island_hud.refresh_context()
			var seated_buttons:Array=descendants(game.island_hud.context).filter(func(n):return n is Button)
			check(seated_buttons.size()==2 and seated_buttons.all(func(n):return n.text in ["生火","续火","烧烤"]),"all real camp seat positions keep only the two fire actions "+str(seat.id))
	game.world=old_world
	game.queue_free();await process_frame;print("Barbecue UI v4: ",checks," checks, failed=",failed);quit(1 if failed else 0)

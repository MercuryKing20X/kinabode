# DIRECTION 2026-11-11: five added real-fish recipes; retain exact original five, jam lock and no-ingredient-grant proof.
extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
const H=preload("res://tests/homestead_fixture.gd")
const UI=preload("res://tests/barbecue_ui_fixture.gd")
var game: Node
var checks:=0
var failed:=false
var output: String
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failed=true;push_error(label)
func shot(name: String) -> void:
	game.homestead_panel.refresh();game.view._process(.1)
	await process_frame;await process_frame
	if not output.is_empty():await RenderingServer.frame_post_draw
	var bounds:=root.get_visible_rect()
	var panel: Control=game.homestead_panel if game.homestead_panel.visible else null
	if panel!=null:check(bounds.encloses(panel.get_global_rect()),"panel fits "+name)
	check(bounds.encloses(game.resident_connections_button.get_global_rect()),"resident UI preserved "+name)
	if not output.is_empty():root.get_texture().get_image().save_png(output.path_join(name+".png"))
func pair(name: String) -> void:
	root.size=Vector2i(1280,800);await shot(name+"-1280x800")
	root.size=Vector2i(960,640);await shot(name+"-960x640")
func choose_actor(id: String) -> void:
	for index in range(game.homestead_panel.actors.item_count):
		if game.homestead_panel.actors.get_item_metadata(index)==id:game.homestead_panel.actors.select(index);game.homestead_panel.actors.item_selected.emit(index)
func run() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	output=OS.get_environment("HABITAT_HOMESTEAD_CAPTURE_DIR")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	await process_frame
	var world: RefCounted=game.world
	# Non-hungry construction fixture; retain every original material/UI assertion.
	world.hunger.enabled=false
	world.director.set_all_enabled(false);game.view.sound_enabled=false;game.chat.hide();game.chat_input.release_focus()
	game.view.follow_player=false;game.view.center=world.homestead.area().get_center()+Vector2(3,1);game.view.zoom=1.3
	var actors: String=world.memories._canonical(world.actors)
	game._open_homestead("human");await pair("project-panel")
	check(world.memories._canonical(world.actors)==actors and world.work.jobs.is_empty(),"opening and resizing do not move anyone or start work")
	check(game.homestead_panel.start_button.text.contains("我") and game.homestead_panel.build_button.disabled,"explicit human initiation and unfunded construction disabled")
	check(H.stock(world),"controller world uses real chopped wood and harvested crops")
	var human: Array=world.actors.human.position.duplicate()
	game._open_homestead("codex");game.homestead_panel.wood_limit.value=5;game.homestead_panel.crop_limit.value=3
	game.homestead_panel.start_button.pressed.emit();world.advance(.1)
	game._bound_companion_event({"kind":"question","id":"homestead-question","text":"测试提问：先暂停这项工程吗？","choices":["等一下"]},"codex")
	check(not game.homestead_panel.visible and game.chat.visible and world.homestead.plans.codex.status=="paused" and not world.work.jobs.has("codex"),"actual question pauses exact plan and prioritizes chat")
	game._cancel_resident_turn("codex");game.chat.hide();game._open_homestead("codex")
	game.homestead_panel.resume_button.pressed.emit();check(F.wait(world,"codex"),"explicit UI resume completes first batch")
	check(world.homestead.site.delivered.wood==5 and world.homestead.crop_count(world.homestead.site.delivered)==3 and world.actors.human.position==human,"UI contributes exactly five and three without moving human")
	await pair("partial-delivery")
	choose_actor("human")
	check(world.actors.human.position==human and not world.work.jobs.has("human"),"selecting human is read-only")
	game.homestead_panel.wood_limit.value=19;game.homestead_panel.crop_limit.value=7;game.homestead_panel.start_button.pressed.emit()
	check(world.work.jobs.has("human") and F.wait(world,"human") and world.homestead.funded(),"only explicit own UI starts and advances human delivery")
	check(world.homestead.site.contributions.human.wood==19 and world.homestead.site.contributions.codex.wood==5,"two residents retain actual independent contributions")
	game.homestead_panel.refresh();check(not game.homestead_panel.build_button.disabled and not world.homestead.completed(),"funding enables explicit construction, never completes automatically")
	game.homestead_panel.build_button.pressed.emit()
	for tick in range(2000):
		world.advance(.1)
		if world.homestead.site.progress>=1:break
	game.view.center=world.homestead.area().get_center()+Vector2(3,1);game.view.zoom=1.7
	check(world.actors.human.activity=="building" and world.homestead.site.progress>0 and not world.homestead.completed(),"actual worker animates during timed construction")
	await pair("construction")
	check(F.wait(world,"human") and world.homestead.completed(),"real engine construction finishes")
	game.homestead_panel.hide();game.view.center=world.homestead.area().get_center()+Vector2(0,1);game.view.zoom=2.2
	await pair("completed-flowerbed")
	check(not world.walkable("home",world.homestead.area().get_center()),"finished art corresponds to real blocking footprint")
	game._open_homestead("human");game.homestead_panel.refresh();game.homestead_panel.recipe_button.pressed.emit()
	var camp:Node=UI.shown(game,"res://scripts/fireside_panel.gd")
	check(camp!=null and not game.homestead_panel.visible,"unlock routes to sole barbecue entry")
	if camp!=null:
		camp.queue_free();await process_frame
	var menu:=preload("res://scripts/fireside_menu.gd").new();game.add_child(menu);menu.setup(world.life,game.view.font);menu.popup_centered();await process_frame;await process_frame
	check(menu.choices.filter(func(c):return c.category=="dish").size()==32 and ["turnip-soup","roast-pumpkin","tomato-salad","grilled-fish","blueberry-jam"].all(func(id):return menu.choices.any(func(c):return c.id=="recipe:"+id)) and menu.choices.any(func(c):return c.id=="recipe:blueberry-jam" and not c.locked),"actual engineering unlock retains original five within32 authorized fire recipes without granting ingredients")
	check(UI.descendants(menu).any(func(n):return n is Label and n.text.contains("蓝莓")),"jam ingredient text remains reachable in real menu")
	await pair("unlocked-recipe")
	menu.queue_free();await process_frame
	check(H.amount(world,"wood")==24 and H.amount(world,"turnip")==6 and H.amount(world,"pumpkin")==4,"all viewport scenes conserve real invested material")
	check(game.links.values().all(func(connection):return connection._pid==-1),"UI testing launches zero real model processes")
	game.queue_free();await process_frame
	print("Homestead controller: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)

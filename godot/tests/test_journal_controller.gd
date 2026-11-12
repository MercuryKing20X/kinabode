extends SceneTree
const Fish=preload("res://tests/fishing_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
class FakeAdapter extends "res://scripts/companion_link.gd":
	func _start() -> bool:return true
	func _send(_message: Dictionary) -> bool:return true
var game: Node
var output: String
var checks:=0
var failed:=false
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failed=true;push_error(label)
func shot(name: String) -> void:
	await process_frame;await process_frame
	if not output.is_empty():await RenderingServer.frame_post_draw
	var panel: Control=game.journal_panel
	check(Rect2(Vector2.ZERO,root.get_visible_rect().size).encloses(panel.card.get_global_rect()),"journal fits viewport "+name)
	check(panel.grid.columns==4 and panel.grid.get_child_count()==16,"actual color by size cards "+name)
	check(panel.card.get_global_rect().encloses(panel.detail.get_global_rect()),"first catch text remains in book "+name)
	if not output.is_empty():root.get_texture().get_image().save_png(output.path_join(name+".png"))
func run() -> void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	output=OS.get_environment("HABITAT_JOURNAL_CAPTURE_DIR")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	await process_frame
	game.world.director.set_all_enabled(false);game.view.sound_enabled=false;game.world.fishing.rng.seed=101
	for connection in game.links.values():connection.queue_free()
	game.links.clear();game.dialogue_adapter_factory=func(_id,_scope):return FakeAdapter.new()
	game._ensure_link("codex");game.link=game.links.codex
	var world: RefCounted=game.world
	world.hunger.enabled=false # Isolate discovery/read-only ownership across many catches.
	var actors: Dictionary=world.actors.duplicate(true)
	root.size=Vector2i(960,640);game.action_dock.toggle_menu()
	await process_frame;await process_frame
	check(Rect2(Vector2.ZERO,root.get_visible_rect().size).encloses(game.action_dock.menu.get_global_rect()),"actual action menu fits small window")
	check(game.action_dock.menu.get_global_rect().end.y<=game.actions_button.get_global_rect().position.y,"journal entry menu leaves bottom actions usable")
	if not output.is_empty():
		await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(output.path_join("entry-960x640.png"))
	var entry_buttons: Array=game.action_dock.menu.find_children("*","Button",true,false).filter(func(control):return control.text=="鱼图鉴")
	check(entry_buttons.size()==1,"actual functional journal entry exists once")
	if entry_buttons.is_empty():quit(1);return
	entry_buttons[0].pressed.emit();root.size=Vector2i(1280,800)
	check(game.journal_panel.visible and world.actors==actors and world.work.jobs.is_empty(),"journal action opens without moving or controlling anyone")
	check(game.journal_panel.grid.get_children().all(func(tile):return not tile.entry.caught),"empty book never invents caught history")
	await shot("empty-1280x800")
	check(Fish.coast(world,"human"),"player goes to actual sea")
	var first: Dictionary={}
	for i in range(12):
		var caught: Dictionary=Fish.catch_one(world,"human")
		if caught.is_empty():check(false,"viewport real catch");break
		if first.is_empty():first=caught.duplicate(true)
		world.command("human",{"intent":"release_fish","fish_id":caught.id})
	check(not first.is_empty() and world.journal.summary("human").discovered>1,"book populated only from genuine catches including released fish")
	if first.is_empty():quit(1);return
	game.view.follow_player=false;game.view.center=world.point(world.actors.human);game.view.zoom=.7
	var panel: Control=game.journal_panel
	panel.open();panel.progress_labels[first.species_id].pressed.emit()
	var tiles: Array=panel.grid.get_children().filter(func(tile):return tile.entry.first_catch.get("fish_id")==first.id)
	check(tiles.size()==1,"actual first catch has exactly one rendered card")
	if not tiles.is_empty():
		var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;tiles[0]._gui_input(click)
		check(panel.detail.text.contains("第一次亲手钓到") and panel.detail.text.contains(world.fishing.seas[first.source_id].name),"clicking real card shows actual first catch and sea")
	await shot("caught-1280x800")
	root.size=Vector2i(960,640);await shot("caught-960x640")
	var records: Dictionary=world.journal.saved()
	check(Save.save_world(world,directory.path_join("journal")),"real discoveries saved")
	check(Save.load_world(world,directory.path_join("journal")).ok,"real discovery save reopens")
	check(world.memories._canonical(world.journal.saved())==world.memories._canonical(records),"UI save reload retains first catches")
	for i in range(panel.actors.item_count):
		if panel.actors.get_item_metadata(i)=="codex":panel.actors.select(i);panel.actors.item_selected.emit(i)
	check(panel.grid.get_children().all(func(tile):return not tile.entry.caught) and panel.status.text.contains("0种模样"),"viewing another resident shows their own empty book")
	await shot("partner-empty-960x640")
	check(world.command("codex",{"intent":"chop","target_id":"home.tree.01"}).ok,"independent accepted partner job")
	var own: String=world.work.jobs.codex.id
	world.command("codex",{"intent":"journal_read","status":"caught"})
	check(world.work.jobs.codex.id==own,"readonly journal never steals accepted work")
	game._bound_companion_event({"kind":"question","id":"journal-question","text":"测试：先等等吗？","choices":["等等"]},"codex")
	check(not panel.visible and game.chat.visible,"real bound question has visual priority over open journal")
	check(game.links.values().all(func(connection):return connection._pid==-1),"no real model process started")
	game.queue_free();await process_frame
	print("Fish journal controller: %s checks, %s"%[checks,"FAIL" if failed else "PASS"]);quit(1 if failed else 0)

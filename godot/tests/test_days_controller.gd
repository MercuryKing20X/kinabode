extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
const D=preload("res://tests/day_fixture.gd")
const Fish=preload("res://tests/fishing_fixture.gd")
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
func step(delta: float=.1) -> void:game._process(delta);game.view._process(delta);game.day_journal_overlay.refresh()
func shot(name: String) -> void:
	game.action_dock.refresh()
	await process_frame;await process_frame;game.day_journal_overlay.refresh()
	if not output.is_empty():await RenderingServer.frame_post_draw
	var bounds:=Rect2(Vector2.ZERO,root.get_visible_rect().size)
	check(bounds.encloses(game.day_label.get_global_rect()),"day label fits "+name)
	for button in [game.dialogue_button,game.actions_button,game.gathering_button]:check(not button.get_global_rect().intersects(game.day_label.get_global_rect()),"day text never blocks bottom action "+name)
	check(game.day_label.mouse_filter==Control.MOUSE_FILTER_IGNORE,"calendar HUD never consumes input "+name)
	if game.journal_panel.visible:
		var note: Label=game.day_journal_overlay.note
		check(game.journal_panel.card.get_global_rect().encloses(note.get_global_rect()),"today caption fits book "+name)
		check(not note.get_global_rect().intersects(game.journal_panel.actors.get_global_rect()),"today caption does not obscure resident picker "+name)
	if not output.is_empty():root.get_texture().get_image().save_png(output.path_join(name+".png"))
func run() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	output=OS.get_environment("HABITAT_DAYS_CAPTURE_DIR")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	await process_frame
	game.world.director.set_all_enabled(false);game.view.sound_enabled=false
	for connection in game.links.values():connection.queue_free()
	game.links.clear();game.dialogue_adapter_factory=func(_id,_scope):return FakeAdapter.new()
	game._ensure_link("codex");game.link=game.links.codex;game.chat.hide();game.chat_input.release_focus()
	var world: RefCounted=game.world
	world.hunger.enabled=false # Isolate day transitions and the original daily local event.
	var home: Dictionary={"human":world.actors.human.position.duplicate(),"codex":world.actors.codex.position.duplicate()}
	var top_buttons: int=game.stock.get_parent().get_children().filter(func(child):return child is Button).size()
	step(.21);check(game.day_label.text=="有栖 · 世界 · 第1天 · 清晨 · "+world.weather.current().name,"initial noninteractive day HUD")
	await shot("day1-1280x800")
	D.advance_to(world,1499.7);step(.1);check(world.days.day()==1 and game.day_label.text.contains("夜晚"),"night phase changes wording without sleep")
	world.advance(.3);step(.21)
	check(world.days.day()==2 and game.day_label.text=="有栖 · 世界 · 第2天 · 清晨 · "+world.weather.current().name,"day boundary updates persistent HUD")
	check(game.stock.get_parent().get_children().filter(func(child):return child is Button).size()==top_buttons,"calendar adds no top bar buttons")
	root.size=Vector2i(960,640);await shot("day2-960x640")
	world.fishing.rng.seed=101;check(Fish.coast(world,"human"),"real player walk for today's journal evidence")
	var fish: Dictionary=Fish.catch_one(world,"human");check(not fish.is_empty(),"real catch for today badge")
	if fish.is_empty():quit(1);return
	game.journal_panel.open("human");game.journal_panel.progress_labels[fish.species_id].pressed.emit();game.day_journal_overlay.refresh()
	await process_frame;await process_frame;game.day_journal_overlay.refresh()
	var tile: Control=game.journal_panel.grid.get_children().filter(func(control):return control.entry.first_catch.get("fish_id")==fish.id)[0]
	check(tile.get_node("TodayBadge").visible and game.day_journal_overlay.note.text.contains("今日首次1种"),"sidecar marks only actual own combination today")
	var journal: String=world.memories._canonical(world.journal.saved());var revision: String=world.journal.revision("human")
	root.size=Vector2i(1280,800);step(.21);await shot("today-first-1280x800")
	root.size=Vector2i(960,640);await shot("today-first-960x640")
	D.advance_to(world,3001);step(.21);await shot("new-day-journal-960x640")
	check(not tile.get_node("TodayBadge").visible and tile.entry.caught and game.day_journal_overlay.note.text.contains("今日首次0种"),"new day removes only transient badge, permanent card stays caught")
	check(world.memories._canonical(world.journal.saved())==journal and world.journal.revision("human")==revision,"day overlay never mutates journal facts or pagination")
	game.journal_panel.hide();game.action_dock.perform({"intent":"release_fish","fish_id":fish.id},"human");game.action_dock.feedback="";game.action_dock.refresh()
	check(Fish.walk(world,"human",home.human) and Fish.walk(world,"codex",home.codex),"residents return through genuine world routes")
	D.advance_to(world,3181);D.enable_idle(world);step(.1);step(.2)
	check(world.days.small.get("status")=="started" and world.work.jobs.get("codex",{}).get("source")=="local_rules","one actual local cosmetic task starts daily event")
	check(world.actors.codex.activity in ["gesture_wave","gesture_stretch"],"daily animation uses existing engine gesture")
	game.view.follow_player=false;game.view.center=world.point(world.actors.human)+Vector2(0,-1);game.view.zoom=1.1
	root.size=Vector2i(1280,800);await shot("small-event-1280x800")
	root.size=Vector2i(960,640);await shot("small-event-960x640")
	game._bound_companion_event({"kind":"question","id":"daily-question","text":"测试提问：先停一下吗？","choices":["先等等"]},"codex")
	check(world.days.small.status=="interrupted" and not world.work.jobs.has("codex") and game.chat.visible,"exact question interrupts local daily job and shows real dialogue")
	check(world.actors.human.carry.is_empty() and not world.work.jobs.has("human"),"daily scene never acts as host")
	check(game.links.values().all(func(connection):return connection._pid==-1),"zero real model processes or turns")
	game.queue_free();await process_frame
	print("Day cycle controller: %s checks, %s"%[checks,"FAIL" if failed else "PASS"]);quit(1 if failed else 0)

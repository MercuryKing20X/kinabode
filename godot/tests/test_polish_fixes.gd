extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
const Fake=preload("res://tests/test_overnight_autonomy.gd").Fake
var checks:=0
var failed:=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failed=true;push_error(message)
func promise(world: RefCounted) -> Dictionary:
	return world.command("codex",{"intent":"promise","action_type":"come_near","target_id":"human","day":world.days.day()+1,"phase":"morning","valid_seconds":600})
func before_due(world: RefCounted,key: String) -> void:
	world.advance(float(world.promises.entries[key].due_at)-world.forest.clock-1)
func run() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	var game: Node=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false)
	await process_frame
	game.world.director.set_all_enabled(false);game.view.sound_enabled=false;game.chat.hide();game.chat_input.release_focus()
	game.dialogue_adapter_factory=func(_id,_scope):return Fake.new()
	for link in game.links.values():link.queue_free()
	game.links.clear();game._ensure_link("codex");game.link=game.links.codex
	var prefs: RefCounted=game.resident_connections.preferences;prefs.choose("codex","ultra");prefs.enable_autonomy("codex",true)
	var scheduler: RefCounted=game.autonomy.scheduler;scheduler.reset()
	var before: float=scheduler.last_input;var serial: int=scheduler.serial
	var returned:=false
	for frame in range(1800):
		var motion:=InputEventMouseMotion.new();motion.relative=Vector2(1,1);game._input(motion);game._process(1)
		returned=returned or scheduler.queues.get("codex",[]).any(func(event):return event.kind=="player_returned")
	check(not scheduler.input_seen and scheduler.last_input==before and scheduler.serial==serial,"mouse-only 1800 advancing seconds never updates autonomous presence")
	check(not returned and game.links.codex.sent.is_empty() and scheduler.usage("codex").calls==0,"mouse-only creates no player_returned and zero wakes for 30 minutes")
	var click:=InputEventMouseButton.new();click.button_index=MOUSE_BUTTON_LEFT;click.pressed=true;game._input(click)
	check(scheduler.input_seen and scheduler.serial==serial+1,"explicit click remains valid input")
	for frame in range(121):game._process(1)
	before=scheduler.last_input;serial=scheduler.serial
	var motion:=InputEventMouseMotion.new();motion.relative=Vector2(2,1);game._input(motion)
	check(scheduler.last_input==before and scheduler.serial==serial and not scheduler.queues.get("codex",[]).any(func(event):return event.kind=="player_returned"),"motion after prior real input cannot synthesize a return")
	game._input(click)
	check(scheduler.queues.get("codex",[]).any(func(event):return event.kind=="player_returned"),"only real input after absence creates return event")
	game.queue_free();await process_frame
	var world:=F.fresh();var made:=promise(world);before_due(world,made.promise_id)
	check(world.command("codex",{"intent":"gather_wood","tree_count":100}).ok,"real work accepted before appointment")
	var job: String=world.work.jobs.codex.id;world.advance(1.1)
	check(world.promises.entries.has(made.promise_id) and world.work.jobs.get("codex",{}).get("id")==job and world.memories.records.is_empty(),"busy promise waits without failing or preempting accepted work")
	world.advance(5);world.command("codex",{"intent":"stop"});world.advance(24)
	check(not world.work.jobs.has("codex") and world.promises.entries.has(made.promise_id),"retry does not run before 30 seconds")
	world.advance(1.2)
	check(world.work.jobs.get("codex",{}).get("source")=="promise" and F.wait(world,"codex"),"released resident executes at next 30-second retry")
	check(world.memories.records.any(func(entry):return entry.kind=="promise_result" and entry.facts.outcome=="completed"),"retry completion produces only real completion fact")
	world=F.fresh();made=promise(world);before_due(world,made.promise_id);world.command("codex",{"intent":"gather_wood","tree_count":100});world.advance(1.1)
	var elapsed:=0.0
	while elapsed<421:
		world.advance(30);elapsed+=30
	check(not world.promises.entries.has(made.promise_id) and world.memories.records.any(func(entry):return entry.kind=="promise_result" and entry.facts.outcome=="failed"),"busy window expires at phase end, not the next phase or fabricated completion")
	# Build actual crop -> meal -> consumed portions -> cleanup memory, then open the real panel.
	world=F.fresh()
	check(F.harvest(world,"turnip") and F.serve(world,"turnip-soup") and F.eat(world,"human") and F.eat(world,"codex") and F.eat(world,"codex") and F.cleanup(world),"genuine cooking generates a meal memory")
	var meal: Array=world.memories.records.filter(func(entry):return entry.kind=="shared_barbecue")
	check(not meal.is_empty() and not meal[0].facts.has("overlapped_with"),"cooked meal really lacks optional legacy overlap field")
	var panel:=preload("res://scripts/memory_panel.gd").new();root.add_child(panel);panel.setup(world);panel.open()
	if not meal.is_empty():panel.show_memory(meal[0].id)
	check(panel.details.get_parsed_text().contains("参与") and not panel.chosen_id.is_empty(),"actual cooked meal opens safely in memory detail")
	panel.queue_free();await process_frame
	print("Polish fixes: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)

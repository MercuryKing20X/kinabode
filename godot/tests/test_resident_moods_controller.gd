extends SceneTree
const MF=preload("res://tests/resident_mood_fixture.gd")
const F=preload("res://tests/cooking_fixture.gd")
var game: Node
var checks:=0
var failed:=false
var output: String
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failed=true;push_error(label)
func step(delta: float=.1) -> void:game._process(delta);game.view._process(delta)
func advance(seconds: float) -> void:
	for tick in range(int(ceil(seconds/.1))):game.world.advance(.1)
	game.view._process(seconds)
func input() -> void:
	var event:=InputEventMouseMotion.new();event.relative=Vector2(1,0);game._input(event)
func shot(name: String) -> void:
	game.resident_connections.refresh();await process_frame;await process_frame
	if not output.is_empty():await RenderingServer.frame_post_draw
	check(root.get_visible_rect().encloses(game.resident_connections.get_global_rect()),"existing resident page fits "+name)
	check(game.resident_connections.activity.text.contains(game.world.director.moods.summary("codex").name),"derived mood visible without another button or bar "+name)
	if not output.is_empty():root.get_texture().get_image().save_png(output.path_join(name+".png"))
func pair(name: String) -> void:
	root.size=Vector2i(1280,800);await shot(name+"-1280x800")
	root.size=Vector2i(960,640);await shot(name+"-960x640")
func show_line(expected: String) -> void:
	MF.idle(game.world);game.view.clear_local_speech("codex");game.world.director.speech_after=0
	step()
	check(game.world.director.moods.summary("codex").id==expected,"derived state "+expected)
	check(game.view.speech_by_actor.get("codex",{}).get("text") in game.world.personality.pool("codex",expected if expected!="calm" else "ambient") and game.view.speech_by_actor.codex.source=="local_rules","actual local bubble comes from "+expected+" pool")
func run() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	output=OS.get_environment("HABITAT_MOODS_CAPTURE_DIR")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	await process_frame
	var world: RefCounted=game.world;world.director.set_all_enabled(false);game.view.sound_enabled=false;game.chat.hide();game.chat_input.release_focus()
	# Keep this mood probe independent of the authorised hunger exception.
	# Hunger mood/abandonment have separate real-time coverage.
	world.hunger.enabled=false
	# Keep separate memory/day features from occupying this feature's viewport opportunity.
	world.director.memory_reminders.config.first_after=86400
	game.view.follow_player=false;game.view.center=world.point(world.actors.human)+Vector2(2,-1);game.view.zoom=1.3
	game.resident_connections.open("codex");show_line("calm");await pair("calm")
	world.director.set_all_enabled(false)
	check(MF.shared_meal(world),"actual host meal invitation, preparation, eating and cleanup")
	input();advance(2.2)
	game.view.center=world.point(world.actors.human)+Vector2(2,-1)
	show_line("happy");await pair("happy-after-meal")
	check(world.director.moods.last_input==world.director.time-.1-2.2 or is_equal_approx(world.director.moods.last_input,world.director.time-2.3),"physical mouse input, not automatic world updates, resets inactivity")
	world.director.set_all_enabled(false);advance(1202)
	show_line("quiet");await pair("quiet-no-input")
	input();advance(16)
	check(world.director.moods.summary("codex").id=="quiet" and world.director.moods.summary("codex").reason=="夜晚","night is derived from existing day projection after player returns")
	world.director.set_all_enabled(false)
	# Route smoothing makes the smallest house finish before the unchanged tired
	# threshold. Select the existing larger blueprint in this disposable fixture
	# so the same real-work/no-human-control assertions still exercise fatigue.
	assert(world.select_blueprint("home.house.01","cottage-large").ok)
	# The large fatigue fixture needs more than the post-2026-11-05 yield
	# available in its original work zone. Supply only the genuine deficit
	# from another grove before taking the no-human-control snapshot.
	var cost:int=0
	for amount in world.work.stage_costs(world.objects["home.house.01"]):cost+=int(amount)
	var potential:int=world.storage.count("wood")
	for tree in world.objects.values():
		if tree.kind=="tree" and tree.status=="mature" and tree.get("zone_id","")=="home.forest":potential+=int(world.forest.settings.large_wood if int(tree.wood_yield)>8 else world.forest.settings.normal_wood)
	var required_stock:int=world.storage.count("wood")+maxi(0,cost-potential)
	var human_start:Vector2=world.point(world.actors.human)
	for tree in world.objects.values():
		if world.storage.count("wood")>=required_stock:break
		if tree.kind!="tree" or tree.status!="mature" or tree.region_id!="home" or tree.get("zone_id","")=="home.forest":continue
		check(F.job(world,"human",{"intent":"chop","target_id":tree.id}),"host gathers real extra-grove material for large fatigue fixture")
	check(world.storage.count("wood")>=required_stock and F.job(world,"human",{"intent":"move","x":human_start.x,"y":human_start.y}),"real fixture funding and host return complete")
	var human: Dictionary=world.actors.human.duplicate(true)
	check(world.command("codex",{"intent":"build_house","target_id":"home.house.01"}).ok,"explicit construction starts regardless of quiet mood")
	for tick in range(20000):
		world.advance(.1)
		if world.director.moods.summary("codex").id=="tired" and world.work.jobs.has("codex"):break
	game.view.center=world.point(world.actors.codex)+Vector2(1,-1);game.view._process(181);step()
	check(world.director.moods.summary("codex").id=="tired" and world.projects.active("codex"),"tired state visible while authorized work continues")
	await pair("tired-working")
	for tick in range(20000):
		world.advance(.1)
		if world.projects.plans.codex.status=="completed":break
	check(world.projects.plans.codex.status=="completed" and world.actors.human==human,"completed real task without moving human")
	if not world.actors.codex.carry.is_empty():check(F.job(world,"codex",{"intent":"store","target_id":"home.chest.01"}),"surplus physically stored before idle")
	check(F.job(world,"codex",{"intent":"come_near"}),"explicit host social action returns partner near player")
	game.view.center=world.point(world.actors.human)+Vector2(2,-1);game.view._process(100)
	show_line("tired");await pair("tired-idle")
	game._bound_companion_event({"kind":"question","id":"mood-held","text":"等你回答后再继续聊。","choices":["稍等"]},"codex");step()
	check(world.director.routines.codex.held and game.chat.visible and game.view.speech_by_actor.get("codex",{}).get("source")=="model","real pending question wins over mood speech")
	check(game.links.values().all(func(connection):return connection._pid==-1),"no model process started")
	check(game.resident_connections.preferences.preference("codex").runtime_active==false,"Ultra/frontend model settings unchanged")
	game.queue_free();await process_frame
	print("Resident moods controller: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)

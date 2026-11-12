extends SceneTree
const Places=preload("res://scripts/map_locations.gd")
const Fixture=preload("res://tests/fishing_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
const World=preload("res://scripts/world_state.gd")
var game: Node
var checks:=0
var failed:=false
var output:=""
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failed=true;push_error(label)
func step(delta: float=.1) -> void:
	game._process(delta);game.view._process(delta)
func shot(name: String) -> void:
	game.action_dock.refresh()
	if output.is_empty():return
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var bounds:=Rect2(Vector2.ZERO,root.get_visible_rect().size)
	if game.action_dock.strip.visible:
		check(bounds.encloses(game.action_dock.strip.get_global_rect()),"compact frame fits "+name)
		check(game.action_dock.strip.size.y<160 and game.action_dock.strip.size.x<380,"compact dimensions "+name)
	if game.action_dock.reopen_button.visible:check(bounds.encloses(game.action_dock.reopen_button.get_global_rect()),"reopen entry fits "+name)
	root.get_texture().get_image().save_png(output.path_join(name+".png"))
func run() -> void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	output=OS.get_environment("HABITAT_FISHING_CAPTURE_DIR")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false)
	await process_frame
	game.chat.hide();game.chat_input.release_focus();game.view.sound_enabled=false
	var world: RefCounted=game.world
	world.director.set_all_enabled(false);world.fishing.rng.seed=101;world.fishing.life.rng.seed=11
	check(world.error.is_empty() and not world.fishing.life.config.is_empty(),"fishing/life config loads")
	var options: Array=world.fishing.coast_points.duplicate()
	options.sort_custom(func(a,b):return Vector2(a.position[0],a.position[1]).distance_squared_to(Places.point("p_52_10"))<Vector2(b.position[0],b.position[1]).distance_squared_to(Places.point("p_52_10")))
	check(Fixture.walk(world,"human",options[0].position),"host walks to real shore")
	world.director.routines.codex.set_enabled(true);world.director.routines["companion-2"].set_enabled(true)
	var invitation: Dictionary=world.fishing.invite_host(["codex","companion-2"])
	check(invitation.accepted.size()==2,"two partners own separate real fishing jobs")
	if invitation.accepted.size()!=2:quit(1);return
	game.view.center=world.point(world.actors.human)+Vector2(0,-4);game.view.zoom=.73
	var first: String=invitation.accepted[0];var second: String=invitation.accepted[1]
	for tick in range(1500):
		step()
		if world.work.jobs.get(first,{}).get("phase")=="fish_cast" and world.work.jobs[first].time>.8:break
	var job: Dictionary=world.work.jobs[first]
	var origin:=Vector2(job.position[0],job.position[1]);var hook:=Vector2(job.hook[0],job.hook[1])
	check(origin.distance_to(hook)>=world.fishing.rules.cast_min,"cast reaches distant water")
	check(world.fishing._ocean("home",hook),"cast avoids enclosures and land")
	var entered:=false
	for i in range(1,int(origin.distance_to(hook)*4)):
		var at: Vector2=origin.lerp(hook,float(i)/(origin.distance_to(hook)*4))
		if world.fishing._ocean("home",at):entered=true
		elif entered:check(false,"cast never crosses land/net after reaching ocean");break
	var geometry: Dictionary=game.view.fishing_renderer.rod_geometry(game.view,world.actors[first])
	check(not geometry.is_empty() and geometry.hand.distance_to(geometry.tip)>60*game.view.zoom,"rod has a real grip and independent length")
	await shot("cast")
	for i in range(100):step()
	check(world.fishing.fish.is_empty(),"not an instant ten-second catch")
	var seen: Dictionary={};var bubble_seen:=false
	for tick in range(1300):
		step()
		for event in world.director.events:
			if str(event.get("context","")).begins_with("fishing_"):bubble_seen=true
		var phase: String=world.work.jobs.get(first,{}).get("phase","")
		var reaction: Dictionary=world.fishing.life.presentation(first)
		if phase=="fish_wait" and not seen.has("wait"):
			seen.wait=true;await shot("wait")
		if reaction.get("kind")=="nibble" and not seen.has("nibble"):
			seen.nibble=true;await shot("nibble")
		if phase in ["fish_bite","fish_reel"] and not seen.has(phase):
			seen[phase]=true;await shot(phase)
		if not world.fishing.held(first).is_empty() and not world.fishing.held(second).is_empty():break
	check(seen.has("nibble") and seen.has("fish_bite") and seen.has("fish_reel"),"actual task has touches, bite and retrieval")
	check(bubble_seen,"local-life dialogue exists without any model turn")
	check(not world.fishing.held(first).is_empty() and not world.fishing.held(second).is_empty(),"both partners actually catch fish")
	game.action_dock.choose(first);game.action_dock.feedback="";game.action_dock.refresh()
	check(game.action_dock.summary.text.contains("2条待安置"),"UI counts both real catches")
	await shot("two-catches")
	root.size=Vector2i(960,640);await shot("small-two-catches")
	game.action_dock.toggle_targets();await shot("small-destinations");game.action_dock.toggle_targets()
	root.size=Vector2i(1280,800)
	check(Save.save_world(world,directory.path_join("two-held")),"two real catches save")
	var restored:=World.new();check(Save.load_world(restored,directory.path_join("two-held")).ok and restored.fishing.pending(first).size()==1 and restored.fishing.pending(second).size()==1,"reload retains both real fish without tasks")
	game.action_dock.dismissed=true;game.action_dock.refresh()
	check(game.action_dock.reopen_button.visible and not game.action_dock.strip.visible,"closing keeps a visible pending entry")
	await shot("collapsed")
	game.action_dock.reopen_button.pressed.emit()
	check(game.action_dock.strip.visible,"pending entry restores the small frame")
	var first_fish: Dictionary=world.fishing.held(first);var other_fish: Dictionary=world.fishing.held(second)
	check(game.action_dock.perform({"intent":"release_fish","fish_id":first_fish.id},first).ok,"release first actual fish")
	check(game.action_dock.actor_id()==second and game.action_dock.strip.visible and game.action_dock.stock_button.visible and world.fishing.held(second).id==other_fish.id,"releasing first keeps second fish and switches usable UI")
	await shot("remaining-catch")
	check(not game.action_dock.perform({"intent":"release_fish","fish_id":other_fish.id},first).ok,"UI action cannot release another resident's fish")
	game.action_dock.choose(second);game.action_dock.feedback="";game.action_dock.refresh()
	var own: Array=world.actors[second].position.duplicate()
	check(game.action_dock.perform({"intent":"stock_fish","fish_id":other_fish.id,"pen_id":"home.fishery.east"},second).ok and world.actors[second].position==own,"last fish enters selected pen without moving character")
	check(world.fishing.fish.size()==1,"release plus stock conserves remaining fish")
	# Authored reactions obey quiet/chat priority and cannot issue another task.
	world.director.routines[first].set_chatter(false)
	var before: int=world.director.serial
	world.fishing.life.trigger(first,"wait")
	check(world.director.serial==before,"local chatter switch suppresses task-side dialogue")
	world.director.routines[first].set_held(true)
	check(world.fishing.life.presentation(first).is_empty(),"real conversation suppresses local reaction")
	world.director.routines[first].set_held(false)
	world.command(first,{"intent":"stop"});world.fishing.life.trigger(first,"wait")
	check(world.fishing.life.presentation(first).is_empty() and world.fishing.life.replies.all(func(reply):return reply.actor_id!=first and reply.target_id!=first),"stop clears local response queue and quiets reaction")
	check(world.work.jobs.is_empty(),"local reactions never restart fishing")
	check(game.links.values().all(func(link):return link._pid==-1 and not link.is_busy()),"no real model turn or process was created")
	# Four actual coast directions; movement and casting remain real commands.
	world.director.set_all_enabled(false)
	var directions: Dictionary={}
	for target in world.fishing.coast_points:
		var normal:=Vector2(target.hook[0]-target.position[0],target.hook[1]-target.position[1])
		var facing: String=game.view.motion.direction(normal)
		if not directions.has(facing):directions[facing]=target
	check(directions.size()==4,"catalog supplies all four natural cast directions")
	for facing in directions:
		check(Fixture.walk(world,"human",directions[facing].position) and world.command("human",{"intent":"fish"}).ok,"real cast "+facing)
		for i in range(13):step()
		game.view.center=world.point(world.actors.human)+Vector2(0,-3);game.view.zoom=.74
		check(not game.view.fishing_renderer.rod_geometry(game.view,world.actors.human).is_empty(),"directional hand/rod geometry "+facing)
		await shot("cast-"+facing)
		world.command("human",{"intent":"stop"})
	root.size=Vector2i(960,640);await shot("small")
	game.queue_free();await process_frame
	print("Fishing experience: %s checks, %s"%[checks,"FAIL" if failed else "PASS"]);quit(1 if failed else 0)

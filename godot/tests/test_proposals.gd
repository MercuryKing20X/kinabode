extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
var checks:=0
var failed:=false
var game: Node
func _initialize() -> void:call_deferred("run")
func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok:failed=true;push_error(text)
func args(text: String="一起煮点汤吧") -> Dictionary:return {"intent":"propose","text":text,"activity":"cook_together","target_id":"turnip-soup","ttl_seconds":300}
func shot(size: Vector2i,output: String) -> void:
	root.size=size;await process_frame;await process_frame
	check(root.get_visible_rect().encloses(game.proposal_panel.get_global_rect()),"edge card panel fits "+str(size))
	if not output.is_empty():
		await RenderingServer.frame_post_draw
		var image:=root.get_texture().get_image();check(image.get_size()==size,"viewport dimensions "+str(size));image.save_png(output.path_join("proposals-%dx%d.png"%[size.x,size.y]))
func run() -> void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	var world:=F.fresh();var human: Dictionary=world.actors.human.duplicate(true)
	check(world.command("codex",{"intent":"chop","target_id":"home.tree.01"}).ok,"real work starts before proposal")
	var job: Dictionary=world.work.jobs.codex.duplicate(true)
	var made: Dictionary=world.command("codex",args());world.advance(.1)
	check(made.ok and world.work.jobs.codex.id==job.id and world.actors.human==human,"proposing never pauses work or acts as human")
	check(not world.command("codex",args()).ok and world.proposals.cards.size()==1,"one concurrent proposal per resident")
	var bad:=args();bad["actor_id"]="human"
	check(not world.command("codex",bad).ok and not world.command("human",args()).ok,"no actor override or human model proposal")
	bad=args("字".repeat(41));check(not world.command("companion-2",bad).ok,"text bound enforced")
	bad=args();bad.ttl_seconds=601;check(not world.command("companion-2",bad).ok,"expiry at most ten minutes")
	bad=args();bad.activity="move_human";check(not world.command("companion-2",bad).ok,"arbitrary suggested actions rejected")
	bad=args();bad.target_id="missing";check(not world.command("companion-2",bad).ok,"unknown target rejected")
	check(world.memories.records.is_empty(),"creating card does not invent a shared experience")
	check(world.proposals.respond_host(made.proposal_id,false).ok,"explicit decline accepted")
	check(world.work.jobs.codex.id==job.id and world.actors.human==human and world.memories.records.size()==1 and world.memories.records[0].facts.decision=="declined","decline only records true two-person decision, no penalty or interruption")
	check(not world.proposals.respond_host(made.proposal_id,true,func(_card):return {"ok":true}).ok,"already decided card cannot be replayed")
	check(world.memories.valid_saved(world.memories.saved(),world.actors,world.world_id),"new canonical kind passes full validator")
	world.command("codex",{"intent":"stop"});world.advance(601)
	made=world.command("codex",args());check(made.ok,"proposal cooldown equals medium autonomy cooldown")
	world.advance(301);check(world.proposals.cards.is_empty() and world.memories.records.size()==1,"expired card disappears without a fake refusal memory")
	check(Save.save_world(world,directory.path_join("facts")),"save schema7 decision fact")
	var loaded:=F.fresh();check(Save.load_world(loaded,directory.path_join("facts")).ok and loaded.memories.records.size()==1,"old schema7 extended facts reload, no phantom card")
	check(world.memories.MARK_LIMIT==192 and world.memories.capacity==256,"direct decision commits do not expand marks or diary capacity")
	# Actual explicit UI acceptance starts existing real cooking work, with real harvest.
	game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	await process_frame
	game.world.director.set_all_enabled(false);game.view.sound_enabled=false;game.chat.hide();game.chat_input.release_focus()
	game.world.hunger.enabled=false # Non-hungry suggestion acceptance; preserve real source/consumption checks.
	check(F.harvest(game.world,"turnip"),"real harvest funds accepted suggestion")
	check(preload("res://tests/barbecue_fixture.gd").approach(game.world),"host explicitly approaches camp before accepting meal suggestion")
	var before:Dictionary=game.world.actors.human.duplicate(true)
	made=game.world.command("codex",args());game._process(.1)
	check(made.ok and game.proposal_panel.visible and not game.world.work.jobs.has("codex"),"UI shows proposal before executing anything")
	var output:=OS.get_environment("HABITAT_OVERNIGHT_CAPTURE_DIR")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	for size in [Vector2i(1280,800),Vector2i(960,640)]:await shot(size,output)
	game.proposal_panel.responded.emit(made.proposal_id,true)
	check(not game.world.work.jobs.has("codex") and game.get_children().any(func(n):return n.get_script()==preload("res://scripts/fireside_invitation.gd") and n.visible),"accept opens real invitation menu without executing recipe or controlling human")
	check(game.world.actors.human==before,"accept cooking does not secretly move the invited human")
	check(game.world.memories.records.any(func(entry):return entry.kind=="proposal_decision" and entry.facts.decision=="accepted" and entry.participants.size()==2),"accepted choice recorded, never claimed completed meal")
	check(F.amount(game.world,"turnip")==3 and game.world.work.jobs.is_empty(),"accepted menu is not a completed meal and consumes no food")
	check(game.links.values().all(func(connection):return connection._pid==-1),"suggestion path creates zero model processes")
	game.memory_panel.open()
	game.queue_free();await process_frame
	print("Proposals: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)

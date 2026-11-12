extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
var checks:=0
var failed:=false
var directory: String
func _initialize() -> void:call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failed=true;push_error(message)
func near(world: RefCounted,id: String,target: String) -> bool:
	var p: Vector2=world.point(world.actors[target])
	for offset in [Vector2(2,0),Vector2(-2,0),Vector2(0,2),Vector2(0,-2)]:
		if world.walkable(world.actors[target].region_id,p+offset) and F.job(world,id,{"intent":"move","x":p.x+offset.x,"y":p.y+offset.y}):return true
	return false
func step(world: RefCounted,seconds: float) -> void:
	for frame in range(int(ceil(seconds/.2))):world.advance(.2)
func prepare(world: RefCounted) -> bool:
	if not F.harvest(world,"turnip") or not F.withdraw(world,"human","turnip") or not near(world,"codex","human"):return false
	for count in [1,2]:
		if not world.command("human",{"intent":"give","receiver_id":"codex","item_id":"turnip","quantity":count}).ok:return false
		step(world,1)
	# Gifts are retained on their recipient; grow separate real cooking ingredients for the host.
	if not F.harvest(world,"turnip"):return false
	return F.serve(world,"turnip-soup","",["human","codex","npc.mira"]) and F.eat(world,"human") and F.eat(world,"codex") and F.eat(world,"npc.mira") and F.cleanup(world) and preload("res://tests/local_life2_fixture.gd").shared_catch(world)
func run() -> void:
	directory=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	var world:=F.fresh()
	check(world.relationships.summary("codex").name=="初识" and world.relationships.states.is_empty(),"fresh world has no invented progress")
	step(world,120);check(world.relationships.states.is_empty(),"idle time alone grants no relationship")
	check(prepare(world),"real harvest, explicit gifts and completed shared cooking")
	step(world,1)
	check(world.relationships.index("codex")==1 and world.relationships.summary("codex").name=="熟悉","real meal and actual gifts reach configured familiar stage")
	check(world.relationships.states.codex.counts.gift==1,"two distinct actual gifts share one daily type allowance")
	check(world.relationships.index("npc.mira")==0 and world.relationships.states["npc.mira"].counts.shared_barbecue==1 and not world.relationships.states.has("companion-2"),"actual eater gets own progress, invited/absent others do not")
	var before: Dictionary=world.relationships.saved();step(world,20)
	check(world.relationships.saved()==before,"same retained facts cannot be counted every advancing frame")
	var context: Dictionary=world.autonomy_context("codex");context.self.relationship.name="tampered"
	check(world.relationships.summary("codex").name=="熟悉" and JSON.stringify(world.autonomy_context("codex")).to_utf8_buffer().size()<=4096,"bounded context exposes deep-copy stage, not numeric bar")
	check(Save.save_world(world,directory.path_join("legacy")),"save real experience before local stage event")
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("legacy/island-v2.json")));data.erase("relationships")
	var file:=FileAccess.open(directory.path_join("legacy/island-v2.json"),FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close()
	var loaded:=F.fresh();check(Save.load_world(loaded,directory.path_join("legacy")).ok,"old optional-field-less save loads")
	step(loaded,20);check(loaded.relationships.states.is_empty() and loaded.relationships.index("codex")==0,"old facts baseline does not backfill free progress")
	var human: Dictionary=world.actors.human.duplicate(true)
	var r: RefCounted=world.director.routines.codex;r.set_enabled(true);r.set_chatter(false)
	for key in r.preferences.weights:r.preferences.weights[key]=0
	step(world,80);check(not world.memories.records.any(func(entry):return entry.kind=="relationship_stage"),"chatter-off prevents stage speech/event")
	r.set_chatter(true);r.set_held(true);step(world,80)
	check(not world.memories.records.any(func(entry):return entry.kind=="relationship_stage"),"held prevents stage event")
	r.set_held(false);check(near(world,"codex","human"),"explicit QA route brings actual resident back near player")
	world.command("codex",{"intent":"stop"});step(world,119)
	check(not world.memories.records.any(func(entry):return entry.kind=="relationship_stage"),"stop quiet period cannot be bypassed by relationship")
	step(world,180)
	var memories: Array=world.memories.records.filter(func(entry):return entry.kind=="relationship_stage")
	if memories.is_empty():print("STAGE_DEBUG ",r.state()," time ",r.time," next ",r.next_decision," speech ",r.next_speech," group ",world.director.speech_after," quiet ",world.fishing.life.quiet_until," available ",world.relationships.available("codex")," enabled ",world.relationships.config.stage_events_enabled," point ",world.point(world.actors.codex)," human ",world.point(world.actors.human)," relation ",world.relationships.states.codex)
	check(memories.size()==1 and memories[0].facts.stage_id=="familiar","one idle actual local stage greeting writes one truthful fact")
	check(world.director.events.any(func(event):return event.source=="local_rules" and event.context=="relationship_stage"),"stage speech uses shared local_rules outlet")
	check(world.actors.human==human and world.actors["npc.mira"].carry.is_empty(),"local progression never controls human or gives NPC inventory")
	step(world,200);check(world.memories.records.filter(func(entry):return entry.kind=="relationship_stage").size()==1,"stage event only once")
	check(Save.save_world(world,directory.path_join("progress")),"save announced stage")
	loaded=F.fresh();check(Save.load_world(loaded,directory.path_join("progress")).ok,"reload persisted relationship")
	step(loaded,20);check(loaded.relationships.index("codex")==1 and loaded.relationships.states.codex.announced==1,"reload preserves independent stage and once-only announcement")
	check(world.memories.valid_saved(world.memories.saved(),world.actors,world.world_id),"new kind follows existing strict memory bounds")
	var invalid: Dictionary=world.relationships.saved();invalid.states.codex.stage=4
	check(not world.relationships.valid_saved(invalid,world.actors),"unearned saved stage rejected")
	world=F.fresh()
	var fish_fixture=preload("res://tests/fishing_fixture.gd")
	check(fish_fixture.coast(world,"human") and near(world,"codex","human"),"actual sea positions before catch")
	var fish: Dictionary=fish_fixture.catch_one(world,"human");step(world,1)
	check(not fish.is_empty() and world.relationships.states.codex.counts.fishing==1 and not world.relationships.states.has("companion-2"),"real catch companions credit only actual human/resident presence")
	world=F.fresh()
	var homestead_fixture=preload("res://tests/homestead_fixture.gd")
	check(homestead_fixture.stock(world) and homestead_fixture.deliver(world,"human",5,0) and homestead_fixture.deliver(world,"codex",19,10) and homestead_fixture.build(world,"codex"),"real mixed two-contributor homestead completion")
	step(world,1)
	check(world.relationships.states.codex.counts.homestead_completed==1 and not world.relationships.states.has("npc.nora"),"homestead grants only true human co-contributor pair")
	check(not world.relationships.valid_config({}) and world.relationships.valid_config(world.relationships.config),"bounded content validation rejects malformed config")
	print("Relationships: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)

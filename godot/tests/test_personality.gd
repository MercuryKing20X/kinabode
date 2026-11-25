extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
var checks:=0
var failed:=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok:failed=true;push_error(text)
func step(world: RefCounted,seconds: float) -> void:
	for tick in range(int(ceil(seconds/.5))):world.advance(.5)
func near(world: RefCounted) -> bool:
	var offsets: Array=[Vector2(2,0),Vector2(-2,0),Vector2(0,2),Vector2(0,-2)];var at:=0
	var p: Vector2=world.point(world.actors.human)
	for id in world.director.routines:
		var target: Vector2=p+offsets[at];at+=1
		if not F.job(world,id,{"intent":"move","x":target.x,"y":target.y}):return false
	return true
func rain(world: RefCounted) -> void:
	for candidate in range(1000):
		world.weather.weather_seed=candidate
		if world.weather.current().id=="rain":return
func enable(world: RefCounted) -> void:
	world.days.config.greeting_after=world.days.day_seconds+1;world.days.config.small_after=world.days.day_seconds+1
	for r in world.director.routines.values():
		world.activities.default_follow_excluded[r.ID]=true # Isolate authored reaction selection from following.
		r.set_enabled(true);r.set_chatter(true)
		for key in r.preferences.weights:r.preferences.weights[key]=0
func run() -> void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	var world:=F.fresh();check(world.error.is_empty() and world.personality.valid_config(world.personality.config),"four bounded authored personality configurations")
	check(world.actors.values().filter(func(actor):return actor.controller=="model").size()>=2 and world.actors.values().filter(func(actor):return actor.controller=="local").size()>=2,"same data keeps two model and two local identities")
	var tags: Dictionary={}
	for id in world.director.routines:tags[world.personality.tag(id)]=true
	check(tags.size()==4,"four configured identities have independent traits without name/provider branches")
	for context in ["meal","giant","rain"]:
		var pools: Dictionary={}
		for id in world.director.routines:
			var lines: Array=world.personality.pool(id,context);pools[JSON.stringify(lines)]=true
			check(lines.size()>=4,"authored common event pool has at least four lines "+context+id)
		check(pools.size()==4,"same true event selects four distinct personality pools "+context)
	check(near(world),"all four actually move into same scene using existing World routes")
	rain(world);enable(world);var human: Dictionary=world.actors.human.duplicate(true)
	var captured: Dictionary={}
	for frame in range(1200):
		world.advance(.5)
		for event in world.director.events:
			if event.context=="personality_rain":
				captured[event.actor_id]=event.duplicate(true);world.director.routines[event.actor_id].set_chatter(false)
		if captured.size()==4:break
	var reactions: Array=captured.values()
	var speakers: Dictionary={}
	for event in reactions:
		speakers[event.actor_id]=true;check(event.text in world.personality.pool(event.actor_id,"rain") and event.source=="local_rules","visible actual weather reaction uses own local pool")
	check(speakers.size()==4,"two model/two local all visibly react to the same actual rain")
	check(world.actors.human==human and world.work.jobs.is_empty() and world.actors.values().all(func(actor):return actor.carry.is_empty()),"personality reaction never moves human, steals work or creates materials")
	var context: Dictionary=world.autonomy_context("codex");context.self.personality.name="fake"
	check(world.personality.summary("codex").name!="fake" and JSON.stringify(world.autonomy_context("codex")).to_utf8_buffer().size()<=4096,"bounded deep-copy personality context")
	# One hour, genuinely advancing. Count delivered outlet events, not attempted lines.
	world=F.fresh();check(near(world),"one-hour repeat probe uses real positions")
	enable(world);var serial:=0;var counts: Dictionary={};var total:=0;var source_ok:=true
	for tick in range(7200):
		world.advance(.5)
		for event in world.director.events:
			if event.serial<=serial:continue
			serial=event.serial;var key: String=event.actor_id+":"+event.text
			counts[key]=int(counts.get(key,0))+1;total+=1;source_ok=source_ok and event.source=="local_rules"
	check(total>=60 and counts.values().all(func(value):return int(value)<=2),"one-hour actual delivered lines never repeat more than twice, not achieved by silencing everyone")
	check(source_ok and world.actors.human==human,"one-hour local-only scene preserves human")
	check(Save.save_world(world,directory.path_join("reactions")),"save existing real world with no personality-history fields")
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("reactions/island-v2.json")))
	check(not data.has("personality") and data.schema_version==7,"traits stay content and reaction/de-dup observation stays memory, no new persistent invented history")
	var r: RefCounted=world.director.routines.codex;r.set_held(true);var before: int=world.director.serial;step(world,20)
	check(not world.personality.try_event("codex") and world.director.serial>=before,"held cannot be bypassed by personality")
	# A real shared meal after accelerated growth is still a new observed fact.
	world=F.fresh();check(F.harvest(world,"turnip") and F.serve(world,"turnip-soup") and F.eat(world,"human") and F.eat(world,"codex") and F.eat(world,"codex") and F.cleanup(world),"real meal for factual personality reaction")
	step(world,2)
	check(world.personality.factual("codex").get("context")=="meal" and world.personality.factual("companion-2").get("context")!="meal","only actual eaters get meal reaction after real advance")
	world.personality.reset();check(world.personality.factual("codex").get("context")!="meal","reload baseline does not replay old meal as just happened")
	# Predict a deterministic seed through unchanged weighted draws, then perform a real giant catch.
	world=F.fresh();var fish_fixture=preload("res://tests/fishing_fixture.gd")
	check(fish_fixture.coast(world,"human") and F.job(world,"codex",{"intent":"come_near"}),"true coastal presence before giant fish")
	for candidate in range(1000):
		world.fishing.rng.seed=candidate
		var wait: Dictionary=world.fishing._pick(world.fishing.rules.waits);world.fishing.rng.randf_range(wait.min,wait.max)
		world.fishing._pick(world.fishing.rules.species);world.fishing._pick(world.fishing.rules.colors)
		if world.fishing._pick(world.fishing.rules.sizes).id=="giant":world.fishing.rng.seed=candidate;break
	var caught: Dictionary=fish_fixture.catch_one(world,"human");step(world,2)
	check(caught.get("size_id")=="giant" and world.personality.factual("codex").get("context")=="giant","real stock-debited giant seen by nearby companion selects giant pool")
	check(world.personality.factual("npc.mira").get("context")!="giant","absent companion cannot claim seeing that fish")
	world.memories.records.clear();check(world.personality.factual("codex").get("context")!="giant","evicted canonical fish is never revived through old source stream")
	for condition in ["chatter","held","pending","assembly","stop","work"]:
		world=F.fresh();rain(world);enable(world);r=world.director.routines.codex
		check(world.personality.factual("codex").get("context")=="rain","genuine available rain candidate before guard "+condition)
		match condition:
			"chatter":r.set_chatter(false)
			"held":r.set_held(true)
			"pending":world.activities.held["codex"]=true
			"assembly":world.activities.gather()
			"stop":world.command("codex",{"intent":"stop"})
			"work":check(world.command("codex",{"intent":"gather_wood","tree_count":1}).ok,"actual accepted work before local reaction")
		step(world,2)
		check(not world.personality.try_event("codex") and not world.director.events.any(func(event):return event.actor_id=="codex" and event.context.begins_with("personality_")),"personality obeys original gate "+condition)
	print("Personality: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)

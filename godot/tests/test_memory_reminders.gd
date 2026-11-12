extends SceneTree
const W=preload("res://scripts/world_state.gd")
const S=preload("res://scripts/save_store.gd")
const M=preload("res://tests/memory_fixture.gd")
const F=preload("res://tests/cooking_fixture.gd")
const Fish=preload("res://tests/fishing_fixture.gd")
var checks:=0
var failed:=false
var directory: String
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failed=true;push_error(label)
func idle(world: RefCounted,id: String="codex") -> void:
	world.director.set_all_enabled(false)
	# C: isolate idle reminders from the independently tested default-follow route.
	world.activities.default_follow_excluded[id]=true
	# Isolate the existing reminder contract from independently tested new stage announcements.
	world.relationships.config.stage_events_enabled=false
	world.days.config.small_after=world.days.day_seconds+1;world.days.config.greeting_after=world.days.day_seconds+1
	var routine: RefCounted=world.director.routines[id]
	routine.set_enabled(true);routine.chatter=true;routine.next_speech=0;routine.next_decision=0;routine.last_walk=0
	for key in routine.preferences.weights:routine.preferences.weights[key]=0
	var reminders: RefCounted=world.director.memory_reminders
	reminders.config.first_after=0;reminders.config.min_age=0;reminders.config.personal_gap=.5;reminders.config.village_gap=.5;reminders.config.check_interval=.1
func setup(world: RefCounted,part: String) -> ConfigFile:
	var path:=directory.path_join(part).path_join("local-life.cfg");DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var settings:=ConfigFile.new();settings.load(path);world.director.memory_reminders.setup(settings,path);return settings
func load_real() -> RefCounted:
	var world:=W.new();world.residents.provision(world)
	world.library=preload("res://scripts/character_library.gd").new();world.library.configure(directory.path_join("fixture-art"))
	check(S.load_world(world,directory.path_join("real")).ok,"load genuine shared history")
	return world
func notices(world: RefCounted) -> Array:return world.director.events.filter(func(event):return event.context=="memory_reminder")
func run() -> void:
	directory=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	var real:=W.new();check(M.populate(real,directory),"genuine construction, seating and finished barbecue")
	check(Fish.walk(real,"human",[51,44]) and Fish.walk(real,"codex",[53,44]),"real movement brings both home before idle tests")
	check(S.save_world(real,directory.path_join("real")),"save real fixture, no invented memory entries")
	var world:=load_real();var settings:=setup(world,"once");idle(world)
	var reminders: RefCounted=world.director.memory_reminders;reminders.config.kinds=["house_completed"]
	var facts: Dictionary=world.memories.saved();var human: Dictionary=world.actors.human.duplicate(true)
	world.advance(.1)
	check(notices(world).size()==1 and notices(world)[0].source=="local_rules","actual idle tick emits one local reminder")
	check(notices(world)[0].text.contains("盖好") and reminders.history("codex").size()==1,"real contributed house fact marked only after durable write")
	world.advance(2);world.advance(2)
	check(notices(world).size()==1,"same canonical memory never repeated after cooldown")
	check(world.memories.saved()==facts and world.actors.human==human and world.work.jobs.is_empty(),"speech does not alter memories, human, jobs or inventory")
	check(S.save_world(world,directory.path_join("resume")),"save after reminder without schema changes")
	var restored:=W.new();restored.residents.provision(restored);check(S.load_world(restored,directory.path_join("resume")).ok,"reload genuine world")
	setup(restored,"once");idle(restored);restored.director.memory_reminders.config.kinds=["house_completed"]
	restored.advance(3);restored.advance(3)
	check(notices(restored).is_empty() and restored.director.memory_reminders.history("codex").size()==1,"cfg survives restart and prevents repeated reminder")
	settings.set_value("resident:codex","chatter",false);settings.save(reminders.path)
	var cfg:=ConfigFile.new();cfg.load(reminders.path)
	check(cfg.get_value(reminders.section("codex"),"mentioned")==reminders.history("codex") and cfg.get_value("resident:codex","chatter")==false,"shared ConfigFile preserves marks when ordinary toggles are saved")
	var empty:=F.fresh();setup(empty,"empty");idle(empty);empty.advance(3)
	check(notices(empty).is_empty() and empty.director.memory_reminders.history("codex").is_empty(),"no canonical memories means no reminder or invented history")
	world=load_real();setup(world,"identity");idle(world,"companion-2");world.director.memory_reminders.config.kinds=["house_completed"]
	check(Fish.walk(world,"companion-2",[53,44]),"nonparticipant comes near by real route")
	world.advance(40);world.advance(1)
	check(notices(world).is_empty(),"others' real house memory cannot become this actor's experience")
	guards();kinds();eviction();failures();spacing()
	print("Memory reminders: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
func guards() -> void:
	# DIRECTION 2026-11-10: 没接 AI 时，本地伙伴不再主动提起记忆。
	# Keep positive model-controller coverage and all original guard assertions.
	for condition in ["disabled","chatter","held","pending","quiet","personal","village","too_new","local"]:
		var guarded:=load_real();setup(guarded,"guard-"+condition);idle(guarded)
		var guarded_reminders: RefCounted=guarded.director.memory_reminders;guarded_reminders.config.kinds=["house_completed"]
		var routine: RefCounted=guarded.director.routines.codex
		match condition:
			"disabled":routine.set_enabled(false)
			"local":guarded.actors.codex.controller="local"
			"chatter":routine.chatter=false
			"held":guarded.director.set_held("codex",true)
			"pending":guarded.activities.held["codex"]=true
			"quiet":guarded.command("codex",{"intent":"stop"})
			"personal":routine.next_speech=routine.time+10
			"village":guarded.director.speech_after=guarded.director.time+10
			"too_new":guarded_reminders.config.min_age=86400
		guarded.advance(.1)
		check(notices(guarded).is_empty() and guarded_reminders.history("codex").is_empty(),"guard preserves unsaid memory: "+condition)
	var world:=load_real();setup(world,"guards");idle(world);var reminders: RefCounted=world.director.memory_reminders
	reminders.config.kinds=["house_completed"]
	check(world.activities.gather().ok,"real assembly begins")
	world.advance(1);check(notices(world).is_empty(),"assembly blocks reminiscing")
	world.activities.dismiss();idle(world)
	check(world.command("codex",{"intent":"gather_wood","tree_count":1}).ok,"real task starts")
	var job: Dictionary=world.work.jobs.codex.duplicate(true);world.advance(.1)
	check(notices(world).is_empty() and world.work.jobs.codex.id==job.id,"real work continues without speech or task takeover")
	world.command("codex",{"intent":"stop"});world.advance(119)
	check(notices(world).is_empty(),"all 120 seconds after stop remain quiet")
	for tick in range(1200):
		world.advance(.1)
		if not notices(world).is_empty():break
	check(notices(world).size()==1,"eligible remembered experience still available after blockers expire")
func kinds() -> void:
	var world:=load_real();setup(world,"kinds");idle(world);var reminders: RefCounted=world.director.memory_reminders
	check(world.memories.records.any(func(entry):return entry.kind=="shared_barbecue" and not reminders.text_for("codex",entry).is_empty()),"actual shared completed barbecue has truthful template")
	check(world.memories.records.filter(func(entry):return entry.kind=="meal").all(func(entry):return reminders.text_for("codex",entry).is_empty()),"completed barbecue portions do not repeat its whole activity")
	world.director.set_all_enabled(false)
	check(F.harvest(world,"turnip") and F.serve(world,"turnip-soup","",["human","codex","companion-2"]) and F.eat(world,"human") and F.eat(world,"codex") and F.eat(world,"companion-2") and F.cleanup(world),"genuine cooked meal and cleanup for exact eater facts")
	var meal:Dictionary=world.memories.records.filter(func(entry):return entry.kind=="shared_barbecue" and entry.facts.get("foods",{}).get("codex",[]).any(func(food):return food.food_id=="turnip-soup"))[0]
	check(not reminders.text_for("codex",meal).is_empty() and reminders.text_for("npc.mira",meal).is_empty(),"only actual recipe eaters recall true shared-barbecue event")
	world.director.set_all_enabled(false);world.fishing.rng.seed=23
	check(Fish.coast(world,"codex"),"real walk to catch sea fish")
	var large: Dictionary={};var small: Dictionary={}
	for attempt in range(12):
		var fish: Dictionary=Fish.catch_one(world,"codex")
		if fish.is_empty():break
		var entry: Dictionary=world.memories.records.filter(func(record):return record.kind=="fishing_catch" and record.facts.fish_id==fish.id)[0]
		if fish.scale>=2:large=entry
		else:small=entry
		world.command("codex",{"intent":"release_fish","fish_id":fish.id})
		if not large.is_empty() and not small.is_empty():break
	check(not large.is_empty() and not small.is_empty(),"real seeded catches contain large and person-sized fish")
	if not large.is_empty():check(reminders.text_for("codex",large).contains("我上次") and reminders.text_for("companion-2",large).is_empty(),"only catcher recalls large fish, never guesses current ownership")
	if not small.is_empty():check(reminders.text_for("codex",small).is_empty(),"person-sized fish omitted by configured scale threshold")
	check(F.job(world,"codex",{"intent":"gather_wood","tree_count":10}) and F.job(world,"codex",{"intent":"build_facility","target_id":"play.gomoku"}),"actual table built from real wood")
	check(world.gomoku.begin_host("play.gomoku","codex",true,"local","normal").ok,"host explicitly starts shared chess")
	for tick in range(2000):
		world.advance(.1)
		if world.gomoku.sessions["play.gomoku"].phase=="playing":break
	var game: Dictionary=world.gomoku.sessions["play.gomoku"]
	check(world.command("human",{"intent":"gomoku_move","site_id":game.site_id,"match_id":game.id,"revision":game.revision,"x":7,"y":7}).ok,"real first chess move")
	check(world.command("human",{"intent":"gomoku_resign","site_id":game.site_id,"match_id":game.id,"revision":game.revision}).ok,"real explicit resignation finishes match")
	world.advance(.1)
	var match_entries: Array=world.memories.records.filter(func(entry):return entry.kind=="gomoku_match")
	check(match_entries.size()==1 and not reminders.text_for("codex",match_entries[0]).is_empty() and reminders.text_for("companion-2",match_entries[0]).is_empty(),"only actual chess participants recall a finished played match")
func eviction() -> void:
	var world:=load_real();setup(world,"evicted");idle(world);var reminders: RefCounted=world.director.memory_reminders;reminders.config.kinds=["house_completed"]
	check(world.projects.memories.size()==1,"genuine original house source still exists")
	world.memories.capacity=1;world.memories.records=world.memories.records.slice(-1)
	world.memories.sync();world.advance(2)
	check(notices(world).is_empty(),"evicted canonical house fact never read back from old source list")
func failures() -> void:
	var world:=load_real();var settings:=setup(world,"failure");idle(world);var reminders: RefCounted=world.director.memory_reminders
	reminders.config.kinds=["house_completed"];var path: String=reminders.path;reminders.path=directory
	world.advance(.1)
	check(notices(world).is_empty() and reminders.history("codex").is_empty(),"failed cfg write does not speak or consume memory")
	reminders.path=path;reminders.checks_after.clear();world.director.routines.codex.next_decision=0
	settings.set_value(reminders.section("codex"),"mentioned",["bad-id"]);world.advance(.1)
	check(notices(world).is_empty(),"invalid dedupe metadata fails closed without inventing history")
func spacing() -> void:
	var world:=load_real();world.director.set_all_enabled(false)
	check(Fish.walk(world,"companion-2",[55,44]),"second actual participant walks near player before speech test")
	setup(world,"spacing");idle(world)
	var reminders: RefCounted=world.director.memory_reminders
	reminders.config.personal_gap=10;reminders.config.village_gap=5;reminders.config.kinds=["shared_barbecue"]
	world.activities.default_follow_excluded["companion-2"]=true # Same isolated idle contract for the second speaker.
	var other: RefCounted=world.director.routines["companion-2"];other.set_enabled(true);other.chatter=true;other.next_speech=0;other.next_decision=0;other.last_walk=0
	for key in other.preferences.weights:other.preferences.weights[key]=0
	world.advance(.1)
	check(notices(world).size()==1 and notices(world)[0].actor_id=="codex","shared outlet prevents simultaneous village reminders")
	world.advance(1)
	check(reminders.history("companion-2").is_empty(),"village cooldown does not consume another resident's eligible fact")
	check(S.save_world(world,directory.path_join("spacing-world")),"save during persisted reminder cooldown")
	var restored:=W.new();restored.residents.provision(restored);check(S.load_world(restored,directory.path_join("spacing-world")).ok,"reload during cooldown")
	setup(restored,"spacing");idle(restored);restored.advance(.1)
	check(notices(restored).is_empty(),"persisted personal and village cooldowns survive restart despite fresh routine clocks")
	world.director.routines.codex.set_enabled(false);world.advance(6);other.next_speech=0;world.advance(.1)
	check(notices(world).size()==2 and notices(world)[1].actor_id=="companion-2","another true participant can recall own memory after village cooldown")
	check(Fish.walk(world,"companion-2",[65,44]),"participant walks out of configured near-player range")
	other.next_speech=0;reminders.checks_after.clear();world.advance(10)
	check(notices(world).size()==2,"far-away participant never speaks a memory at player")

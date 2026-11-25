extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
const D=preload("res://tests/day_fixture.gd")
const Fish=preload("res://tests/fishing_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
var checks:=0
var failed:=false
var directory: String
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failed=true;push_error(label)
func copy(world: RefCounted,name: String) -> RefCounted:
	check(Save.save_world(world,directory.path_join(name)),"save "+name)
	var next:=F.fresh();var result: Dictionary=Save.load_world(next,directory.path_join(name));check(result.ok,"load "+name+str(result));next.director.set_all_enabled(false);return next
func run() -> void:
	directory=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	clock_tests();small_tests();today_tests();offline_tests()
	print("Day cycle: %s checks, %s"%[checks,"FAIL" if failed else "PASS"]);quit(1 if failed else 0)
func clock_tests() -> void:
	var world:=F.fresh()
	check(world.error.is_empty() and world.days.day()==1 and world.days.phase().id=="morning","new world starts day1 with valid fixed content")
	var origin: float=world.days.origin
	world.farms.advance(3000);world.fishing.advance(3000)
	check(world.days.day()==1 and world.days.origin==origin,"resource and job durations cannot advance calendar authority")
	world.advance(1499)
	check(world.days.day()==1 and world.days.phase().id=="night","real World advance approaches next day")
	world.advance(1)
	check(world.days.day()==2 and world.days.phase().id=="morning","exact 1500 seconds boundary")
	var observation: Dictionary=world.observe("human")
	check(observation.day.day==2 and not observation.day.has("elapsed") and not observation.day.has("clock"),"stable lightweight day summary has no drifting timers")
	world=copy(world,"day2")
	check(world.days.day()==2 and world.days.origin==origin and world.work.jobs.is_empty(),"reload preserves origin and day, starts no jobs")
	world.advance(1500*3+450)
	check(world.days.day()==5 and world.days.phase().id=="afternoon" and world.days.small.is_empty(),"multi-day advance has no forced rewards or missed small events")
	var data: Dictionary=world.days.saved();data.day_seconds=0
	check(not world.days.valid_saved(data,world.actors,world.forest.clock),"reject invalid period")
	data=world.days.saved();data.origin=world.forest.clock+1
	check(not world.days.valid_saved(data,world.actors,world.forest.clock),"reject future origin")
	data=world.days.saved();data.marked_day=999999999
	check(not world.days.valid_saved(data,world.actors,world.forest.clock),"reject future daily bucket")
	check(Save.save_world(world,directory.path_join("legacy")),"temporary old format source")
	var legacy: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("legacy/island-v2.json")));legacy.erase("day_cycle")
	Fish.write_json(directory.path_join("legacy/island-v2.json"),legacy)
	var old:=F.fresh();check(Save.load_world(old,directory.path_join("legacy")).ok,"schema7 missing optional day field loads")
	check(old.days.day()==1 and absf(old.days.origin-old.forest.clock)<.0011 and old.days.first_today.is_empty() and old.days.small.is_empty(),"old world begins day1 now, no invented daily content")
	legacy["day_cycle"]={"version":1}
	Fish.write_json(directory.path_join("bad/island-v2.json"),legacy)
	var rejected: Dictionary=Save.load_world(F.fresh(),directory.path_join("bad"))
	check(not rejected.ok and FileAccess.file_exists(rejected.get("backup","")),"bad calendar preserves recoverable save")
func small_tests() -> void:
	var world:=F.fresh();var host: Dictionary=world.actors.human.duplicate(true)
	var stocks: Dictionary=world.farms.containers.duplicate(true);var materials:=F.amount(world,"wood")
	world.advance(181)
	check(world.days.small.is_empty(),"disabled local activity cannot trigger daily small event")
	D.enable_idle(world)
	world.director.routines.codex.set_chatter(false);world.advance(.1)
	check(world.days.small.is_empty(),"chatter setting suppresses authored daily event")
	world.director.routines.codex.set_chatter(true);world.director.routines.codex.set_held(true);world.advance(.1)
	check(world.days.small.is_empty(),"pending conversation wins over daily behavior")
	world.director.routines.codex.set_held(false);world.director.routines.codex.next_speech=0;world.director.routines.codex.next_decision=1e12
	world.advance(.1)
	check(world.days.small.get("status")=="started" and world.work.jobs.get("codex",{}).get("source")=="local_rules","one accepted engine gesture starts daily small event")
	var event_id: String=world.days.small.id
	check(world.actors.human==host and world.farms.containers==stocks and F.amount(world,"wood")==materials,"daily gesture never moves/acts as human or creates/consumes resources")
	check(world.director.events.any(func(event):return event.context=="daily_small" and event.source=="local_rules"),"daily authored line is explicitly local rules")
	world=copy(world,"daily-started")
	check(world.days.small.status=="interrupted" and world.work.jobs.is_empty() and world.days.owned_job_id.is_empty(),"reload incomplete small event interrupted without auto resume")
	D.enable_idle(world);world.advance(.1)
	check(world.days.small.id==event_id and world.work.jobs.is_empty(),"same-day reload cannot replay consumed small event opportunity")
	world.director.set_all_enabled(false);D.advance_to(world,1501)
	D.enable_idle(world);D.advance_to(world,1681)
	for i in range(1200):
		if not world.days.small.is_empty():break
		world.advance(.1)
	check(world.days.day()==2 and world.days.small.get("status")=="started" and world.days.small.id!=event_id,"new day can have one fresh small event")
	var second_id: String=world.days.small.id
	for i in range(22):world.advance(.1)
	check(world.days.small.status=="completed" and world.work.jobs.is_empty(),"actual gesture completion marks daily event completed")
	world.director.routines.codex.next_speech=0;world.director.speech_after=0
	for i in range(100):world.advance(.1)
	check(world.days.small.id==second_id and world.work.jobs.is_empty(),"no second small action on same day")
	world=copy(world,"daily-completed");check(world.days.small.status=="completed","completion survives reload")
	# Explicit work preempts only this local job; daily cancellation never stops replacement work.
	world=F.fresh();world.advance(181);D.enable_idle(world);world.advance(.1)
	check(world.days.small.get("status")=="started","start cancelable cosmetic event")
	check(world.command("codex",{"intent":"chop","target_id":"home.tree.01"}).ok,"explicit real work preempts local gesture")
	var owned: String=world.work.jobs.codex.id
	world.days.interrupt("codex")
	check(world.work.jobs.codex.id==owned and world.days.small.status=="interrupted","old daily ownership cannot cancel new accepted work")
	world.command("codex",{"intent":"stop"})
	world=F.fresh();world.advance(1499);D.enable_idle(world);world.command("codex",{"intent":"stop"});world.advance(1)
	check(world.days.day()==2 and not world.days.eligible("codex"),"crossing day boundary does not bypass stop quiet period")
	world=F.fresh();world.advance(31);D.enable_idle(world);world.advance(.1)
	check(world.days.spoken==["morning"] and world.director.events.any(func(event):return event.context=="day_phase_morning"),"phase greeting uses actual calendar and local speech outlet")
	var phase_count: int=world.director.events.filter(func(event):return event.context=="day_phase_morning").size();world.director.routines.codex.next_speech=0;world.director.speech_after=0;world.advance(.1)
	check(world.director.events.filter(func(event):return event.context=="day_phase_morning").size()==phase_count,"same phase greeting never repeats")
	world=copy(world,"greeting");D.enable_idle(world);world.advance(.1)
	check(not world.director.events.any(func(event):return event.context=="day_phase_morning"),"greeting is not replayed on same-day reload")
func today_tests() -> void:
	var world:=F.fresh();world.fishing.rng.seed=101
	check(Fish.coast(world,"human"),"real sea arrival for today-first")
	check(world.command("human",{"intent":"fish"}).ok,"actual cast")
	world.advance(3);world.command("human",{"intent":"stop"});world.advance(1)
	check(world.days.first_today.is_empty() and world.journal.discoveries.is_empty(),"canceled cast never becomes today-first or permanent discovery")
	# Save RNG before cast to repeat the same genuine combination on the next day.
	var rng_state: int=world.fishing.rng.state
	var fish: Dictionary=Fish.catch_one(world,"human");check(not fish.is_empty(),"first actual catch")
	if fish.is_empty():return
	var combination: String=world.journal.key(fish.species_id,fish.color_id,fish.size_id)
	check(world.days.today("human",combination).fish_id==fish.id and world.days.summary("codex").today_first_count==0,"today-first credits only the actual catcher")
	check(world.command("human",{"intent":"release_fish","fish_id":fish.id}).ok,"release real caught fish")
	check(not world.days.today("human",combination).is_empty(),"release never erases today-first")
	var permanent: Dictionary=world.journal.saved();var revision: String=world.journal.revision("human")
	world=copy(world,"today");check(world.days.today("human",combination).fish_id==fish.id,"today-first survives same-day reload")
	world.fishing.rng.state=rng_state
	var repeat: Dictionary=Fish.catch_one(world,"human");check(not repeat.is_empty(),"same-day genuine repeated catch")
	if repeat.is_empty():return
	check(world.days.today("human",combination).fish_id==fish.id,"same combination keeps first-of-day source")
	world.command("human",{"intent":"release_fish","fish_id":repeat.id})
	D.advance_to(world,1501)
	check(world.days.day()==2 and world.days.today("human",combination).is_empty(),"day changes only transient today marker")
	check(world.memories._canonical(world.journal.saved())==world.memories._canonical(permanent) and world.journal.revision("human")==revision,"calendar rollover never changes permanent journal or its independent revision")
	world.fishing.rng.state=rng_state
	var next: Dictionary=Fish.catch_one(world,"human");check(not next.is_empty(),"next-day real catch of same known combination")
	if next.is_empty():return
	check(world.days.today("human",combination).fish_id==next.id and next.id!=fish.id,"known fish gets new first-of-day without overwriting permanent first")
	check(world.memories._canonical(world.journal.saved())==world.memories._canonical(permanent),"permanent first catch remains exact old source")
	# A catch committing in the last work tick of the day is settled after forest advance.
	world=F.fresh();world.fishing.rng.seed=101;check(Fish.coast(world,"human") and world.command("human",{"intent":"fish"}).ok,"boundary cast")
	for i in range(1200):
		world.advance(.1)
		var job: Dictionary=world.work.jobs.get("human",{})
		if job.get("phase")=="fish_reel" and float(job.time)>=float(world.fishing.rules.reel_seconds)-.15:break
	var before: float=world.forest.clock
	# Valid near-boundary calendar fixture, the fish and job remain genuinely engine-owned.
	world.days.origin=before-1499.95
	world.advance(.2)
	check(world.days.day()==2 and world.days.marked_day==2 and world.days.summary("human").today_first_count==1,"same-frame catch and crossover settle into one authoritative day")
func offline_tests() -> void:
	var world:=F.fresh()
	check(F.job(world,"human",{"intent":"plant","target_id":"farm.home.plot.01","crop_id":"tomato"}) and F.job(world,"human",{"intent":"water","target_id":"farm.home.plot.01"}),"real planted and watered perennial before offline")
	check(Save.save_world(world,directory.path_join("offline")),"save temporary offline fixture")
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("offline/island-v2.json")))
	# Simulate a real elapsed absence only in this disposable saved timestamps, never stock.
	var absence:=10000.0
	data.forest_saved_wall-=absence;data.farming.clock-=absence
	for plot in data.farming.plots.values():
		if plot.planted_at>0:plot.planted_at-=absence
	Fish.write_json(directory.path_join("offline/island-v2.json"),data)
	var restored:=F.fresh();check(Save.load_world(restored,directory.path_join("offline")).ok,"offline clock restore")
	check(restored.days.day()>=7 and restored.days.small.is_empty() and restored.days.spoken.is_empty() and restored.work.jobs.is_empty(),"offline skips old days without replaying greetings or small events")
	var plot: Dictionary=restored.farms.plots["farm.home.plot.01"]
	check(restored.farms.stage(plot)=="mature" and plot.harvests==0 and F.amount(restored,"tomato")==0,"offline reaches one mature batch without automatic harvest or material creation")
	restored.advance(30000)
	check(plot.harvests==0 and F.amount(restored,"tomato")==0,"more days cannot auto harvest or repeat crop batches")
	check(F.job(restored,"human",{"intent":"harvest","target_id":plot.id}) and F.amount(restored,"tomato")==3,"one actual harvest yields original three tomatoes")
	check(restored.farms.stage(plot)!="mature" and plot.harvests==1,"existing perennial restarts only after actual harvest")

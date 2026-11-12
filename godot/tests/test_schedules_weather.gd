extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
var checks:=0
var failed:=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool,message: String) -> void:
	checks+=1
	if not ok:failed=true;push_error(message)
func step(world: RefCounted,seconds: float) -> void:
	for tick in range(int(ceil(seconds/.5))):world.advance(.5)
func run() -> void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	var world:=F.fresh()
	check(world.error.is_empty() and world.weather.valid_config(world.weather.config) and world.schedules.valid_config(world.schedules.config),"validated cosmetic weather and loose daily preferences")
	world.weather.weather_seed=4294967295 # String.hash returns an unsigned32 value, including its upper half.
	check(world.weather.valid_saved(world.weather.saved()),"full unsigned32 seed range stays legal in schema7")
	var first: Dictionary=world.weather.current();step(world,100)
	check(world.weather.current()==first,"same day has stable weather after actual elapsed time")
	seed(414);var expected:=randi();seed(414);world.weather.for_day(200)
	check(randi()==expected,"weather never advances shared gameplay RNG")
	check(Save.save_world(world,directory.path_join("weather")),"save optional weather seed")
	var restored:=F.fresh();check(Save.load_world(restored,directory.path_join("weather")).ok and restored.weather.current()==first,"reload same day's weather is identical")
	check(world.days.day()==restored.days.day(),"no second weather clock")
	step(world,world.days.day_seconds);step(restored,restored.days.day_seconds)
	check(world.days.day()==2 and world.weather.current()==restored.weather.current() and world.weather.marked_day==2,"same seed and real day rollover determine same next day without drift")
	var context: Dictionary=world.autonomy_context("codex");context.self.weather.id="invented"
	check(world.weather.current().id!="invented" and context.self.has("schedule") and JSON.stringify(world.autonomy_context("codex")).to_utf8_buffer().size()<=4096,"deep-copy bounded weather/schedule context with no trigger")
	var malformed: Dictionary=world.weather.saved();malformed.seed=-1
	check(not world.weather.valid_saved(malformed),"reject invalid cosmetic save seed")
	# Scheduled routines must route through World and yield to any genuine task.
	world=F.fresh();var r: RefCounted=world.director.routines.codex
	world.activities.default_follow_excluded["codex"]=true # Explicit schedule-module fixture, not default-follow mode.
	r.set_enabled(true);r.set_chatter(false);world.schedules.config.first_after=1;world.schedules.config.chance=1
	world.days.config.small_after=world.days.day_seconds+1;world.days.config.greeting_after=world.days.day_seconds+1
	world.schedules.config.phases.morning=[{"place":"garden","weight":10}]
	for candidate in range(1000):
		world.weather.weather_seed=candidate
		if world.weather.current().id=="sunny":break
	step(world,30)
	check(int(world.schedules.statistics.started.get("codex",0))>=1 and int(world.schedules.statistics.arrived.get("codex",0))>=1,"idle actually walks and arrives at a real configured garden")
	check(world.schedules.targets.codex.place=="garden" and world.schedules.targets.codex.target_id in world.farms.farms,"schedule resolves existing world target")
	var human: Dictionary=world.actors.human.duplicate(true)
	check(world.command("codex",{"intent":"gather_wood","tree_count":1}).ok,"explicit real work preempts idle local schedule")
	var job_id: String=world.work.jobs.codex.id
	step(world,1)
	check(r.kind.is_empty() and world.work.jobs.get("codex",{}).get("id")==job_id,"schedule cancels only owned route and never steals accepted work")
	check(F.wait(world,"codex") and world.actors.human==human,"real work actually completes while schedule cannot move human")
	if not world.actors.codex.carry.is_empty():check(F.job(world,"codex",{"intent":"store","target_id":"home.chest.01"}),"real surplus safely stored")
	r.set_held(true);step(world,110)
	var started: int=world.schedules.statistics.started.get("codex",0);step(world,120)
	check(world.schedules.statistics.started.get("codex",0)==started,"held/dialogue blocks scheduled movement")
	r.set_held(false);world.command("codex",{"intent":"stop"});step(world,119)
	check(world.schedules.statistics.started.get("codex",0)==started,"stop's120 seconds remain effective for schedule")
	# Real completed house creates a real shelter; no phantom home before completion.
	world=F.fresh();check(not world.schedules.options("codex").any(func(option):return option.place=="shelter"),"unfinished house is not a shelter")
	check(world.command("codex",{"intent":"build_house","target_id":"home.house.01"}).ok,"real wood-funded house plan accepted")
	for tick in range(16000):
		world.advance(.5)
		if world.projects.plans.codex.status=="completed":break
	check(world.objects["home.house.01"].stage_index==5,"shelter only after all actual construction stages finish")
	for candidate in range(100):
		world.weather.weather_seed=candidate
		if world.weather.current().id=="rain":break
	check(world.weather.current().id=="rain" and world.schedules.options("codex").any(func(option):return option.place=="shelter"),"real rain biases towards existing porch, not invented indoor room")
	# Identical genuine work advances identically in two differently coloured weather worlds.
	var other:=F.fresh();world=F.fresh();world.weather.weather_seed=1;other.weather.weather_seed=2
	check(world.command("codex",{"intent":"gather_wood","tree_count":1}).ok and other.command("codex",{"intent":"gather_wood","tree_count":1}).ok,"paired actual wood work accepted")
	var identical:=true
	for tick in range(1800):
		world.advance(.5);other.advance(.5)
		identical=identical and world.actors.codex.position==other.actors.codex.position and world.actors.codex.carry==other.actors.codex.carry
		if not world.work.jobs.has("codex") and not other.work.jobs.has("codex"):break
	check(identical and world.drops==other.drops,"weather alters no frame of speed/work/material outcome")
	check(world.farms.crops==other.farms.crops and world.fishing.rules==other.fishing.rules and world.work.CARRY_LIMIT==20,"crop timing/yield and fishing chances/carry unchanged")
	check(Save.save_world(world,directory.path_join("old")),"old weatherless fixture save")
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("old/island-v2.json")));data.erase("weather")
	var file:=FileAccess.open(directory.path_join("old/island-v2.json"),FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close()
	check(Save.load_world(other,directory.path_join("old")).ok and other.schedules.targets.is_empty(),"old save has no schedule history or work restore; cosmetic weather starts without history")
	print("Schedules/weather: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)

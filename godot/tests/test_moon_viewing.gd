extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Library=preload("res://scripts/character_library.gd")
const Opening=preload("res://scripts/world_opening.gd")
const Save=preload("res://scripts/save_store.gd")
const FX=preload("res://scripts/moon_atmosphere.gd")
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	var w:=World.new("res://content/home-v3/world.json");w.library=Library.new();w.library.configure(directory);w.residents.provision(w);w.director.set_all_enabled(false);assert(Opening.apply(w,w.library).ok)
	while w.days.phase().id!="night":w.advance(1)
	for seed in range(1000):
		w.weather.weather_seed=seed
		if w.weather.current().id=="sunny":break
	var site:String=w.moon.config.platform_sites[0]
	check(w.command("human",{"intent":"use_facility","target_id":site}).ok and w.command("codex",{"intent":"use_facility","target_id":site}).ok,"explicitly reserve two real Leisure seats")
	for tick in range(3000):
		w.advance(.1)
		if not w.memories.records.filter(func(e):return e.kind=="moon_viewing").is_empty():break
	var entries:Array=w.memories.records.filter(func(e):return e.kind=="moon_viewing")
	check(entries.size()==1 and entries[0].participants==["codex","human"],"only actual seated pair recorded, no passerby")
	check(entries.size()==1 and entries[0].facts.day==w.days.day() and entries[0].facts.moon_phase==w.moon.phase(),"day and moon phase are true facts")
	check(Save.save_world(w,directory),"save viewing marker and real memory")
	var restored:=World.new("res://content/home-v3/world.json");restored.library=w.library
	check(Save.load_world(restored,directory).ok,"strict memory/Leisure validation reloads moon scene")
	check(restored.moon.last_viewing_day==w.days.day() and restored.work.jobs.is_empty() and restored.work.claims.is_empty(),"reload marker persists without seats/tasks restored")
	for tick in range(20):restored.advance(.1)
	check(restored.memories.records.filter(func(e):return e.kind=="moon_viewing").size()==1,"no replay after reload")
	while w.days.day()<5 or w.days.phase().id!="night":w.advance(1)
	for seed in range(1000):
		w.weather.weather_seed=seed
		if w.weather.current().id=="sunny":break
	check(FX.reflection_strength(w)>.95,"real elapsed full-moon night has visible reflection before rain/fog suppression")
	for weather in ["rain","fog"]:
		for seed in range(1000):
			w.weather.weather_seed=seed
			if w.weather.current().id==weather:break
		check(FX.reflection_strength(w)==0,"no visible moon reflection in "+weather)
	check(w.memories.capacity==256 and w.memories.MARK_LIMIT==192,"diary and marks remain bounded")
	print("Moon viewing: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)

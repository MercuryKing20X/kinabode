extends SceneTree
const World=preload("res://scripts/world_state.gd")
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func advance_to(w:RefCounted,seconds:float)->void:
	while w.forest.clock-w.days.origin<seconds-.0001:w.advance(minf(.25,seconds-(w.forest.clock-w.days.origin)))
func _initialize()->void:call_deferred("run")
func run()->void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	var library=preload("res://scripts/character_library.gd").new();library.configure(OS.get_environment("HABITAT_DATA_DIR"))
	var w:=World.new("res://content/home-v3/world.json");w.library=library;w.residents.provision(w);w.director.set_all_enabled(false)
	check(preload("res://scripts/world_opening.gd").apply(w,library).ok,"unchanged physical showcase applies")
	var layout:Dictionary=w.catalog.regions.home.layout
	check(layout.plaza_lamps.size()==8 and not layout.plaza_lamps.any(func(p):return p.role=="corner"),"eight useful lamps, corner lamps removed")
	check(Color(layout.ground_art.formal_plaza.ring_tint).get_luminance()<.5,"well ring is clearly dark stone")
	for owner in layout.yard_motifs:
		var own:Array=layout.art_props.filter(func(p):return p.get("yard_owner")==owner.owner_id)
		var other:Array=layout.art_props.filter(func(p):return p.has("yard_owner") and p.yard_owner!=owner.owner_id)
		var unique:=0
		for prop in own:
			if not other.any(func(q):return q.kind==prop.kind and q.get("asset","")==prop.get("asset","")):unique+=1
		check(unique*2>=own.size(),"at least half household props unique "+owner.owner_id)
	for id in layout.reserved_sites:
		var site:Dictionary=w.objects[id];var rect:=Rect2(w.point(site)-w.site_size(site)/2,w.site_size(site))
		check(not layout.art_props.any(func(p):return p.id.begins_with("stage3.south") and rect.has_point(Vector2(p.position[0],p.position[1]))),"future pad free of southern scenery "+id)
	var fishing_state:int=w.fishing.rng.state;var life_state:int=w.fishing.life.rng.state;var revision:int=w.revision;var seed:int=w.weather.weather_seed
	var view=preload("res://scripts/island_v3_view.gd").new();view.world=w;view.library=library;view.font=load("res://assets/fonts/NotoSansSC.ttf");view.hide();root.add_child(view);view.set_process(false);view.sound_enabled=false
	var renderer=view.atmosphere
	check(w.fishing.rng.state==fishing_state and w.fishing.life.rng.state==life_state and w.revision==revision and w.weather.weather_seed==seed,"preparing presentation changes no gameplay RNG or world revision")
	var stats:Dictionary=renderer.stats()
	check(stats.birds==6 and stats.butterflies==10 and stats.fireflies==20 and stats.waves<=80,"explicit particle and wave limits")
	check(stats.window_masks==5,"five built house glass masks cached without changing artworks")
	var cache_keys:Array=renderer.window_cache.keys()
	var states:Array=[]
	for phase in w.days.config.phases:
		advance_to(w,float(phase.start)*w.days.day_seconds+.1)
		var sampled:Dictionary=renderer.sample(w);states.append(sampled)
		check(w.days.phase().id==phase.id and sampled.tint.is_equal_approx(Color(renderer.config.phases[phase.id].tint)),"real advance reaches correct time tint "+phase.id)
		var index:int=w.days.config.phases.find(phase);var end:float=float(w.days.config.phases[index+1].start)*w.days.day_seconds if index+1<w.days.config.phases.size() else w.days.day_seconds
		advance_to(w,end-.01);var before:Color=renderer.sample(w).tint
		w.advance(.02);var after:Color=renderer.sample(w).tint
		check(Vector3(before.r,before.g,before.b).distance_to(Vector3(after.r,after.g,after.b))<.002,"continuous tint through phase/day boundary "+phase.id)
	check(states[0].mist>0 and states[1].light==0 and states[3].light==1,"morning mist, neutral afternoon and night emission derive from DayCycle")
	for index in range(600):
		view.clock+=.1;renderer.sample(w);renderer.refresh_houses(view)
	check(renderer.wave_builds==1 and renderer.window_cache.keys()==cache_keys,"600 presentation frames reuse coast/window caches")
	check(w.work.jobs.is_empty() and w.memories.records.is_empty(),"presentation never authors work or history")
	for weather_id in ["sunny","cloudy","rain","fog"]:
		for candidate in range(1000):
			w.weather.weather_seed=candidate
			if w.weather.current().id==weather_id:break
		check(w.weather.current().id==weather_id and renderer.sample(w).tint==renderer.sample(w).tint,"all existing cosmetic weather states coexist with time tint "+weather_id)
	check(w.fishing.rng.state==fishing_state and w.fishing.life.rng.state==life_state,"advancing visual clock and weather checks do not consume fish RNG")
	view.overview=true;view.overview_factor=2;view.zoom=1;view.update_ambience()
	check(view.zoom==.5,"half-sampled houses and child emission share projection before drawing")
	view.overview_factor=6;view.zoom=1;view.update_ambience()
	check(is_equal_approx(view.zoom,1.0/6),"overview emission and geometry share integer sampling")
	check(renderer.window_pixel_counts.values().all(func(count):return count>100 and count<1800),"only original glass panes emit, never large blue roof rectangles")
	print("Home v3 atmosphere: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)

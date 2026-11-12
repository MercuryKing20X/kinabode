extends SceneTree
## Deterministic supplemental observer probe, not a mouse acceptance test.
const Helper=preload("res://tests/test_barbecue_v2.gd")
var failed:=false
func _initialize()->void:call_deferred("run")
func run()->void:
	var dir:=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-test-"))
	var h:=Helper.new();var w:RefCounted=h.fresh(dir)
	var view:=preload("res://scripts/island_view.gd").new();view.world=w;view.library=w.library;view.font=load("res://assets/fonts/NotoSansSC.ttf");root.add_child(view);view.set_process(false)
	var audio:=preload("res://scripts/game_audio.gd").new();root.add_child(audio);audio.setup(w,view,dir);audio.mute_unfocused=false;audio.focused=true
	w.hunger.ensure("codex");w.hunger.states.codex.elapsed=1600
	view.center=w.point(w.actors.codex)
	var rows:Array=[];var symbols:=0;var events:=0
	for region in ["home","dark"]:
		view.region_id=region
		var base:float=.3 if region=="home" else .22;var peak:float=.6 if region=="home" else .4
		var low:=INF;var high:=0.0;var bird_times:Array=[]
		for frame in range(1800):
			w.advance(.1);view.clock+=.1;audio.advance(.1)
			if view.hunger_symbols.get("codex",0)>view.clock:symbols+=1
			var gain:float=audio.observer.wind_gain(base,peak)
			low=minf(low,gain);high=maxf(high,gain)
			var wind_items:Array=audio.active.filter(func(item):return item.event=="ambience.wind" and item.key==("wind" if region=="home" else "dark:wind"))
			rows.append({"region":region,"clock":audio.clock,"target_gain":gain,"actual_gain":wind_items[0].gain if not wind_items.is_empty() else 0.0})
			if gain<base-.00001 or gain>peak+.00001:failed=true
		for row in audio.trace:
			if row.get("action")=="scheduled" and row.get("event")=="ambience.birds":bird_times.append(float(row.time))
		for index in range(1,bird_times.size()):
			if bird_times[index]-bird_times[index-1]<float(audio.tuning.nature.bird_interval_min)-.3:failed=true
		if not is_equal_approx(low,base) or not is_equal_approx(high,peak):failed=true
	for event in audio.trace:
		if event.get("action")=="scheduled" and str(event.get("event","")).begins_with("hunger."):events+=1
	if events!=0 or symbols==0:failed=true
	if audio.catalog.events["ambience.birds"].loop:failed=true
	if not audio.catalog.events["ambience.birds"].variants.A.file.contains("quiet-nature"):failed=true
	if not audio.catalog.events["ambience.insects"].variants.A.file.contains("quiet-nature"):failed=true
	FileAccess.open(dir.path_join("wind-gains.json"),FileAccess.WRITE).store_string(JSON.stringify(rows))
	print("Quiet audio: 180s per region, hunger events=",events," visible cue frames=",symbols," failed=",failed," gains=",dir.path_join("wind-gains.json"))
	audio.shutdown();audio.queue_free();view.queue_free();h.free();await process_frame
	quit(1 if failed else 0)

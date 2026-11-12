extends SceneTree
const Visit=preload("res://scripts/companion_return.gd")
var failed:=false
var checks:=0
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	for invalid in [{"interval_seconds":true},{"interval_seconds":299},{"far_seconds":INF},{"stay_seconds":-1},{"wat":1}]:check(not Visit.valid(invalid),"strict visit validator rejects "+str(invalid))
	check(Visit.valid({}) and Visit.valid(Visit.DEFAULT),"optional legacy defaults valid")
	var w:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");w.residents.provision(w)
	w.library=preload("res://scripts/character_library.gd").new();w.library.configure(OS.get_environment("HABITAT_DATA_DIR"))
	check(preload("res://scripts/world_opening.gd").apply(w,w.library,"showcase").ok,"isolated showcase")
	w.intelligence.activate_presets();w.director.set_all_enabled(true)
	w.activities.set_followers([]) # Explicit host dismissal: this scenario measures free idle visits, not follow mode.
	# C: mirror the current player follow UI opt-out as well as clearing selected followers.
	for id in w.director.routines:w.activities.default_follow_excluded[id]=true
	var inventory:Dictionary={}
	for chest in [{"id":"storage","items":w.storage.saved().items,"capacity":9007199254740991,"kind":"storage"}]:inventory[chest.id]=chest.get("items",{}).duplicate(true)
	var distances:Dictionary={}
	for id in w.director.routines:distances[id]={"within8":0,"within24":0,"far":0}
	var simulation_seconds:=0.0
	var profile_start:=Time.get_ticks_usec()
	var profile_marker:=600.0
	while simulation_seconds<3600.0:
		# Pure idle waits may advance in larger slices; retain .5s for any actual work; local-life motion still uses original World advance.
		var delta:float=minf(3600.0-simulation_seconds,.5 if w.work.jobs.values().any(func(job):return job.get("source")!="local_rules") else 2.0)
		w.advance(delta);simulation_seconds+=delta
		if simulation_seconds>=profile_marker:
			print("Return profile seconds=",simulation_seconds," wall_ms=",(Time.get_ticks_usec()-profile_start)/1000.0," routes=",w._routes.size()," jobs=",w.work.jobs.size());profile_marker+=600.0
		for id in distances:
			var d:float=w.point(w.actors[id]).distance_to(w.point(w.actors.human))
			distances[id]["within8" if d<=8 else "within24" if d<=24 else "far"]+=delta/.5
	print("Return profile simulation_ms=",(Time.get_ticks_usec()-profile_start)/1000.0)
	var results:Dictionary={}
	for id in w.director.routines:
		var visits:Array=w.director.routines[id].return_visit.arrivals
		var gaps:Array=[]
		for i in range(1,visits.size()):gaps.append(float(visits[i].at)-float(visits[i-1].at))
		results[id]={"due":w.director.routines[id].return_visit.due,"diagnostics":w.director.routines[id].return_visit.diagnostics,"kind":w.director.routines[id].kind,"enabled":w.director.routines[id].enabled,"visits":visits,"count":visits.size(),"mean_interval":gaps.reduce(func(a,b):return a+b,0.0)/maxi(1,gaps.size()),"distance_samples":distances[id]}
		check(not visits.is_empty(),"each idle resident really completes social visits "+id)
		check(visits.all(func(v):return v.distance<=8),"every actual arrival near human "+id)
	for chest in [{"id":"storage","items":w.storage.saved().items,"capacity":9007199254740991,"kind":"storage"}]:check(chest.get("items",{})==inventory[chest.id],"social visits never consume stock "+chest.id)
	# A real accepted work order must retain its exact ID until its normal receipt.
	var trees:Array=w.objects.values().filter(func(o):return o.get("kind")=="tree" and o.get("state",o.get("status",""))!="stump")
	var worker_id:String=w.director.routines.keys()[0]
	var accepted:=false
	for tree in trees:
		var result:Dictionary=w.command(worker_id,{"intent":"chop","target_id":tree.id})
		if result.get("ok",false):accepted=true;break
	check(accepted,"real work accepted while social visits enabled")
	if accepted:
		var job_id:String=str(w.work.jobs.get(worker_id,{}).get("id",""))
		for step in range(600):
			if not w.work.jobs.has(worker_id):break
			w.advance(.5)
			check(w.work.jobs.get(worker_id,{}).get("id",job_id)==job_id,"social visits never replace actual work")
		check(w.work.events.any(func(e):return e.get("job_id")==job_id and e.get("status")=="completed"),"actual work completed with original receipt")
	var output:String=OS.get_environment("HABITAT_RETURN_REPORT")
	if not output.is_empty():
		var file:=FileAccess.open(output,FileAccess.WRITE);file.store_string(JSON.stringify({"seconds":3600,"delta":.5,"natural_hunger":false,"fixture":"social-only idle world; hunger follow verified separately","residents":results},"  "))
	print("Companion return: ",checks," checks failed=",failed," ",JSON.stringify(results));quit(1 if failed else 0)

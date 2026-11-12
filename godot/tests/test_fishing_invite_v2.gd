extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Opening=preload("res://scripts/world_opening.gd")
const Library=preload("res://scripts/character_library.gd")
const Fixture=preload("res://tests/fishing_fixture.gd")
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var temp:String=OS.get_environment("HABITAT_DATA_DIR");assert(temp.contains("youqi-test-"))
	var w:=World.new("res://content/home-v3/world.json");w.residents.provision(w);w.library=Library.new();w.library.configure(temp);assert(Opening.apply(w,w.library,"showcase").ok)
	w.intelligence.activate_presets();w.hunger.start();w.director.set_all_enabled(false)
	var ids: Array=["codex","companion-2","npc.mira","npc.nora"]
	for id in ids:check(not w.work.jobs.has(id),"not invited never automatically fishes "+id)
	var shore_found:=false
	for target in w.fishing.nearby_shores("human",32):
		if not Fixture.walk(w,"human",target.position):continue
		var coast:Dictionary=w.fishing.shore("human")
		if coast.is_empty():continue
		if not w.command("human",{"intent":"fish"}).ok:continue
		var result:Dictionary=w.fishing.invite_host(ids)
		if result.accepted.size()==4:shore_found=true;break
		for id in ids+["human"]:
			if w.work.jobs.has(id):w.work.stop(id)
	check(shore_found,"all four invited companions accept reachable shore positions")
	if shore_found:
		var positions:Array=[]
		for id in ids+["human"]:
			var job:Dictionary=w.work.jobs.get(id,{})
			check(job.get("intent")=="fish","own independent job "+id)
			var p:=Vector2(job.position[0],job.position[1])
			check(positions.all(func(q):return p.distance_to(q)>=2.0),"shore spacing at least two tiles "+id)
			positions.append(p)
		var keep:String=w.work.jobs[ids[1]].id
		w.work.stop(ids[0]);check(w.work.jobs.get(ids[1],{}).get("id")==keep,"stop releases only own job")
		for i in range(2400):
			w.advance(.1)
			if ids.slice(1).all(func(id):return not w.work.jobs.has(id)):break
		for id in ids.slice(1):check(w.fishing.held(id).get("owner_id")==id,"actual caught instance belongs to its catcher "+id)
	for id in ids+["human"]:
		if w.work.jobs.has(id):w.work.stop(id)
	# A fresh real-world hunger state rejects a further host invitation.
	w.hunger.states["codex"].elapsed=float(w.hunger.config.thresholds[3]);w.hunger.states["codex"].full_meal=false
	var rejected:Dictionary=w.fishing.invite_host(["codex"])
	check("codex" in rejected.skipped and not w.work.jobs.has("codex"),"very hungry companion refuses invitation")
	print("Fishing invite v2: ",checks," checks, failed=",failed);quit(1 if failed else 0)

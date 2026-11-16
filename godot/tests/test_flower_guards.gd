extends SceneTree
var failed:=false
var checks:=0
func check(v:bool,label:String)->void:
	checks+=1
	if not v:failed=true;push_error(label)
func _initialize()->void:
	var w:RefCounted=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");w.residents.provision(w)
	var f:RefCounted=w.flower_creation;f.next_auto=INF
	w.storage.add({"rose_red":100,"wood":20})
	var before:Dictionary=w.storage.saved()
	var gesture:Dictionary=w.host_command("codex",{"intent":"gesture","gesture":"wave"})
	var job:Dictionary=w.work.jobs.get("codex",{}).duplicate(true)
	check(gesture.ok,"real existing gesture accepted")
	check(not w.host_command("codex",{"intent":"arrange_flowers","pattern":"heart"}).ok,"flowers never interrupt existing work")
	check(w.work.jobs.get("codex",{})==job and w.storage.saved()==before,"busy rejection preserves original task and warehouse")
	w.command("codex",{"intent":"stop"})
	w.hunger.start();w.hunger.ensure("codex");w.hunger.states.codex.elapsed=w.hunger.config.thresholds[3]
	check(w.hunger.rank("codex")==3,"fixture reaches original very hungry threshold")
	for action in ["arrange_flowers","gift_flower","place_flower"]:
		var result:Dictionary=w.host_command("codex",{"intent":action,"pattern":"heart"})
		check(result.error=="very_hungry" and not str(result.message).is_empty(),"hungry refusal explains "+action)
	check(w.storage.saved()==before,"very hungry never spends roses")
	var human:Dictionary=w.actors.human.duplicate(true)
	check(not f.execute("human",{"intent":"trade_flowers","quantity":10}).ok,"remote trade rejected")
	check(w.actors.human==human and w.storage.saved()==before,"remote trade never moves host or commits wood")
	var road:Dictionary=w.catalog.regions.home.layout.roads[0];var p:Vector2=w.Layout.points(road.points)[0]
	check(not f.space("home",p),"road placement rejected")
	for bed in preload("res://scripts/resort_renderer.gd").BEDS:check(not f.space("home",bed.get_center()),"scenic rose fields cannot be placed over")
	check(not f.valid_saved({"version":1,"flowers":{},"gifts":{},"serial":-1,"first_received":false},w.actors),"invalid persistence rejects negative serial")
	var over:Dictionary={}
	for i in range(800):over[str(i)]={}
	f.flowers=over
	check(f.execute("human",{"intent":"place_flower","position":[40,40]}).error=="world_limit","801st flower refused before payment")
	check(w.storage.saved()==before,"capacity guard keeps all real material")
	print("flower guards ",checks," failed=",failed);quit(1 if failed else 0)

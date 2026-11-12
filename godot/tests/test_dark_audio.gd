extends SceneTree
## Audio observer integration; real World routes/resources/advance, not mouse acceptance.
const Audio=preload("res://scripts/game_audio.gd")
const Helper=preload("res://tests/test_barbecue_v2.gd")
var failed:=false
var checks:=0
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failed=true;push_error(message)
func _initialize()->void:call_deferred("run")
func count(a:Node,event:String)->int:return a.trace.filter(func(e):return e.action=="scheduled" and e.event==event).size()
func tick(w:RefCounted,a:Node,v:Node,seconds:float)->void:
	for i in range(ceili(seconds/.05)):
		w.advance(.05);v.clock+=.05;v.center=w.point(w.actors.human);a.advance(.05)
func settle(w:RefCounted,a:Node,v:Node)->void:
	for i in range(4000):
		tick(w,a,v,.05)
		if not w._routes.has("human") and not w.work.jobs.has("human") and w.dark.pending.is_empty():return
	check(false,"real routed action finishes")
func run()->void:
	var dir:=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-test-"))
	var h:=Helper.new();var w:RefCounted=h.fresh(dir);check(w.error.is_empty() and w.dark.enabled(),"dark content initializes")
	check(h.pickup(w,"wood",12),"twelve authentic wood picked up from existing opening stock")
	var view:=preload("res://scripts/island_view.gd").new();view.world=w;view.library=w.library;view.font=load("res://assets/fonts/NotoSansSC.ttf");root.add_child(view);view.set_process(false);view.center=w.point(w.actors.human)
	var a:=Audio.new();root.add_child(a);a.setup(w,view,dir);check(a.error.is_empty(),"strict dark audio manifest loads")
	for name in ["torch.ignite","torch.plant","torch.lift","torch.warning","dark.kindling","dark.beacon"]:check(a.catalog.events.has(name),"recorded source event exists "+name)
	tick(w,a,view,.3);check(count(a,"ambience.birds")==1,"home still has day birds")
	check(w.command("human",{"intent":"move","x":w.dark.config.home_arrival[0],"y":w.dark.config.home_arrival[1]}).ok,"World routes to north boat")
	settle(w,a,view)
	check(w.dark.travel([]).ok,"explicit host travel after actual arrival")
	view.region_id="dark";view.center=w.point(w.actors.human);tick(w,a,view,.3)
	check(a.active.all(func(e):return e.event!="ambience.birds"),"no birds survive arrival in dark")
	check(a.active.any(func(e):return e.key=="dark:wind" and e.target>=.22 and e.target<=.4),"dark wind uses quieter configured gain")
	check(a.active.any(func(e):return e.key=="dark:waves" and is_equal_approx(e.target,.35)),"dark distant waves use quieter configured gain")
	check(a.active.any(func(e):return e.key=="dark:insects" and is_equal_approx(e.target,.45)),"dark insects use quieter configured gain")
	check(w.dark.life.fireside.light_host().ok,"real third fire debits wood at camp")
	tick(w,a,view,.3)
	check(a.active.any(func(e):return e.key=="fire:dark.barbecue" and e.target>0),"third station fire loop follows dark region")
	check(w.dark.start("torch",w.dark.p(w.dark.config.camp)).ok,"explicit torch start uses original route and real resource debit")
	settle(w,a,view);check(count(a,"torch.ignite")==1,"committed torch ignition emits exactly once")
	var rev:int=w.revision;var fish_rng:int=w.fishing.rng.state;var remain:float=w.dark.torch.remaining
	for i in range(8):a.advance(.05)
	check(w.revision==rev and w.fishing.rng.state==fish_rng and w.dark.torch.remaining==remain,"audio observer mutates no world or RNG or torch time")
	check(count(a,"torch.ignite")==1,"old event ring does not replay")
	tick(w,a,view,101);check(count(a,"torch.warning")==1,"actual advance crosses warning once")
	tick(w,a,view,5);check(count(a,"torch.warning")==1,"low torch never repeats warning")
	check(a.trace.filter(func(e):return e.action=="scheduled").all(func(e):return int(e.active_total)<=5),"new events preserve five-sound cap")
	a.shutdown();a.queue_free();view.queue_free();h.free();await process_frame
	print("Dark audio: ",checks," checks; World route/resource observer fixture, not player mouse acceptance")
	quit(1 if failed else 0)

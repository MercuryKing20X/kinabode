extends SceneTree
## Integration/Logic — BEHAVIOR.md. Real World routes/advance, separate from mouse acceptance.
const World=preload("res://scripts/world_state.gd")
const Library=preload("res://scripts/character_library.gd")
const Opening=preload("res://scripts/world_opening.gd")
const F=preload("res://tests/cooking_fixture.gd")
const B=preload("res://tests/backpack_fixture.gd")
const BBQ=preload("res://tests/barbecue_fixture.gd")
var checks:=0
var failed:=false
var reports:Array=[]
var directory:String
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func fresh(name:String)->RefCounted:
	var w:=World.new("res://content/home-v3/world.json")
	check(w.error.is_empty(),"valid isolated dark world "+name)
	w.residents.provision(w);w.library=Library.new();w.library.configure(directory.path_join(name))
	check(Opening.apply(w,w.library,"showcase").ok,"real showcase opening "+name)
	w.intelligence.activate_presets();w.hunger.start();w.director.set_all_enabled(false)
	return w
func walk(w:RefCounted,at:Vector2,id:String="human")->bool:return F.job(w,id,{"intent":"move","x":at.x,"y":at.y})
func board(w:RefCounted)->bool:
	return walk(w,w.dark.p(w.dark.config.home_arrival)) and w.dark.travel(w.actors.keys().filter(func(id):return id!="human")).ok
func advance(w:RefCounted,seconds:float)->void:
	for frame in range(ceili(seconds/.25)):w.advance(minf(.25,seconds-frame*.25))
func settled(w:RefCounted)->void:
	for i in range(5000):
		w.advance(.05)
		if w.dark.pending.is_empty() and not w._routes.has("human"):return
func inventory(w:RefCounted)->Dictionary:
	var result:Dictionary={}
	for chest in [{"id":"storage","items":w.storage.saved().items,"capacity":9007199254740991,"kind":"storage"}]:result[chest.id]=chest.get("items",{}).duplicate(true)
	for chest in w.farms.containers.values():result[chest.id]=chest.get("items",{}).duplicate(true)
	for id in w.actors:result[id]=w.actors[id].carry.duplicate(true)
	return result
func run()->void:
	directory=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	OS.set_environment("HABITAT_OPENING","legacy")
	light_roaming();fear_and_gates();torch_reactions();real_work();very_hungry_in_light();home_passthrough()
	var out:String=OS.get_environment("HABITAT_DARK_EVIDENCE")
	if not out.is_empty():var f:=FileAccess.open(out.path_join("behavior-results.json"),FileAccess.WRITE);f.store_string(JSON.stringify({"checks":checks,"failed":failed,"cases":reports},"  "))
	print("Dark companions: ",checks," checks, failed=",failed);quit(1 if failed else 0)
func light_roaming()->void:
	var w:RefCounted=fresh("lit");check(board(w),"host walks and selected party boards real boat")
	var before:Dictionary=inventory(w);var human:Dictionary=w.actors.human.duplicate(true)
	w.director.set_all_enabled(true)
	var moved:Dictionary={};var initial:Dictionary={};var failures:=0;var checks_before:int=checks;var resting:Dictionary={}
	for id in w.director.routines:initial[id]=w.point(w.actors[id])
	for frame in range(900):
		w.advance(.1)
		for id in w.director.routines:
			if w.point(w.actors[id]).distance_to(initial[id])>.4:moved[id]=true
			if w.actors[id].activity==("local_look" if w.intelligence.tag(id)=="quiet" else "local_sit"):resting[id]=true
			if not w.dark.permanent(w.point(w.actors[id])):failures+=1
			if w.dark.companions.owns_wander(id) and not w.dark.companions.route_lit(w._routes[id],w.point(w.actors[id])):failures+=1
	check(failures==0,"light roaming never leaves permanent light, including whole route")
	check(moved.size()==4,"all four residents physically relax/roam inside light")
	check(resting.size()==4,"each resident reaches the authored quiet-look or seated light-relax pose")
	check(w.actors.human==human,"local light roaming never controls host")
	check(inventory(w)==before,"local relaxing does not take, eat, store or consume items")
	check(not w.dark.companions.route_lit([Vector2(44,66)],w.dark.p(w.dark.config.camp)),"a dark shortcut is rejected even from a lit origin")
	var blue:String="companion-2";var r:RefCounted=w.director.routines[blue]
	for step in range(500):
		w.advance(.1)
		if w.dark.companions.owns_wander(blue):break
	check(w.dark.companions.owns_wander(blue),"real local lit wander owns an actual route")
	if w.dark.companions.owns_wander(blue):
		var replacement:Array=w._routes[blue].duplicate();w._apply_route(blue,replacement)
		w.dark.companions.tick(r,.1)
		check(w._routes.has(blue) and is_same(w._routes[blue],replacement),"later same-endpoint route is preserved instead of being cancelled as old local wander")
	reports.append({"case":"lit","seconds":90,"moved_residents":moved.keys(),"boundary_failures":failures,"checks":checks-checks_before})
func fear_and_gates()->void:
	var w:RefCounted=fresh("fear");check(board(w),"fear party crosses by actual boat")
	check(walk(w,Vector2(44,66)),"host explicitly walks out of camp through World")
	var before:Dictionary=inventory(w);var human:Dictionary=w.actors.human.duplicate(true)
	w.director.set_all_enabled(true);advance(w,140)
	var max_distance:=0.0
	for id in w.director.routines:max_distance=maxf(max_distance,w.point(w.actors[id]).distance_to(w.point(w.actors.human)))
	check(max_distance<10,"all dark followers physically catch up to host through World")
	check(w.actors.human==human,"fear following never moves host")
	check(inventory(w)==before,"fear never handles resources")
	var kinds:Dictionary={}
	for e in w.director.events:
		if e.context in ["dark_fear","dark_glow","dark_fire","dark_warning","dark_out"]:kinds[e.actor_id]=true
	check(kinds.size()==4,"all four authored personalities deliver dark local speech through shared outlet")
	var blue_distance:float=w.point(w.actors["companion-2"]).distance_to(w.point(w.actors.human))
	var other_distances:Array=[]
	for id in ["codex","npc.mira","npc.nora"]:other_distances.append(w.point(w.actors[id]).distance_to(w.point(w.actors.human)))
	check(blue_distance<=other_distances.min()+.8,"lively personality takes nearest queue slot independent of ID ordering")
	var route_starts:int=w.hunger.statistics.follow_routes
	var id:String="codex";check(w.command(id,{"intent":"move","x":132,"y":77}).ok,"explicit resident route accepted while dark following")
	var manual:Array=w._routes.get(id,[])
	advance(w,9)
	check(w._routes.has(id) and is_same(w._routes[id],manual),"dark fear does not replace an explicit resident route after follow cooldown expires")
	w.command(id,{"intent":"stop"});var stopped:Vector2=w.point(w.actors[id]);var stop_clock:float=w.director.time
	advance(w,100)
	check(w.point(w.actors[id]).distance_to(stopped)<.001,"stop preserves original 120 second motion quiet period")
	check(w.director.events.all(func(e):return e.actor_id!=id or e.time<stop_clock),"stop quiet also rejects new dark speeches")
	id="companion-2";w.director.set_held(id,true);var held:Vector2=w.point(w.actors[id]);var serial:int=w.director.serial
	advance(w,20)
	check(w.point(w.actors[id]).distance_to(held)<.001 and not w._routes.has(id),"held cancels only owned dark-follow route")
	check(w.director.events.all(func(e):return e.actor_id!=id or e.serial<=serial),"held blocks dark local speech")
	w.director.set_held(id,false);w.director.routines[id].set_chatter(false);serial=w.director.serial;advance(w,60)
	check(w.director.events.all(func(e):return e.actor_id!=id or e.serial<=serial),"chatter switch blocks dark speech while retaining movement preference")
	var personality_tag:String=w.intelligence.tag("npc.nora");check(w.assign_appearance("npc.nora","ai-glm"),"host assigns nondefault existing appearance in logic fixture")
	check(w.intelligence.tag("npc.nora")==personality_tag,"changing appearance preserves authored personality")
	var quiet:RefCounted=w.director.routines["npc.nora"]
	var target:Vector2=w.dark.companions.landmark(w.point(w.actors["npc.nora"]))
	check(target.is_finite() and not w.dark.permanent(target),"quiet hint selects actual still-unlit glow or beacon")
	var recent:Array=w.director.events.duplicate(true)
	var gaps_valid:=true
	for i in range(1,recent.size()):
		if float(recent[i].time)-float(recent[i-1].time)<float(w.hunger.config.village_gap)-.001:gaps_valid=false
	check(gaps_valid,"dark lines retain original village speech gap")
	reports.append({"case":"fear","max_distance":max_distance,"blue_distance":blue_distance,"other_distances":other_distances,"speaking_residents":kinds.keys(),"follow_routes":w.hunger.statistics.follow_routes-route_starts})
func torch_reactions()->void:
	var w:RefCounted=fresh("torch")
	check(BBQ.meal(w,"single:mushroom",w.actors.keys()),"torch fixture serves an actual prior barbecue so peckish chatter does not consume the warning turn")
	check(F.job(w,"human",{"intent":"take","target_id":"home.chest.01"}),"torch fixture physically collects existing twenty wood")
	check(board(w),"torch reaction party boards from original coast")
	check(w.dark.start("torch",w.dark.p(w.dark.config.camp)).ok,"host requests torch ignition from real camp")
	settled(w)
	check(w.dark.torch.remaining>0 and w.dark.torch.owned,"actual ignition committed")
	w.director.set_all_enabled(true)
	check(walk(w,Vector2(44,82)),"party follows host through still-dark approach before lighting")
	advance(w,8)
	check(w.dark.light_portable_torch().ok,"host confirms already-held torch without adding a fire")
	settled(w)
	check(w.dark.fires.is_empty() and w.dark.torch.remaining>0,"portable torch remains lit with no player-created fire")
	w.director.set_all_enabled(true)
	advance(w,45)
	check(w.director.events.any(func(e):return e.actor_id=="companion-2" and e.context=="dark_fire"),"lively resident really cheers a newly committed fire through original gates")
	# Disable until actual remaining time crosses100 seconds, leaving speech gates untouched.
	w.director.set_all_enabled(false)
	if w.dark.torch.remaining>18:advance(w,float(w.dark.torch.remaining)-18)
	check(w.dark.torch.remaining>0 and w.dark.torch.remaining<=20,"real advance reaches warning window")
	w.director.set_all_enabled(true)
	advance(w,16)
	check(w.director.events.any(func(e):return e.context=="dark_warning"),"party really delivers a warning while torch is still burning")
	check(walk(w,Vector2(44,66)),"host takes original route back into dark for expiry")
	if w.dark.torch.remaining>0:advance(w,float(w.dark.torch.remaining)+.2)
	advance(w,80)
	check(w.dark.torch.remaining==0,"torch expires only by actual elapsed advance")
	check(w.director.events.any(func(e):return e.context=="dark_out"),"party really delivers authored nervous line after actual expiry")
	var blue:String="companion-2";var sample:Dictionary=w.hunger.follow_targets.get(blue,{})
	check(not sample.is_empty() and sample.region=="dark" and sample.point.distance_to(w.point(w.actors.human))<3,"extinguished-torch queue stays close on original World route")
func real_work()->void:
	var w:RefCounted=fresh("work");check(board(w),"work party crosses real boat")
	w.director.set_all_enabled(true)
	var id:="codex";var result:Dictionary=w.command(id,{"intent":"chop","target_id":"dark.tree.00"})
	check(result.ok,"explicit real resident tree task accepted")
	if not result.ok:return
	var job_id:String=w.work.jobs[id].id;var before:int=B.wood_total(w);var replaced:=false
	var expected:int=int(w.forest.settings.large_wood if int(w.objects["dark.tree.00"].wood_yield)>8 else w.forest.settings.normal_wood)
	for frame in range(1500):
		w.advance(.1)
		if not w.work.jobs.has(id):break
		if w.work.jobs[id].id!=job_id:replaced=true;break
	check(not replaced,"dark routines never replace a true task/job identity")
	check(w.work.events.any(func(e):return e.get("job_id")==job_id and e.status=="completed"),"real tree task completes through original Work receipts")
	check(B.wood_total(w)==before+expected,"real dark chop alone creates exact configured wood; ambient routines create none")
func very_hungry_in_light()->void:
	var w:RefCounted=fresh("very-hungry-lit")
	check(board(w),"hungry light fixture boards selected party before actual hunger")
	# Advance the original thresholds with the routines disabled; no hunger state edits.
	for second in range(ceili(float(w.hunger.config.thresholds[3]))+1):w.advance(1.0)
	check(w.director.routines.keys().all(func(id):return w.hunger.rank(id)==3),"every selected companion becomes very hungry through actual elapsed time")
	check(walk(w,Vector2(43,96)),"host explicitly moves within permanently lit dock camp")
	var human:Dictionary=w.actors.human.duplicate(true);var stock:Dictionary=inventory(w)
	var distances:Dictionary={};var routes_survived:Dictionary={};var dark_samples:=0
	for id in w.director.routines:distances[id]=w.point(w.actors[id]).distance_to(w.point(w.actors.human))
	w.director.set_all_enabled(true)
	for frame in range(100):
		w.advance(.1)
		for id in w.director.routines:
			if w.dark.companions.owns_follow(id):routes_survived[id]=true
			if not w.dark.permanent(w.point(w.actors[id])):dark_samples+=1
	check(routes_survived.size()==4,"lit local branch retains all four exact original very-hungry follow routes")
	check(w.director.routines.keys().all(func(id):return w.point(w.actors[id]).distance_to(w.point(w.actors.human))<distances[id]-2),"very hungry residents really move promptly to host in the light")
	check(dark_samples==0,"ordinary hungry routes and all physical follow samples stay within this lit camp")
	check(w.actors.human==human and inventory(w)==stock,"hungry lit follow never moves host or handles any food/resources")
	var id:="codex";check(w.command(id,{"intent":"stop"}).ok,"explicit stop accepted during lit hunger follow")
	var stopped:Vector2=w.point(w.actors[id]);var stop_clock:float=w.director.time
	advance(w,100)
	check(w.point(w.actors[id]).distance_to(stopped)<.001 and not w._routes.has(id),"lit very-hungry follow still respects original stop120 seconds")
	check(w.director.events.all(func(e):return e.actor_id!=id or e.time<stop_clock),"lit very-hungry stop keeps original speech silence")
	# The only hungry-work exception is original abandonment; a genuine eating job must survive.
	var fire:RefCounted=w.dark.life.fireside
	check(BBQ.approach(w,"dark.barbecue"),"host physically returns to third fire while companions are very hungry")
	check(fire.light_host().ok and fire.invite(["companion-2"]).ok and fire.roast_host("single:mushroom").ok,"explicit third-fire meal consumes existing authorized wood and mushroom")
	var eat_job:="";var finished:=false;var replaced:=false
	for frame in range(1200):
		w.advance(.1)
		var job:Dictionary=w.work.jobs.get("companion-2",{})
		if job.get("intent")=="eat":
			if eat_job.is_empty():eat_job=str(job.id)
			elif str(job.id)!=eat_job:replaced=true
		if not eat_job.is_empty() and "companion-2" in fire.state.get("current",{}).get("eaters",[]):
			finished=w.hunger.rank("companion-2")<3;break
	check(not eat_job.is_empty() and not replaced,"lit hunger branch never replaces actual shared eating job")
	check(finished and w.hunger.rank("companion-2")<3,"actual third-fire meal alone resolves hunger through original completion")
	reports.append({"case":"very-hungry-lit","actual_wait_seconds":ceili(float(w.hunger.config.thresholds[3]))+1,"retained_follow_residents":routes_survived.keys(),"dark_samples":dark_samples,"actual_eat_job":eat_job})
func home_passthrough()->void:
	var w:RefCounted=fresh("home")
	var before:Dictionary=w.actors.duplicate(true);var weights:Dictionary={}
	var base:Dictionary={"nearby":1.0,"wander":1.0,"rest":1.0,"facility":1.0,"garden":1.0,"watch":1.0,"stretch":1.0,"look":1.0,"flower_gift":1.0}
	for id in w.director.routines:weights[id]=w.intelligence.behavior_weights(id,base)
	for id in w.director.routines:check(not w.dark.companions.tick(w.director.routines[id],.1),"dark behavior yields completely outside dark region "+id)
	check(w.director.routines.keys().all(func(id):return w.intelligence.behavior_weights(id,base)==weights[id]),"dark probe cannot alter main-island behavior weights or cooldowns")
	check(w.intelligence.catalog.traits.values().all(func(t):return t.behavior_units.all(func(uid):return not uid.begins_with("dark-"))),"dark exploration behavior units never enter the global main-island trait pipeline")
	check(w.actors==before and w.dark.companions.owned.is_empty(),"main island dark probe cannot move or own residents")

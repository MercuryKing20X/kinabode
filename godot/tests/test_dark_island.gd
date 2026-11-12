extends SceneTree
## Integration/Logic — production/evidence/2026-11-01-黑暗岛/DARK_QA.md — BLOCKING.
## These are system tests, not the separate real-mouse player acceptance.
const World=preload("res://scripts/world_state.gd")
const Library=preload("res://scripts/character_library.gd")
const Opening=preload("res://scripts/world_opening.gd")
const Save=preload("res://scripts/save_store.gd")
const F=preload("res://tests/cooking_fixture.gd")
const B=preload("res://tests/backpack_fixture.gd")
var checks:=0
var failed:=false
var base_dir:String
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func fresh(label:String,opening:String="showcase")->RefCounted:
	var w:=World.new("res://content/home-v3/world.json")
	check(w.error.is_empty(),"dark catalog validates "+label+": "+w.error)
	w.residents.provision(w);w.library=Library.new();w.library.configure(base_dir.path_join(label))
	check(Opening.apply(w,w.library,opening).ok,"explicit fresh opening "+label)
	w.intelligence.activate_presets();w.hunger.start();w.director.set_all_enabled(false)
	if w.standard.active():w.standard.install_sites(w.library)
	return w
func walk(w:RefCounted,at:Vector2,actor:String="human")->bool:
	return F.job(w,actor,{"intent":"move","x":at.x,"y":at.y})
func settled(w:RefCounted)->bool:
	for tick in range(5000):
		w.advance(.1)
		if w.dark.pending.is_empty() and not w._routes.has("human"):return true
	return false
func action(w:RefCounted,kind:String,at:Vector2)->bool:
	return w.dark.start(kind,at).ok and settled(w)
func write_json(directory:String,data:Dictionary)->void:
	DirAccess.make_dir_recursive_absolute(directory)
	var file:=FileAccess.open(directory.path_join("island-v2.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(data));file.close()
func read_json(directory:String)->Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("island-v2.json")))
func board(w:RefCounted,ids:Array)->bool:
	return walk(w,w.dark.p(w.dark.config.home_dock)) and w.dark.travel(ids).ok
func conservation(w:RefCounted,expected:int,label:String)->void:
	check(B.wood_total(w)==expected,label+" real total expected="+str(expected)+" actual="+str(B.wood_total(w)))
func run()->void:
	base_dir=OS.get_environment("HABITAT_DATA_DIR")
	if not base_dir.contains("youqi-test-"):quit(1);return
	OS.set_environment("HABITAT_OPENING","legacy")
	for opening in ["standard","showcase"]:core(opening)
	print("Dark island integration: ",checks," checks, failed=",failed)
	quit(1 if failed else 0)
func core(opening:String)->void:
	var w:RefCounted=fresh(opening,opening);var d:RefCounted=w.dark
	if opening=="standard":check(F.job(w,"human",{"intent":"gather_wood","zone_id":"home.forest","tree_count":8}),"standard fixture gathers actual exploration fuel before exploration")
	if not w.error.is_empty() or not d.enabled():check(false,"dark region available "+opening);return
	check(int(w.catalog.regions.dark.size[0])==187 and int(w.catalog.regions.dark.size[1])==240 and d.config.areas.size()==6,"expansion has independent187x240 map and six areas")
	check(d.config.areas.filter(func(a):return a.has("beacon")).size()==4,"four authored beacons, stars has none")
	check(w.barbecues.has("dark.barbecue") and d.life.station.region_id=="dark" and d.life.patches.size()>0,"third independent camp and real mushroom patch")
	check(not w.objects.has("dark.chest") and w.storage!=null,"dock uses the same global warehouse without a chest")
	var home:Dictionary=w.actors.human.duplicate(true);var before:int=B.wood_total(w)
	check(not d.travel(["codex"]).ok and w.actors.human==home,"far boat rejection never moves host")
	check(not d.start("torch",d.p(d.config.camp)).ok,"dark action rejected while on main island")
	if opening=="showcase":
		check(F.job(w,"human",{"intent":"take","target_id":"home.chest.01"}),"host physically takes authored wood before voyage")
		check(int(w.actors.human.carry.get("wood",0))==20,"original capacity twenty remains authoritative")
	var source_stock:int=int(w.actors.human.carry.get("wood",0))
	var legacy_dir:String=base_dir.path_join(opening+"-legacy-source")
	check(Save.save_world(w,legacy_dir),"save untouched opening before new island actions")
	var legacy:Dictionary=read_json(legacy_dir)
	# A genuine schema7 baseline with the new optional field/catalog IDs absent.
	legacy.erase("dark_island")
	if legacy.has("extra_barbecues"):legacy.extra_barbecues.erase("dark.barbecue")
	for id in legacy.objects.keys():
		if str(id).begins_with("dark."):legacy.objects.erase(id)
	var uninvited:Dictionary=w.actors["npc.nora"].duplicate(true)
	check(board(w,["codex","companion-2"]),"host really walks to boat and confirms selected voyage "+opening)
	check(w.actors.human.region_id=="dark" and w.actors.codex.region_id=="dark" and w.actors["companion-2"].region_id=="dark","only selected party crosses")
	check(w.actors["npc.nora"]==uninvited,"uninvited resident remains exactly on main island")
	check(d.permanent(d.p(d.config.arrival)) and not d.permanent(Vector2(44,66)),"dock permanently lit; forest starts dark")
	check(not w.walkable("dark",Vector2(108,50)) and not w.walkable("dark",Vector2(-1,30)),"lake and outside sea are impassable")
	check(w.find_route("human",Vector2(44,66)).size()>0 and w.find_route("human",Vector2(132,66)).size()>0,"both distinct areas reachable through original World grid")
	conservation(w,before,"voyage neither creates nor loses wood")
	var start_at:Vector2=w.point(w.actors.human)
	check(d.start("torch",d.p(d.config.camp)).ok,"host requests first torch near permanent fire")
	check(w.point(w.actors.human)==start_at and B.wood_total(w)==before,"accepted torch action neither teleports nor debits ahead of arrival")
	check(settled(w) and d.torch.owned and d.torch.remaining>0,"torch ignites only after World arrival and gesture")
	conservation(w,before-int(d.config.torch_wood),"first torch spends exactly configured wood")
	check(int(w.actors.human.carry.get("wood",0))==maxi(0,source_stock-int(d.config.torch_wood)),"backpack is used first; empty backpack correctly uses authorized box")
	var after_torch:int=B.wood_total(w)
	check(action(w,"torch",d.p(d.config.camp)),"host refills owned torch at permanent fire")
	check(d.torch.remaining>float(d.config.torch_seconds)-1,"refill resets actual remaining time")
	conservation(w,after_torch,"owned torch refill is free")
	check(not d.start("fire",d.p(d.config.camp)).ok,"small fire rejected in already lit camp")
	check(not d.start("fire",Vector2(108,50)).ok,"small fire rejected in water")
	check(not d.start("beacon",Vector2(44,66)).ok,"non-beacon target cannot light an area")
	check(not d.start("unknown",Vector2(44,66)).ok,"unknown dark action rejected before route or debit")
	if not d.pending.is_empty():w.command("human",{"intent":"stop"});settled(w)
	var fire_a:=Vector2(44,82);var fire_b:=Vector2(44,66)
	check(d.start("fire",fire_a).ok,"interrupt fixture requests a real fire route")
	for tick in range(5000):
		w.advance(.1)
		if d.phase=="ignite":break
	check(d.phase=="ignite" and d.fires.is_empty(),"arrival begins gesture before commit")
	check(w.command("human",{"intent":"stop"}).ok,"explicit host stop interrupts pending ignition")
	w.advance(1)
	check(d.pending.is_empty() and d.fires.is_empty() and B.wood_total(w)==after_torch,"stopped ignition cannot debit or create permanent light")
	check(action(w,"fire",fire_a) and d.fires.size()==1,"first small fire uses real route and completed action")
	conservation(w,after_torch-int(d.config.fire_wood),"first permanent fire spends exactly two")
	check(not d.start("fire",fire_a+Vector2(1,0)).ok,"nearby duplicate fire rejected with no debit")
	check(action(w,"fire",fire_b) and d.fires.size()==2,"second separated fire completes")
	conservation(w,after_torch-2*int(d.config.fire_wood),"second fire spends exactly two")
	check(d.permanent(fire_a) and d.permanent(fire_b) and not d.permanent(Vector2(83,78)),"only permanent source radii stay lit; transient torch adds no explored cells")
	var beacon:Vector2=d.p(d.config.areas.filter(func(a):return a.has("beacon"))[0].beacon)
	check(action(w,"beacon",beacon) and d.beacons.size()==1,"actual beacon action permanently commits one area")
	conservation(w,after_torch-2*int(d.config.fire_wood)-int(d.config.beacon_wood),"beacon spends exactly six")
	check(d.permanent(Vector2(25,30)) and not d.permanent(Vector2(130,30)),"only selected entire area lights")
	var records:Array=w.memories.records.filter(func(e):return e.kind=="dark_beacon")
	check(records.size()==1 and records[0].participants.has("human") and not records[0].participants.has("npc.nora"),"one truthful beacon memory excludes uninvited main-island resident")
	check(not d.start("beacon",beacon).ok,"same beacon cannot debit twice or replay memory")
	check(walk(w,fire_b) and action(w,"torch",fire_b),"permanent small fire can refill torch")
	var exact_remaining:float=d.torch.remaining
	w.advance(float(d.config.torch_seconds)-float(d.config.torch_warning_seconds)+.1)
	check(d.torch.remaining>0 and d.torch.remaining<float(d.config.torch_warning_seconds),"real advance crosses warning at about100 seconds")
	check(d.events.any(func(e):return e.kind=="torch_warning"),"warning event arises from crossing actual remaining threshold")
	w.advance(float(d.config.torch_warning_seconds)+.1)
	check(d.torch.remaining==0 and d.visible_radius()==float(d.config.bare_radius),"real120 seconds expires torch and restores bare radius")
	check(d.events.any(func(e):return e.kind=="torch_out"),"one actual expiry event recorded")
	var no_fire_stock:int=B.wood_total(w)
	check(action(w,"fire",Vector2(85,80)) and B.wood_total(w)==no_fire_stock-int(d.config.fire_wood),"wood alone ignites a real fire with extinguished torch")
	check(action(w,"torch",fire_b),"extinguished owned torch relights free at permanent fire")
	conservation(w,no_fire_stock-int(d.config.fire_wood),"free torch relight preserves wood after actual new fire debit")
	# A real dark chop exercises planting, physical drops, interrupted receipts and reload.
	if not w.actors.human.carry.is_empty():check(F.job(w,"human",{"intent":"store","target_id":"dark.chest"}),"host physically stores carried wood in dock chest before taking axe")
	check(walk(w,fire_b) and action(w,"torch",fire_b),"host really returns to permanent fire before chopping")
	var pre_chop:int=B.wood_total(w)
	check(w.command("human",{"intent":"chop","target_id":"dark.tree.00"}).ok,"host starts real dark tree job")
	for tick in range(5000):
		w.advance(.1)
		if d.torch.planted and w.actors.human.activity=="chopping":break
	check(d.torch.planted and w.actors.human.activity=="chopping" and d.events.any(func(e):return e.kind=="torch_plant"),"torch planting gesture finishes before real axe work")
	var planted_before:float=d.torch.remaining;var planted_at:Array=d.torch.position.duplicate()
	w.advance(.4)
	check(is_equal_approx(float(d.torch.remaining),planted_before-.4) and d.torch.position==planted_at,"planted torch keeps its actual position and countdown")
	var planted_dir:String=base_dir.path_join(opening+"-planted")
	check(Save.save_world(w,planted_dir),"save real planted torch during active chop")
	var planted_copy:RefCounted=fresh(opening+"-planted-restored",opening)
	var planted_load:Dictionary=Save.load_world(planted_copy,planted_dir)
	check(planted_load.ok and planted_copy.dark.torch.planted and is_equal_approx(float(planted_copy.dark.torch.remaining),float(d.torch.remaining)) and planted_copy.work.jobs.is_empty(),"reload retains planted torch/time but never resumes chop")
	for tick in range(5000):
		w.advance(.1)
		if w.drops.has("drop.dark.tree.00"):break
	check(w.drops.has("drop.dark.tree.00") and int(w.drops["drop.dark.tree.00"].wood)==int(w.forest.settings.normal_wood),"real cut commits exactly configured wood at dark tree")
	conservation(w,pre_chop+int(w.forest.settings.normal_wood),"only actual dark cut adds configured wood")
	var drop_dir:String=base_dir.path_join(opening+"-drop")
	check(Save.save_world(w,drop_dir),"save real dark drop before pickup")
	var drop_copy:RefCounted=fresh(opening+"-drop-restored",opening);var drop_load:Dictionary=Save.load_world(drop_copy,drop_dir)
	check(drop_load.ok and drop_copy.drops.has("drop.dark.tree.00") and int(drop_copy.drops["drop.dark.tree.00"].wood)==int(w.forest.settings.normal_wood) and drop_copy.work.jobs.is_empty() and drop_copy.work.claims.is_empty(),"dark drop reload preserves physical wood and releases old job/claim")
	check(F.wait(w,"human"),"original chop/pickup/haul reaches real dock chest")
	for tick in range(20):w.advance(.1)
	check(not d.torch.planted and d.events.any(func(e):return e.kind=="torch_lift"),"completed hand work automatically lifts live torch")
	conservation(w,pre_chop+int(w.forest.settings.normal_wood),"finished haul conserves all actual cut wood")
	# Save on dark with real action history; no offline torch advancement or running jobs.
	w.advance(3.25);exact_remaining=float(d.torch.remaining)
	var save_dir:String=base_dir.path_join(opening+"-save")
	check(Save.save_world(w,save_dir),"save real dark progress "+opening)
	var restored:RefCounted=fresh(opening+"-restored",opening)
	var loaded:Dictionary=Save.load_world(restored,save_dir)
	if not loaded.ok:diagnose(restored,read_json(save_dir))
	check(loaded.ok and loaded.get("loaded",false),"reload valid dark save "+opening+": "+str(loaded))
	if loaded.ok:
		check(restored.actors.human.region_id=="dark" and restored.actors.codex.region_id=="dark","reload retains each person's actual region")
		check(restored.dark.fires==d.fires and restored.dark.beacons==d.beacons,"reload retains exact permanent light sources")
		check(is_equal_approx(float(restored.dark.torch.remaining),exact_remaining),"offline load does not advance torch seconds")
		check(restored.work.jobs.is_empty() and restored.work.claims.is_empty() and restored._routes.is_empty() and restored.dark.pending.is_empty(),"reload stops jobs, claims, routes and pending ignition")
		conservation(restored,B.wood_total(w),"reload preserves every real remaining wood")
	var old_dir:String=base_dir.path_join(opening+"-old")
	write_json(old_dir,legacy)
	var old:RefCounted=fresh(opening+"-old-restored",opening);loaded=Save.load_world(old,old_dir)
	check(loaded.ok and loaded.get("loaded",false),"schema7 missing optional new island state still loads "+opening)
	if loaded.ok:
		check(old.actors.human.region_id=="home" and old.dark.fires.is_empty() and old.dark.beacons.is_empty() and not old.dark.torch.owned,"old save starts unchanged home with dark island unlit except camp")
		conservation(old,before,"old save no resource backfill")
	var saved:Dictionary=d.saved();var malformed:Dictionary=saved.duplicate(true)
	malformed.torch.remaining=-1
	check(not d.valid(malformed,w.actors),"negative saved torch time rejected")
	malformed=saved.duplicate(true);malformed.torch.remaining=float(d.config.torch_seconds)+1
	check(not d.valid(malformed,w.actors),"oversized saved torch time rejected")
	malformed=saved.duplicate(true);malformed.beacons.append("invented")
	check(not d.valid(malformed,w.actors),"unknown saved beacon rejected")
	malformed=saved.duplicate(true);malformed.fires.append(malformed.fires[0].duplicate(true))
	check(not d.valid(malformed,w.actors),"duplicate saved fire ID rejected")
	malformed=saved.duplicate(true);malformed.fires[0].position=[108,50]
	check(not d.valid(malformed,w.actors),"saved fire in lake rejected")
	malformed=saved.duplicate(true);malformed.torch.planted=true;malformed.torch.position=[-10,20]
	check(not d.valid(malformed,w.actors),"planted saved torch outside island rejected")
	var permanent_position:Array=d.fires[0].position.duplicate()
	saved.fires[0].position[0]+=1
	check(d.fires[0].position==permanent_position,"saved snapshot deeply copies light coordinates")
	var permanent_ids:Array=d.fires.map(func(fire):return fire.id)
	var return_party:Array=w.actors.keys().filter(func(id):return w.actors[id].region_id=="dark")
	check(walk(w,d.p(d.config.dock)) and d.travel([]).ok,"host explicitly returns by actual boat route")
	check(return_party.all(func(id):return w.actors[id].region_id=="home") and d.party.is_empty(),"every visitor returns, no resident left behind")
	check(d.fires.map(func(fire):return fire.id)==permanent_ids and d.beacons.size()==1,"leaving island preserves all permanent light IDs")

func diagnose(w:RefCounted,data:Dictionary)->void:
	print("DARK SAVE DIAGNOSTIC dark=",w.dark.valid(data.get("dark_island",{}),data.actors)," interior=",Save._valid_interior(w,data)," life=",Save._valid_life(w,data.shared_life,data.actors))
	for id in data.get("extra_barbecues",{}):print("DARK SAVE DIAGNOSTIC extra ",id,"=",Save._valid_life(w,data.extra_barbecues[id],data.actors,w.barbecues[id]))
	for id in data.actors:
		var actor:Dictionary=data.actors[id]
		print("DARK SAVE DIAGNOSTIC actor ",id," region=",actor.region_id," position=",actor.position," walkable=",w.walkable(actor.region_id,w.point(actor)))
	for id in data.objects:
		var object:Dictionary=data.objects[id]
		if object.kind=="tree" and not w.forest.valid_tree(object,w.catalog._number):print("DARK SAVE DIAGNOSTIC tree ",id,"=",object)
	print("DARK SAVE DIAGNOSTIC farming=",w.farms.valid_saved(data.farming,data.actors)," leisure=",w.leisure.valid_saved(data.leisure)," fishing=",w.fishing.valid_saved(data.fishing,data.actors)," memories=",w.memories.valid_saved(data.shared_memories,data.actors,data.world_id)," hunger=",w.hunger.valid(data.hunger,data.actors)," homestead=",w.homestead.valid_saved(data.homestead,data)," relationships=",w.relationships.valid_saved(data.relationships,data.actors)," days=",w.days.valid_saved(data.day_cycle,data.actors,data.get("forest_clock")))

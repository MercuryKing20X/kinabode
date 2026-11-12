extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Library=preload("res://scripts/character_library.gd")
const Opening=preload("res://scripts/world_opening.gd")
const Save=preload("res://scripts/save_store.gd")
const F=preload("res://tests/cooking_fixture.gd")
const BBQ=preload("res://tests/barbecue_fixture.gd")
var checks:=0
var failed:=false
var library:RefCounted
var directory:String
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func fresh()->RefCounted:
	var w:=World.new("res://content/home-v3/world.json");w.library=library;w.residents.provision(w);w.director.set_all_enabled(false)
	assert(Opening.apply(w,library).ok);return w
func go(w:RefCounted,id:String,p:Array)->bool:return F.job(w,id,{"intent":"move","x":p[0],"y":p[1]}) and w.point(w.actors[id]).distance_to(Vector2(p[0],p[1]))<.7
func _initialize()->void:
	directory=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	library=Library.new();library.configure(directory)
	var w:=fresh();var layout:Dictionary=w.catalog.regions.home.layout
	check(w.farms.containers.is_empty(),"one physical shared seed and one harvest chest")
	check(w.farms.container_id("farm.home","harvest")==w.farms.container_id("farm.east","harvest"),"farms refer to canonical shared stock")
	check(w.life.activity_rules.seat_offsets.size()==6,"six validated camp seats")
	check(w.point(w.life.station)==Vector2(w.map_anchor("camp.stove")[0],w.map_anchor("camp.stove")[1]),"cook and barbecue same canonical station")
	check(w.fishing.pens.size()==2,"two real fisheries loaded")
	check(w.observe("codex").template_id=="home-v3","observe identifies new template")
	check(w.read_map("codex",{}).ok,"bound map API reads new catalog")
	check(w.interior.rooms().values().all(func(room):return not room.owner_id.is_empty()),"all rooms have stable owners")
	check(not w.command("codex",{"intent":"take","target_id":"home.private.01","item_id":"wood"}).ok,"model cannot take human private items")
	check([{"id":"storage","items":w.storage.saved().items,"capacity":9007199254740991,"kind":"storage"}].all(func(c):return w.storage_owner(c).is_empty()),"automatic supply excludes private homes")
	var human:Array=w.actors.human.position.duplicate();var before:=F.amount(w,"turnip")
	var positions:Dictionary=w.actors.duplicate(true)
	check(not w.command("codex",{"intent":"cook","recipe_id":"turnip-soup"}).ok and w.actors==positions,"removed independent chef cannot move or operate human")
	check(F.serve(w,"turnip-soup"),"host real fire accepts existing recipe")
	check(F.amount(w,"turnip")==before-3 and w.life.fireside.state.current.total==3,"real ingredients converted exactly once")
	check(F.eat(w,"human") and F.eat(w,"codex") and F.cleanup(w),"selected host and companion actually eat on fire")
	check(w.life.fireside.state.current.eaten==2 and w.life.fireside.state.current.wasted==1 and w.life.station.portions==0,"extra recipe output wasted without leftovers")
	w=fresh();before=F.amount(w,"turnip")
	check(F.serve(w,"turnip-soup"),"cancellation fixture uses real host fire")
	w.life.fireside.end_circle("host cancellation")
	check(F.amount(w,"turnip")==before-3 and w.life.fireside.state.current.eaten+w.life.fireside.state.current.wasted==3,"cancel conserves original recipe receipt as consumed output")
	check(Save.save_world(w,directory),"canceled real food saves")
	var restored:=World.new("res://content/home-v3/world.json");restored.library=library
	check(Save.load_world(restored,directory).ok and F.amount(restored,"turnip")==before-3 and restored.work.jobs.is_empty() and restored.life.station.portions==0,"reload never recreates food or claims")
	w=fresh();check(go(w,"human",w.map_anchor("dock.south.end")),"human explicitly walks to south dock")
	var fish_result:Dictionary=w.command("human",{"intent":"fish"});check(fish_result.ok,"dock is natural sea fishing, not enclosure fishing: "+str(fish_result))
	if fish_result.ok:
		check(F.wait(w,"human") and w.fishing.fish.values().filter(func(f):return f.owner_id=="human" and f.location=="storage").size()==1,"actual elapsed fishing yields one real instance")
		var fish:Dictionary=w.fishing.fish.values().filter(func(f):return f.owner_id=="human" and f.location=="storage")[0];human=w.actors.human.position.duplicate()
		check(w.command("human",{"intent":"stock_fish","fish_id":fish.id,"pen_id":"home.fishery.south"}).ok and w.fishing.fish.size()==1,"stock transfers existing fish without duplication")
		check(w.actors.human.position==human,"stocking does not move human")
	w=fresh();var tree:Dictionary=w.objects.values().filter(func(o):return o.kind=="tree" and o.zone_id=="home.forest")[0]
	before=F.amount(w,"wood")
	check(F.job(w,"codex",{"intent":"gather_wood","target_id":tree.id,"zone_id":tree.zone_id,"tree_count":1}),"new forest real chop-and-haul task completes")
	check(tree.status=="stump" and F.amount(w,"wood")==before+int(w.forest.settings.large_wood if int(tree.wood_yield)>8 else w.forest.settings.normal_wood) and {"id":"storage","items":w.storage._items,"capacity":9007199254740991,"kind":"storage","region_id":"home","position":w.actors.human.position}.items.get("wood",0)==before+int(w.forest.settings.large_wood if int(tree.wood_yield)>8 else w.forest.settings.normal_wood),"one real tree yields configured wood stored in warehouse")
	for table in ["play.gomoku","play.gomoku.2"]:
		w=fresh();check(w.gomoku.begin_host(table,"codex",true,"local","easy").ok,"host can start at "+table)
		for frame in range(600):
			w.advance(.1)
			if w.gomoku.sessions[table].phase=="playing":break
		check(w.gomoku.sessions[table].phase=="playing","both players really reach/seat at "+table)
	w=fresh()
	var total:int=F.amount(w,"seed.turnip")
	check(F.withdraw(w,"human","seed.turnip"),"real shared seed pickup through selected farm")
	check(F.amount(w,"seed.turnip")==total and w.actors.human.carry.get("seed.turnip")==4,"shared pickup neither duplicates nor loses seeds")
	check(w.deposit_all("human").ok and F.amount(w,"seed.turnip")==total,"shared seed return conserves stock")
	var mature:Dictionary=w.farms.farm_plots("farm.home").filter(func(p):return w.farms.stage(p)=="mature")[0]
	var crop:String=mature.crop_id;before=F.amount(w,crop)
	check(F.job(w,"human",{"intent":"harvest","target_id":mature.id}),"real harvest reaches shared harvest chest")
	check(F.amount(w,crop)==before+int(w.farms.crops[crop].yield),"only actual harvest creates configured produce")
	check(not w.command("companion-2",{"intent":"manage_farm","farm_id":"farm.home","mode":"harvest"}).ok,"shared box does not grant another manager control of crops")
	w=fresh()
	var growth:float=w.farms.crops.values().reduce(func(total,crop):return maxf(total,float(crop.seconds)),0.0)
	w.advance(growth+1) # Real maturation before testing a finite full-harvest completion.
	check(w.command("codex",{"intent":"manage_farm","farm_id":"farm.home","mode":"harvest"}).ok,"continuous harvest order accepts own farm")
	for frame in range(6000):
		w.advance(.2)
		if w.farms.orders.codex.status not in ["working","waiting"]:break
	check(w.farms.orders.codex.status=="completed" and w.actors.codex.carry.is_empty(),"continuous harvest uses shared storage to finish without stranded stock")
	check(go(w,"codex",w.map_anchor("plaza.north")),"explicitly enter nearby routine area before checking bounded schedule choices")
	var options:Array=w.schedules.options("codex")
	check(not options.is_empty() and options.all(func(e):return w.walkable("home",e.point)),"schedule anchors are real walkable destinations")
	var measurements:Array=[]
	for plot in w.catalog.regions.home.layout.residential:
		if str(plot.owner_id).is_empty():continue
		w=fresh();var door:Vector2=w.interior.outside("room."+str(plot.site_id))
		check(go(w,"human",[door.x,door.y]),"explicit measurement walk to "+str(plot.site_id))
		var gates:Array=[w.map_anchor("plaza.northwest"),w.map_anchor("plaza.north"),w.map_anchor("plaza.northeast")]
		gates.sort_custom(func(a,b):return door.distance_squared_to(Vector2(a[0],a[1]))<door.distance_squared_to(Vector2(b[0],b[1])))
		var elapsed:=walk_seconds(w,gates[0]);check(elapsed<=8,"actual home-to-plaza walk within eight seconds "+str(plot.owner_id)+" "+str(elapsed))
		measurements.append({"target":"plaza","owner":plot.owner_id,"seconds":elapsed,"start":plot.site_id,"limit":8})
	for farm in w.catalog.regions.home.layout.farms:
		w=fresh();assert(go(w,"human",w.map_anchor("plaza.south")))
		var elapsed:=walk_seconds(w,farm.entrance)
		check(is_finite(elapsed),"new-layout farm remains reachable "+farm.id+" "+str(elapsed))
		measurements.append({"target":farm.id,"seconds":elapsed,"start":"plaza.south","limit":null})
	for pair in [["dock.south.end","plaza.south"],["dock.west.end","plaza.west"],["logging.entry","plaza.east"]]:
		w=fresh();assert(go(w,"human",w.map_anchor(pair[1])))
		var elapsed:=walk_seconds(w,w.map_anchor(pair[0]))
		check(is_finite(elapsed),"new-layout facility remains reachable "+pair[0]+" "+str(elapsed))
		measurements.append({"target":pair[0],"seconds":elapsed,"start":pair[1],"limit":null})
	var output:String=OS.get_environment("HABITAT_STAGE2_EVIDENCE")
	if not output.is_empty():
		var file:=FileAccess.open(output.path_join("2C-actual-distances.json"),FileAccess.WRITE);file.store_string(JSON.stringify(measurements,"  "))
	print("Home v3 systems: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)

func walk_seconds(w:RefCounted,destination:Array)->float:
	if not w.command("human",{"intent":"move","x":destination[0],"y":destination[1]}).ok:return INF
	var elapsed:=0.0
	while w._routes.has("human") and elapsed<120:
		w.advance(.05);elapsed+=.05
	if w.point(w.actors.human).distance_to(Vector2(destination[0],destination[1]))>.7:return INF
	return snappedf(elapsed,.05)

extends SceneTree
## Logic/boundary fixtures only; real seed, route, water and warehouse acceptance is
## test_farm_helpers_1105.gd and uses native InputEvent in a genuine opening.
const World=preload("res://scripts/world_state.gd")
const Library=preload("res://scripts/character_library.gd")
const Opening=preload("res://scripts/world_opening.gd")
const IDS=["codex","companion-2","npc.mira","npc.nora"]
var checks:int=0
var failed:bool=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func fresh()->RefCounted:
	var w:RefCounted=World.new("res://content/home-v3/world.json");w.residents.provision(w)
	w.library=Library.new();w.library.configure(OS.get_environment("HABITAT_DATA_DIR"))
	check(Opening.apply(w,w.library,"standard").ok,"true standard fixture")
	w.intelligence.activate_presets();w.director.set_all_enabled(false);w.hunger.start()
	return w
func run()->void:
	var w:RefCounted=fresh();var before:Dictionary=w.storage.saved()
	var p:Dictionary=w.farms.preview_host_orders(IDS,"plant","","mixed")
	check(p.rows.size()==4 and p.rows.all(func(r):return r.eligible and r.farm_id=="farm.home"),"unbuilt fields never used; four share sole built field")
	var missing:int=0;var assigned:int=0
	for row in p.rows:
		assigned+=row.plot_ids.size()
		for n in row.missing.values():missing+=int(n)
	check(assigned==8 and missing==4,"twelve real plots, eight funded, four missing counted exactly once")
	check(w.storage.saved()==before and w.farms.orders.is_empty(),"preview has no inventory or task effects")
	var tampered:Dictionary=p.duplicate(true);tampered.rows[0].farm_id="farm.hill"
	check(not w.farms.confirm_host_orders(tampered).ok and w.farms.orders.is_empty(),"modified sealed targets rejected")
	check(not w.farms.confirm_host_orders(p,[]).ok and w.farms.orders.is_empty(),"explicit empty checkbox subset never means everyone")
	var r:Dictionary=w.farms.confirm_host_orders(p,["npc.mira"])
	check(r.ok and r.rows.size()==1 and r.rows[0].actor_id=="npc.mira" and r.rows[0].has("order_id"),"checkbox subset never enrolls unselected people")
	check(w.storage.saved()==before and w.farms.orders.size()==1,"acceptance does not prepay or create any harvest")
	check(w.farms.orders["npc.mira"].host_order_id==r.rows[0].order_id,"exact session token bound to this order")
	check(w.farms.host_grants["npc.mira"].plot_ids==p.rows[2].plot_ids,"confirmation retains original exact plot subset")
	check(not w.command("npc.mira",{"intent":"manage_farm","farm_id":"farm.home","crop_id":"mixed","mode":"plant"}).ok,"active grant cannot authorize unrelated public command")
	check(not w.command("npc.mira",{"intent":"plant","target_id":p.rows[0].plot_ids[0],"crop_id":"turnip"}).ok,"social resident gets no general work tool capability")
	var active_saved:Dictionary=w.farms.saved()
	check(not active_saved.orders["npc.mira"].has("host_order_id") and w.farms.valid_saved(active_saved,w.actors),"strict original save supports order but excludes session token")
	w.farms.pause("npc.mira")
	check(not w.farms.host_grants.has("npc.mira") and not w.farms.allowed("npc.mira","farm.home"),"pause releases authorization without manager change")
	var again:Dictionary=w.farms.preview_host_orders(["npc.mira"],"plant","farm.home","mixed")
	var next:Dictionary=w.farms.confirm_host_orders(again)
	check(next.ok and next.rows[0].order_id!=r.rows[0].order_id and w.farms.orders["npc.mira"].completed.is_empty(),"new confirmation owns fresh token and bookkeeping")
	check(w.command("npc.mira",{"intent":"stop"}).ok and not w.farms.host_grants.has("npc.mira"),"real stop command revokes scoped grant")
	w.farms.restore(active_saved)
	check(w.farms.host_grants.is_empty() and w.farms.orders["npc.mira"].status=="paused" and not w.farms.orders["npc.mira"].has("host_order_id"),"reload cannot restore permission, tracking token or running order")
	w=fresh();p=w.farms.preview_host_orders(IDS,"plant","farm.home","mixed")
	w.storage._items.erase("seed.turnip");w.storage._items.erase("seed.tomato")
	r=w.farms.confirm_host_orders(p)
	check(not r.ok and w.farms.orders.is_empty() and r.rows.all(func(row):return row.error=="no_seed"),"stock change rechecked before any enrollment; no fake completion")
	w=fresh();p=w.farms.preview_host_orders(IDS,"plant","farm.home","mixed")
	w.work.claims[p.rows[0].plot_ids[0]]="human"
	r=w.farms.confirm_host_orders(p,["codex"])
	check(not r.ok and r.rows[0].error=="changed" and w.farms.orders.is_empty(),"claimed plot invalidates exact row without substitution")
	w=fresh();w.hunger.states["npc.mira"].elapsed=float(w.hunger.config.thresholds[3])+1
	w.hunger.states["npc.nora"].elapsed=float(w.hunger.config.thresholds[2])+1
	w.actors["companion-2"].region_id="room.home.house.01"
	p=w.farms.preview_host_orders(IDS,"plant","farm.home","mixed")
	check(p.rows[1].reason=="different_region" and p.rows[2].reason=="very_hungry" and p.rows[3].reason=="hungry","unchanged hunger gates and different island reason")
	# Own carry is available only to its actual owner, not a shared invisible seed pool.
	w=fresh();w.storage._items.erase("seed.turnip");w.storage._items.erase("seed.tomato")
	for id in IDS:w.actors[id].carry={"seed.turnip":1}
	p=w.farms.preview_host_orders(IDS,"plant","farm.home","turnip")
	check(p.rows.all(func(row):return row.plot_ids.size()==1),"independent retained own seeds budgeted once")
	r=w.farms.confirm_host_orders(p)
	check(r.ok and r.rows.all(func(row):return row.ok),"own-carry seeds do not count against another resident")
	w=fresh();check(w.activities.set_followers(IDS).ok,"explicit diagnostic host-follow fixture")
	check(not w.command("npc.mira",{"intent":"manage_farm","farm_id":"farm.home","crop_id":"mixed","mode":"plant"}).ok and w.activities.following.has("npc.mira"),"ordinary social tool cannot escape following or self-authorize")
	p=w.farms.preview_host_orders(["npc.mira"],"plant","farm.home","mixed")
	r=w.farms.confirm_host_orders(p)
	check(r.ok and w.farms.active("npc.mira") and w.activities.following.has("npc.mira") and w.activities.following.size()==4 and not w.hunger.owned_routes.has("npc.mira"),"exact confirmed farm order pauses only selected actor follow route while retaining return preference")
	var own_order:String=w.farms.orders["npc.mira"].host_order_id
	for tick in 20:w.advance(.1)
	check(w.farms.orders["npc.mira"].host_order_id==own_order and not w.hunger.owned_routes.has("npc.mira") and IDS.filter(func(who):return who!="npc.mira").all(func(who):return w.activities.following.has(who) and not w.farms.active(who)),"real farm advance never gets replaced by follow and unselected preferences/orders stay unchanged")
	w=fresh();w.activities.set_followers(IDS);w.hunger.states["npc.mira"].elapsed=float(w.hunger.config.thresholds[2])+1
	check(not w.farms.host_order("npc.mira","farm.home","mixed","plant").ok and w.activities.following.has("npc.mira"),"rejected hungry order preserves following")
	# Boundary geometry fixture only: retained showcase positions and two authored farm entries.
	w=World.new("res://content/home-v3/world.json");w.residents.provision(w);w.library=Library.new();w.library.configure(OS.get_environment("HABITAT_DATA_DIR").path_join("nearby"));check(Opening.apply(w,w.library,"showcase").ok,"actual showcase geometry for distance boundary")
	w.director.set_all_enabled(false)
	for plot in w.farms.plots.values():plot.crop_id="";plot.watered=false
	w.actors.human.position=w.farms.farms["farm.home"].meeting_at.duplicate()
	p=w.farms.preview_host_orders(IDS,"plant","","mixed")
	check(p.rows.all(func(row):return row.farm_id=="farm.home"),"unspecified field keeps all four at nearest available twelve-plot field")
	# Nearest-field boundary uses a real productive main-island field; vacation gardens are disabled.
	w.actors.human.position=w.farms.farms["farm.east"].meeting_at.duplicate()
	p=w.farms.preview_host_orders(IDS,"plant","","mixed")
	check(p.rows.all(func(row):return row.farm_id=="farm.east"),"nearest actual main-island field selected rather than dictionary-first field")
	for plot in w.farms.farm_plots("farm.east").slice(1):w.work.claims[plot.id]="human"
	p=w.farms.preview_host_orders(IDS,"plant","","mixed")
	check(p.rows[0].farm_id=="farm.east" and p.rows.slice(1).all(func(row):return row.farm_id!="farm.east"),"one nearest real slot enrolls one person; overflow selects next nearest available field")
	print("Farm host plan: ",checks," checks, failed=",failed);quit(1 if failed else 0)

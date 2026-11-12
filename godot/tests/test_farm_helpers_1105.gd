extends "res://tests/test_ingredient_native_input.gd"
const Opening=preload("res://scripts/world_opening.gd")
var checks:int=0
var failed:bool=false
const IDS=["codex","companion-2","npc.mira","npc.nora"]
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func fresh(chosen:String)->void:
	if is_instance_valid(game):game.queue_free();await process_frame
	OS.set_environment("HABITAT_OPENING","legacy" if chosen=="showcase" else chosen);root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.world.director.set_all_enabled(false);game.chat.hide()
	await process_frame;await process_frame
	check(game.world.opening_id==chosen,"genuine chosen opening "+chosen)
func invite(mode:String)->Node:
	var first:Dictionary=game.world.farms.farm_plots("farm.home")[0]
	await click_world(game.world.point(first));check(game.farm_panel.visible,"native field click opens farm")
	check(await UI.click(self,game.farm_panel.helpers_button),"native helpers click")
	var dialog:Node=UI.shown(game,"res://scripts/farm_invitation.gd")
	check(dialog!=null and dialog.checks.size()==4 and IDS.all(func(id):return dialog.checks.has(id)),"all four stable residents listed")
	if dialog==null:return null
	check(await UI.click(self,dialog.all_box),"native all checkbox")
	check(dialog.selected_ids().size()==4,"all selects exactly four")
	await capture("farm-four-"+mode,game.world.point(first))
	var button:Button=dialog.get_ok_button()
	if mode=="ready":button=dialog.harvest_button
	check(await UI.click(self,button),"native explicit "+mode+" confirmation")
	return dialog
func until_done()->void:
	for i in range(4000):
		game.world.advance(.2)
		if IDS.all(func(id):return not game.world.farms.active(id) and not game.world.work.jobs.has(id) and not game.world.deliveries.active(id)):return
	check(false,"bounded genuine routes and order completion")
func run()->void:
	await fresh("standard")
	var w:RefCounted=game.world
	var stock:Dictionary=w.storage.saved().duplicate(true);var managers:Dictionary={}
	for fid in w.farms.farms:managers[fid]=w.farms.farms[fid].manager_id
	var p:Dictionary=w.farms.preview_host_orders(IDS,"plant","farm.home","mixed")
	check(w.storage.saved()==stock and w.farms.orders.is_empty() and w.work.jobs.is_empty(),"preview is pure and never prepays seeds")
	check(p.rows.size()==4 and p.rows.all(func(r):return r.eligible and r.plot_ids.size()==2),"real standard eight seeds split two plots each")
	var unique:Dictionary={}
	for row in p.rows:
		for pid in row.plot_ids:check(not unique.has(pid),"no duplicate planned plot");unique[pid]=true
	await invite("plant")
	var tokens:Dictionary={}
	for id in IDS:
		check(w.farms.active(id) and w.farms.orders[id].has("host_order_id"),"selected resident has exact session order "+id);tokens[id]=w.farms.orders.get(id,{}).get("host_order_id","")
	var scope:Dictionary={}
	for id in IDS:scope[id]=w.farms.host_grants.get(id,{}).duplicate(true)
	await until_done()
	var plots:Array=w.farms.farm_plots("farm.home")
	check(plots.filter(func(x):return not x.crop_id.is_empty() and x.watered).size()==8,"eight actual seeds planted and first-watered")
	check(w.storage.count("seed.turnip")==0 and w.storage.count("seed.tomato")==0,"exact eight seeds deducted only by real arrival commits")
	check(w.actors.human.carry.is_empty() and not w.farms.orders.has("human"),"helper selection never authorizes human work")
	for id in IDS:
		check(w.farms.orders[id].status=="completed" and w.farms.orders[id].completed.size()==2,"each real actor watered its two unique plots "+id)
		check(not w.farms.host_grants.has(id),"completion revokes grant "+id)
		check(not w.farms.saved().orders[id].has("host_order_id"),"session token never saved "+id)
	for fid in managers:check(w.farms.farms[fid].manager_id==managers[fid],"manager unchanged "+fid)
	await capture("farm-four-watered",w.point(plots[0]))
	# Boundary fixtures below deliberately mutate only isolated diagnostic states.
	for id in IDS:w.hunger.states[id].elapsed=0.0
	var no_seed:Dictionary=w.farms.preview_host_orders(IDS,"plant","farm.home","mixed")
	check(no_seed.rows.all(func(r):return not r.eligible and r.reason=="no_seed" and not r.missing.is_empty()),"no seeds reports missing counts, no false completed order")
	w.hunger.states["npc.mira"].elapsed=float(w.hunger.config.thresholds[3])+1
	w.hunger.states["npc.nora"].elapsed=float(w.hunger.config.thresholds[2])+1
	w.actors["companion-2"].region_id="room.home.house.01"
	var blocked:Dictionary=w.farms.preview_host_orders(IDS,"plant","farm.home","mixed")
	check(blocked.rows[1].reason=="different_region" and blocked.rows[2].reason=="very_hungry" and blocked.rows[3].reason=="hungry","accurate region and unchanged two hunger boundaries")
	# Diagnostic-only state fixtures: inspect actual disabled UI and native All behavior.
	await click_world(w.point(w.farms.farm_plots("farm.home")[0]))
	check(await UI.click(self,game.farm_panel.helpers_button),"native open diagnostic refusal list")
	var grey:Node=UI.shown(game,"res://scripts/farm_invitation.gd")
	check(grey!=null and grey.checks["npc.mira"].disabled and grey.checks["npc.nora"].disabled and grey.checks["companion-2"].disabled,"hungry and foreign-region choices disabled in actual UI")
	if grey!=null:
		check(await UI.click(self,grey.all_box) and grey.selected_ids()==["codex"],"native All excludes disabled companions")
		await capture("farm-disabled-reasons",w.point(w.farms.farm_plots("farm.home")[0]))
		await key(KEY_ESCAPE)
	# Genuine showcase maturity provides harvested produce without creating crops for the test.
	await fresh("showcase");w=game.world
	var before:Dictionary=w.storage.saved().items.duplicate(true);var ripe:Array=w.farms.farm_plots("farm.home").filter(func(x):return w.farms.stage(x)=="mature")
	check(not ripe.is_empty(),"authored showcase has genuinely ripe batch")
	var expected_yield:int=0
	for plot in ripe:expected_yield+=int(w.farms.crops[plot.crop_id].yield)
	var hp:Dictionary=w.farms.preview_host_orders(IDS,"ready","farm.home","")
	var allowed:Array=hp.rows.filter(func(r):return r.eligible).map(func(r):return r.actor_id)
	await invite("ready");await until_done()
	var gain:int=0
	for item in w.storage.saved().items:
		if not str(item).begins_with("seed.") and item!="wood":gain+=w.storage.count(item)-int(before.get(item,0))
	print("HARVEST_DIAGNOSTIC ",{"gain":gain,"ripe":ripe.size(),"orders":w.farms.orders,"jobs":w.work.jobs,"carry":IDS.map(func(id):return w.actors[id].carry),"note":game.farm_panel.note.text})
	check(gain==expected_yield,"exact actual ripe yield deposited into sole warehouse")
	check(allowed.all(func(id):return w.farms.orders.get(id,{}).get("status")=="completed" and w.actors[id].carry.is_empty() and not w.farms.host_grants.has(id)),"harvest completes only after true warehouse delivery")
	await capture("farm-four-harvested",w.point(w.farms.farm_plots("farm.home")[0]))
	game.queue_free();await process_frame
	print("Farm helpers 1105: ",checks," checks, failed=",failed);quit(1 if failed else 0)

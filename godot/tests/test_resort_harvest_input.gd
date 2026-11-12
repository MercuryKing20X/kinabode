extends "res://tests/test_intelligence_core_input.gd"
## Integration/UI — targeted native command test — BLOCKING.
## Preparation uses original explicit host jobs/real growth/real meals, never stock grants.
const BBQ=preload("res://tests/barbecue_fixture.gd")
const Cook=preload("res://tests/cooking_fixture.gd")
func step(seconds:float)->void:
	for i in int(seconds*10):
		game._process(.1);game.local_host_commands._process(.1)
		if i%200==0:await process_frame
func meal()->void:
	var w:RefCounted=game.world
	check(BBQ.approach(w),"host takes original route to camp")
	check(w.life.fireside.light_host().ok,"real camp fuel")
	check(w.life.fireside.invite(["companion-2"]).ok,"explicit preparation meal invite")
	check(w.life.fireside.roast_host("single:mushroom").ok,"real mushroom receipt")
	await step(50)
	check("companion-2" in w.life.fireside.state.current.eaters,"blue eats actual meal")
	w.life.fireside.end_circle("preparation complete")
func run()->void:
	await fresh()
	var w:RefCounted=game.world
	check(Cook.job(w,"human",{"intent":"gather_wood","tree_count":3}),"human obtains real fuel by original wood job")
	check(Cook.job(w,"human",{"intent":"forage","target_id":"home.mushrooms.1"}),"human picks real mushrooms")
	check(Cook.job(w,"human",{"intent":"build_facility","target_id":"play.standard.camp"}),"original camp construction")
	var plot:Dictionary=w.farms.farm_plots("farm.home")[0]
	check(Cook.job(w,"human",{"intent":"plant","target_id":plot.id,"crop_id":"turnip"}),"human plants one real seed")
	check(Cook.job(w,"human",{"intent":"water","target_id":plot.id}),"original first water")
	await step(500)
	await meal()
	await step(500)
	await meal()
	await step(210)
	check(w.farms.stage(plot)=="mature","actual elapsed growth reaches mature")
	var before:int=w.storage.count("turnip")
	await text_input("小蓝去收菜")
	check(w.farms.active("companion-2"),"native harvest starts true order")
	await step(180)
	check(w.farms.orders.get("companion-2",{}).get("status")=="completed","exact harvest order completes")
	check(w.storage.count("turnip")==before+int(w.farms.crops.turnip.yield),"real crop yield enters warehouse")
	check(w.point(w.actors["companion-2"]).distance_to(w.point(w.actors.human))<=3,"harvester returns within three tiles")
	game.chat.hide();game.view.center=w.point(w.actors.human);game.view.queue_redraw();await picture("harvest-real-return")
	print("RESORT_HARVEST_INPUT ",checks," failed=",failed)
	game.queue_free();await process_frame;quit(1 if failed else 0)

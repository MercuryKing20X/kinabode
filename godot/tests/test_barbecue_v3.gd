# DIRECTION 2026-11-07: 烤蘑菇永久无限供应，不扣任何食材；其它食材守恒断言保留。
extends SceneTree
const H=preload("res://tests/test_barbecue_v2.gd")
var checks:=0
var failed:=false
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failed=true;push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	var h:=H.new();var w:RefCounted=h.fresh(OS.get_environment("HABITAT_DATA_DIR"));w.director.set_all_enabled(false)
	var fire:RefCounted=w.life.fireside;var chest:Dictionary={"id":"storage","items":w.storage._items,"capacity":9007199254740991,"kind":"storage","region_id":"home","position":w.actors.human.position}
	check(h.pickup(w,"wood",3) and h.approach(w,w.life),"real stock pickup and World arrival")
	var before:int=int(chest.items.wood)
	var r:Dictionary=fire.light_host()
	check(r.ok and r.sources.backpack.wood==2 and r.sources.storage.is_empty() and chest.items.wood==before,"backpack enough: exactly two, no chest debit")
	r=fire.light_host()
	check(r.ok and r.sources.backpack.wood==1 and r.sources.storage.is_empty() and chest.items.wood==before,"partial backpack: one plus one, conserved")
	r=fire.light_host()
	check(r.ok and r.sources.backpack.is_empty() and r.sources.storage.wood==1,"empty backpack uses authorized chest")
	# Warehouse has no box owner permission; invalid costs still fail atomically.
	var snapshot:Dictionary=w.storage.saved()
	check(not w.storage.take({"wood":w.storage.count("wood")+1}).ok and w.storage.saved()==snapshot,"insufficient warehouse wood rejects atomically")
	check(w.farms.containers.is_empty(),"farm storage objects removed")
	var menu:Array=fire.menu()
	check(menu[0].id=="single:mushroom" and menu[0].seconds==3,"mushroom first and fastest")
	check(menu.any(func(c):return c.id=="single:apple" and c.maximum==0) and menu.filter(func(c):return c.category=="dish").size()==w.recipes.recipe_catalog.size(),"missing foods and entire recipe catalog retained")
	var mushrooms:int=int(chest.items.mushroom)
	check(not fire.roast_host("single:missing").ok and not fire.roast_host("recipe:missing").ok and chest.items.mushroom==mushrooms,"unknown menu choices reject atomically without debit")
	check(fire.invite(w.standard.config.companions).ok,"explicit guest selection determines five diners")
	r=fire.roast_host("single:mushroom")
	check(r.ok and r.sources.storage.is_empty() and chest.items.mushroom==mushrooms and fire.state.current.receipt.is_empty(),"unlimited mushroom meal has empty debit and receipt; warehouse unchanged")
	for i in range(200):w.advance(.1)
	check(fire.state.current.eaten+fire.state.current.wasted+w.life.station.portions==5,"actual eating conserves portions")
	var used:Array=[]
	for id in fire.seats:used.append(w.life.seats().filter(func(s):return s.id==fire.seats[id])[0])
	for i in range(used.size()):
		for j in range(i):check(w.point(used[i]).distance_to(w.point(used[j]))>2,"seats spread and unique")
	var standard:RefCounted=preload("res://tests/standard_fixture.gd").new();standard.start(OS.get_environment("HABITAT_DATA_DIR").path_join("standard"))
	check(standard.w.life.fireside.menu()[0].maximum>=6,"formal opening immediately exposes actual mushrooms")
	for life in standard.w.barbecues.values():
		if life.station.id=="homelands.barbecue":continue # Retired southern production is covered by vacation rejection tests.
		check(life.patches.values().any(func(p):return standard.w.point(p).distance_to(standard.w.point(life.station))<=5.1),"each camp has nearby configured harvestable mushroom patch")
	h.free();print("Barbecue v3: ",checks," checks, failed=",failed);quit(1 if failed else 0)

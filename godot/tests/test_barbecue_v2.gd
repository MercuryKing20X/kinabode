# DIRECTION 2026-11-07: 烤蘑菇永久无限供应，不扣任何食材；其它食材守恒断言保留。
extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
const World=preload("res://scripts/world_state.gd")
const Save=preload("res://scripts/save_store.gd")
var checks:=0
var failed:=false
func check(ok:bool,msg:String)->void:
	checks+=1
	if not ok:failed=true;push_error(msg)
func advance(w:RefCounted,seconds:float)->void:
	for frame in range(ceili(seconds/.1)):w.advance(.1)
func fresh(dir:String)->RefCounted:
	var w:=World.new("res://content/home-v3/world.json");w.residents.provision(w);w.library=preload("res://scripts/character_library.gd").new();w.library.configure(dir);assert(preload("res://scripts/world_opening.gd").apply(w,w.library).ok);w.hunger.start();w.director.set_all_enabled(false);return w
func pickup(w:RefCounted,item:String,n:int)->bool:
	for chest in [{"id":"storage","items":w.storage.saved().items,"capacity":9007199254740991,"kind":"storage"}]:
		if int(chest.items.get(item,0))>=n:
			if not w.work.take_food_host(chest.id,item,n).ok:return false
			for frame in range(3000):
				w.advance(.1)
				if not w.work.jobs.has("human"):return true
	return false
func approach(w:RefCounted,life:RefCounted)->bool:
	var at:Vector2=w.point(life.station)+Vector2(2.5,0)
	return F.job(w,"human",{"intent":"move","x":at.x,"y":at.y})
func _initialize()->void:call_deferred("run")
func run()->void:
	var dir:=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-test-"))
	var w:=fresh(dir);var life:RefCounted=w.life;var chest:Dictionary={"id":"storage","items":w.storage._items,"capacity":9007199254740991,"kind":"storage","region_id":"home","position":w.actors.human.position};var all_stock:Dictionary=chest.items.duplicate()
	check(not life.fireside.light_host().ok and chest.items==all_stock,"far lighting never takes any chest material")
	check(pickup(w,"wood",4) and pickup(w,"mushroom",5),"explicit real mixed backpack pickup preserves both kinds")
	check(w.actors.human.carry=={"wood":4,"mushroom":5} and chest.items.wood==20 and chest.items.mushroom==7,"real chest to mixed carry, no duplicate or loss")
	var picked_stock:Dictionary=chest.items.duplicate(true)
	check(approach(w,life) and life.fireside.light_host().ok,"host explicitly walks within three and lights")
	check(w.actors.human.carry.wood==2 and life.station.fuel_used==2,"lighting debits precisely two carried wood")
	var lit_position:Vector2=w.point(w.actors.human);advance(w,1.1)
	check(w.point(w.actors.human)==lit_position and not life.fireside.jobs.has("human"),"lighting alone never moves human; auto-seating requires actually cooked food")
	var remaining:float=life.fireside.state.remaining
	check(life.fireside.light_host().ok and life.fireside.state.remaining==remaining+180 and w.actors.human.carry.get("wood")==1,"renewal debits real wood and adds 180 seconds")
	check(life.fireside.available().wood==21,"empty backpack still exposes real authorized wood")
	check(life.fireside.invite(["codex","companion-2","npc.mira","npc.nora"]).ok,"explicit four-person invitation")
	check(life.fireside.menu().any(func(m):return m.id=="single:mushroom" and m.maximum==160),"mushroom menu remains available at its full limit independent of stock")
	check(life.fireside.roast_host("single:mushroom").ok and w.actors.human.carry.get("mushroom")==5 and life.fireside.state.current.receipt.is_empty(),"unlimited grilled mushrooms preserve backpack food with empty receipt")
	advance(w,2.8);check(life.station.portions==0 and not life.fireside.state.current.ready,"not cooked early")
	advance(w,90)
	check(life.fireside.state.current.ready and life.fireside.state.current.eaten==5 and life.station.portions==0,"five actual diners finish without flip or cleanup")
	check(life.fireside.state.current.eaters.has("human"),"host eats automatically only after explicit fire actions")
	check(w.standard.config.companions.all(func(id):return w.hunger.rank(id)==0),"actual finished food restores every companion")
	check(chest.items==picked_stock,"no local or model resident takes anything from chest")
	check(Save.save_world(w,dir.path_join("reload")),"fire and true food save")
	var loaded:=fresh(dir.path_join("read"));check(Save.load_world(loaded,dir.path_join("reload")).ok,"schema7 optional fire batch reload valid")
	check(not loaded.life.fireside.state.consent and loaded.work.jobs.is_empty() and loaded.work.claims.is_empty(),"reload preserves state but restores no jobs or seat claims")
	check(loaded.life.station.meals_eaten==5 and loaded.life.fireside.state.current.eaten==5,"reload does not recreate eaten food")
	life.fireside.end_circle("test")
	var memories:Array=w.memories.records.filter(func(m):return m.kind=="shared_barbecue" and m.facts.get("version")==2)
	check(memories.size()==1 and memories[0].participants.size()==5 and memories[0].facts.foods.size()==5,"one true gathering memory with actual foods and eaters")
	advance(w,float(w.director.memory_reminders.config.min_age)+.1)
	var reminder:String=w.director.memory_reminders.text_for("codex",memories[0])
	check(not reminder.is_empty() and not reminder.contains("收拾"),"new true reminder never invents removed cleanup step")
	life.fireside.end_circle("again");check(w.memories.records.filter(func(m):return m.kind=="shared_barbecue" and m.facts.get("version")==2).size()==1,"same gathering memory never duplicated")
	check(Save.save_world(w,dir.path_join("facts")) and Save.load_world(fresh(dir.path_join("fact-read")),dir.path_join("facts")).ok,"new canonical food facts pass strict save reload")
	var small:=fresh(dir.path_join("small"));check(pickup(small,"wood",2) and pickup(small,"mushroom",1) and approach(small,small.life),"one-portion real fixture")
	var reserved:int=small.storage.count("mushroom")
	check(small.storage.take({"mushroom":reserved}).ok,"reserve actual uninvited-owner food without changing total")
	small.actors["npc.nora"].carry["mushroom"]=reserved
	check(F.job(small,"npc.nora",{"intent":"enter","target_id":"home.house.01"}),"uninvited owner keeps real food in another region")
	check(small.life.fireside.light_host().ok and small.life.fireside.invite(["codex","companion-2"]).ok and small.life.fireside.roast_host("single:mushroom").ok,"one portion offered to several actual guests")
	advance(small,60);check(small.life.fireside.state.current.eaten==3 and small.life.station.meals_eaten==3,"unlimited mushrooms feed every invited diner even with one carried ingredient")
	advance(small,140);check(small.life.fireside.state.remaining==0 and small.life.station.state=="cold","fire naturally extinguishes without cleanup")
	var dish:=fresh(dir.path_join("dish"));var box:Dictionary={"id":"storage","items":dish.storage._items,"capacity":9007199254740991,"kind":"storage","region_id":"home","position":dish.actors.human.position}
	check(pickup(dish,"wood",2),"real wood for dish")
	check(dish.work.take_food_host(box.id,"turnip",3).ok,"host explicitly takes real recipe ingredients")
	for frame in range(2000):
		dish.advance(.1)
		if not dish.work.jobs.has("human"):break
	check(approach(dish,dish.life) and dish.life.fireside.light_host().ok,"dish light near actual stove")
	check(dish.life.fireside.invite(["codex"]).ok,"one real invited dish companion")
	check(dish.life.fireside.roast_host("recipe:turnip-soup").ok,"whole recipe accepted with frozen real ingredients")
	advance(dish,7.5);check(not dish.life.fireside.state.current.ready,"whole dish not ready before eight seconds")
	advance(dish,1);check(dish.life.fireside.state.current.ready and dish.life.fireside.state.current.total==3,"three ingredients become original three portions")
	check(not dish.life.fireside.has_method("pack_host") and not dish.hunger.has_method("pack") and not dish.hunger.has_method("feed"),"removed packing and feeding APIs unavailable")
	check(not dish.life.fireside.has_method("resume_host"),"old batch resume API unavailable")
	advance(dish,60);dish.life.fireside.end_circle("real dish complete")
	check(dish.life.fireside.state.current.eaten==2 and dish.life.fireside.state.current.wasted==1 and dish.life.station.portions==0,"recipe extras wasted without carry or leftovers")
	check(dish.actors.human.carry.is_empty() and Save.save_world(dish,dir.path_join("dish")) and Save.load_world(fresh(dir.path_join("dish-read")),dir.path_join("dish")).ok,"real eaten and wasted recipe validates with no packed food")
	var fishworld:=fresh(dir.path_join("fish"));check(pickup(fishworld,"wood",2) and approach(fishworld,fishworld.life) and fishworld.life.fireside.light_host().ok,"real fish fixture first lights with owned wood")
	var shores:Array=fishworld.fishing.nearby_shores("human");var shore:Array=shores[0].position
	check(F.job(fishworld,"human",{"intent":"move","x":shore[0],"y":shore[1]}),"human explicitly walks to real coast")
	var fish:Dictionary=preload("res://tests/fishing_fixture.gd").catch_one(fishworld,"human")
	check(not fish.is_empty(),"one real catch instance")
	check(approach(fishworld,fishworld.life),"human carries same fish to fire")
	var portions:int=fishworld.recipes.config.fish_portions[fish.size_id]
	check(fishworld.life.fireside.roast_host("fish:"+fish.id).ok and not fishworld.fishing.fish.has(fish.id),"roasting removes owned original instance exactly once")
	check(not fishworld.life.fireside.roast_host("fish:"+fish.id).ok,"same fish cannot be spent twice")
	advance(fishworld,5.1);check(fishworld.life.fireside.state.current.total==portions,"fish uses canonical body size portion conversion")
	check(Save.save_world(fishworld,dir.path_join("fish-save")) and Save.load_world(fresh(dir.path_join("fish-read")),dir.path_join("fish-save")).ok,"real fish receipt and portions reload without an extra fish")
	print("Barbecue v2: ",checks," checks, failed=",failed);quit(1 if failed else 0)

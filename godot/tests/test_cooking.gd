# DIRECTION 2026-11-11: five new real-fish recipes; only derived counts change.
# DIRECTION 2026-11-07: 主角鱼直接入库；以原真实实例验证后续流程。
extends SceneTree
## Integration — production/evidence/barbecue-v4 — BLOCKING physical resources / actor authority.
## Independent cooking was explicitly removed; recipes now run only on real host fires.
const F=preload("res://tests/cooking_fixture.gd")
const BBQ=preload("res://tests/barbecue_fixture.gd")
const Fish=preload("res://tests/fishing_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
var checks:=0
var failed:=false
var directory:String
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func reload_world(w:RefCounted,name:String)->RefCounted:
	check(Save.save_world(w,directory.path_join(name)),"save "+name)
	var next:=F.fresh();var result:Dictionary=Save.load_world(next,directory.path_join(name));check(result.ok,"load "+name+str(result));return next
func run()->void:
	directory=OS.get_environment("HABITAT_DATA_DIR");assert(directory.contains("youqi-test-"))
	var w:=F.fresh()
	check(w.error.is_empty() and w.recipes.recipes.size()==31 and w.recipes.recipe_catalog.size()==32,"original four unlocked plus27 authorized recipes, old jam lock retained")
	var soup:Dictionary=w.recipes.recipe_catalog["turnip-soup"]
	check(soup.size()==6 and soup.id=="turnip-soup" and soup.name=="萝卜汤" and soup.ingredients.size()==1 and soup.ingredients.get("turnip")==3 and soup.portions==3 and soup.fish==false and soup.seconds==12,"old soup exact six fields retained with JSON integer/float count equivalence")
	var before:Dictionary=w.actors.duplicate(true);var inventory:int=F.amount(w,"turnip")
	for actor in ["human","codex","npc.mira"]:
		for intent in ["cook","eat","turn_food","cleanup","farm_meal"]:
			check(not w.command(actor,{"intent":intent,"target_id":"home.barbecue","recipe_id":"turnip-soup"}).ok,"retired independent/manual action rejects "+actor+":"+intent)
	check(w.actors==before and w.work.jobs.is_empty() and F.amount(w,"turnip")==inventory,"all removed actions leave actors inventory and jobs unchanged")
	check(F.harvest(w,"turnip") and F.amount(w,"turnip")==3,"real planted watered mature crop yields exactly three")
	check(F.serve(w,"turnip-soup","",["human","codex"]),"host explicitly lights invites and cooks actual soup on fire")
	check(F.amount(w,"turnip")==0 and w.life.fireside.state.current.receipt=={"turnip":3},"one fixed recipe atomically consumes exactly three real turnips")
	check(F.eat(w,"human") and F.eat(w,"codex"),"only actual automatic fire diners finish eating")
	var current:Dictionary=w.life.fireside.state.current
	check(current.total==3 and current.eaten==2 and current.wasted==1 and w.life.station.portions==0,"two diners eat once and extra recipe output is immediately wasted")
	check(not current.eaters.has("npc.mira") and not current.eaters.has("companion-2"),"uninvited bystanders do not eat any real output")
	check(F.cleanup(w),"host ends actual circle without obsolete cleanup job")
	var memories:Array=w.read_memories("human",{"kind":"shared_barbecue"}).memories
	check(memories.size()==1 and memories[0].participants.has("human") and memories[0].participants.has("codex") and memories[0].facts.foods.codex[0].food_id=="turnip-soup","one canonical barbecue records exact actual recipe eaters")
	check(w.read_memories("npc.mira",{"kind":"shared_barbecue"}).total==0,"uninvited person receives no meal history")
	w=reload_world(w,"finished");w.memories.sync();w.memories.sync()
	check(w.work.jobs.is_empty() and w.work.claims.is_empty() and w.read_memories("human",{"kind":"shared_barbecue"}).total==1,"reload does not restore jobs claims or duplicate true dinner")
	for crop in ["tomato","pumpkin"]:
		var test:=F.fresh();check(F.harvest(test,crop),"actual crop source "+crop)
		var amount:int=F.amount(test,crop);var recipe:String="tomato-salad" if crop=="tomato" else "roast-pumpkin"
		check(F.serve(test,recipe) and F.eat(test,"human") and F.eat(test,"codex") and F.cleanup(test),"actual recipe completes only through barbecue "+recipe)
		check(F.amount(test,crop)==amount-(2 if crop=="tomato" else 1) and test.life.fireside.state.current.eaten==2 and test.life.fireside.state.current.wasted==0,"original vegetable recipe exact cost and no fictitious leftovers "+recipe)
	barriers();fish_sizes();low_fire_same_fish();finishable_fire_same_fish();old_save()
	print("Cooking merged into barbecue: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
func barriers()->void:
	var w:=F.fresh();check(F.harvest(w,"turnip"),"permission source is actual crop")
	check(BBQ.light(w),"human actually approaches and lights real fire")
	var fire:RefCounted=w.life.fireside;check(fire.invite(["codex"]).ok,"host chooses exact guest without moving her")
	var raw:int=F.amount(w,"turnip");var host:Array=w.actors.human.position.duplicate()
	check(fire.available().get("turnip",0)==raw,"shared warehouse harvest is available without private box permissions")
	check(F.job(w,"human",{"intent":"assign_farm","farm_id":"farm.home","manager_id":"human"}),"host explicitly obtains management")
	check(fire.roast_host("recipe:turnip-soup").ok and F.amount(w,"turnip")==0 and w.actors.human.position==host,"authorized debit consumes real source without transporting human")
	var receipt:Dictionary=fire.state.current.receipt.duplicate(true)
	check(not fire.roast_host("recipe:turnip-soup").ok and fire.state.current.receipt==receipt,"in-flight batch rejects replacement and never debits a second time")
	for tick in range(18000):
		w.advance(.1)
		if w.work.jobs.values().any(func(j):return j.get("phase")=="fire_eat"):break
	check(fire.state.current.eaten==0,"partial eating animation is not completed consumption")
	fire.end_circle("host cancels actual meal")
	check(w.work.jobs.is_empty() and w.work.claims.is_empty() and fire.state.current.eaten==0,"explicit cancellation releases only real circle jobs without invented eater")
	check(fire.state.current.eaten+fire.state.current.wasted==fire.state.current.total and w.life.station.portions==0,"all uneaten canceled output is accounted as waste")
	w=reload_world(w,"canceled")
	check(F.amount(w,"turnip")==0 and w.work.jobs.is_empty() and w.work.claims.is_empty() and w.life.station.portions==0,"reload preserves exact consumption with no leftovers claims or running work")
	check(w.read_memories("human",{"kind":"shared_barbecue"}).total==0,"partial canceled eating creates no finished dinner memory")
func fish_sizes()->void:
	var w:=F.fresh();w.fishing.rng.seed=101
	check(F.job(w,"human",{"intent":"gather_wood","tree_count":4,"zone_id":"home.forest"}),"real fuel for four separate fish dinners is gathered before holding a fish")
	check(F.mushroom(w) and BBQ.light(w),"real mushrooms and real fuel before fish catch")
	var seen:Dictionary={}
	for attempt in range(90):
		if seen.size()==4:break
		check(Fish.coast(w,"human"),"host genuinely reaches sea")
		var fish:Dictionary=Fish.catch_one(w,"human").duplicate(true)
		if fish.is_empty():w.advance(301);continue
		if seen.has(fish.size_id):w.command("human",{"intent":"release_fish","fish_id":fish.id});continue
		if F.amount(w,"mushroom")==0:
			w.command("human",{"intent":"stock_fish","fish_id":fish.id,"pen_id":"home.fishery.east"})
			check(F.mushroom(w),"additional actual mushroom batch without fabricated inventory");continue
		var mushroom_before:int=F.amount(w,"mushroom");var expected:int=w.recipes.config.fish_portions[fish.size_id]
		check(BBQ.start(w,"recipe:grilled-fish",["human"]).ok,"host cooks exact owned real fish "+fish.size_id)
		check(not w.fishing.fish.has(fish.id) and F.amount(w,"mushroom")==mushroom_before-1,"unique fish and side ingredient consumed exactly once "+fish.size_id)
		check(BBQ.ate(w,"human"),"human actually finishes unique fish "+fish.size_id)
		var cur:Dictionary=w.life.fireside.state.current
		check(cur.total==expected and cur.eaten==1 and cur.wasted==expected-1 and w.life.station.portions==0,"exact size output equals actual eater plus waste "+fish.size_id)
		BBQ.end(w);seen[fish.size_id]=true
		# Continue the already seeded test stream across a new World instance.
		# Production reload deliberately starts its own RNG; assertions require
		# reproducible real catches here, never fabricated fish or changed weights.
		var catch_rng_state:int=w.fishing.rng.state
		w=reload_world(w,"fish-"+fish.size_id)
		w.fishing.rng.state=catch_rng_state
		check(not w.fishing.fish.has(fish.id) and w.life.station.portions==0,"reload never duplicates fish or leftovers "+fish.size_id)
	check(seen.size()==4,"all four sizes exercised by real catches without manufactured fish")
	for pair in [["person",1],["large",2],["huge",4],["giant",8]]:check(w.recipes.config.fish_portions[pair[0]]==pair[1],"original fish size yield "+pair[0])
func old_save()->void:
	var w:=F.fresh();check(Save.save_world(w,directory.path_join("old")),"write disposable schema7 fixture")
	var path:String=directory.path_join("old/island-v2.json");var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path))
	data["cooking"]={"deprecated":"ignored","buffer":{"turnip":999},"phase":"served"}
	Fish.write_json(path,data);var old:=F.fresh()
	check(Save.load_world(old,directory.path_join("old")).ok,"removed optional cooking state is ignored without crash")
	check(F.amount(old,"wood")==F.amount(w,"wood") and F.amount(old,"mushroom")==F.amount(w,"mushroom") and F.amount(old,"turnip")==0 and old.life.station.portions==0,"ignored legacy fields grant no ingredients food or history")
	check(old.read_memories("human").total==0 and old.work.jobs.is_empty(),"legacy cooking data cannot replay completion or run human")

func low_fire_same_fish()->void:
	var w:=F.fresh();w.fishing.rng.seed=101
	check(F.mushroom(w) and BBQ.light(w) and Fish.coast(w,"human"),"low-fire boundary starts with real mushrooms fuel and host travel")
	var fish:Dictionary=Fish.catch_one(w,"human").duplicate(true)
	check(not fish.is_empty() and BBQ.approach(w),"same real pending fish actually returns to its fire")
	if fish.is_empty():return
	var fire:RefCounted=w.life.fireside
	w.advance(maxf(0.,float(fire.state.remaining)-7.))
	var mushroom:int=F.amount(w,"mushroom");var wood:int=F.amount(w,"wood");var used:int=w.life.station.fuel_used
	check(is_equal_approx(fire.state.remaining,7.) and fire.burning(),"actual elapsed time leaves seven seconds without assigning fire state")
	check(fire.invite([]).ok,"host explicitly chooses own fish dinner without extra diners")
	var rejected:Dictionary=fire.roast_host("recipe:grilled-fish")
	check(not rejected.ok and rejected.get("error")=="fire_needs_wood","original eight-second recipe rejects the still-burning seven-second fire")
	check(w.fishing.fish.has(fish.id) and preload("res://tests/fishing_fixture.gd").unplaced(w).get("id")==fish.id and F.amount(w,"mushroom")==mushroom and F.amount(w,"wood")==wood,"low-fire rejection preserves exact unique fish and every real ingredient")
	check(BBQ.start(w,"recipe:grilled-fish",["human"]).ok,"scripted host genuinely renews insufficient fire before retrying the same chosen recipe")
	check(F.amount(w,"wood")==wood-1 and w.life.station.fuel_used==used+1,"renewal consumes exactly one real authorized wood without fishing-hand gathering")
	check(not w.fishing.fish.has(fish.id) and F.amount(w,"mushroom")==mushroom-1,"only the same actual held fish and one mushroom are debited after renewal")
	check(BBQ.ate(w,"human"),"host really eats renewed-fire output")
	var current:Dictionary=fire.state.current
	check(current.total==w.recipes.config.fish_portions[fish.size_id] and current.eaten==1 and current.eaten+current.wasted==current.total and w.life.station.portions==0,"all real fish-size output equals actual eating plus authorized waste after renewal")
	check(F.amount(w,"wood")+int(w.life.station.fuel_used)==wood+used,"renewal retains original total physical wood plus genuinely burned fuel")
	BBQ.end(w)

func finishable_fire_same_fish()->void:
	var w:=F.fresh();w.fishing.rng.seed=101
	check(F.mushroom(w) and BBQ.light(w) and Fish.coast(w,"human"),"meal-time boundary starts with real food fuel and travel")
	var fish:Dictionary=Fish.catch_one(w,"human").duplicate(true)
	check(not fish.is_empty() and BBQ.approach(w) and BBQ.light(w),"actual held fish returns to its burning fire")
	if fish.is_empty():return
	var fire:RefCounted=w.life.fireside
	if fire.state.remaining<10.3:check(fire.light_host().ok,"real wood extends short fire for boundary setup")
	w.advance(maxf(0.,float(fire.state.remaining)-10.3))
	check(is_equal_approx(fire.state.remaining,10.3),"actual elapsed time leaves enough to cook but not finish eating")
	var wood:int=F.amount(w,"wood");var fuel:int=w.life.station.fuel_used
	check(BBQ.start(w,"recipe:grilled-fish",["human"]).ok,"meal helper explicitly renews fire before cooking")
	check(F.amount(w,"wood")==wood-1 and w.life.station.fuel_used==fuel+1,"renewal debits exactly one real wood")
	check(BBQ.ate(w,"human"),"human actually eats before renewed fire expires")
	var current:Dictionary=fire.state.current
	check(current.eaten==1 and current.eaten+current.wasted==current.total and not w.fishing.fish.has(fish.id),"meal and its unique fish remain conserved")
	BBQ.end(w)

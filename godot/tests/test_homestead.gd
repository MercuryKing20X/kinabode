# DIRECTION 2026-11-11: five added recipes, original jam unlock/physical assertions retained.
extends SceneTree
const Places=preload("res://scripts/map_locations.gd")
const F=preload("res://tests/cooking_fixture.gd")
const H=preload("res://tests/homestead_fixture.gd")
const Fish=preload("res://tests/fishing_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
var checks:=0
var failed:=false
var directory: String
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failed=true;push_error(label)
func reload_world(world: RefCounted,name: String) -> RefCounted:
	check(Save.save_world(world,directory.path_join(name)),"save "+name)
	var next:=F.fresh();var result: Dictionary=Save.load_world(next,directory.path_join(name));check(result.ok,"reload "+name+str(result));next.director.set_all_enabled(false);return next
func run() -> void:
	directory=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	var world:=F.fresh()
	check(world.error.is_empty(),"M4 config loads: "+world.error)
	if not world.error.is_empty():quit(1);return
	check(world.homestead.occupancy().is_empty(),"configured flowerbed starts on clear ground: "+world.homestead.occupancy())
	check(world.recipes.recipes.size()==31 and not world.command("human",{"intent":"cook","recipe_id":"blueberry-jam"}).ok,"locked recipe absent and cannot be made")
	check(H.stock(world),"real harvested 24 wood, six turnips and four pumpkins")
	var human: Array=world.actors.human.position.duplicate()
	check(H.deliver(world,"codex",5,3),"explicit first delivery finishes real pickup/arrival/deposit")
	check(world.homestead.site.delivered.get("wood")==5 and world.homestead.crop_count(world.homestead.site.delivered)==3,"exact first five wood and three crops physically credited")
	check(not world.homestead.funded() and world.homestead.site.progress==0 and not H.build(world,"codex"),"partial materials never start construction")
	check(H.amount(world,"wood")==24 and H.amount(world,"turnip")==6 and H.amount(world,"pumpkin")==4,"first batch conserves all materials")
	check(world.actors.human.position==human,"companion work never moves human")
	world=reload_world(world,"partial")
	check(world.homestead.plans.codex.status=="paused" and world.work.jobs.is_empty() and world.work.claims.is_empty() and world.homestead.site.delivered.wood==5,"partial reload keeps deposits and no work or claims")
	check(H.deliver(world,"codex"),"explicit resume funds remaining materials")
	check(world.homestead.funded() and world.homestead.site.delivered.get("turnip")==6 and world.homestead.site.delivered.get("pumpkin")==4,"mixed crop pieces total ten, no seeds or mushrooms")
	check(not world.homestead.completed() and world.homestead.site.progress==0 and not world.recipes.recipes.has("blueberry-jam"),"funding alone does not finish or unlock")
	check(world.command("codex",{"intent":"homestead_build","plan_id":world.homestead.plans.codex.id}).ok,"explicit construction starts")
	for tick in range(2000):
		world.advance(.1)
		if world.homestead.site.progress>=1:break
	check(world.homestead.site.progress>0 and world.homestead.site.progress<6,"real elapsed construction has partial progress")
	world.command("codex",{"intent":"stop"})
	var progress: float=world.homestead.site.progress
	world=reload_world(world,"building")
	check(is_equal_approx(world.homestead.site.progress,progress) and not world.homestead.completed() and world.homestead.plans.codex.status=="paused","stop and reload preserve partial construction without unlock")
	check(H.build(world,"codex") and world.homestead.completed() and world.recipes.recipes.size()==32,"only actual construction completion unlocks one recipe")
	var event: Dictionary=world.homestead.site.completion.duplicate(true)
	check(world.wishes.proofs({"template_id":"flowerbed","resident_id":"codex"})==["homestead:"+event.id],"genuine construction remains valid wish proof")
	check(H.amount(world,"wood")==24 and H.amount(world,"turnip")==6 and H.amount(world,"pumpkin")==4,"completed investments still conserve wood and crops")
	check(not world.command("codex",{"intent":"homestead_build","plan_id":world.homestead.plans.codex.id}).ok and not world.command("human",{"intent":"homestead_start","site_id":world.homestead.config.site.id}).ok and world.homestead.site.completion==event,"duplicate commands neither debit nor create another completion")
	world=reload_world(world,"completed")
	check(world.recipes.recipes.has("blueberry-jam") and world.homestead.site.completion.id==event.id and is_equal_approx(world.homestead.site.completion.at,event.at),"completed reload derives same unlock once")
	check(not world.walkable("home",world.homestead.area().get_center()) and world.find_route("human",world.homestead.area().get_center()).is_empty(),"completed flowerbed blocks world movement and route cache")
	check(F.harvest(world,"blueberry") and F.serve(world,"blueberry-jam"),"real harvested blueberries cook unlocked jam")
	check(world.life.station.portions==2 and F.amount(world,"blueberry")==1,"jam consumes two blueberries for two actual servings")
	check(F.eat(world,"human") and F.eat(world,"codex") and F.cleanup(world),"new recipe uses existing shared meal and cleanup")
	var meals:Array=world.read_memories("human",{"kind":"shared_barbecue"}).memories
	check(meals.size()==1 and meals[0].facts.foods.human[0].name=="蓝莓果酱","real completed jam meal enters existing memory")
	reload_world(world,"jam-finished")
	barriers();cancel_and_carry();old_save();contracts();provenance_and_timeout();cooperation()
	print("Homestead: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)
func barriers() -> void:
	var world:=F.fresh()
	var missing: Dictionary=world.command("codex",{"intent":"homestead_start","site_id":world.homestead.config.site.id})
	check(not missing.ok and missing.error=="missing_materials" and world.homestead.site.state=="unstarted" and world.homestead.site.delivered.is_empty(),"empty source refuses with reason and no free stock")
	check(not missing.message.is_empty(),"missing materials expose real blocker")
	check(not world.command("codex",{"intent":"homestead_cancel","plan_id":"nonexistent"}).ok,"cannot cancel a nonexistent plan")
	check(H.stock(world) and H.deliver(world,"codex",5,3),"real partial investment for collision tests")
	for kind in ["tree","construction_site"]:
		var object: Dictionary=world.objects.values().filter(func(value):return value.kind==kind)[0]
		var original: Array=object.position.duplicate();object.position=[world.homestead.area().get_center().x,world.homestead.area().get_center().y]
		var response: Dictionary=world.command("codex",{"intent":"homestead_resume","plan_id":world.homestead.plans.codex.id})
		check(not response.ok and response.error=="occupied" and world.homestead.site.delivered.wood==5 and H.amount(world,"wood")==24,"occupied "+kind+" refuses and preserves all deposits")
		object.position=original
	var farm: Dictionary=world.farms.farms["farm.home"];var rect: Array=farm.rect.duplicate();farm.rect=[26,38,12.4,8.8]
	check(not world.command("codex",{"intent":"homestead_resume","plan_id":world.homestead.plans.codex.id}).ok and world.homestead.site.delivered.wood==5,"farm overlap rejects without covering crops")
	farm.rect=rect
	var site: Dictionary=world.leisure.sites["play.swing"];var position: Array=site.position.duplicate();site.position=Places.pair("p_28_0_39_0")
	check(not world.command("codex",{"intent":"homestead_resume","plan_id":world.homestead.plans.codex.id}).ok,"existing facility blocks site")
	site.position=position
	var entry: Array=world.homestead.config.site.entry.duplicate();world.homestead.config.site.entry=[0,0]
	check(world.command("codex",{"intent":"homestead_resume","plan_id":world.homestead.plans.codex.id}).get("error")=="unreachable" and world.homestead.site.delivered.wood==5,"unreachable entry refuses without losing investments")
	world.homestead.config.site.entry=entry
	# The chef/task actor is far away; the player really empties the chosen chest first.
	world=F.fresh();check(H.stock(world),"real materials for source race")
	check(world.command("codex",{"intent":"homestead_start","site_id":world.homestead.config.site.id}).ok,"race order accepted")
	world.advance(.1)
	check(world.storage.take({"wood":0}).ok,"player actually takes source wood during travel")
	F.wait(world,"codex")
	check(H.amount(world,"wood")==24 and not world.homestead.completed(),"source race conserves real stock")
func cancel_and_carry() -> void:
	var world:=F.fresh();check(H.stock(world),"real material for carried cancellation")
	check(world.command("codex",{"intent":"homestead_start","site_id":world.homestead.config.site.id}).ok,"start transport")
	world.advance(.1)
	check(world.homestead.site.delivered.get("wood")==24 and world.homestead.plans.codex.receipt.is_empty(),"direct investment retains exact committed wood without in-flight hauling")
	world.command("codex",{"intent":"stop"});world=reload_world(world,"in-flight")
	check(world.homestead.site.delivered.get("wood")==24 and world.homestead.plans.codex.status=="paused" and world.work.jobs.is_empty() and world.work.claims.is_empty(),"stop/reload keeps actual carry and receipt with no tasks or claims")
	check(H.deliver(world,"codex") and world.homestead.funded() and H.amount(world,"wood")==24,"explicit resume delivers same carried units exactly once")
	check(world.command("codex",{"intent":"homestead_cancel","plan_id":world.homestead.plans.codex.id}).ok and world.homestead.funded() and not world.homestead.completed(),"cancel funded plan keeps site materials and does not unlock")
	world=reload_world(world,"cancelled")
	check(world.homestead.site.delivered.wood==24 and world.homestead.crop_count(world.homestead.site.delivered)==10 and not world.recipes.recipes.has("blueberry-jam"),"cancelled deposits survive restart")
func old_save() -> void:
	var world:=F.fresh();check(Save.save_world(world,directory.path_join("old")),"save optional-field fixture")
	var path:=directory.path_join("old/island-v2.json");var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path));data.erase("homestead");Fish.write_json(path,data)
	var old:=F.fresh();check(Save.load_world(old,directory.path_join("old")).ok and old.homestead.site.state=="unstarted" and old.homestead.site.delivered.is_empty() and old.homestead.plans.is_empty() and old.recipes.recipes.size()==31,"schema7 missing optional M4 starts empty, no unlock or history")
	data["homestead"]=world.homestead.saved();data.homestead.site.state="completed";Fish.write_json(directory.path_join("fake/island-v2.json"),data)
	var rejected: Dictionary=Save.load_world(F.fresh(),directory.path_join("fake"))
	check(not rejected.ok and FileAccess.file_exists(rejected.get("backup","")),"false completion rejected with recoverable original")
func contracts() -> void:
	var world:=F.fresh();var host: Array=world.actors.human.position.duplicate()
	check(not world.command("codex",{"intent":"homestead_start","site_id":world.homestead.config.site.id,"actor_id":"human"}).ok,"cannot supply another actor in action payload")
	check(not world.command("npc.mira",{"intent":"homestead_start","site_id":world.homestead.config.site.id}).ok,"model connection never grants missing labor capability")
	check(world.command("human",{"intent":"homestead_read"}).ok and world.actors.human.position==host,"reading never moves human")
	var snapshot: Dictionary=world.observe("codex")
	check(not JSON.stringify(snapshot.homestead).contains("pixels") and snapshot.homestead.site.rect==world.homestead.config.site.rect,"summary has configured geometry but no raster data")
	snapshot.homestead.delivered["wood"]=99
	check(world.homestead.site.delivered.is_empty(),"observed summary is a deep copy")
	var recipe: Dictionary=world.homestead.config.unlock_recipe.duplicate(true)
	check(world.recipes.valid_recipe(recipe),"six-key blueberry recipe is explicitly valid")
	recipe["unlock"]=true;check(not world.recipes.valid_recipe(recipe),"six-key recipe schema remains strict")
func provenance_and_timeout() -> void:
	var world:=F.fresh();check(H.stock(world),"real stock for timeout and provenance")
	check(F.job(world,"codex",{"intent":"move","x":Places.point("p_55_0_44_0").x,"y":Places.point("p_55_0_44_0").y}),"real walk before route-time deadline test")
	check(world.command("codex",{"intent":"homestead_start","site_id":world.homestead.config.site.id}).ok,"timed order accepted")
	world.advance(.1);check(world.homestead.site.delivered.get("wood")==24,"initial supply commits warehouse material without source travel")
	world.advance(.1)
	check(world._routes.has("codex"),"deadline fixture is genuinely in transit")
	world.advance(float(world.homestead.config.job_timeout)+1)
	check(world.homestead.plans.codex.status=="blocked" and world.work.jobs.is_empty() and world._routes.is_empty() and H.amount(world,"wood")==24 and world.homestead.site.delivered.get("wood")==24,"elapsed timeout includes route time and preserves all stock")
	check(H.deliver(world,"codex",0,10),"warehouse crop-only resume works without source travel")
	check(world.homestead.crop_count(world.homestead.site.delivered)==10 and H.amount(world,"wood")==24,"warehouse resume conserves actual crop and wood contributions")
	world=F.fresh();check(F.harvest(world,"turnip"),"real produce before warehouse provenance test")
	check(H.deliver(world,"codex",0,3) and H.amount(world,"turnip")==3,"warehouse produce credits exact real harvest with no box permission")
	reload_world(world,"warehouse-produce")

func cooperation() -> void:
	var world:=F.fresh();check(H.stock(world) and H.deliver(world,"codex"),"funded genuine shared site")
	var host: Array=world.actors.human.position.duplicate()
	check(H.deliver(world,"human") and world.actors.human.position==host,"explicit new human plan joins funded site without unnecessary movement")
	check(not world.command("human",{"intent":"homestead_resume","plan_id":world.homestead.plans.codex.id}).ok,"resident cannot advance another resident plan")
	check(world.command("codex",{"intent":"homestead_build","plan_id":world.homestead.plans.codex.id}).ok,"one worker claims actual construction")
	check(world.command("human",{"intent":"homestead_build","plan_id":world.homestead.plans.human.id}).get("error")=="claimed","second worker cannot steal or duplicate construction")
	check(F.wait(world,"codex") and world.homestead.completed() and not world.homestead.site.contributions.has("human"),"completion credits only actual supplied material, not passive plan joiner")
	reload_world(world,"cooperation")

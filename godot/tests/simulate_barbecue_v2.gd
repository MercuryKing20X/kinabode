extends SceneTree
const F=preload("res://tests/standard_fixture.gd")
const Helpers=preload("res://tests/test_barbecue_v2.gd")
var w:RefCounted
var elapsed:=0.0
var bubbles:Array=[]
var timeline:Array=[]
var serial:=0
func step()->void:
	w.advance(.1);elapsed+=.1
	for e in w.director.events:
		if e.serial<=serial:continue
		serial=e.serial
		if str(e.context).begins_with("fireside_"):bubbles.append(e.duplicate(true))
	if int(elapsed*10)%50==0:timeline.append({"seconds":elapsed,"hunger":w.standard.config.companions.map(func(id):return {"id":id,"state":w.hunger.summary(id).state})})
func wait(id:String)->void:
	for frame in range(6000):
		if not w.work.jobs.has(id) and not w._routes.has(id):return
		step()
	assert(false,"real action did not finish")
func pickup(item:String,n:int)->void:
	for chest in [{"id":"storage","items":w.storage.saved().items,"capacity":9007199254740991,"kind":"storage"}]:
		if int(chest.items.get(item,0))>=n:assert(w.work.take_food_host(chest.id,item,n).ok);wait("human");return
	assert(false,"not enough actual food")
func _initialize()->void:call_deferred("run")
func run()->void:
	var f:=F.new();f.start(OS.get_environment("HABITAT_DATA_DIR"));w=f.w
	assert(f.build_first());elapsed=f.elapsed
	pickup("wood",2);pickup("mushroom",5)
	var camp:Vector2=w.point(w.life.station)
	assert(w.command("human",{"intent":"move","x":camp.x+2.5,"y":camp.y}).ok);wait("human")
	var fire:RefCounted=w.life.fireside
	assert(w.shared_activity.begin_fireside(w.standard.config.companions).ok)
	var lit:float=elapsed;assert(fire.light_host().ok and fire.roast_host("single:mushroom").ok)
	for frame in range(1750):
		step()
		if fire.state.current.eaten==5:break
	assert(fire.state.current.eaten==5)
	var full_at:float=elapsed
	var hunger_after:Dictionary={}
	for id in w.standard.config.companions:hunger_after[id]=w.hunger.summary(id).state;assert(w.hunger.rank(id)==0)
	while fire.burning():step()
	var total:int=preload("res://tests/backpack_fixture.gd").wood_total(w)+int(w.life.station.fuel_used)
	assert(total==12,"four original plus eight chopped wood accounted in stock/build/fuel")
	var facts:Array=w.memories.records.filter(func(m):return m.kind=="shared_barbecue" and m.facts.get("version")==2)
	assert(facts.size()==1 and facts[0].facts.consumed_by.size()==5)
	var result:Dictionary={"opening":"standard","game_model_calls":0,"advance_delta":.1,"camp_built_at":f.timeline.filter(func(e):return e.event=="camp_built")[0].seconds,"fire_lit_at":lit,"all_five_finished_at":full_at,"light_to_all_full_seconds":full_at-lit,"after_meal_hunger":hunger_after,"fireside_seconds_after_last_bite":elapsed-full_at,"bubble_count":bubbles.size(),"bubbles":bubbles,"hunger_timeline":timeline,"wood_accounted":total,"wood_expected":12,"mushroom_receipt":fire.state.current.receipt,"actual_eaten":fire.state.current.eaten,"left_portions":w.life.station.portions,"memory":facts[0],"conserved":true}
	var out:=FileAccess.open(OS.get_environment("HABITAT_STAGE2_EVIDENCE").path_join("simulation.json"),FileAccess.WRITE);out.store_string(JSON.stringify(result,"  "));out.close()
	print("Barbecue v2 standard simulation: five full in ",full_at-lit,"s; bubbles=",bubbles.size(),"; conserved wood=",total);quit()

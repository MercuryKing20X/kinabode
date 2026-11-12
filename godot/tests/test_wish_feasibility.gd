extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
var checks:=0
var failed:=false
func _initialize() -> void:call_deferred("run")
func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok:failed=true;push_error(text)
func step(w: RefCounted,seconds: float) -> void:
	for tick in range(int(ceil(seconds/.5))):w.advance(.5)
func run() -> void:
	var root:=OS.get_environment("HABITAT_DATA_DIR")
	if not root.contains("youqi-test-"):quit(1);return
	var w:=F.fresh();var wishes: RefCounted=w.wishes
	check(wishes.meal_possible("turnip-soup"),"real seeds and plantable beds make soup attainable")
	check(not wishes.meal_possible("roast-pumpkin"),"unplanted six-hour pumpkin cannot meet five-day wish expiry")
	check(not wishes.meal_possible("blueberry-jam"),"locked recipe cannot generate meal wish")
	check(wishes.target(wishes.template("chair"),"codex").is_empty(),"no completed room means no furniture wish")
	check(not wishes.target(wishes.template("bean-cream"),"codex").is_empty(),"current walkable coast permits a genuinely catchable fish")
	check(wishes.hint(wishes.template("soup")).contains("种下"),"seed-only recipe explains planting prerequisite")
	# Exhaust seed access through actual planting, not inventory injection.
	for farm in w.farms.farms.values():
		if "turnip" not in farm.crop_ids:continue
		for plot in w.farms.farm_plots(farm.id):
			check(F.job(w,"human",{"intent":"plant","target_id":plot.id,"crop_id":"turnip"}),"plant a genuine available seed")
	check(wishes.hint(wishes.template("soup")).contains("生长"),"growing crop hint derives from actual plots")
	check(wishes.meal_possible("turnip-soup"),"planted unwatered crops are achievable by watering")
	# Crop availability is read-only and never grants goods to companions.
	var before: String=JSON.stringify(w.actors)
	for tick in range(10):wishes.meal_possible("turnip-soup");wishes.target(wishes.template("chair"),"codex")
	check(JSON.stringify(w.actors)==before,"feasibility never moves actors or grants materials")
	wishes.config.templates=[wishes.template("soup")];wishes.config.first_after=1
	for id in w.director.routines:w.director.routines[id].set_enabled(true);w.director.routines[id].set_chatter(false)
	step(w,5)
	check(not wishes.active("codex").is_empty() and not wishes.summary("codex").hint.is_empty(),"feasible desire is generated with lightweight hint")
	check(Save.save_world(w,root.path_join("wish")),"save real unfinished feasible wish")
	var loaded:=F.fresh();check(Save.load_world(loaded,root.path_join("wish")).ok,"old nine-field wish record stays compatible")
	check(loaded.wishes.active("codex").id==wishes.active("codex").id,"reload preserves wish identity without invented completion")
	var n: int=w.memories.records.size();step(w,w.days.day_seconds*5+2)
	check(wishes.statistics.expired.get("codex",0)==1 and wishes.statistics.expiry_reasons.get("player_did_not_complete",0)>0,"real deadline distinguishes accessible-but-unfulfilled desire")
	check(w.memories.records.size()==n,"expiry has no failure memory, penalty or reward")
	check(w.actors.codex.carry.is_empty(),"local layer never holds crop material")
	print("Wish feasibility: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)

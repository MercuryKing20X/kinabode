extends SceneTree
const Helper=preload("res://tests/test_barbecue_v2.gd")
const Motion=preload("res://scripts/meal_motion.gd")
var checks:=0
func check(ok:bool,msg:String)->void:
	checks+=1;assert(ok,msg)
func _initialize()->void:call_deferred("run")
func run()->void:
	var helper:=Helper.new();var w:RefCounted=helper.fresh(OS.get_environment("HABITAT_DATA_DIR"));var fire:RefCounted=w.life.fireside
	check(helper.pickup(w,"wood",2) and helper.pickup(w,"mushroom",2) and helper.approach(w,w.life),"fixture uses real acquired wood/food and World route")
	check(fire.light_host().ok and fire.invite(["codex"]).ok and fire.roast_host("single:mushroom").ok,"fixture explicit shared meal")
	var seen_chew:=false;var seen_eat:=false;var previous_rank:int=w.hunger.rank("codex");var difference:=-1.0
	for frame in range(15000):
		w.advance(.02)
		var job:Dictionary=w.work.jobs.get("codex",{})
		if job.get("phase")=="fire_eat":
			var t:float=float(job.time)/float(fire.config.eat_seconds)
			var threshold:float=Motion.first_chew(w,"codex",int(job.meal_rank))
			if t<threshold:check(not job.get("taste_queued",false),"no taste reaction before actual first chew")
			if job.get("taste_queued",false):
				seen_chew=true;check(fire.state.current.eaten==0 or not fire.state.current.eaters.has("codex"),"first chew is not falsely credited as completed food")
		if fire.state.current.eaters.has("codex"):
			seen_eat=true
			check(previous_rank>0 and w.hunger.rank("codex")==0,"full meal resets hunger only on actual consumption")
			difference=float(w.hunger.reactions.get("codex",{}).get("queued_at",-20))-float(job.get("meal_finished_at",-10));check(difference==0.0,"finish and full timestamps exactly agree")
			check(Motion.timeline(w,"codex",job).column==6,"one-second satisfaction starts after actual completion")
			break
	check(seen_chew and seen_eat,"real first chew and true completion both observed")
	var old_appearance:String=w.actors["companion-2"].appearance_id
	var before:Dictionary=Motion.style(w,"companion-2",1);w.actors["companion-2"].appearance_id="ai-glm"
	check(Motion.style(w,"companion-2",1)==before and not before.blow and before.puff,"personality eating style survives changing appearance")
	w.actors["companion-2"].appearance_id=old_appearance
	check(not Motion.style(w,"codex",3).blow and Motion.first_chew(w,"codex",3)<Motion.first_chew(w,"codex",1),"very hungry skips blowing with earlier first chew")
	print("Meal timeline: ",checks," checks; finish/full delta=",difference,"s; fixture, not player input")
	helper.free();quit()

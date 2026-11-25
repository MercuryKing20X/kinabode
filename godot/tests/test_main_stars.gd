extends SceneTree
var failed:=0
func _initialize()->void:run.call_deferred()
func check(value:bool,label:String)->void:
 print("MAIN_STARS ",label," ",value)
 if not value:failed+=1
func run()->void:
 var w:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");w.residents.provision(w)
 w.library=preload("res://scripts/character_library.gd").new();w.library.configure(OS.get_environment("HABITAT_DATA_DIR"))
 preload("res://scripts/world_opening.gd").apply(w,w.library,"standard");w.intelligence.activate_presets();w.hunger.start()
 var original:Dictionary=w.storage.saved().duplicate(true)
 var human:Array=w.actors.human.position.duplicate()
 var target:String=w.resort.nearest("stars")
 check(target=="main.stars" and w.point(w.resort.activities[target]).y<150,"stars use existing main-island plaza")
 check(not w.resort.begin(target,["codex"]).ok,"daytime rejected")
 check(not w.resort.begin("resort.human.stars",["codex"]).ok,"retired vacation activity stays rejected")
 for i in 1200:w.advance(1)
 check(w.days.phase().id=="night","actual advance enters night")
 var started:Dictionary=w.resort.begin(target,["codex"])
 check(started.ok,"existing real job starts at clear night")
 check(w.work.jobs.get("codex",{}).get("intent")=="resort" and w._routes.has("codex"),"World route and original job own arrival")
 var elapsed:=0
 while elapsed<120 and w.resort.using("codex")!="stars":w.advance(.5);elapsed+=1
 check(w.resort.using("codex")=="stars","only arrived actor is stargazing")
 check(w.standard.goals.proof(w,"stars"),"tutorial proof observes real stargazing")
 check(w.storage.saved()==original and w.actors.human.position==human,"no items or human movement")
 check(not w.resort.begin(target,["codex"]).ok,"busy actor cannot duplicate its job")
 w.work.stop("codex",false)
 check(w.resort.using("codex").is_empty(),"stop releases real stargazing")
 check(w.work.claims.keys().all(func(key):return not str(key).begins_with(target+":")),"stop releases exact seats")
 print("MAIN_STARS failed=",failed);quit(1 if failed else 0)

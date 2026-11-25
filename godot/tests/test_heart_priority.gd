extends SceneTree
var failures:=0
func check(ok:bool,label:String)->void:
 print("HEART_PRIORITY ",label," ",ok)
 if not ok:failures+=1
func _initialize()->void:run.call_deferred()
func run()->void:
 var w:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");w.residents.provision(w)
 w.library=preload("res://scripts/character_library.gd").new();w.library.configure(OS.get_environment("HABITAT_DATA_DIR"))
 preload("res://scripts/world_opening.gd").apply(w,w.library,"standard");w.intelligence.activate_presets();w.hunger.start();w.director.set_all_enabled(true);w.advance(.25)
 var b:RefCounted=w.director.brains.codex
 b.intention.card()
 check(b.intention.accept({"activity":"daydream","minutes":1,"reason":"Quietly notice one small thing."}),"host accepts ready intention")
 for tick in 40:
  w.advance(.25)
  if b.current.has("ai_plan"):break
 check(b.current.has("ai_plan"),"real executor owns intention")
 var called:Dictionary={"value":false}
 check(not b.execute_provider("day_event",func():called.value=true;return true),"lower-priority idle provider cannot replace AI")
 check(not called.value and b.current.has("ai_plan"),"blocked provider has no side effect")
 for tick in 400:
  w.advance(.25)
  if not b.current.has("ai_plan"):break
 check(b.intention.recent.any(func(row):return row.outcome=="completed"),"accepted intention reaches real completion")
 b.begin_external("command","watch")
 check(b.current.source=="command","player command still has authority")
 print("HEART_PRIORITY failures=",failures);quit(1 if failures else 0)

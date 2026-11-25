extends SceneTree
var failed:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
 print("HEART_CONTRACT ",label," ",ok)
 if not ok:failed+=1
func run()->void:
 var w:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");w.residents.provision(w)
 w.library=preload("res://scripts/character_library.gd").new();w.library.configure(OS.get_environment("HABITAT_DATA_DIR"))
 preload("res://scripts/world_opening.gd").apply(w,w.library,"standard");w.intelligence.activate_presets();w.hunger.start();w.director.set_all_enabled(true)
 w.advance(.25)
 var b:RefCounted=w.director.brains.codex
 var entropy:int=b.rng.state;var card:Dictionary=b.intention.card()
 check(entropy==b.rng.state,"observation never consumes decision entropy")
 check(card.available.any(func(v):return v.activity=="daydream" and v.ready),"real local prerequisites")
 var original:Dictionary={"activity":"daydream","minutes":1,"reason":"Quietly watch the island.","mood":{"joy":1000}}
 for delta in [{"activity":"invented"},{"minutes":0},{"minutes":11},{"minutes":NAN},{"reason":""},{"mood":{"joy":INF}},{"mood":{"free_wood":1}}]:
  var value:Dictionary=original.merged(delta,true)
  check(not b.intention.accept(value),"reject "+str(delta.keys()[0]))
 check(b.intention.accept(original),"valid intention")
 var joy:float=w.hearts.mood("codex").joy
 for tick in 40:
  w.advance(.25)
  if b.current.has("ai_plan"):break
 check(b.current.has("ai_plan") and b.current.score==b.config.ai_intention.score,"AI wins over local choice")
 check(w.hearts.mood("codex").joy-joy<=8,"AI mood delta bounded")
 b.begin_external("command","watch")
 check(b.current.source=="command" and not b.intention.recent.is_empty() and b.intention.recent.back().outcome=="interrupted","human command wins with actual outcome")
 b.finish("completed");b.intention.card()
 check(b.intention.accept(original),"second pending decision")
 w.hunger.ensure("codex");w.hunger.states.codex.elapsed=float(w.hunger.config.thresholds[3])
 check(b.candidates().all(func(v):return v.action=="food"),"very hungry food only even with pending AI")
 var Save=preload("res://scripts/save_store.gd")
 check(Save.save_world(w,OS.get_environment("HABITAT_DATA_DIR")),"save")
 check(Save.load_world(w,OS.get_environment("HABITAT_DATA_DIR")).get("loaded",false),"load")
 check(b.current.is_empty() and b.intention.pending.is_empty(),"reload never replays AI decisions")
 # DIRECTION v0.8 round 3: combinations keep the parts that can be done.
 var mixed:Dictionary=b.intention.card()
 # Recover from the earlier hunger fixture using the existing meal boundary.
 w.hunger.states.codex.elapsed=0
 mixed=b.intention.card()
 check(b.intention.accept({"activity":"daydream","reason":"Watch quietly","with":"human","place":"fake","target":"fake","bring":"fake"}),"invalid optional fields do not discard a valid activity")
 var accepted:Dictionary=b.intention.pending.get("plan",{})
 check(not accepted.is_empty() and not accepted.has("with") and not accepted.has("target") and not accepted.has("place") and not accepted.has("bring") and not w._routes.has("human"),"discarded fields grant no human route or material authority")
 mixed=b.intention.card()
 check(mixed.feedback.any(func(row):return row.reason=="unavailable_item" and not row.message.is_empty()),"next card explains the discarded details")
 print("HEART_CONTRACT failures=",failed);quit(1 if failed else 0)

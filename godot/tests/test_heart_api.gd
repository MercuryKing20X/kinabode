extends SceneTree
var events:Array=[]
var failed:=0
var w:RefCounted
var transport:Node
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
 print("HEART_API ",label," ",ok)
 if not ok:failed+=1
func wait_event(seconds:float)->Dictionary:
 var until:int=Time.get_ticks_msec()+int(seconds*1000)
 var last:int=Time.get_ticks_msec()
 while Time.get_ticks_msec()<until:
  for event in events:
   if event.kind in ["intent_result","error"]:return event
  var at:int=Time.get_ticks_msec();w.advance(float(at-last)/1000);last=at
  await create_timer(.02).timeout
 return {}
func run()->void:
 w=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");w.residents.provision(w)
 w.library=preload("res://scripts/character_library.gd").new();w.library.configure(OS.get_environment("HABITAT_DATA_DIR"))
 preload("res://scripts/world_opening.gd").apply(w,w.library,"standard");w.intelligence.activate_presets();w.hunger.start();w.director.set_all_enabled(true)
 w.advance(.25)
 var b:RefCounted=w.director.brains.codex
 transport=preload("res://scripts/direct_api_transport.gd").new();root.add_child(transport);transport.directory=OS.get_environment("HABITAT_DATA_DIR");transport.event_received.connect(func(e):events.append(e))
 preload("res://scripts/api_credentials.gd").save_key(transport.directory,"stub-heart-key")
 var cfg:=ConfigFile.new();cfg.set_value("openai","base",OS.get_environment("HABITAT_STUB_BASE"))
 for model in (["normal","outside","bad","disconnect"] if OS.get_environment("HABITAT_HEART_FAST")=="1" else ["normal","outside","bad","disconnect","slow"]):
  cfg.set_value("openai","thinking",model);cfg.save(transport.directory.path_join("connection-mode.cfg"))
  events.clear();var card:Dictionary={"heart_request":b.intention.card(),"memory":{}}
  var before:float=b.clock;var history_before:int=b.history.size();var outcomes_before:int=b.intention.recent.size()
  check(transport.send({"turn_key":model,"kind":"autonomy_event","world":{"heart_card":card}}, {"text":"Snow is gentle and curious."}),"send "+model)
  var response:Dictionary=await wait_event(110 if model=="slow" else 8)
  if model in ["normal","slow"]:
   print("HEART_RESPONSE ",response," OFFERED ",b.intention.offered.keys())
   check(response.get("kind")=="intent_result" and b.intention.accept(response.get("intention")),"accept "+model)
   for tick in 160:
    w.advance(.25)
    if b.current.has("ai_plan"):break
   print("HEART_CURRENT ",b.current.get("action","")," OUTCOMES ",b.intention.recent)
   check(b.current.has("ai_plan") or b.intention.recent.size()>outcomes_before,"AI candidate entered executor "+model)
   for tick in 300:w.advance(.25)
   check(b.intention.recent.size()>outcomes_before,"new accepted intention really settled "+model)
  elif model=="outside":check(not b.intention.accept(response.get("intention")),"outside list rejected")
  else:check(response.get("kind")=="error","fallback "+model)
  if model=="slow":check(b.clock-before>=89 and b.history.size()>history_before,"90 seconds of local life while waiting")
 check(not b.intention.accept({"activity":"daydream","minutes":1,"reason":"x","mood":{"joy":NAN}}),"nonfinite mood rejected")
 transport.close();transport.queue_free();print("HEART_API failures=",failed);quit(1 if failed else 0)

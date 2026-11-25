extends "res://tests/test_brain_30min.gd"
## Deterministic host-decision fixture. Transport failure modes are simulated here;
## the separate native HTTP test owns actual HTTP/JSON/disconnect coverage.
var modes:Array=["normal","slow_90","outside","bad_json","disconnect","quota"]
var summaries:Array=[]
func heart_sample(index:int)->Dictionary:
 await fresh_title(index)
 var w:RefCounted=game.world
 var curves:Array=[];var pending:Dictionary={};var results:Array=[]
 var symbols:Dictionary={};var shown:Dictionary={};var idle:Dictionary={};var max_idle:Dictionary={};var sequence:Array=[]
 var initial:Dictionary=w.storage.saved().duplicate(true)
 var initial_human:Array=w.actors.human.position.duplicate()
 for id in w.director.brains:symbols[id]=0;shown[id]=false;idle[id]=0.0;max_idle[id]=0.0
 for tick in 7200:
  var at:float=tick*.25
  if tick%720==0:
   var mode:String=modes[(tick/720)%modes.size()]
   for id in w.director.brains:
    var brain:RefCounted=w.director.brains[id]
    if mode=="quota":
     results.append({"actor":id,"at":at,"mode":mode,"result":"no_dispatch_local_fallback"});continue
    var card:Dictionary=brain.intention.card();brain.intention.requested()
    var activity:String="daydream"
    if not card.available.any(func(option):return option.activity==activity and option.ready):
     var ready:Array=card.available.filter(func(option):return option.ready)
     if ready.is_empty():continue
     activity=ready[0].activity
    pending[id]={"at":at+(90 if mode=="slow_90" else 1),"mode":mode,"activity":activity,"started_at":at}
  for id in pending.keys():
   var row:Dictionary=pending[id]
   if at<float(row.at):continue
   var brain:RefCounted=w.director.brains[id]
   var accepted:=false
   if row.mode=="disconnect":results.append({"actor":id,"at":at,"mode":row.mode,"result":"network_error_local_fallback"})
   else:
    var value:Variant=null if row.mode=="bad_json" else {"activity":"invent_a_new_island" if row.mode=="outside" else row.activity,"minutes":1,"reason":"想安静看看身边的海岛。","say":"我想在这里安静待一会儿。","mood":{"joy":8}}
    accepted=brain.intention.accept(value)
    results.append({"actor":id,"at":at,"mode":row.mode,"accepted":accepted,"activity":row.activity})
    check(not accepted if row.mode in ["outside","bad_json"] else accepted,"host validates "+row.mode+" "+id)
   pending.erase(id)
  w.advance(.25)
  for id in w.director.brains:
   var b:RefCounted=w.director.brains[id]
   idle[id]=float(idle[id])+.25 if b.current.is_empty() and not w._routes.has(id) and not w.work.jobs.has(id) else 0.0
   max_idle[id]=maxf(float(max_idle[id]),float(idle[id]))
   var symbol:String=w.hearts.symbol(id,w.forest.clock)
   if not symbol.is_empty() and not shown[id]:symbols[id]+=1
   shown[id]=not symbol.is_empty()
  if tick%120==0:
   for id in w.director.brains:
    var b:RefCounted=w.director.brains[id]
    curves.append({"actor":id,"at":at,"mood":w.hearts.mood(id),"distance":b.distance(),"action":b.current.get("action",""),"ai":b.current.has("ai_plan")})
    sequence.append({"actor":id,"at":at,"mood":w.hearts.mood(id),"position":w.actors[id].position.duplicate(),"action":b.current.get("action","")})
  if tick%240==0:await process_frame
 check(w.storage.saved()==initial,"no fixture action changes stock")
 check(w.actors.human.position==initial_human,"fixture never moves human")
 for id in max_idle:check(float(max_idle[id])<=4.5,"slow request keeps body active "+id)
 var outcomes:Dictionary={}
 for id in w.director.brains:
  outcomes[id]=w.director.brains[id].intention.recent.duplicate(true)
  check(not outcomes[id].is_empty(),"AI accepted decision reaches an outcome "+id)
 var report:Dictionary={"fixture":"host_decision_stub_not_http","seconds":1800,"requests":results,"curves":curves,"symbol_episodes":symbols,"idle_max":max_idle,"outcomes":outcomes,"sequence":sequence}
 var file:=FileAccess.open(evidence.path_join("heart-30min-"+str(index)+".json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
 return report
func photo(path:String)->void:
 game.view.queue_redraw()
 await process_frame
 await RenderingServer.frame_post_draw
 root.get_texture().get_image().save_png(path)
func run()->void:
 base_directory=OS.get_environment("HABITAT_DATA_DIR");evidence=OS.get_environment("HABITAT_HEART_EVIDENCE")
 if evidence.is_empty():evidence=base_directory
 DirAccess.make_dir_recursive_absolute(evidence)
 root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
 node_added.connect(func(node):
  if node.get_script()!=null and node.get_script().resource_path=="res://scripts/main.gd":node.set_process(false);node.dialogue_adapter_factory=func(_id,_scope):return Fake.new())
 var one:Dictionary=await heart_sample(1)
 game.queue_free();await process_frame
 var two:Dictionary=await heart_sample(2)
 check(one.sequence==two.sequence,"same seed repeats exact moods positions and choices")
 var media:String=OS.get_environment("HABITAT_CAPTURE_DIR")
 if not media.is_empty() and DisplayServer.get_name()!="headless":
  DirAccess.make_dir_recursive_absolute(media)
  game.chat.hide();game.island_hud.residents_collapsed=true;game.island_hud.refresh();game.view.center=game.world.point(game.world.actors.human);game.view.zoom=1.6
  for frame in 120:
   game.world.advance(.5);game.view._process(.5);game.island_hud.refresh()
   await photo(media.path_join("heart-%03d.png"%frame))
  var displayed:=FileAccess.open(evidence.path_join("heart-rendered-symbols.json"),FileAccess.WRITE);displayed.store_string(JSON.stringify(game.world.hearts.symbol_counts,"\t"));displayed.close()
  game.brain_panel.open("codex")
  await photo(media.path_join("heart-panel-zh.png"))
  TranslationServer.set_locale("en");game.brain_panel.refresh()
  await photo(media.path_join("heart-panel-en.png"));game.brain_panel.hide()
  game.connection_overview.pool.settings.set_value("api","codex","openai")
  game.connection_overview.pool.settings.set_value("enabled","codex",false)
  game.connection_overview.pool.settings.set_value("openai","base","http://127.0.0.1:11434/v1")
  game.connection_overview.pool.settings.set_value("openai","chat","qwen3:1.7b")
  game.connection_overview.pool.settings.set_value("openai","thinking","qwen3:1.7b")
  game.connection_overview.open()
  await photo(media.path_join("ollama-config-en.png"))
 game.queue_free();await process_frame
 print("HEART_LONG_CAPTURE ",checks," failed=",failed);quit(1 if failed else 0)

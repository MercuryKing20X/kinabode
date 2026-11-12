extends SceneTree
## System/viewport benchmark: all30 permanent fires created by normal debits/routes.
## This does not replace the separate mouse acceptance.
const UI=preload("res://tests/barbecue_ui_fixture.gd")
const F=preload("res://tests/cooking_fixture.gd")
const B=preload("res://tests/backpack_fixture.gd")
var game:Node
var results:Dictionary={}
func _initialize()->void:call_deferred("run")
func advance_until_done()->void:
 for tick in range(12000):
  game._process(.1);game.view._process(.1)
  if not game.world._routes.has("human") and game.world.dark.pending.is_empty():return
 assert(false,"bounded action did not finish")
func action(kind:String,at:Vector2)->bool:
 var result:Dictionary=game.world.dark.start(kind,at)
 if not result.ok:return false
 advance_until_done();return true
func fps()->Dictionary:
 game.view.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
 var intervals:Array=[];var before:int=Time.get_ticks_usec()
 for frame in range(120):
  game._process(1.0/60.0);game.view._process(1.0/60.0)
  game.view.queue_redraw();await process_frame;await RenderingServer.frame_post_draw
  var now:int=Time.get_ticks_usec();intervals.append(float(now-before)/1000000.0);before=now
 var total:float=intervals.reduce(func(a,b):return a+b,0.0)
 intervals.sort()
 return {"frames":120,"seconds":total,"fps":120.0/total,"median_ms":intervals[60]*1000,"p95_ms":intervals[114]*1000}
func run()->void:
 assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"))
 game=UI.init_game(self);await process_frame;await process_frame
 root.size=Vector2i(1280,800);DisplayServer.window_set_size(root.size)
 var w:RefCounted=game.world;var d:RefCounted=w.dark
 game.view.center=w.point(w.actors.human);game.view.zoom=1.25;game.view._process(.01)
 results["home"]=await fps()
 var before:int=B.wood_total(w)
 assert(F.job(w,"human",{"intent":"gather_wood","zone_id":"home.forest","tree_count":10}),"real repeated chop/haul/storage")
 var gathered:int=B.wood_total(w)-before
 results["wood_before"]=before;results["wood_gathered"]=gathered
 assert(gathered>=64,"eight real trees minimum for30fires")
 assert(F.job(w,"human",{"intent":"move","x":d.config.home_arrival[0],"y":d.config.home_arrival[1]}))
 assert(d.travel([]).ok);game.view.show_region("dark");game.view.last_human_region="dark";game.view.follow_player=true
 assert(action("torch",d.p(d.config.camp)) and d.torch.remaining>0)
 for y in range(29,93,12):
  for x in range(23,142,12):
   if d.fires.size()>=30:break
   var at:=Vector2(x,y)
   if not w.walkable("dark",at) or d.permanent(at) or d.fires.any(func(f):return d.p(f.position).distance_to(at)<d.config.fire_spacing):continue
   if d.torch.remaining<60:
    var nearby:Array=d.light_sources();nearby.sort_custom(func(a,b):return w.point(w.actors.human).distance_to(d.p(a.position))<w.point(w.actors.human).distance_to(d.p(b.position)))
    assert(action("torch",d.p(nearby[0].position)))
   var old:int=d.fires.size()
   if not action("fire",at):continue
   print("PERF realfires=",d.fires.size()," target=",at)
   assert(d.fires.size()==old+1,"normal ignition committed")
  if d.fires.size()>=30:break
 assert(d.fires.size()==30,"thirty physically debited permanent fires")
 assert(B.wood_total(w)==before+gathered-61,"one torch plus30fires physical wood conservation")
 game.view.center=w.point(w.actors.human);game.view._process(.01)
 results["dark_30_fires"]=await fps();results["fires"]=d.fires.duplicate(true);results["wood_final"]=B.wood_total(w)
 results["scope"]="System probe: normal World/Fireside routes and real wood; not mouse acceptance; real process/update and draw120frames; rendering throughput, not vblank-capped display FPS"
 var out:String=OS.get_environment("HABITAT_MOTION_EVIDENCE")
 var file:=FileAccess.open(out.path_join("performance.json"),FileAccess.WRITE);file.store_string(JSON.stringify(results,"  "));file.close()
 root.get_texture().get_image().save_png(out.path_join("30-real-fires.png"))
 print("Dark performance ",JSON.stringify(results))
 game.queue_free();await process_frame;quit()

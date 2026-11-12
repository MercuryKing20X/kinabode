extends "res://tests/test_dialogue_bar_input.gd"
var game:Node
var w:RefCounted
var timeline:Array=[]
func click_ground(at:Vector2,shift:bool=false)->void:
 game.view.follow_player=false;game.view.center=at;await frames(2)
 var key:=InputEventKey.new();key.keycode=KEY_SHIFT;key.pressed=shift;root.push_input(key,true)
 var pixel:Vector2=game.view.screen(at)
 for pressed in [true,false]:
  var ev:=InputEventMouseButton.new();ev.button_index=MOUSE_BUTTON_LEFT;ev.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0;ev.position=pixel;ev.global_position=pixel;ev.pressed=pressed;ev.shift_pressed=shift;root.push_input(ev,true);await process_frame
 key=InputEventKey.new();key.keycode=KEY_SHIFT;key.pressed=false;root.push_input(key,true)
func ground(near:Vector2,radius:int=8)->Vector2:
 for rr in range(radius+1):
  for ox in range(-rr,rr+1):
   for oy in range(-rr,rr+1):
    var at:Vector2=near+Vector2(ox,oy)
    if not w.walkable("home",at) or w.find_route("human",at).is_empty():continue
    game.view.center=at
    if game.view.hit(game.view.screen(at)).is_empty():return at
 return Vector2.INF
func travel(at:Vector2,label:String,shift:bool=false)->void:
 check(at.is_finite(),label+" reachable mouse target")
 if not at.is_finite():return
 var before:Vector2=w.point(w.actors.human)
 await click_ground(at,shift)
 check(w._routes.has("human"),label+" actual input created World route")
 var samples:=0;var columns:Dictionary={};var directions:Dictionary={};var moving:=0
 for tick in range(5000):
  game._process(.05);game.view._process(.05)
  var state:Dictionary=game.view.motion.states.get("npc.mira",{})
  if w._routes.has("npc.mira"):
   moving+=1;directions[str(w.actors["npc.mira"].facing)]=true
   var col:int=game.view.motion.run_column("npc.mira",w.intelligence.gait("npc.mira"));columns[col]=true
   if label=="showcase-main-run" and tick%2==0 and samples<30:
    game.view.center=w.point(w.actors["npc.mira"]);await frames(2);await capture("input-run-%02d"%samples);samples+=1
  if not w._routes.has("human") and tick>5:
   for settle in range(180):game._process(.05);game.view._process(.05)
   break
 game.view.center=w.point(w.actors.human);await frames(3);await capture(label)
 check(w.point(w.actors.human).distance_to(at)<.2,label+" host reaches click without teleport")
 check(moving>0,label+" Orange follows original World route")
 timeline.append({"case":label,"from":[before.x,before.y],"to":[at.x,at.y],"moving_ticks":moving,"run_columns":columns.keys(),"directions":directions.keys(),"captures":samples})
func run()->void:
 root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
 var original_dir:String=OS.get_environment("HABITAT_DATA_DIR")
 for mode in ["standard","showcase"]:
  var dir:String=original_dir.path_join(mode);DirAccess.make_dir_recursive_absolute(dir);OS.set_environment("HABITAT_DATA_DIR",dir);OS.set_environment("HABITAT_OPENING",mode)
  var pool:Node=preload("res://scripts/connection_session_pool.gd").obtain(self,dir);pool.factory=func(_id):return Stub.new()
  game=load("res://scenes/main_v3.tscn").instantiate();game.dialogue_adapter_factory=func(_id,_scope):return Stub.new()
  root.add_child(game);game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.chat.hide();w=game.world
  w.assign_appearance("codex","ai-gpt");w.assign_appearance("companion-2","ai-deepseek");w.assign_appearance("npc.nora","ai-claude")
  check(w.actors["npc.mira"].appearance_id=="orange-sunflower-girl",mode+" new Orange alongside three alternate outfits")
  w.activities.set_followers(["codex","companion-2","npc.mira","npc.nora"])
  game.view.zoom=1.25;await frames(3)
  await travel(ground(w.point(w.actors.human)+Vector2(6,1)),mode+"-main-walk")
  await travel(ground(w.point(w.actors.human)+Vector2(36,0)),mode+"-main-run",true)
  var moon:Vector2=w.point(w.barbecues["moon.barbecue"].station)
  await travel(ground(moon+Vector2(0,7)),mode+"-moon-run",true)
  await travel(ground(w.point(w.actors.human)+Vector2(6,0)),mode+"-moon-walk")
  var average:=Vector2.ZERO
  for id in w.actors:average+=w.point(w.actors[id])
  game.view.center=average/w.actors.size();game.island_hud.hide();await frames(3)
  await capture(mode+"-four-companions")
  game.queue_free();await frames(3)
 var file:=FileAccess.open(OS.get_environment("HABITAT_UI_EVIDENCE").path_join("input-timeline.json"),FileAccess.WRITE);file.store_string(JSON.stringify({"checks":checks,"failed":failed,"timeline":timeline},"  "));file.close()
 print("ORANGE_REWORK_INPUT ",checks," failed=",failed);quit(1 if failed else 0)

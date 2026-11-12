extends SceneTree
## 菜园一句话: host buttons, confirmed local commands, walking odometer.
const UI=preload("res://tests/barbecue_ui_fixture.gd")
const Commands=preload("res://scripts/farm_commands.gd")
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")

func world_fixture()->RefCounted:
	var w:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");w.residents.provision(w)
	w.library=preload("res://scripts/character_library.gd").new();w.library.configure(OS.get_environment("HABITAT_DATA_DIR"))
	check(preload("res://scripts/world_opening.gd").apply(w,w.library,"showcase").ok,"isolated showcase")
	w.intelligence.activate_presets();w.director.set_all_enabled(false)
	if w.hunger!=null:
		w.hunger.start()
		for id in w.hunger.states:w.hunger.states[id].elapsed=0.0
	for plot in w.farms.farm_plots("farm.home"):plot.crop_id="";plot.watered=false;plot.planted_at=0.0
	return w

## Real time passes while they work; keep the fixture's residents fed so the test
## measures farming, not the (unchanged) hunger gate that is checked separately below.
func fed(w:RefCounted)->void:
	if w.hunger!=null:
		for id in w.hunger.states:w.hunger.states[id].elapsed=0.0
func run_until(w:RefCounted,done:Callable,limit:int=4000)->bool:
	for i in range(limit):
		w.advance(.5)
		if i%200==0:fed(w)
		if done.call():return true
	return false

func run()->void:
	# --- Parser: pure, strict content, no side effects.
	check(Commands.valid(JSON.parse_string(FileAccess.get_file_as_string(Commands.DATA_PATH))),"farm command content valid")
	for bad in [{},{"version":2},{"version":1,"plant_words":[]}]:check(not Commands.valid(bad),"strict content rejects "+str(bad))
	var w:=world_fixture();var parser:=Commands.new()
	var seeds_before:Dictionary={"id":"storage","items":w.storage._items,"capacity":9007199254740991,"kind":"storage","region_id":"home","position":w.actors.human.position}.items.duplicate()
	var a:Dictionary=parser.parse(w,"帮我种萝卜")
	check(a.get("ok") and a.intent=="plant" and a.crop_id=="turnip","plant turnip")
	var b:Dictionary=parser.parse(w,"去收菜");check(b.get("ok") and b.intent=="ready","harvest command")
	var c:Dictionary=parser.parse(w,"把东岸种满");check(c.get("ok") and c.farm_id=="farm.east" and c.crop_id=="mixed","fill named farm with mixed")
	var d:Dictionary=parser.parse(w,"种香蕉");check(not d.is_empty() and not d.ok and d.error=="crop_unknown" and "能种" in str(d.message),"unknown crop lists what can grow")
	var e:Dictionary=parser.parse(w,"去家园菜园种苹果");check(not e.is_empty() and not e.ok and e.error=="crop_unsuitable","unsuitable crop refused")
	for chat in ["你好呀","这种事不急","收到啦","今天天气真好"]:check(parser.parse(w,chat).is_empty(),"ordinary chat is not a command: "+chat)
	check({"id":"storage","items":w.storage._items,"capacity":9007199254740991,"kind":"storage","region_id":"home","position":w.actors.human.position}.items==seeds_before,"parsing never touches stock")

	# --- Host order: companion may farm only when the host asks; the grant ends with the order.
	var helper:="companion-2"
	check(not w.farms.allowed(helper,"farm.home") or w.farms.farms["farm.home"].manager_id==helper,"companion has no standing farm right")
	fed(w);var plan:Dictionary=w.farms.host_order(helper,"farm.home","mixed","plant")
	check(plan.get("ok",false) and w.farms.active(helper),"host order accepted for companion")
	var mine:Dictionary=w.farms.host_order("human","farm.home","mixed","plant")
	check(mine.get("ok",false),"human joins the same fill")
	check(run_until(w,func():return not w.farms.active(helper) and not w.farms.active("human")),"fill finishes")
	var plots:Array=w.farms.farm_plots("farm.home")
	check(plots.all(func(p):return not p.crop_id.is_empty() and p.watered),"every plot planted and watered once")
	var planted:=0
	for item in seeds_before:planted+=int(seeds_before[item])-int({"id":"storage","items":w.storage._items,"capacity":9007199254740991,"kind":"storage","region_id":"home","position":w.actors.human.position}.items.get(item,0))
	check(planted==plots.size(),"exactly one real seed per plot, no double planting")
	check(not w.farms.host_grants.has(helper) and not (w.farms.allowed(helper,"farm.home") and w.farms.farms["farm.home"].manager_id!=helper),"grant cleared when the order completes")

	# --- 收菜 only takes what is ripe, then stops (no waiting on growing plots).
	var ripe:Array=plots.slice(0,4)
	for p in ripe:p.planted_at=w.farms.clock-float(w.farms.crops[p.crop_id].seconds)-5
	var box:Dictionary={"id":"storage","items":w.storage._items,"capacity":9007199254740991,"kind":"storage","region_id":"home","position":w.actors.human.position};var before_box:Dictionary=box.items.duplicate()
	fed(w);var harvest_plan:Dictionary=w.farms.host_order("codex","farm.home","","ready")
	check(harvest_plan.get("ok",false),"ready harvest accepted "+str(harvest_plan))
	check(run_until(w,func():return not w.farms.active("codex") and not w.deliveries.active("codex")),"ready harvest completes instead of waiting")
	check(w.farms.orders.get("codex",{}).get("status","")=="completed","harvest order completed")
	var gained:=0
	for item in box.items:if not str(item).begins_with("seed."):gained+=int(box.items[item])-int(before_box.get(item,0))
	check(gained>0,"ripe crops reached the harvest box")
	check(w.barbecues.values().any(func(life):return life.fireside.available().get("turnip",0)>=w.storage.count("turnip")),"barbecue can use actual warehouse harvest")

	# --- Mixed planting falls back to a crop that really has seed.
	var seed_box:Dictionary={"id":"storage","items":w.storage._items,"capacity":9007199254740991,"kind":"storage","region_id":"home","position":w.actors.human.position}
	var harvest_box:Dictionary={"id":"storage","items":w.storage._items,"capacity":9007199254740991,"kind":"storage","region_id":"home","position":w.actors.human.position}
	seed_box.items["seed.turnip"]=0;harvest_box.items["seed.turnip"]=0;seed_box.items["seed.tomato"]=1
	var first_turnip:Dictionary=plots.filter(func(p):return w.farms.farms["farm.home"].crop_ids[(int(p.id.get_slice(".",3))-1)%3]=="turnip")[0]
	check(w.farms._mixed_crop("farm.home",first_turnip)=="tomato","mixed skips an empty seed type")
	check(not w.command("npc.mira",{"intent":"manage_farm","farm_id":"farm.home","crop_id":"mixed","mode":"plant"}).get("ok",false),"social resident still cannot self-authorize farm work")
	check(w.farms.host_order("npc.mira","farm.home","mixed","plant").get("ok",false),"explicit host may authorize social resident for this order")
	w.farms.pause("npc.mira")
	check(not w.farms.host_grants.has("npc.mira") and not w.farms.allowed("npc.mira","farm.home"),"social resident permission revoked on pause, never becomes manager")

	# --- Hungry residents refuse; strict saved modes.
	var hungry:="companion-2"
	if w.hunger!=null and w.hunger.states.has(hungry):
		w.hunger.states[hungry].elapsed=float(w.hunger.config.thresholds[2])+20
		var refused:Dictionary=w.farms.host_order(hungry,"farm.home","mixed","plant")
		check(not refused.get("ok",false) and refused.get("error")=="hungry" and not w.farms.host_grants.has(hungry),"hungry resident refuses farm work")
	check(not w.farms.host_order(helper,"farm.home","mixed","repeat").get("ok",false),"host order only plant/ready")
	var saved:Dictionary=w.farms.saved();check(w.farms.valid_saved(saved,w.actors),"saved farm with ready order valid")
	check(saved.orders.has("codex") and saved.orders["codex"].mode=="ready","ready mode is what was saved")
	var bad:Dictionary=saved.duplicate(true)
	if bad.orders.has("codex"):bad.orders["codex"].mode="sometime";check(not w.farms.valid_saved(bad,w.actors),"unknown saved mode rejected")
	var restored:=world_fixture();restored.farms.restore(saved);check(restored.farms.host_grants.is_empty(),"grants never restored from save")

	# --- Walking follows the real odometer (no sliding when speed changes).
	var motion:=preload("res://scripts/actor_motion.gd").new()
	var actors:={"human":{"id":"human","activity":"walking","facing":"right","position":[0,0],"region_id":"home","carry":{}}}
	motion.advance(.5,actors,{},{"human":{"moving":true,"distance":0.0}},{})
	check(is_equal_approx(float(motion.states.human.step),0.0),"no distance, no step")
	motion.advance(.1,actors,{},{"human":{"moving":true,"distance":.5}},{})
	check(is_equal_approx(float(motion.states.human.step),16.0/motion.WALK_STRIDE_PIXELS),"step equals real pixels / stride")
	motion.advance(.1,actors,{},{"human":{"moving":true,"distance":.25}},{"human":{"step_scale":2.0}})
	check(is_equal_approx(float(motion.states.human.step),(16.0+16.0)/motion.WALK_STRIDE_PIXELS),"gait step_scale still applies")
	var legacy:=preload("res://scripts/actor_motion.gd").new();legacy.advance(.4,actors)
	check(is_equal_approx(float(legacy.states.human.step),0.0),"callers without displacement evidence keep planted feet still")

	# --- Real input: panel buttons, helper dialog, one-line chat with confirm card.
	var game:Node=UI.init_game(self);await process_frame
	var gw:RefCounted=game.world
	if gw.hunger!=null:
		for id in gw.hunger.states:gw.hunger.states[id].elapsed=0.0
	for plot in gw.farms.farm_plots("farm.home"):plot.crop_id="";plot.watered=false
	for id in ["codex","companion-2"]:gw.director.set_controller(id,"local")
	game.farm_panel.open_farm("farm.home","");await process_frame
	check(game.farm_panel.more_scroll.visible==false and game.farm_panel.manager_picker.is_visible_in_tree()==false,"advanced options folded by default")
	var fill_ok:bool=await UI.click(self,game.farm_panel.fill_button)
	if not fill_ok:print("hovered=",root.gui_get_hovered_control()," rect=",game.farm_panel.fill_button.get_global_rect()," visible=",game.farm_panel.fill_button.is_visible_in_tree())
	check(fill_ok,"click 种满")
	check(gw.farms.active("human") and gw.farms.orders.human.mode=="plant","种满 starts the human fill")
	check(await UI.click(self,game.farm_panel.helpers_button),"click 叫伙伴一起")
	var dialog:Node=null
	for child in game.get_children():if child.get_script()==load("res://scripts/farm_invitation.gd"):dialog=child
	check(dialog!=null and dialog.checks.size()==4 and ["codex","companion-2","npc.mira","npc.nora"].all(func(id):return dialog.checks.has(id)),"helper dialog lists exactly all four companions")
	if dialog!=null:
		check(await UI.click(self,dialog.checks["codex"]),"tick 小白")
		check(await UI.click(self,dialog.get_ok_button()),"click 一起种满")
		check(gw.farms.active("codex") and gw.farms.orders["codex"].mode=="plant","helper got a real fill order")
	var chatter:="companion-2"
	check(not gw.director.model_controlled(chatter),"chat target is local")
	game.farm_panel.hide();game._select_chat(chatter);game.chat.show();await process_frame
	game.chat_input.text="帮我种番茄";game.chat_input.grab_focus();await process_frame
	for down in [true,false]:
		var key:=InputEventKey.new();key.keycode=KEY_ENTER;key.physical_keycode=KEY_ENTER;key.pressed=down;root.push_input(key,true);await process_frame
	var card:ConfirmationDialog=null
	for child in game.get_children():if child is ConfirmationDialog and child.title=="确认农活":card=child
	check(card==null,"ordinary single farm command directly executes without a card")
	check(gw.farms.active(chatter) and gw.farms.orders[chatter].crop_id=="tomato","direct command starts her real tomato order")
	game.chat_input.text="今天天气真好";game._send_direct(chatter,"今天天气真好")
	var unknown_response:Dictionary=game.local_host_commands.unknown([chatter])
	check(unknown_response.examples.all(func(example):return example in str(game.dialogue.statuses.get("direct:"+chatter,""))),"unknown chat keeps all context-valid command examples")
	game.queue_free();await process_frame
	print("Garden command: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)

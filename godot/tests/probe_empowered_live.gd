extends "res://tests/test_intelligence_core_input.gd"
var events:Array=[]
var turns:Array=[]
var seen_keys:Dictionary={}
var number:=0
var base:String
func mouse_at(at:Vector2)->void:
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.position=at;event.global_position=at;event.pressed=down;root.push_input(event,true);await process_frame
func key_press(code:int)->void:
	for down in [true,false]:
		var event:=InputEventKey.new();event.keycode=code;event.pressed=down;root.push_input(event,true);await process_frame
func ready_frames(count:int=5)->void:
	for i in range(count):await process_frame
func record_event(value:Dictionary)->void:
	var key:String=str(value.get("turn_key",""))
	if not key.is_empty() and value.kind in ["usage","intent_result","assistant","error"]:seen_keys[key]=true
	if value.kind in ["usage","intent_result","assistant","error"]:events.append({"turn":number,"event":value.duplicate(true)})
func finished(index:int)->bool:
	var w:RefCounted=game.world
	if index==1:return not w.fishing.held("codex").is_empty()
	if index==3:return w.resort.using("codex")=="pool" and w.resort.using("companion-2")=="pool"
	if index==4:return not game.intentions.plans.has("codex")
	if index==5:return w.cat.carrier=="codex"
	if index in [2,6]:return w.barbecues.values().any(func(life):return life.fireside.state.get("roast_by")=="codex" and not life.fireside.state.current.is_empty() and life.fireside.state.current.eaten>0 and (life.fireside.state.current.food_id=="mushroom" if index==2 else life.fireside.state.current.food_id=="fish"))
	return true
func one(words:String,index:int)->void:
	number=index
	var started:int=Time.get_ticks_msec();var origin:Vector2=game.world.point(game.world.actors.codex);var first_ms:=-1
	var offset:int=game.intentions.history.size()
	await text_input(words)
	var connection:Node=game.links.codex
	while connection.is_busy() and Time.get_ticks_msec()-started<90000:
		game._process(.1)
		if first_ms<0 and game.world.point(game.world.actors.codex)!=origin:first_ms=Time.get_ticks_msec()-started
		await create_timer(.1).timeout
	var timed_out:bool=connection.is_busy()
	if timed_out:connection.cancel_turn()
	for i in range(6000):
		if finished(index):break
		game._process(.1)
		if first_ms<0 and game.world.point(game.world.actors.codex)!=origin:first_ms=Time.get_ticks_msec()-started
		if not game.intentions.plans.has("codex") and game.intentions.last_failure.has("codex"):break
		if i%20==0:await process_frame
	var row:Dictionary={"turn":index,"human":words,"first_move_wall_ms":first_ms,"elapsed_wall_ms":Time.get_ticks_msec()-started,"completed":finished(index),"timeout":timed_out,"actions":game.intentions.history.slice(offset),"failure":game.intentions.last_failure.get("codex","")}
	turns.append(row);print("LIVE_TURN ",row)
	await picture("live-empowered-"+str(index))
	game.memory_books.atomic(base.path_join("empowered-live-results.json"),{"attempts":number,"seen_turn_keys":seen_keys.keys(),"turns":turns,"events":events})
func run()->void:
	base=OS.get_environment("HABITAT_DATA_DIR")
	if OS.get_environment("HABITAT_LIVE_TEST")!="1" or not base.contains("habitat-live-test-") or not base.contains("youqi-"):quit(1);return
	OS.set_environment("HABITAT_OPENING","showcase")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	var title:Node=load("res://scenes/title.tscn").instantiate();root.add_child(title);current_scene=title;await ready_frames(10)
	check(await UI.click(self,title.menu.get_node("connections")),"real title opens connections")
	check(await UI.click(self,title.connection_panel.buttons.codex),"real title connects only Snow")
	var pool:Node=title.connection_panel.pool
	var start:int=Time.get_ticks_msec()
	while pool.states.get("codex",{}).get("state")!="ready" and Time.get_ticks_msec()-start<45000:await create_timer(.1).timeout
	check(pool.states.get("codex",{}).get("state")=="ready","real handshake succeeds")
	await create_timer(.3).timeout;await picture("live-title-connected")
	if failed:quit(1);return
	title.queue_free();await ready_frames()
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);current_scene=game;game.save_enabled=false;game.set_process(false);game.memory_life.set_process(false)
	await ready_frames(10);game.links.codex.event_received.connect(record_event)
	preload("res://tests/dialogue_ui_fixture.gd").open(game,"codex")
	var phrases:Array=["去钓条鱼","去营火生火烤蘑菇叫大家来吃","带小蓝去泳池玩","你自己逛逛吧","抱抱柚柚","先逛逛，再去钓鱼，回来烤鱼"]
	for i in range(phrases.size()):
		if game._connection_light("codex").state!="ready" or seen_keys.size()>=11:break
		await one(phrases[i],i+1)
	game.resident_connections.open("codex");await ready_frames()
	var panel:Node=game.resident_connections
	await UI.reveal(self,panel.tabs);await mouse_at(panel.tabs.global_position+panel.tabs.get_tab_rect(2).get_center());await ready_frames()
	if panel.level_picker.selected!=1:
		await UI.click(self,panel.level_picker);await key_press(KEY_HOME);await key_press(KEY_DOWN);await key_press(KEY_ENTER);await ready_frames()
	check(await UI.click(self,panel.autonomy_toggle),"actual UI enables budgeted autonomy")
	panel.close_panel();game.chat_input.release_focus();game.chat.hide()
	var observe_begin:int=Time.get_ticks_msec()
	while Time.get_ticks_msec()-observe_begin<300000 and seen_keys.size()<11:
		game._process(.1);await create_timer(.1).timeout
	var observation:Dictionary={"wall_ms":Time.get_ticks_msec()-observe_begin,"status":game.autonomy.status("codex"),"history":game.intentions.history.duplicate(true)}
	game.resident_connections.preferences.enable_autonomy("codex",false)
	preload("res://tests/dialogue_ui_fixture.gd").open(game,"codex")
	if seen_keys.size()<12 and not game.links.codex.is_busy():await one("我想写个整理文件的小工具，应该从哪里开始？",7)
	game.memory_books.atomic(base.path_join("empowered-live-results.json"),{"attempts":number,"seen_turn_keys":seen_keys.keys(),"turns":turns,"events":events,"autonomy_observation":observation,"checks":checks,"failed":failed,"opening":"showcase","completion_clock":"real Godot advance(delta), accelerated after model reply"})
	game.links.codex.shutdown();game.queue_free();await ready_frames()
	print("EMPOWERED_LIVE_DONE ",base);quit(1 if failed else 0)

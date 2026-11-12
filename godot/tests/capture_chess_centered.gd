extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
const Text=preload("res://scripts/localization.gd")
const Player=preload("res://scripts/jieqi_player.gd")
const Rules=preload("res://scripts/jieqi_rules.gd")
var game: Node
var failures:=0
var events: Array = []
var hand_log: Array = []
func _initialize() -> void:call_deferred("run")
func check(ok: bool, message: String) -> void:
	if not ok:failures+=1;push_error(message)
func mouse(at: Vector2) -> void:
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.position=at;event.global_position=at;root.push_input(event,true);await process_frame
func find_button(node: Node,label: String) -> BaseButton:
	if node is BaseButton and node.text==label:return node
	for child in node.get_children():
		var found:=find_button(child,label)
		if found!=null:return found
	return null
func click_label(node: Node,key: String) -> void:
	if DisplayServer.get_name()!="headless":await RenderingServer.frame_post_draw
	var button:=find_button(node,Text.text(key));check(button!=null,"missing button "+key)
	if button!=null:check(await UI.click(self,button),"real click "+key)
func capture(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(OS.get_environment("HABITAT_PLAYTEST_CAPTURE").path_join(name+".png"))
func step(delta: float=0.1) -> void:
	game._process(delta);game.view._process(delta)
func choose_option(picker: OptionButton,index: int) -> void:
	check(index>=0,"missing picker entry")
	if index<0:return
	await UI.click(self,picker)
	var popup:=picker.get_popup()
	await mouse(Vector2(popup.position)+Vector2(popup.size.x*.5,(index+.5)*float(popup.size.y)/picker.item_count))
func bottom() -> void:
	await UI.click(self,game.island_hud.chess_button)
	check(game.chess_choice.visible,"bottom opens chess choice")
	if DisplayServer.get_name()!="headless":await RenderingServer.frame_post_draw
func select_jieqi(mode: String,actor_id: String) -> void:
	await click_label(game.chess_choice,"jieqi.title")
	await click_label(game.chess_choice,"chess."+mode)
	var panel: Control=game.jieqi_panel
	check(panel.visible,"jieqi picker visible")
	await choose_option(panel.picker,panel.ids.find(actor_id))
	await click_label(panel,"jieqi.start")
	check(game.world.jieqi.opponent==actor_id and game.world.jieqi.game.get("mode")==mode,"requested opponent and mode started")
	for tick in range(6000):
		step()
		if game.world.jieqi.phase!="arriving":break
	check(game.world.jieqi.phase=="playing","players reached table")
func jieqi_human_move() -> void:
	var s: RefCounted=game.world.jieqi
	if s.game.turn!=1:return
	var move:=Player.choose(Rules.public_state(s.game),{"random":0.0,"capture":1.0,"forward":0.0,"reveal":0.0},int(s.game.seed)+s.game.history.size()*7919)
	if move.is_empty():return
	var board: Control=game.jieqi_panel.board
	await mouse(board.global_position+game.jieqi_panel.cell_position(move[0]))
	await mouse(board.global_position+game.jieqi_panel.cell_position(move[1]))
func record_hand(panel:Control)->void:
	var history:Array=game.world.jieqi.game.history
	if history.size()>hand_log.size():
		var actors: Dictionary={}
		var visible_count:=0
		for id in panel.presentation.actor_views:
			var view=panel.presentation.actor_views[id]
			actors[id]={"pose":view.pose_name,"speech":view.speech.is_visible_in_tree()}
			if view.speech.is_visible_in_tree():visible_count+=1
		check(visible_count<=2,"at most two visible bubbles")
		hand_log.append({"hand":history.size(),"move":history[-1].duplicate(true),"actors":actors})
func run() -> void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	var output:=OS.get_environment("HABITAT_PLAYTEST_CAPTURE")
	if not directory.contains("youqi-test-") or output.is_empty():quit(1);return
	var width:=int(OS.get_environment("CHESS_WIDTH"))
	if width not in [960,1280]:width=1280
	var locale:=OS.get_environment("CHESS_LOCALE")
	if locale not in ["zh_CN","en"]:locale="zh_CN"
	Text.select(directory,locale)
	root.size=Vector2i(width,640 if width==960 else 800);root.content_scale_size=Vector2i.ZERO
	var fixture=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	fixture.residents.provision(fixture);fixture.library=preload("res://scripts/character_library.gd").new();fixture.library.configure(directory)
	check(preload("res://scripts/world_opening.gd").apply(fixture,fixture.library,"showcase").ok,"showcase fixture")
	fixture.intelligence.activate_presets();fixture.hunger.start()
	var point: Vector2=fixture.point(fixture.leisure.sites["play.gomoku"])
	fixture.actors.human.position=[point.x,point.y+2]
	for id in {"codex":"ai-gpt","companion-2":"ai-deepseek","npc.mira":"ai-claude","npc.nora":"ai-glm"}:
		fixture.actors[id].appearance_id={"codex":"ai-gpt","companion-2":"ai-deepseek","npc.mira":"ai-claude","npc.nora":"ai-glm"}[id];fixture.actors[id].custom_appearance=true
	check(preload("res://scripts/save_store.gd").save_world(fixture,directory),"serialized fixture")
	OS.set_environment("HABITAT_OPENING","showcase");seed(197)
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game)
	for i in range(30):await process_frame
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.chat.hide()
	if OS.get_environment("CHESS_KIND")=="gomoku":
		await bottom()
		await click_label(game.chess_choice,"ui.main.gomoku")
		var gp: Control=game.gomoku_panel
		check(await UI.click(self,gp.start_button),"real Gomoku start")
		for tick in range(6000):
			step(.1)
			if game.world.gomoku.sessions.get("play.gomoku",{}).get("phase","")=="playing":break
		check(game.world.gomoku.sessions.get("play.gomoku",{}).get("phase","")=="playing","Gomoku actually playing")
		for i in range(10):step(.1);await process_frame
		await centered_capture(gp.board,"gomoku",locale,width)
		print("Centered capture failures: ",failures);quit(1 if failures else 0);return
	for scenario in [{"mode":"standard","actor":"companion-2"}]:
		events.clear();hand_log.clear()
		await bottom();await select_jieqi(scenario.mode,scenario.actor)
		var panel: Control=game.jieqi_panel
		for i in range(10):step(.1);await process_frame
		await centered_capture(panel.board,"jieqi",locale,width)
		if OS.get_environment("CHESS_LAYOUT_ONLY")=="1":print("Centered capture failures: ",failures);quit(1 if failures else 0);return
		var game_seed: int=game.world.jieqi.game.seed
		var collector:=func(event: Dictionary) -> void: events.append(event.duplicate(true))
		panel.bubble_delivered.connect(collector)
		var previous:=0
		var captured_states: Dictionary={}
		for turn in range(200):
			if game.world.jieqi.phase!="playing" or game.world.jieqi.game.history.size()>=30:break
			if game.world.jieqi.game.turn==1:await jieqi_human_move();record_hand(panel)
			for tick in range(100):
				step(0.1)
				record_hand(panel)
				await process_frame
				var pose: String=panel.presentation.pose_name
				if pose in ["happy","panic","thinking"] and not captured_states.has(pose):
					captured_states[pose]=true;await capture(scenario.mode+"-"+pose)
				if panel.presentation.capture_flight>0 and not captured_states.has("flight"):
					captured_states.flight=true;await capture(scenario.mode+"-flight")
				if game.world.jieqi.game.turn==1 or game.world.jieqi.phase!="playing":break
			var count: int=game.world.jieqi.game.history.size()
			for tick in range(42):step(0.1)
			await process_frame
			previous=count
		check(previous>=30,"at least thirty actual hands: "+scenario.mode)
		await capture(scenario.mode+"-thirty-hands")
		panel.bubble_delivered.disconnect(collector)
		await mouse(panel.presentation.portrait.global_position+panel.presentation.portrait.size/2)
		for tick in range(41):step(0.1)
		await process_frame;await capture(scenario.mode+"-tap")
		for event in events:
			check(event.get("world_gate_before")==event.get("world_gate_after") and event.get("personal_gate_before")==event.get("personal_gate_after"),"speech gates unchanged")
		var previous_at:=-1000.0
		var personal: Dictionary={}
		var seen: Dictionary={}
		for event in events:
			var at: float=event.at
			var actor: String=event.actor_id
			check(at-previous_at>=3.0-0.001,"global bubble gap")
			check(at-float(personal.get(actor,-1000.0))>=4.0-0.001,"personal bubble gap")
			check(not seen.has(event.text),"no repeated bubble text")
			previous_at=at;personal[actor]=at;seen[event.text]=true
		for hand in hand_log:
			hand["events"]=events.filter(func(event):return int(event.get("hand",-1))==int(hand.hand)).duplicate(true)
		var audio_rows: Array=[]
		for row in game.game_audio.trace:
			if row.get("action")=="scheduled" and str(row.get("key","")).begins_with("chess-bubble"):audio_rows.append(row.duplicate(true))
		var file:=FileAccess.open(output.path_join(scenario.mode+"-bubble-rate.json"),FileAccess.WRITE)
		if file==null:check(false,"cannot write bubble log")
		else:file.store_string(JSON.stringify({"mode":scenario.mode,"actor":scenario.actor,"seed":game_seed,"hands":hand_log,"events":events,"audio":audio_rows,"captures":captured_states},"\t"))
		if scenario.mode=="standard":
			var before: Array=panel.facts.get("captures",[]).duplicate(true)
			check(preload("res://scripts/save_store.gd").save_world(game.world,directory),"midgame saved")
			game.queue_free();await process_frame
			game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game)
			for i in range(30):await process_frame
			game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.chat.hide()
			await bottom();await click_label(game.chess_choice,"chess.continue")
			panel=game.jieqi_panel
			for i in range(5):step(0.1);await process_frame
			check(panel.facts.get("captures",[])==before,"captures identical after actual main reload")
			await capture("standard-reloaded")
		await click_label(panel,"jieqi.resign");await click_label(panel,"jieqi.close")
	print("Tricolumn capture failures: ",failures);quit(1 if failures else 0)

func centered_capture(board: Control,kind: String,locale: String,width: int) -> void:
	var rect:=board.get_global_rect()
	var offset:=absf(rect.get_center().x-float(root.size.x)*.5)
	var vertical:=absf(rect.get_center().y-float(root.size.y)*.5)
	check(board.is_visible_in_tree(),"actual visible board")
	check(offset<=float(root.size.x)*.02 and vertical<=float(root.size.y)*.02,"board centered within two percent in both axes")
	var grid:float=board.geometry().side if kind=="gomoku" else game.jieqi_panel.spacing()*9
	check(grid>=root.size.y*.60-1,"real grid at least sixty percent height")
	var row:Dictionary={"kind":kind,"locale":locale,"width":width,"height":root.size.y,"offset_x":offset,"offset_y":vertical,"grid":grid}
	var file:=FileAccess.open(OS.get_environment("HABITAT_PLAYTEST_CAPTURE").path_join("centering-%s-%s-%s.json"%[kind,locale,width]),FileAccess.WRITE);file.store_string(JSON.stringify(row,"\t"))
	print("CENTER ",kind," ",locale," ",width," rect=",rect," offsets=",offset,"/",vertical)
	await capture("centered-%s-%s-%d"%[kind,locale,width])

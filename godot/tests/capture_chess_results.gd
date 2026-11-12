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
	var button:=find_button(node,Text.text(key));check(button!=null,"missing button "+key)
	if button!=null:await UI.click(self,button)
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
func run() -> void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	var output:=OS.get_environment("HABITAT_PLAYTEST_CAPTURE")
	if not directory.contains("youqi-test-") or output.is_empty():quit(1);return
	var selected_locale:=OS.get_environment("CHESS_LOCALE")
	Text.select(directory,selected_locale if selected_locale in ["zh_CN","en"] else "zh_CN")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	var fixture=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	fixture.residents.provision(fixture);fixture.library=preload("res://scripts/character_library.gd").new();fixture.library.configure(directory)
	check(preload("res://scripts/world_opening.gd").apply(fixture,fixture.library,"showcase").ok,"showcase fixture")
	fixture.intelligence.activate_presets();fixture.hunger.start()
	var point: Vector2=fixture.point(fixture.leisure.sites["play.gomoku"])
	fixture.actors.human.position=[point.x,point.y+2]
	fixture.jieqi.game=Rules.initial(197,"standard");fixture.jieqi.opponent="companion-2";fixture.jieqi.phase="paused";fixture.jieqi.match_id="jieqi-result-seed197"
	check(fixture.jieqi.valid_saved(fixture.jieqi.saved()),"seed 197 initial save valid")
	check(preload("res://scripts/save_store.gd").save_world(fixture,directory),"serialized fixture")
	OS.set_environment("HABITAT_OPENING","showcase");seed(197)
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game)
	for i in range(30):await process_frame
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.chat.hide()
	await results_run(output)

func results_run(output: String) -> void:
	var locale:=OS.get_environment("CHESS_LOCALE")
	if locale not in ["zh_CN","en"]:locale="zh_CN"
	Text.select(OS.get_environment("HABITAT_DATA_DIR"),locale)
	await bottom();await click_label(game.chess_choice,"chess.continue")
	await UI.click(self,game.jieqi_panel.start_button)
	for tick in range(6000):
		step(0.1)
		if game.world.jieqi.phase!="arriving":break
	check(game.world.jieqi.phase=="playing" and int(game.world.jieqi.game.seed)==197,"saved seed resumed")
	for turn in range(300):
		if game.world.jieqi.phase!="playing":break
		if game.world.jieqi.game.turn==1:await jieqi_human_move()
		for tick in range(100):
			step(0.1)
			await process_frame
			if game.world.jieqi.game.turn==1 or game.world.jieqi.phase!="playing":break
	check(game.world.jieqi.phase!="playing","Jieqi reached actual terminal state")
	var final_game: Dictionary=game.world.jieqi.game
	print("KING_CAPTURE=",final_game.winner==1 and not final_game.captured.is_empty() and final_game.captured[-1].kind=="K")
	print("Jieqi terminal seed=",final_game.seed," hands=",final_game.history.size()," winner=",final_game.winner," last_capture=",final_game.captured.back() if not final_game.captured.is_empty() else {})
	await capture("jieqi-terminal-"+locale)
	await exercise_result(game.jieqi_panel.presentation,"jieqi-"+locale)
	var old_id: String=game.world.jieqi.match_id
	await click_label(game.jieqi_panel.presentation.result_layer,"chess.presentation.replay")
	check(game.world.jieqi.match_id!=old_id and game.world.jieqi.opponent=="companion-2" and game.world.jieqi.game.mode=="standard","replay starts new match with same opponent and mode")
	for tick in range(6000):
		step(0.1)
		if game.world.jieqi.phase!="arriving":break
	await click_label(game.jieqi_panel,"jieqi.resign")
	step(0.1);await process_frame
	await capture("jieqi-resigned-"+locale)
	await click_label(game.jieqi_panel.presentation.result_layer,"chess.presentation.change")
	print("CHANGE choice=",game.chess_choice.visible," panel=",game.jieqi_panel.visible," layer=",game.jieqi_panel.presentation.result_layer.visible," effective=",game.jieqi_panel.presentation.result_layer.is_visible_in_tree())
	check(game.chess_choice.visible and not game.jieqi_panel.presentation.result_layer.visible,"change opens choice and dismisses result")
	await select_jieqi("standard","companion-2")
	await click_label(game.jieqi_panel,"jieqi.resign")
	step(0.1);await process_frame
	await click_label(game.jieqi_panel.presentation.result_layer,"chess.presentation.leave")
	check(not game.jieqi_panel.visible,"leave hides panel")
	game.queue_free();await process_frame
	var fixture=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	fixture.residents.provision(fixture);fixture.library=preload("res://scripts/character_library.gd").new();fixture.library.configure(OS.get_environment("HABITAT_DATA_DIR"))
	check(preload("res://scripts/world_opening.gd").apply(fixture,fixture.library,"showcase").ok,"gomoku fixture opening")
	fixture.intelligence.activate_presets();fixture.hunger.start()
	var point: Vector2=fixture.point(fixture.leisure.sites["play.gomoku"])
	fixture.actors.human.position=[point.x,point.y+2]
	var started: Dictionary=fixture.gomoku.begin_host("play.gomoku","companion-2",true,"local","easy")
	check(started.get("ok",false),"fixture session created")
	var session: Dictionary=fixture.gomoku.sessions["play.gomoku"]
	fixture.gomoku.pause(session,"fixture")
	var history: Array=[[3,7],[0,0],[4,7],[0,2],[5,7],[0,4],[6,7],[1,0]]
	var rules=preload("res://scripts/gomoku_rules.gd")
	check(rules.replay(history).get("winner",-1)==0,"fixture history legal and nonterminal")
	session.history=history;session.revision+=history.size()
	check(fixture.gomoku.valid_saved(fixture.gomoku.saved(),fixture.actors,fixture.leisure.sites),"fixture validates")
	check(preload("res://scripts/save_store.gd").save_world(fixture,OS.get_environment("HABITAT_DATA_DIR")),"fixture saved")
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game)
	for i in range(30):await process_frame
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.chat.hide()
	await bottom();await click_label(game.chess_choice,"ui.main.gomoku")
	var gp: Control=game.gomoku_panel
	await UI.click(self,gp.resume_button)
	for tick in range(6000):
		step(0.1)
		if game.world.gomoku.sessions.get("play.gomoku",{}).get("phase","")=="playing":break
	for i in range(10):step(0.1);await process_frame
	var geom: Dictionary=gp.board.geometry()
	await mouse(gp.board.global_position+geom.origin+Vector2(7,7)*float(geom.step))
	step(0.1);await process_frame
	var terminal: Dictionary=game.world.gomoku.sessions.get("play.gomoku",{})
	check(terminal.get("result","")=="five" and terminal.get("winner_id","")=="human","Gomoku human five on ninth hand")
	await capture("gomoku-terminal-"+locale)
	await exercise_result(gp.presentation,"gomoku-"+locale)
	print("Results capture failures: ",failures);quit(1 if failures else 0)

func exercise_result(presentation: Control, prefix: String) -> void:
	check(presentation.result_layer.visible,"result visible")
	step(0.55);await process_frame
	await capture(prefix+"-stamp")
	step(0.7);await process_frame
	await capture(prefix+"-confetti")
	print("COLLAPSE ",prefix," rect=",presentation.result_layer.get_global_rect()," point=",presentation.result_layer.global_position+Vector2(4,4)," hovered=",root.gui_get_hovered_control())
	await mouse(presentation.result_layer.global_position+Vector2(4,4))
	print("COLLAPSE after visible=",presentation.result_layer.visible," hovered=",root.gui_get_hovered_control())
	check(not presentation.result_layer.visible,"result collapses")
	await UI.click(self,presentation.reopen)
	check(presentation.result_layer.visible,"result reopens")
	await capture(prefix+"-reopened")

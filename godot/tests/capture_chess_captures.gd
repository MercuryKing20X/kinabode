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
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	var state: Dictionary=Rules.initial(197,"chaos")
	var target_move: Array=[]
	for turn in range(160):
		var moves: Array=Rules.legal_moves(state)
		if moves.is_empty():break
		var facts:Dictionary=preload("res://scripts/chess_history.gd").jieqi(197,state.history,"chaos")
		var counts:Dictionary={};var owners:Dictionary={};var doubled:=false;var own:=false
		for piece in facts.get("captures",[]):
			var key:String="%s:%s:%s"%[piece.capturer,piece.side,piece.kind]
			counts[key]=int(counts.get(key,0))+1
			owners[str(piece.capturer)]=int(owners.get(str(piece.capturer),0))+1
			if counts[key]>=2:doubled=true
			if piece.own:own=true
		var captures:=moves.filter(func(m):return state.board[m[1]]!=null)
		if state.turn==1 and int(owners.get("1",0))>=2 and int(owners.get("2",0))>=2 and doubled and own and not captures.is_empty():target_move=captures[0];break

		var chosen: Array=Player.choose(Rules.public_state(state),{"random":0.0,"capture":1.0,"forward":0.0,"reveal":0.0},197+state.history.size()*7919)
		if chosen.is_empty():break
		state=Rules.move(state,chosen[0],chosen[1])
		if state.winner!=0 or state.draw:break
	check(not target_move.is_empty(),"fixture has two capture groups, stack, and next human capture")
	check(not Rules.replay(197,state.history,"chaos").is_empty(),"fixture history replays")
	var fixture=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	fixture.residents.provision(fixture);fixture.library=preload("res://scripts/character_library.gd").new();fixture.library.configure(directory)
	check(preload("res://scripts/world_opening.gd").apply(fixture,fixture.library,"showcase").ok,"opening")
	fixture.intelligence.activate_presets();fixture.hunger.start()
	var point: Vector2=fixture.point(fixture.leisure.sites["play.gomoku"]);fixture.actors.human.position=[point.x,point.y+2]
	fixture.jieqi.game=state;fixture.jieqi.opponent="npc.nora";fixture.jieqi.phase="paused";fixture.jieqi.match_id="jieqi-capture-fixture"
	check(fixture.jieqi.valid_saved(fixture.jieqi.saved()),"saved history valid")
	check(preload("res://scripts/save_store.gd").save_world(fixture,directory),"fixture saved")
	var file:=FileAccess.open(output.path_join("capture-fixture.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"seed":197,"mode":"chaos","history":state.history,"captures":state.captured,"next_capture":target_move},"\t"))
	OS.set_environment("HABITAT_OPENING","showcase")
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game)
	for i in range(30):await process_frame
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.chat.hide()
	await bottom();await click_label(game.chess_choice,"chess.continue");await UI.click(self,game.jieqi_panel.start_button)
	for tick in range(6000):
		step(0.1)
		if game.world.jieqi.phase!="arriving":break
	for i in range(10):step(0.1);await process_frame
	check(game.world.jieqi.phase=="playing","fixture resumed")
	await capture("fixture-captures-groups")
	if not target_move.is_empty():
		var panel: Control=game.jieqi_panel
		await mouse(panel.board.global_position+panel.cell_position(target_move[0]))
		await mouse(panel.board.global_position+panel.cell_position(target_move[1]))
		step(0.1);await process_frame
		check(panel.presentation.capture_flight>0,"real capture flight")
		await capture("fixture-captures-flight")
	print("Capture fixture failures: ",failures);quit(1 if failures else 0)

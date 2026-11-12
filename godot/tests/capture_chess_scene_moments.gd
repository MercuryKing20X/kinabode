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
	var source:=OS.get_environment("CHESS_MOMENTS_SOURCE")
	if not directory.contains("youqi-test-") or output.is_empty() or not FileAccess.file_exists(source):quit(1);return
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(source))
	var recorded: Array=data.hands
	var mode:=OS.get_environment("CHESS_MOMENT")
	if mode not in ["big","tense","cheer"]:mode="tense"
	var history: Array=[]
	for hand in recorded.slice(0,16 if mode=="big" else 14 if mode=="cheer" else 11):history.append(hand.move)
	var state: Dictionary=Rules.replay(int(data.seed),history,"standard")
	check(not state.is_empty() and state.turn==(2 if mode=="tense" else 1) and state.winner==0,"valid nonterminal fixture")
	var fixture=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	fixture.residents.provision(fixture);fixture.library=preload("res://scripts/character_library.gd").new();fixture.library.configure(directory)
	check(preload("res://scripts/world_opening.gd").apply(fixture,fixture.library,"showcase").ok,"showcase fixture")
	fixture.intelligence.activate_presets();fixture.hunger.start()
	var point: Vector2=fixture.point(fixture.leisure.sites["play.gomoku"]);fixture.actors.human.position=[point.x,point.y+2]
	for id in {"codex":"ai-gpt","companion-2":"ai-deepseek","npc.mira":"ai-claude","npc.nora":"ai-glm"}:
		fixture.actors[id].appearance_id={"codex":"ai-gpt","companion-2":"ai-deepseek","npc.mira":"ai-claude","npc.nora":"ai-glm"}[id];fixture.actors[id].custom_appearance=true
	fixture.jieqi.game=state;fixture.jieqi.opponent="companion-2";fixture.jieqi.phase="paused";fixture.jieqi.match_id="jieqi-moments-fixture"
	check(fixture.jieqi.valid_saved(fixture.jieqi.saved()),"fixture validates")
	check(preload("res://scripts/save_store.gd").save_world(fixture,directory),"fixture saved")
	OS.set_environment("HABITAT_OPENING","showcase")
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game)
	for i in range(30):await process_frame
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.chat.hide()
	await bottom();await click_label(game.chess_choice,"chess.continue");await UI.click(self,game.jieqi_panel.start_button)
	for tick in range(6000):
		step(.1)
		if game.world.jieqi.phase!="arriving":break
	check(game.world.jieqi.phase=="playing","resumed")
	var panel: Control=game.jieqi_panel
	if mode=="big":await capture_big(panel,data,history,output)
	elif mode=="cheer":await capture_cheer(panel,data,history,output)
	else:await capture_moments(panel, data, history, output)

func capture_cheer(panel: Control,data: Dictionary,history: Array,output: String) -> void:
	var move: Array=data.hands[14].move
	await mouse(panel.board.global_position+panel.cell_position(move[0]))
	await mouse(panel.board.global_position+panel.cell_position(move[1]))
	var observed:=false
	var poses: Dictionary={}
	for tick in range(7):
		step(.1);await process_frame
		poses.clear()
		for id in panel.presentation.actor_views:poses[id]=panel.presentation.actor_views[id].pose_name
		var cheering:=false
		for id in ["codex","npc.mira","npc.nora"]:
			if poses.get(id)=="cheer":cheering=true
		if game.world.jieqi.game.history.size()==15 and poses.get("companion-2")=="thinking" and cheering:
			observed=true;await capture("scene-thinking-and-cheer");break
	check(observed,"simultaneous thinking and spectator cheer")
	var file:=FileAccess.open(output.path_join("scene-thinking-cheer-proof.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"seed":data.seed,"fixture_history":history,"move":move,"actual_history":game.world.jieqi.game.history,"poses":poses,"observed":observed},"\t"))
	print("Scene cheer failures: ",failures);quit(1 if failures else 0)

func capture_big(panel: Control,data: Dictionary,history: Array,output: String) -> void:
	var delivered: Array=[]
	panel.bubble_delivered.connect(func(event):delivered.append(event.duplicate(true)))
	var move: Array=data.hands[16].move
	await mouse(panel.board.global_position+panel.cell_position(move[0]))
	await mouse(panel.board.global_position+panel.cell_position(move[1]))
	step(.1);await process_frame
	check(game.world.jieqi.game.history.size()==17,"real seventeenth hand")
	await capture("scene-big-reaction")
	var spectator: String="npc.nora"
	var initial_rank: int=game.world.hunger.rank(spectator)
	for tick in range(1800):
		if game.world.hunger.rank(spectator)>=2:break
		step(1.0)
		if tick%20==0:await process_frame
	check(game.world.hunger.rank(spectator)>=2 and initial_rank<2,"spectator hunger naturally advanced")
	await process_frame
	check(panel.presentation.actor_views[spectator].symbol.text==Text.text("ui.island_view.rumble"),"spectator hunger symbol")
	await capture("scene-spectator-hunger")
	var view=panel.presentation.actor_views[spectator]
	await mouse(view.portrait.global_position+view.portrait.size/2)
	for tick in range(50):step(.1);await process_frame
	await capture("scene-spectator-tap")
	check(delivered.any(func(event):return event.get("actor_id")==spectator and event.get("category")=="tap"),"spectator tap delivered")
	var file:=FileAccess.open(output.path_join("scene-moments.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"fixture_seed":data.seed,"fixture_history":history,"played_move":move,"spectator":spectator,"rank":game.world.hunger.rank(spectator),"events":delivered},"\t"))
	print("Scene big failures: ",failures);quit(1 if failures else 0)

func capture_moments(panel: Control,data: Dictionary,history: Array,output: String) -> void:
	var tense:=false
	var cheer:=false
	var thinking:=false
	var actual_move: Array=[]
	for tick in range(100):
		step(.1);await process_frame
		var actors: Dictionary=panel.presentation.actor_views
		if not thinking and actors["companion-2"].pose_name=="thinking":
			thinking=true;await capture("scene-opponent-thinking")
		if game.world.jieqi.game.history.size()>history.size():
			actual_move=game.world.jieqi.game.history[history.size()].duplicate(true)
			if not tense and actors.human.pose_name=="tense":
				tense=true;await capture("human-tense")
			for id in ["codex","npc.mira","npc.nora"]:
				if not cheer and actors[id].pose_name=="cheer":
					cheer=true;await capture("scene-spectator-cheer")
			if tense and cheer:break
		if game.world.jieqi.phase!="playing":break
	check(not actual_move.is_empty(),"AI made actual next move")
	check(tense,"human tense actually observed")
	check(cheer,"spectator cheer actually observed")
	check(thinking,"opponent thinking actually observed")
	var file:=FileAccess.open(output.path_join("scene-tense-proof.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify({"seed":data.seed,"fixture_history":history,"actual_move":actual_move,"tense":tense,"cheer":cheer,"thinking":thinking},"\t"))
	print("Scene moments failures: ",failures);quit(1 if failures else 0)

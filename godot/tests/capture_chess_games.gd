extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
const Text=preload("res://scripts/localization.gd")
const Player=preload("res://scripts/jieqi_player.gd")
const Rules=preload("res://scripts/jieqi_rules.gd")
var game: Node
var failures:=0
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
	if not directory.contains("youqi-test-") or OS.get_environment("HABITAT_PLAYTEST_CAPTURE").is_empty():quit(1);return
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	var fixture=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	fixture.residents.provision(fixture);fixture.library=preload("res://scripts/character_library.gd").new();fixture.library.configure(directory)
	check(preload("res://scripts/world_opening.gd").apply(fixture,fixture.library,"showcase").ok,"showcase fixture")
	fixture.intelligence.activate_presets();fixture.hunger.start()
	var point: Vector2=fixture.point(fixture.leisure.sites["play.gomoku"])
	fixture.actors.human.position=[point.x,point.y+2]
	fixture.actors["companion-2"].appearance_id="ai-deepseek";fixture.actors["companion-2"]["custom_appearance"]=true
	fixture.actors["codex"].appearance_id="ai-gpt";fixture.actors["codex"]["custom_appearance"]=true
	check(preload("res://scripts/save_store.gd").save_world(fixture,directory),"serialized fixture")
	OS.set_environment("HABITAT_OPENING","showcase");seed(197)
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game)
	for i in range(30):await process_frame
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.chat.hide()
	check(game.world.actors["companion-2"].appearance_id=="ai-deepseek","main loaded saved appearance")
	game.view.center=game.world.point(game.world.leisure.sites["play.gomoku"]);game.view.zoom=1
	for i in range(5):await process_frame
	if OS.get_environment("CHESS_CHAOS_ONLY")!="1":
		var rect: Rect2=game.view.leisure_renderer.rect(game.view,game.world.leisure.sites["play.gomoku"])
		await mouse(rect.position+Vector2(rect.size.x*.5,rect.size.y*.25))
		check(game.chess_choice.visible,"table opens chess choice")
		await click_label(game.chess_choice,"ui.main.gomoku")
		var gp: Control=game.gomoku_panel
		var gomoku_index:=-1
		for i in range(gp.opponent.item_count):
			if gp.opponent.get_item_metadata(i)=="companion-2":gomoku_index=i;break
		await choose_option(gp.opponent,gomoku_index);await UI.click(self,gp.start_button)
		for tick in range(6000):
			step()
			if game.world.gomoku.sessions.get("play.gomoku",{}).get("phase")=="playing":break
		var started: Dictionary=game.world.gomoku.sessions.get("play.gomoku",{})
		check(not started.is_empty() and "companion-2" in game.world.gomoku.players(started),"gomoku selected companion")
		var human_moves:=0
		for hand in range(10):
			if human_moves>=5:break
			for tick in range(100):
				step()
				await process_frame
				if gp.current.get("turn_actor_id")=="human":break
			var occupied: Array=gp.current.get("history",[]).duplicate(true);var pos:=Vector2i(7+hand,7)
			if [pos.x,pos.y] in occupied:pos=Vector2i(hand,0)
			var geom: Dictionary=gp.board.geometry()
			await mouse(gp.board.global_position+geom.origin+Vector2(pos)*float(geom.step))
			var after_count: int=game.world.gomoku.sessions.get("play.gomoku",{}).get("history",[]).size()
			print("Gomoku human hand ",hand," before=",occupied.size()," after=",after_count," turn=",gp.current.get("turn_actor_id")," interactive=",gp.board.interactive)
			if after_count>occupied.size():human_moves+=1
		check(human_moves==5,"five human gomoku moves")
		await capture("gomoku-five-human")
		if OS.get_environment("CHESS_GOMOKU_ONLY")=="1":print("Gomoku only failures: ",failures);quit(1 if failures else 0);return
		await UI.click(self,gp.resign_button)
		if gp.confirm.visible:await UI.click(self,gp.confirm.get_ok_button())
		await click_label(gp,"ui.gomoku_panel.close")
		await bottom();await select_jieqi("standard","companion-2")
		for hand in range(10):
			if game.world.jieqi.phase!="playing":break
			if game.world.jieqi.game.turn==1:await jieqi_human_move()
			for tick in range(30):
				step()
				if game.world.jieqi.game.turn==1 or game.world.jieqi.phase!="playing":break
		check(game.world.jieqi.game.history.size()>=10,"standard ten moves")
		await capture("standard-ten-moves")
		await click_label(game.jieqi_panel,"jieqi.resign");await click_label(game.jieqi_panel,"jieqi.close")
	await bottom();await select_jieqi("chaos","codex")
	var delivered:=false
	for hand in range(200):
		if game.world.jieqi.phase!="playing":break
		if game.world.jieqi.game.turn==1:await jieqi_human_move()
		for tick in range(30):
			step()
			if game.world.jieqi.game.turn==1 or game.world.jieqi.phase!="playing":break
		if game.world.jieqi.pending_reaction=="chaos_opposite":
			for tick in range(120):
				step(1.0)
				if int(game.world.jieqi.reactions.get("chaos_opposite",0))>0:break
		if int(game.world.jieqi.reactions.get("chaos_opposite",0))>0:delivered=true;break
	check(delivered,"opposite reveal reaction delivered through director")
	print("Chaos actual moves: ",game.world.jieqi.game.history.size()," opponent=",game.world.jieqi.opponent," reaction=",game.world.jieqi.last_line_key)
	if delivered:await capture("chaos-opposite-reaction")
	print("Chess games capture failures: ",failures);quit(1 if failures else 0)

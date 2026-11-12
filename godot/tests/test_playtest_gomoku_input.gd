extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
const Rules=preload("res://scripts/gomoku_rules.gd")
var game:Node
var failed:=false
var count:=0
func check(ok:bool,label:String)->void:
	count+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func mouse(at:Vector2)->void:
	for down in [true,false]:
		var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;e.position=at;e.global_position=at;root.push_input(e,true);await process_frame
func key(code:int)->void:
	for down in [true,false]:
		var e:=InputEventKey.new();e.keycode=code;e.pressed=down;root.push_input(e,true);await process_frame
func step()->void:game._process(.1);game.view._process(.1)
func run()->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-test-"));OS.set_environment("HABITAT_OPENING","legacy")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	var w:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");w.residents.provision(w);w.library=preload("res://scripts/character_library.gd").new();w.library.configure(dir);assert(preload("res://scripts/world_opening.gd").apply(w,w.library,"showcase").ok);w.intelligence.activate_presets();w.hunger.start()
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=w;root.add_child(game);game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.chat.hide();w.director.set_all_enabled(false)
	for layout_frame in range(10):await process_frame
	var panel:Node=game.gomoku_panel
	game.view.center=w.point(w.leisure.sites["play.gomoku"]);game.view.zoom=1
	await mouse(game.view.screen(w.point(w.leisure.sites["play.gomoku"])))
	for walk_tick in range(2000):
		if game.pending_chess.is_empty():break
		step()
	check(game.chess_choice.visible,"real chess kind selector opens")
	var gomoku_choice:BaseButton
	for choice in game.chess_choice.column.get_children():
		if choice is BaseButton and choice.get_meta("chess_key","")=="ui.main.gomoku":gomoku_choice=choice
	check(await UI.click(self,gomoku_choice),"explicit Gomoku choice mouse")
	for layout_frame in range(4):await process_frame
	check(panel.card.visible,"map mouse opens chess")
	if not panel.card.visible:quit(1);return
	check(await UI.click(self,panel.start_button),"one start mouse")
	check(w.gomoku.sessions.has("play.gomoku"),"one click creates match")
	if not w.gomoku.sessions.has("play.gomoku"):quit(1);return
	check(not panel.confirm.visible,"local match no budget")
	check(not panel.start_button.visible or panel.start_button.disabled,"cannot repeat start")
	for i in range(6000):
		step()
		if w.gomoku.sessions["play.gomoku"].phase!="arriving":break
	var match_state:Dictionary=w.gomoku.sessions["play.gomoku"]
	check(match_state.phase=="playing","two players arrive")
	var out:String=OS.get_environment("HABITAT_PLAYTEST_CAPTURE")
	for dimensions in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=dimensions
		for mode in ["小","标准","大"]:
			game.island_hud.set_interface_size(mode,false);panel.refresh();await process_frame;await process_frame
			check(panel.board.geometry().side>=dimensions.y*.6-1,"board60percent "+str(dimensions)+mode)
			check(Rect2(Vector2.ZERO,Vector2(dimensions)).encloses(panel.card.get_global_rect()),"card fits "+str(dimensions)+mode)
			if not out.is_empty():
				await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(out.path_join("gomoku-%d-%s.png"%[dimensions.x,mode]))
	print("human start ",match_state.phase)
	for i in range(12000):
		if i%1000==0:print("human progress ",i," ",match_state.history.size()," ",match_state.phase)
		if match_state.phase=="finished":break
		if match_state.phase=="playing" and w.gomoku.read("play.gomoku","human").match.get("turn_actor_id")=="human":
			panel.refresh()
			var state:Dictionary=Rules.replay(match_state.history);var p:Vector2i=Rules.ranked(state.board,1+match_state.history.size()%2)[0].p;var geo:Dictionary=panel.board.geometry()
			await mouse(panel.board.global_position+geo.origin+Vector2(p)*geo.step)
		step()
	print("human end ",match_state.history.size()," ",match_state.phase)
	check(match_state.phase=="finished","human mouse completes full local game")
	panel.refresh()
	# The new result card routes setup through Change opponent; keep the original model/spectator assertions below.
	var change_buttons:Array=UI.descendants(panel.presentation.result_layer).filter(func(n):return n is Button and n.text==preload("res://scripts/localization.gd").text("chess.presentation.change"))
	check(change_buttons.size()==1 and await UI.click(self,change_buttons[0]),"result Change opponent returns to choice")
	check(game.chess_choice.visible,"actual choice card visible")
	var gomoku_buttons:Array=UI.descendants(game.chess_choice).filter(func(n):return n is Button and n.text==preload("res://scripts/localization.gd").text("ui.main.gomoku"))
	check(gomoku_buttons.size()==1 and await UI.click(self,gomoku_buttons[0]),"choice reopens original Gomoku setup")
	check(await UI.click(self,panel.game_type),"mouse selects spectator mode")
	var mode_popup:PopupMenu=panel.game_type.get_popup()
	await process_frame;await process_frame
	await mouse(Vector2(mode_popup.position)+Vector2(mode_popup.size)*Vector2(.5,.75))
	check(panel.game_type.selected==1,"spectator selection by popup mouse")
	panel.refresh();await process_frame;await process_frame
	check(await UI.click(self,panel.ai_button),"single local AI start")
	check(not panel.confirm.visible,"two local players bypass budget")
	var ai_match:Dictionary=w.gomoku.sessions["play.gomoku"]
	check(ai_match.mode=="ai","spectator match created")
	for dimensions in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=dimensions;panel.refresh();await process_frame;await process_frame
		if not out.is_empty():
			await RenderingServer.frame_post_draw;root.get_texture().get_image().save_png(out.path_join("gomoku-ai-%d.png"%dimensions.x))
	for i in range(12000):
		step()
		if ai_match.phase=="finished":break
		if ai_match.phase=="paused":
			check(ai_match.history.size()==int(ai_match.ai.step_limit) and ai_match.history.size()==int(w.gomoku.match_config.max_steps),"original confirmed move cap pauses the actual local match")
			panel.refresh();await process_frame;await process_frame
			check(await UI.click(self,panel.resume_button),"host explicitly resumes the same actual local match through UI")
			if panel.confirm.visible:check(await UI.click(self,panel.confirm.get_ok_button()),"host confirms original continuation budget")
			if ai_match.phase=="paused":break
	if ai_match.phase!="finished":print("AI_TERMINAL_DIAGNOSTIC ",ai_match.get("phase")," reason=",ai_match.get("reason")," hands=",ai_match.history.size()," clock=",w.forest.clock)
	check(ai_match.phase=="finished","two local players finish original strength")
	print("Playtest gomoku input ",count," failed=",failed);game.queue_free();await process_frame;quit(1 if failed else 0)

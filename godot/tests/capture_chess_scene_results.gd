extends "res://tests/capture_chess_centered.gd"
func run()->void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	assert(directory.contains("youqi-test-"))
	var locale:=OS.get_environment("CHESS_LOCALE")
	if locale not in ["zh_CN","en"]:locale="zh_CN"
	var kind:=OS.get_environment("CHESS_RESULT")
	assert(kind in ["selfcheck","draw","win"])
	Text.select(directory,locale);root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	var fixture=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	fixture.residents.provision(fixture);fixture.library=preload("res://scripts/character_library.gd").new();fixture.library.configure(directory)
	check(preload("res://scripts/world_opening.gd").apply(fixture,fixture.library,"showcase").ok,"opening")
	fixture.intelligence.activate_presets();fixture.hunger.start()
	var point:Vector2=fixture.point(fixture.leisure.sites["play.gomoku"]);fixture.actors.human.position=[point.x,point.y+2]
	for id in {"codex":"ai-gpt","companion-2":"ai-deepseek","npc.mira":"ai-claude","npc.nora":"ai-glm"}:
		fixture.actors[id].appearance_id={"codex":"ai-gpt","companion-2":"ai-deepseek","npc.mira":"ai-claude","npc.nora":"ai-glm"}[id];fixture.actors[id].custom_appearance=true
	if kind=="win":
		check(fixture.gomoku.begin_host("play.gomoku","companion-2",true,"local","easy").ok,"original session fixture")
		var session:Dictionary=fixture.gomoku.sessions["play.gomoku"];fixture.gomoku.pause(session,"fixture")
		session.history=[[3,7],[0,0],[4,7],[0,2],[5,7],[0,4],[6,7],[1,0]];session.revision+=8
		check(fixture.gomoku.valid_saved(fixture.gomoku.saved(),fixture.actors,fixture.leisure.sites),"legal eight-hand fixture")
	else:
		fixture.jieqi.game=Rules.initial(0 if kind=="selfcheck" else 2,"chaos" if kind=="selfcheck" else "standard")
		fixture.jieqi.opponent="companion-2" if kind=="selfcheck" else "codex"
		fixture.jieqi.match_id="jieqi-scene-result-"+kind;fixture.jieqi.phase="paused"
		check(fixture.jieqi.valid_saved(fixture.jieqi.saved()),"valid saved initial match")
	check(preload("res://scripts/save_store.gd").save_world(fixture,directory),"fixture saved")
	OS.set_environment("HABITAT_OPENING","showcase")
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game)
	for i in range(30):await process_frame
	game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.chat.hide()
	await bottom();await click_label(game.chess_choice,"chess.continue")
	var panel:Control=game.gomoku_panel if kind=="win" else game.jieqi_panel
	if kind=="win":check(await UI.click(self,panel.resume_button),"real resume Gomoku")
	else:check(await UI.click(self,panel.start_button),"real resume Jieqi")
	for tick in range(6000):
		step(.1)
		if (game.world.gomoku.sessions["play.gomoku"].phase if kind=="win" else game.world.jieqi.phase)!="arriving":break
	for i in range(10):step(.1);await process_frame
	if kind=="win":
		var geometry:Dictionary=panel.board.geometry()
		await mouse(panel.board.global_position+geometry.origin+Vector2(7,7)*float(geometry.step))
		check(game.world.gomoku.sessions["play.gomoku"].winner_id=="human","actual mouse five wins")
	elif kind=="selfcheck":
		await mouse(panel.board.global_position+panel.cell_position(88));await mouse(panel.board.global_position+panel.cell_position(69))
		check(game.world.jieqi.game.winner==2 and game.world.jieqi.game.terminal_reason=="chaos_selfcheck","actual reveal loses immediately")
	else:
		await click_label(panel,"jieqi.draw")
		check(game.world.jieqi.game.draw,"actual draw offer accepted")
	for i in range(6):step(.1);await process_frame
	check(panel.presentation.result_layer.visible,"result visible")
	var rect:Rect2=panel.presentation.result_layer.get_global_rect()
	check(rect.get_center().distance_to(Vector2(root.size)*.5)<=2,"result centered on screen")
	if kind=="selfcheck":check(panel.presentation.result_summary.text.contains(Text.text("chess.selfcheck.reason").split("%s")[0]),"reason visible")
	await capture("scene-result-"+kind+"-"+locale)
	var row:Dictionary={"kind":kind,"locale":locale,"rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y],"title":panel.presentation.result_title.text,"summary":panel.presentation.result_summary.text,"failures":failures}
	var file:=FileAccess.open(OS.get_environment("HABITAT_PLAYTEST_CAPTURE").path_join("scene-result-"+kind+"-"+locale+".json"),FileAccess.WRITE);file.store_string(JSON.stringify(row,"\t"))
	print("Scene result ",kind," ",locale," failures=",failures)
	quit(1 if failures else 0)

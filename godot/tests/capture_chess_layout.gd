extends SceneTree
const Text=preload("res://scripts/localization.gd")
const Rules=preload("res://scripts/jieqi_rules.gd")
var game:Node
func _initialize()->void:call_deferred("run")
func mouse(at:Vector2)->void:
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.position=at;event.global_position=at;root.push_input(event,true);await process_frame
func find_button(node:Node,label:String)->BaseButton:
	if node is BaseButton and node.text==label:return node
	for child in node.get_children():
		var result:=find_button(child,label)
		if result!=null:return result
	return null
func click_button(node:Node,label:String)->bool:
	var button:=find_button(node,label)
	if button==null:push_error("Missing button: "+label);return false
	await mouse(button.global_position+button.size/2);return true
func run()->void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	var output:=OS.get_environment("HABITAT_PLAYTEST_CAPTURE")
	var locale:=OS.get_environment("CHESS_LOCALE")
	var kind:=OS.get_environment("CHESS_KIND")
	var width:=int(OS.get_environment("CHESS_WIDTH"))
	if not directory.contains("youqi-test-") or output.is_empty() or locale not in ["zh_CN","en"] or kind not in ["gomoku","jieqi"] or width not in [960,1280]:quit(1);return
	root.size=Vector2i(width,640 if width==960 else 800);root.content_scale_size=Vector2i.ZERO
	var world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	world.residents.provision(world);world.library=preload("res://scripts/character_library.gd").new();world.library.configure(directory)
	assert(preload("res://scripts/world_opening.gd").apply(world,world.library,"showcase").ok)
	var site:Dictionary=world.leisure.sites["play.gomoku"];var point:Vector2=world.point(site)
	world.actors.human.position=[point.x,point.y+2]
	for id in {"codex":"ai-gpt","companion-2":"ai-deepseek","npc.mira":"ai-claude","npc.nora":"ai-glm"}:
		world.actors[id].appearance_id={"codex":"ai-gpt","companion-2":"ai-deepseek","npc.mira":"ai-claude","npc.nora":"ai-glm"}[id];world.actors[id].custom_appearance=true
	assert(preload("res://scripts/save_store.gd").save_world(world,directory))
	OS.set_environment("HABITAT_OPENING","showcase");Text.select(directory,locale)
	game=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);game.save_enabled=false
	for i in range(30):await process_frame
	game.chat.hide();game.island_hud.context_signature="";game.island_hud.refresh_context()
	await mouse(game.island_hud.chess_button.global_position+game.island_hud.chess_button.size/2)
	assert(game.chess_choice.visible)
	assert(await click_button(game.chess_choice,Text.text("ui.main.gomoku" if kind=="gomoku" else "jieqi.title")))
	if kind=="jieqi":
		assert(await click_button(game.chess_choice,Text.text("chess.standard")))
		assert(game.jieqi_panel.visible)
		assert(await click_button(game.jieqi_panel,Text.text("jieqi.start")))
		for tick in range(6000):
			game._process(0.1);game.view._process(0.1)
			if game.world.jieqi.phase!="arriving":break
		assert(game.world.jieqi.phase=="playing")
		var moves:Array=Rules.legal_moves(game.world.jieqi.game)
		assert(not moves.is_empty())
		await mouse(game.jieqi_panel.board.global_position+game.jieqi_panel.cell_position(moves[0][0]))
		await mouse(game.jieqi_panel.board.global_position+game.jieqi_panel.cell_position(moves[0][1]))
		assert(not game.world.jieqi.game.history.is_empty())
		for i in range(40):await process_frame
	else:
		assert(game.gomoku_panel.card.visible)
		assert(await click_button(game.gomoku_panel,Text.text("ui.gomoku_panel.take_your_seat_start")))
		for tick in range(6000):
			game._process(0.1);game.view._process(0.1)
			if game.world.gomoku.sessions.get("play.gomoku",{}).get("phase","")=="playing":break
		assert(game.world.gomoku.sessions.get("play.gomoku",{}).get("phase","")=="playing")
	for i in range(15):await process_frame
	var panel:Control=game.jieqi_panel if kind=="jieqi" else game.gomoku_panel
	var font:Font=panel.get_theme_default_font()
	assert(font.resource_path.contains("NotoSerifSC-Black"))
	var board:Control=panel.board
	var card:Control=panel.card
	var rect:=card.get_global_rect()
	print("CHECK ",kind," ",locale," ",width," card=",rect," grid=",panel.spacing()*9 if kind=="jieqi" else board.geometry().side)

	assert(rect.position.x>=-1 and rect.position.y>=-1 and rect.end.x<=root.size.x+1 and rect.end.y<=root.size.y+1)
	var grid_height:float=panel.spacing()*9 if kind=="jieqi" else board.geometry().side
	assert(grid_height>=root.size.y*0.60-1)
	var three:Control=panel.presentation
	assert(not three.left.get_global_rect().intersects(board.get_global_rect()))
	assert(not three.right.get_global_rect().intersects(board.get_global_rect()))
	assert(three.left.get_global_rect().encloses(three.portrait.get_global_rect()))
	assert(three.left.get_global_rect().encloses(three.speech.get_global_rect()))
	assert(three.portrait.texture_filter==CanvasItem.TEXTURE_FILTER_NEAREST)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(output.path_join("%s-%s-%s.png"%[kind,locale,width]))
	print("PASS ",kind," ",locale," ",width," board=",board.size," grid=",grid_height," card=",rect," font=",font.resource_path)
	quit(0)

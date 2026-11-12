extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
const Player=preload("res://scripts/jieqi_player.gd")
const Rules=preload("res://scripts/jieqi_rules.gd")
const Text=preload("res://scripts/localization.gd")
var game: Node
var failures:=0
var river_capture:=false
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
	if not value:failures+=1;push_error(label)
func mouse(at: Vector2) -> void:
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;event.position=at;event.global_position=at;root.push_input(event,true);await process_frame
func key(code: int) -> void:
	for down in [true,false]:
		var event:=InputEventKey.new();event.keycode=code;event.pressed=down;root.push_input(event,true);await process_frame
func find_button(node: Node,label: String) -> BaseButton:
	if node is BaseButton and node.text==label:return node
	for child in node.get_children():
		var result:=find_button(child,label)
		if result!=null:return result
	return null
func step() -> void:game._process(0.1);game.view._process(0.1)
func capture(name: String) -> void:
	var out:=OS.get_environment("HABITAT_PLAYTEST_CAPTURE")
	if not out.is_empty():
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out.path_join(name+".png"))
func run() -> void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	OS.set_environment("HABITAT_OPENING","legacy");root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	var world:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	world.residents.provision(world);world.library=preload("res://scripts/character_library.gd").new();world.library.configure(directory)
	check(preload("res://scripts/world_opening.gd").apply(world,world.library,"showcase").ok,"showcase fixture")
	world.intelligence.activate_presets();world.hunger.start()
	world.actors["companion-2"].appearance_id="ai-deepseek";world.actors["companion-2"]["custom_appearance"]=true
	check(preload("res://scripts/save_store.gd").save_world(world,directory),"isolated nondefault appearance save fixture")
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=world;root.add_child(game);game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.chat.hide()
	for startup_frame in range(20):await process_frame
	game._process(0.01)
	for locale in ["zh_CN"]:
		Text.select(directory,locale)
		for layout_frame in range(10):await process_frame
		game.view.center=world.point(world.leisure.sites["play.gomoku"]);game.view.zoom=1
		await mouse(game.view.screen(world.point(world.leisure.sites["play.gomoku"])))
		check(game.chess_choice.visible,"chess choice from activities")
		await mouse(Vector2(game.chess_choice.position)+Vector2(game.chess_choice.size)*Vector2(0.5,0.75));await process_frame
		var panel: Control=game.jieqi_panel
		check(panel.visible,"jieqi selected through popup")
		if not panel.visible:quit(1);return
		await UI.click(self,panel.picker)
		var opponents: PopupMenu=panel.picker.get_popup()
		var skye_index: int=panel.ids.find("companion-2")
		await mouse(Vector2(opponents.position)+Vector2(opponents.size.x*0.5,(skye_index+0.5)*float(opponents.size.y)/panel.ids.size()))
		var start:=find_button(panel,Text.text("jieqi.start"));await UI.click(self,start)
		check(world.jieqi.opponent=="companion-2","selected Skye")
		for tick in range(6000):
			step()
			if world.jieqi.phase!="arriving":break
		check(world.jieqi.phase=="playing","real routes seat both players")
		await capture(locale+"-jieqi-opening")
		for hand in range(4096):
			if world.jieqi.phase=="finished":break
			if world.jieqi.game.turn==1:
				if not world.jieqi.river_seen:
					for quiet_tick in range(500):
						if world.director.can_say_local("companion-2","jieqi_river"):break
						step()
				var move:=Player.choose(Rules.public_state(world.jieqi.game),{"random":0.0,"capture":1.0,"forward":0.0,"reveal":0.0},197+hand*7919)
				for candidate in Rules.legal_moves(world.jieqi.game):
					var piece: Dictionary=world.jieqi.game.board[candidate[0]]
					if not piece.hidden and piece.kind in ["A","E"] and ((candidate[0]/9<=4)!=(candidate[1]/9<=4)) and not world.jieqi.river_seen:
						move=candidate
						for quiet_tick in range(600):
							if world.director.can_say_local("companion-2","jieqi_river"):break
							step()
						print("River ready can_say=",world.director.can_say_local("companion-2","jieqi_river")," hand=",hand)
						break
				if move.is_empty():break
				await mouse(panel.board.global_position+panel.cell_position(move[0]));await mouse(panel.board.global_position+panel.cell_position(move[1]))
				if hand==0:await capture(locale+"-jieqi-first-reveal")
				if world.jieqi.river_seen and not river_capture:
					river_capture=true
					for river_wait in range(600):
						if int(world.jieqi.reactions.get("river",0))>0:break
						step()
					print("GATES ",world.director.routines["companion-2"].enabled," ",world.director.routines["companion-2"].held," ",world.director.routines["companion-2"].chatter," time ",world.director.routines["companion-2"].time," next ",world.director.routines["companion-2"].next_speech," world ",world.director.time," after ",world.director.speech_after," distance ",world.point(world.actors.human).distance_to(world.point(world.actors["companion-2"])))
					print("River speech=",world.jieqi.last_line," delivered=",world.jieqi.reactions.get("river",0))
					await capture("jieqi-river-speech-1280")
					root.size=Vector2i(960,640)
					for layout_frame in range(10):await process_frame
					await capture("jieqi-river-speech-960")
					check(world.jieqi.reactions.get("river",0)>0,"actual river speech delivered")
					if world.jieqi.reactions.get("river",0)>0:
						print("River seed=",world.jieqi.game.seed," history=",JSON.stringify(world.jieqi.game.history))
						preload("res://scripts/save_store.gd").save_world(world,directory)
						quit(0);return
					root.size=Vector2i(1280,800)
			for tick in range(30):
				step()
				if world.jieqi.game.turn==1 or world.jieqi.phase=="finished":break
		check(world.jieqi.phase=="finished","mouse full game reaches result "+locale)
		print("Jieqi input ",locale," moves=",world.jieqi.game.history.size()," winner=",world.jieqi.game.winner," phase=",world.jieqi.phase)
		await capture(locale+"-jieqi-result")
		check(world.memories.records.any(func(record):return record.kind=="jieqi_result" and record.source.id==world.jieqi.match_id),"one true result diary")
		await UI.click(self,find_button(panel,Text.text("jieqi.close")))
	print("Jieqi river input failures: ",failures);quit(1 if failures else 0)

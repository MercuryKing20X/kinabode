extends "res://tests/test_intent_input.gd"
var capture_rows:Array=[]
var capture_out:String
var capture_english:=false
var capture_dimensions:=Vector2i.ZERO
func settle()->void:
	for i in 12:await process_frame
func capture_matrix(name:String)->void:
	await settle()
	RenderingServer.force_draw(false)
	var image:=root.get_texture().get_image()
	check(image!=null and image.get_size()==capture_dimensions,"real viewport size "+name)
	image.save_png(capture_out.path_join(name+".png"))
func bounds_row(name:String,node:Control)->void:
	var rect:=node.get_global_rect()
	var okay:=root.get_visible_rect().encloses(rect)
	capture_rows.append({"name":name,"size":str(root.get_visible_rect().size),"scale":game.ui_scale.level,"rect":str(rect),"inside":okay})
	check(okay,"viewport contains "+name+" "+str(root.size)+" scale "+str(game.ui_scale.level))
func run()->void:
	capture_out=OS.get_environment("HABITAT_UI_EVIDENCE")
	check(not capture_out.is_empty(),"external evidence path supplied")
	if failed:quit(1);return
	DirAccess.make_dir_recursive_absolute(capture_out)
	capture_english=OS.get_environment("HABITAT_MATRIX_EN")=="1"
	root.content_scale_size=Vector2i.ZERO
	OS.set_environment("HABITAT_OPENING","standard")
	game=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return IntentFake.new()
	root.add_child(game);game.save_enabled=false;game.set_process(false);game.memory_life.set_process(false)
	game.chat.hide()
	if capture_english:preload("res://scripts/localization.gd").select(game.data_dir,"en")
	await settle()
	check(await UI.click(self,game.steward.toggle),"real steward setup click")
	check(await UI.click(self,game.steward.setup_button),"real local steward start")
	await settle()
	var dimensions_list:Array=[Vector2i(960,640)] if capture_english else [Vector2i(960,640),Vector2i(1366,768),Vector2i(1920,1080),Vector2i(2560,1440),Vector2i(3840,2160),Vector2i(2560,1080),Vector2i(1440,900)]
	if OS.get_environment("HABITAT_MATRIX_4K")=="1":dimensions_list=[Vector2i(3840,2160)]
	if OS.get_environment("HABITAT_MATRIX_TAIL")=="1":dimensions_list=[Vector2i(2560,1080),Vector2i(1440,900)]
	if OS.get_environment("HABITAT_MATRIX_SMALL")=="1":dimensions_list=[Vector2i(960,640)]
	for dimensions in dimensions_list:
		capture_dimensions=dimensions
		root.size=dimensions
		root.content_scale_mode=Window.CONTENT_SCALE_MODE_VIEWPORT
		root.content_scale_size=dimensions
		for level in ([3] if capture_english else range(4) if dimensions.x==960 else [2]):
			game.ui_scale.set_level(level,false)
			game.island_hud.layout_residents();game.island_hud.layout_primary_actions()
			await settle()
			var stem:=("game-en-" if capture_english else "game-")+"%sx%s-%s"%[dimensions.x,dimensions.y,level]
			bounds_row("title",game.day_label)
			bounds_row("upper",game.island_hud.upper_status)
			bounds_row("steward",game.steward.panel)
			check(game.steward.panel.get_global_rect().end.y<game.island_hud.primary_actions.get_global_rect().position.y,"steward clears bottom actions "+stem)
			bounds_row("residents",game.island_hud.residents_panel)
			check(not game.island_hud.upper_status.get_global_rect().intersects(game.island_hud.residents_panel.get_global_rect()),"upper and residents do not overlap "+stem)
			await capture_matrix(stem)
			game.steward.body_director.question(game)
			await settle();game.steward.body_director.position_cards(game);await settle()
			bounds_row("question",game.steward.body_director.card)
			check(not game.steward.body_director.card.get_global_rect().intersects(game.island_hud.primary_actions.get_global_rect()),"question clears bottom actions "+stem)
			await capture_matrix(stem+"-question")
			game.steward.body_director.resolve(game,true)
	var file:=FileAccess.open(capture_out.path_join("game-en-matrix.json" if capture_english else "game-4k-matrix.json" if OS.get_environment("HABITAT_MATRIX_4K")=="1" else "game-tail-matrix.json" if OS.get_environment("HABITAT_MATRIX_TAIL")=="1" else "game-small-matrix.json" if OS.get_environment("HABITAT_MATRIX_SMALL")=="1" else "game-matrix.json"),FileAccess.WRITE);file.store_string(JSON.stringify(capture_rows,"\t"));file.close()
	print("V06_GAME_MATRIX ",checks," failed=",failed)
	game.queue_free();await settle();quit(1 if failed else 0)

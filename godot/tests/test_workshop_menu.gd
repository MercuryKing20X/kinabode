extends SceneTree
const World=preload("res://scripts/world_state.gd")
var checks:=0
var failed:=false
func check(ok:bool,msg:String)->void:
	checks+=1
	if not ok:failed=true;push_error(msg)
func _initialize()->void:call_deferred("run")
func run()->void:
	root.size=Vector2i(1280,800)
	var game:Node=load("res://scenes/main_v3.tscn").instantiate();game.world=World.new("res://content/home-v3/world.json");root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.view.sound_enabled=false;await process_frame
	game._toggle_workshop();game.editor.open_art("human-starter")
	var menu:MenuButton
	for m in game.editor.find_children("*","MenuButton",true,false):
		if m.text=="文件 ▾":menu=m
	check(menu!=null,"file menu exists")
	check(not game.editor.rename_row.visible,"old resident selection hidden")
	check(menu.get_popup().item_count==6,"all six file actions available")
	menu.get_popup().id_pressed.emit(1);check(game.editor.assembler_dialog.visible,"assembler entry")
	game.editor.assembler_dialog.hide()
	menu.get_popup().id_pressed.emit(3);check(game.editor.import_dialog.visible,"import entry")
	game.editor.import_dialog.hide()
	menu.get_popup().id_pressed.emit(4);check(game.editor.export_dialog.visible,"export entry")
	game.editor.export_dialog.hide()
	menu.get_popup().id_pressed.emit(5);check(game.editor.feedback.text.contains("没有"),"non-template config safely rejected")
	game.queue_free();await process_frame;await create_timer(.3).timeout
	print("Workshop file menu: ",checks," checks, failed=",failed);quit(1 if failed else 0)

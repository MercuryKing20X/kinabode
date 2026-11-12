extends SceneTree
const World=preload("res://scripts/world_state.gd")
var failed:=false
var checks:=0
func check(ok:bool,msg:String)->void:
	checks+=1
	if not ok:failed=true;push_error(msg)
func _initialize()->void:call_deferred("run")
func run()->void:
	var dir:=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-test-"))
	var game:Node=load("res://scenes/main_v3.tscn").instantiate();game.world=World.new("res://content/home-v3/world.json");root.add_child(game)
	game.save_enabled=false;game.view.sound_enabled=false;game.set_process(false);await process_frame
	var hud:Control=game.island_hud
	check(hud.ui_size_mode=="大","authorized default large size")
	var sizes:=[]
	for mode in ["小","标准","大"]:
		hud.set_interface_size(mode);sizes.append(hud.residents_title.get_theme_font_size("font_size"))
		var p:=ConfigFile.new();p.load(dir.path_join("local-life.cfg"));check(p.get_value("interface","size","")==mode,"size saved "+mode)
		check(game.dialogue_button.custom_minimum_size.y>=32,"button min height "+mode)
	check(sizes[0]<sizes[1] and sizes[1]<sizes[2],"font increases")
	game.queue_free();await process_frame;await create_timer(.3).timeout
	print("UI size: ",checks," checks, failed=",failed);quit(1 if failed else 0)

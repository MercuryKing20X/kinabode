extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Save=preload("res://scripts/save_store.gd")
var checks:=0
var failed:=false
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failed=true;push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	var dir:=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-test-"))
	var game:Node=load("res://scenes/main_v3.tscn").instantiate();game.world=World.new("res://content/home-v3/world.json");root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.view.sound_enabled=false
	await process_frame
	var hud:Control=game.island_hud;var panel:PanelContainer=hud.wardrobe
	hud.appearance_buttons.codex.pressed.emit();check(panel.visible and panel.selected_actor=="codex","row entry")
	check(panel.resident_list.get_child_count()==4,"four partners only")
	var before:String=game.world.actors.codex.appearance_id
	panel.selected_work="ai-gpt";panel.refresh_preview();check(game.world.actors.codex.appearance_id==before,"preview is isolated")
	panel.apply_selection();check(game.world.actors.codex.appearance_id=="ai-gpt","confirmation applies")
	check(Save.save_world(game.world,dir),"save")
	var restored:=World.new("res://content/home-v3/world.json");check(Save.load_world(restored,dir).ok and restored.actors.codex.appearance_id=="ai-gpt","reloaded")
	hud.open_appearance("codex");panel.restore_default();panel.apply_selection();check(game.world.actors.codex.appearance_id==before,"restore default")
	hud.open_entry("wardrobe");check(panel.visible and panel.selected_actor!="human","handbook entry excludes human")
	panel.hide();hud.open_appearance("human");check(not panel.visible,"human blocked")
	panel.open_for("human",true);panel.selected_work="ai-gpt";panel.apply_selection()
	check(game.world.actors.human.appearance_id!="ai-gpt","human needs second confirmation")
	var confirm:ConfirmationDialog
	for node in panel.get_children():
		if node is ConfirmationDialog:confirm=node
	check(confirm!=null,"human confirm shown")
	confirm.confirmed.emit();check(game.world.actors.human.appearance_id=="ai-gpt","human explicitly confirmed")
	game.queue_free();await process_frame;await create_timer(.3).timeout
	print("Wardrobe: ",checks," checks, failed=",failed);quit(1 if failed else 0)

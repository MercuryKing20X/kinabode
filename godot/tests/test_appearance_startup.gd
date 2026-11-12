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
	var base:=OS.get_environment("HABITAT_DATA_DIR")
	assert(base.contains("youqi-test-"))
	for variant in ["legacy","available","missing"]:
		var dir:=base.path_join(variant);DirAccess.make_dir_recursive_absolute(dir)
		var world:=World.new("res://content/home-v3/world.json")
		world.actors.human.appearance_id="ai-gpt" if variant=="available" else "missing-art" if variant=="missing" else "ai-gpt"
		if variant!="legacy":world.actors.human["custom_appearance"]=true
		check(Save.save_world(world,dir),variant+" fixture saved")
		OS.set_environment("HABITAT_DATA_DIR",dir)
		var game:Node=load("res://scenes/main_v3.tscn").instantiate();game.world=World.new("res://content/home-v3/world.json");root.add_child(game)
		game.save_enabled=false;game.set_process(false);game.view.sound_enabled=false
		await process_frame;await process_frame
		var actor:Dictionary=game.world.actors.human
		var expected:="human-starter" if variant=="legacy" else "ai-gpt" if variant=="available" else "missing-art"
		check(actor.appearance_id==expected,variant+" startup preserves explicit appearance or defaults legacy")
		check(game.library.visual_appearance(actor)==("human-starter" if variant!="available" else "ai-gpt"),variant+" visual fallback safe")
		if variant=="available":
			check(not game._human_appearance_warning_acknowledged(),"warning initially unacknowledged")
			var warning:ConfirmationDialog
			for child in game.get_children():
				if child is ConfirmationDialog and child.title=="检查你的外观":warning=child
			check(warning!=null,"startup shows confirmation for non-default human")
			warning.canceled.emit();await process_frame
			check(game._human_appearance_warning_acknowledged(),"keep decision survives reload of preferences")
			game.save_enabled=true;var before:Dictionary=actor.duplicate(true)
			game._offer_human_appearance_restore()
			for child in game.get_children():
				if child is ConfirmationDialog and child.title=="检查你的外观":warning=child
			warning.confirmed.emit();await process_frame
			before.appearance_id="human-starter";before["custom_appearance"]=false
			check(actor==before,"restore button changes only human appearance")
			var found_backup:=false
			for filename in DirAccess.get_files_at(dir):
				if filename.begins_with("island-v2.json.before-appearance-"):found_backup=true
			check(found_backup,"restore button creates backup first")
		game.queue_free();await process_frame
		game=null;world=null
	OS.set_environment("HABITAT_DATA_DIR",base)
	await create_timer(0.3).timeout
	print("Appearance startup: ",checks," checks, failed=",failed)
	quit(1 if failed else 0)

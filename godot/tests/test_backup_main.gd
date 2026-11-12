extends SceneTree
## Temporary integration fixture; not a player-input or restore workflow.
const Helper=preload("res://tests/test_barbecue_v2.gd")
const Save=preload("res://scripts/save_store.gd")
const UI=preload("res://tests/barbecue_ui_fixture.gd")
var checks:=0
var failed:=false
func check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failed=true;push_error(message)
func _initialize()->void:call_deferred("run")
func run()->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-test-"));OS.set_environment("HABITAT_OPENING","legacy")
	var helper:=Helper.new();var world:RefCounted=helper.fresh(dir)
	check(Save.save_world(world,dir),"real source save exists before Main successful load")
	var before:String=FileAccess.get_sha256(dir.path_join("island-v2.json"))
	var game:Node=load("res://scenes/main_v3.tscn").instantiate();game.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");root.add_child(game)
	game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false)
	check(game.backups.active and game.backups.archives().size()==1,"real Main successful existing load triggers startup backup")
	check(FileAccess.get_sha256(dir.path_join("island-v2.json"))==before,"startup backup leaves original loaded save byte-identical")
	var start_day:int=game.world.days.day();game.world.director.set_all_enabled(false)
	game._process(float(game.world.days.day_seconds)+.1)
	check(game.world.days.day()==start_day+1,"actual World.advance delta crosses a real game day")
	check(game.backups.last_day==game.world.days.day() and game.backups.archives().size()==2,"Main backs current day only after ordinary successful autosave")
	var latest:Dictionary=game.backups.archives()[-1]
	check(latest.files["island-v2.json"].sha256==FileAccess.get_sha256(dir.path_join("island-v2.json")),"day archive is current disk save, never stale previous-day bytes")
	var reader:=ZIPReader.new();reader.open(latest.path)
	var value:Dictionary=JSON.parse_string(reader.read_file("island-v2.json").get_string_from_utf8());reader.close()
	check(value.day_cycle.marked_day==game.world.days.day(),"decompressed save contains actual current DayCycle")
	game._open_audio_settings()
	await process_frame;await process_frame
	var labels:Array=UI.descendants(game).filter(func(n):return n is Label and n.text.contains("最近备份"))
	var buttons:Array=UI.descendants(game).filter(func(n):return n is Button and n.text=="打开备份文件夹")
	check(labels.size()==1 and buttons.size()==1,"settings shows latest backup and folder button, without restore")
	game.save_enabled=false;game.queue_free();await process_frame;helper.free()
	print("Backup Main integration: ",checks," checks; failed=",failed,"; actual advance/save/load temporary fixture");quit(1 if failed else 0)

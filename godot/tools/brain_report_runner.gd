extends SceneTree
## Source/editor-only entry. The launcher supplies isolated user/data and deterministic entropy.
class Offline extends "res://scripts/companion_link.gd":
	var sent:Array=[]
	func _start()->bool:return false
	func _send(value:Dictionary)->bool:sent.append(value);return false
func _initialize()->void:call_deferred('run')
func run()->void:
	if not OS.has_feature('editor') or OS.get_environment('HABITAT_BRAIN_REPORT_ISOLATED')!='1':push_error('Use scripts/brain_report.py for an isolated source run.');quit(1);return
	var configured:Dictionary=JSON.parse_string(FileAccess.get_file_as_string('res://content/brain.json')).developer_report
	OS.set_environment('HABITAT_OPENING','standard');OS.set_environment('HABITAT_BRAIN_SEED',str(configured.seed))
	var game:Node=load('res://scenes/main_v3.tscn').instantiate();game.dialogue_adapter_factory=func(_id,_scope):return Offline.new()
	root.add_child(game);game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.chat.hide()
	var report:=preload('res://scripts/brain_report.gd').new();var settings:Dictionary=game.world.director.brains.values()[0].config.developer_report
	for tick in int(float(settings.seconds)/float(settings.step)):
		game.world.advance(float(settings.step));report.sample(game.world,float(settings.step))
		if tick==int(game.world.days.day_seconds/float(settings.step))-1:report.finish(game.world,OS.get_environment("HABITAT_DATA_DIR").path_join("brain-reports/day-1"))
		var speed:float=float(OS.get_environment('HABITAT_BRAIN_REPORT_SPEED'))
		if speed>0:await create_timer(float(settings.step)/speed).timeout
		elif tick%240==0:await process_frame
	for link in game.links.values():
		if not link is Offline or not link.sent.is_empty():push_error('Offline report adapter received a model request.');quit(1);return
	var output:String=OS.get_environment('HABITAT_DATA_DIR').path_join('brain-reports')
	report.finish(game.world,output);print('BRAIN_REPORT ',output);game.queue_free();await process_frame;quit(0)

extends SceneTree
class Fake extends "res://scripts/companion_link.gd":
	func _start()->bool:return false
	func _send(_message:Dictionary)->bool:return false
var game:Node
var results:Array=[]
func _initialize()->void:call_deferred("run")
func shot(label:String)->void:
	game.view.queue_redraw();await process_frame;await process_frame;RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("HABITAT_ISLAND_CAPTURE").path_join(label+".png"))
func profile(at:Vector2,label:String)->void:
	game.view.center=at;game.view.zoom=1.0
	var times:Array=[];var logic:Array=[];var totals:Array=[]
	for i in 180:
		var begin:int=Time.get_ticks_usec()
		game._process(.1)
		var processed:int=Time.get_ticks_usec()
		game.view.queue_redraw();RenderingServer.force_draw(false)
		var cost:float=(Time.get_ticks_usec()-begin)/1000.0
		if i>=30:
			times.append((Time.get_ticks_usec()-processed)/1000.0);logic.append((processed-begin)/1000.0);totals.append(cost)
		await process_frame
	times.sort();var total:=0.0
	for t in times:total+=t
	var logic_total:=0.0;var combined:=0.0
	for t in logic:logic_total+=t
	for t in totals:combined+=t
	results.append({"delta":.1,"logic_mean_ms":logic_total/logic.size(),"process_draw_mean_ms":combined/totals.size(),"label":label,"frames":times.size(),"draw_mean_ms":total/times.size(),"draw_p95_ms":times[int(times.size()*.95)],"draw_max_ms":times.back()})
func run()->void:
	OS.set_environment("HABITAT_OPENING","showcase");root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	game=load("res://scenes/main_v3.tscn").instantiate()
	game.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	game.dialogue_adapter_factory=func(_actor,_scope):return Fake.new()
	root.add_child(game);game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false);game.chat.hide();game.world.director.set_all_enabled(false)
	await process_frame;await process_frame
	game.island_hud.ui_root.hide()
	game.view.follow_player=false;game.view.center=Vector2(77,207);game.view.zoom=.28;await shot("flower-isle-overview")
	game.view.center=Vector2(40,199);game.view.zoom=1;await shot("greenhouse")
	game.view.center=Vector2(68,199);game.view.zoom=1;await shot("rose-fields")
	await profile(Vector2(81,89),"main-island")
	await profile(Vector2(68,199),"flower-isle")
	FileAccess.open(OS.get_environment("HABITAT_DATA_DIR").path_join("frame-times.json"),FileAccess.WRITE).store_string(JSON.stringify(results,"\t"))
	print("FLOWER_ISLE_FRAMES ",JSON.stringify(results))
	game.queue_free();await process_frame;quit()

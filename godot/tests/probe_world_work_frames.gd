extends SceneTree
class Fake extends "res://scripts/companion_link.gd":
	func _start()->bool:return true
	func _send(_payload:Dictionary)->bool:return true

func _initialize()->void:run.call_deferred()

func percentiles(values:Array)->Dictionary:
	values.sort()
	return {"p50":values[ceili(values.size()*.50)-1],"p95":values[ceili(values.size()*.95)-1],"p99":values[ceili(values.size()*.99)-1]}

func run()->void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.begins_with("/tmp/") and not directory.begins_with("/var/folders/"):
		quit(1);return
	root.size=Vector2i(1280,800)
	set_meta("title_opening","standard")
	var game:Node=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return Fake.new()
	root.add_child(game)
	game.save_enabled=false
	var world:RefCounted=game.world
	var ids:Array=["codex","companion-2","npc.mira","npc.nora"]
	for id in ids:
		var result:Dictionary=world.gathering.start(id,{"intent":"gather_wood","tree_count":8})
		if not result.ok:
			push_error("Fixture could not start physical gathering.")
			quit(1);return
	var thinking:=OS.get_environment("MY_AI_PERF")=="1"
	if thinking:
		var status:Button=game.island_hud.my_ai_button
		await preload("res://tests/barbecue_ui_fixture.gd").click(self,status)
		await preload("res://tests/barbecue_ui_fixture.gd").click(self,game.world_door_dialog.move_in)
		await preload("res://tests/barbecue_ui_fixture.gd").click(self,game.world_door_dialog.body.get_child(0).get_child(1))
	for i in 45:await RenderingServer.frame_post_draw
	var frame_ms:Array=[]
	var process_ms:Array=[]
	var previous:=Time.get_ticks_usec()
	var all_working:=0
	var in_flight:=0
	for i in 600:
		await RenderingServer.frame_post_draw
		var now:=Time.get_ticks_usec()
		frame_ms.append(float(now-previous)/1000.0)
		previous=now
		process_ms.append(1000.0*Performance.get_monitor(Performance.TIME_PROCESS))
		if ids.all(func(id):return world.work.jobs.get(id,{}).get("intent")=="gather_wood"):all_working+=1
		if not game.island_ai.rows.get("codex",{}).get("flight",{}).is_empty():in_flight+=1
	print("WORLD_FRAMES ",JSON.stringify({"frames":frame_ms.size(),"four_jobs":all_working,"thinking_frames":in_flight,"frame_ms":percentiles(frame_ms),"process_ms":percentiles(process_ms),"driver":DisplayServer.get_name()}))
	game.queue_free()
	await process_frame
	quit(0 if all_working==frame_ms.size() and (not thinking or in_flight==frame_ms.size()) else 1)

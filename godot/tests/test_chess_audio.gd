extends SceneTree
const Audio=preload("res://scripts/game_audio.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var directory:String=OS.get_environment("HABITAT_DATA_DIR");assert(directory.contains("youqi-"))
	var world:RefCounted=preload("res://tests/cooking_fixture.gd").fresh()
	world.intelligence.activate_presets()
	world.library=preload("res://scripts/character_library.gd").new();world.library.configure(directory);world.library.resident_world=world
	var view:Node=preload("res://scripts/island_view.gd").new();view.world=world;view.library=world.library;view.font=load("res://assets/fonts/NotoSansSC.ttf");root.add_child(view);view.set_process(false)
	view.center=world.point(world.actors.codex);view.region_id="home"
	var audio:=Audio.new();root.add_child(audio);audio.setup(world,view,directory);audio.advance(.1)
	var gate:float=world.director.speech_after
	var personal:float=world.director.routines.codex.next_speech
	var event:Dictionary={"id":"chess-test","actor_id":"codex","key":"bubble-one"}
	assert(audio.observer.panel_bubble(event))
	assert(not audio.observer.panel_bubble(event))
	audio.advance(4)
	event.key="bubble-two";assert(not audio.observer.panel_bubble(event))
	audio.advance(4.1)
	event.key="bubble-three";assert(audio.observer.panel_bubble(event))
	var voices:Array=audio.trace.filter(func(row):return row.action=="scheduled" and str(row.key).begins_with("chess-bubble:"))
	assert(voices.size()==2 and float(voices[1].time)-float(voices[0].time)>=8)
	assert(world.director.speech_after==gate and world.director.routines.codex.next_speech==personal)
	audio.speech_enabled=false;audio.advance(8.1);event.key="bubble-four"
	assert(not audio.observer.panel_bubble(event))
	audio.shutdown();audio.queue_free();view.queue_free()
	print("Chess bubbles share one-blip/eight-second/voice-toggle rules and leave world gates untouched")
	quit(0)

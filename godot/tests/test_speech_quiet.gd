extends SceneTree
const Audio=preload("res://scripts/game_audio.gd")
const Helper=preload("res://tests/test_barbecue_v2.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-test-"))
	var h:=Helper.new();var w:RefCounted=h.fresh(dir);w.intelligence.activate_presets()
	var view:Node=preload("res://scripts/island_view.gd").new();view.world=w;view.library=w.library;view.font=load("res://assets/fonts/NotoSansSC.ttf");root.add_child(view);view.set_process(false);view.center=w.point(w.actors.codex)
	var a:=Audio.new();root.add_child(a);a.setup(w,view,dir);assert(a.error.is_empty())
	for key in ["speech_gap_seconds","speech_max_blips","speech_near_tiles"]:
		for bad in [true,"6",-1,INF]:
			var rules:Dictionary=a.tuning.duplicate(true);rules[key]=bad;assert(not Audio.valid_tuning(rules))
	var old:Dictionary=a.tuning.duplicate(true)
	for key in ["speech_gap_seconds","speech_max_blips","speech_near_tiles"]:old.erase(key)
	assert(Audio.valid_tuning(old))
	view.say("第一条很长的说话气泡只响一声。","local_rules","codex")
	for i in range(100):a.advance(.02)
	var voice_count:int=a.trace.filter(func(e):return e.action=="scheduled" and str(e.event).begins_with("voice.")).size();assert(voice_count==1)
	view.say("第二条只显示不响。","local_rules","codex")
	for i in range(100):a.advance(.02)
	assert(a.trace.filter(func(e):return e.action=="scheduled" and str(e.event).begins_with("voice.")).size()==voice_count)
	# A new bubble inside the full eight-second window stays silent; none is queued.
	for i in range(195):a.advance(.02)
	view.say("八秒还没到，这条也只显示。","local_rules","codex");a.advance(.02)
	assert(a.trace.filter(func(e):return e.action=="scheduled" and str(e.event).begins_with("voice.")).size()==voice_count)
	a.advance(.2);view.say("八秒过后新的气泡只有一声。","local_rules","codex");a.advance(.02)
	assert(a.trace.filter(func(e):return e.action=="scheduled" and str(e.event).begins_with("voice.")).size()==voice_count+1)
	a.speech_enabled=false;a.persist();assert(not a.play_event("voice.soft"));assert(a.config.get_value("audio","speech_enabled")==false)
	a.shutdown();a.queue_free();view.queue_free();h.free();print("Speech quiet: strict defaults, one per bubble, eight-second silence, local preference PASS");quit()

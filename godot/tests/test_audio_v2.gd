extends SceneTree
const Audio=preload("res://scripts/game_audio.gd")
const Helper=preload("res://tests/test_barbecue_v2.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var temp:String=OS.get_environment("HABITAT_DATA_DIR");assert(temp.contains("youqi-test-"))
	var helper:=Helper.new();var world:RefCounted=helper.fresh(temp);world.intelligence.activate_presets()
	var view:Node=preload("res://scripts/island_view.gd").new();view.world=world;view.library=world.library;view.font=load("res://assets/fonts/NotoSansSC.ttf");root.add_child(view);view.hide();view.set_process(false)
	view.center=world.point(world.actors.codex)
	var audio:=Audio.new();root.add_child(audio);audio.setup(world,view,temp);assert(audio.error.is_empty())
	assert(int(audio.tuning.global_oneshot_limit)==5)
	var old:Dictionary=audio.tuning.duplicate(true);old.erase("targets_dbfs");assert(Audio.valid_tuning(old))
	var slots:Dictionary=audio.music_slots.duplicate(true);assert(Audio.valid_music_slots(slots))
	slots.slots.day=["day-song.mp3"];assert(Audio.valid_music_slots(slots));slots.slots.day=["../day-song.mp3"];assert(not Audio.valid_music_slots(slots))
	slots=audio.music_slots.duplicate(true);slots.version=true;assert(not Audio.valid_music_slots(slots))
	var invalid:Dictionary=audio.tuning.duplicate(true);invalid.targets_dbfs.voice=[-14,-18];assert(not Audio.valid_tuning(invalid))
	for id in ["ambience.wind","ambience.birds","ambience.waves","ambience.insects"]:audio.loop_event("budget:"+id,id,1.0)
	assert(audio.active.filter(func(e):return str(e.event).begins_with("ambience.") and e.target>0).size()==3)
	assert(not audio.catalog.events["ambience.birds"].loop)
	assert(audio.play_event("ui.click"))
	for item in audio.active:audio.recycle(item.player)
	audio.active.clear();audio.last_play.clear()
	view.say("测试一二三四五六。","local_rules","codex");view.say("测试一二三四五六。","local_rules","companion-2")
	audio.advance(.02)
	var owner:String=audio.observer.closest_voice();assert(not owner.is_empty())
	var voices:Array=audio.trace.filter(func(e):return e.action=="scheduled" and str(e.event).begins_with("voice."))
	assert(not voices.is_empty() and voices.all(func(e):return e.actor==owner))
	assert(audio.trace.any(func(e):return e.action=="dropped" and e.reason=="farther_speaker"))
	var main:=Button.new();main.set_meta("audio_primary",true);main.text="Chat";assert(audio.observer.primary_button(main));main.text="Dialogue";assert(audio.observer.primary_button(main));main.set_meta("audio_primary",false);assert(not audio.observer.primary_button(main));main.free()
	for item in audio.active:audio.recycle(item.player)
	audio.active.clear();audio.last_play.clear()
	for id in ["ambience.wind","ambience.birds","ambience.insects","ambience.waves","ui.click"]:assert(audio.play_event(id))
	assert(audio.active.size()==5)
	assert(audio.play_event("voice.soft"));assert(audio.active.size()==5)
	assert(audio.active.any(func(e):return e.event=="voice.soft"))
	assert(not audio.play_event("ui.open"));assert(audio.dropped.get("ui.open",0)>0)
	assert(audio.trace.filter(func(e):return e.action=="scheduled").all(func(e):return int(e.active_total)<=5))
	for item in audio.active:audio.recycle(item.player)
	audio.active.clear();audio.last_play.clear()
	for surface in ["grass","sand","stone","wood"]:
		var id:String="step."+surface;var previous:=""
		for version in ["A","B","C"]:
			audio.catalog.events[id].selected=version
			assert(audio.catalog.events[id].variants[version].takes.size()==2)
			for n in range(20):
				for item in audio.active:audio.recycle(item.player)
				audio.active.clear();audio.last_play.erase(id)
				assert(audio.play_event(id))
				var row:Dictionary=audio.trace[-1];assert(row.file_sha256!=previous);previous=row.file_sha256
	var manifest_copy:Dictionary=audio.catalog.duplicate(true)
	var primary:Dictionary=manifest_copy.events["step.grass"].variants.A
	primary.erase("takes");assert(Audio.valid_manifest(manifest_copy))
	manifest_copy=audio.catalog.duplicate(true)
	manifest_copy.events["step.grass"].variants.A.takes[1]=manifest_copy.events["step.grass"].variants.A.takes[0].duplicate(true)
	assert(not Audio.valid_manifest(manifest_copy))
	manifest_copy=audio.catalog.duplicate(true);manifest_copy.events["step.grass"].selected=[];assert(not Audio.valid_manifest(manifest_copy))
	manifest_copy=audio.catalog.duplicate(true);manifest_copy.events["step.grass"].variants.A.source_id=[];assert(not Audio.valid_manifest(manifest_copy))
	var test_result:Dictionary={"text":""}
	audio.sound_test_finished.connect(func(message):test_result.text=message)
	audio.enabled=false;audio.apply_mix();audio.test_sounds()
	await create_timer(1.6).timeout
	assert(test_result.text.contains("未播放") and not test_result.text.contains("音乐还未放入"))
	var music_ids:Array=audio.catalog.events.keys().filter(func(id):return str(id).begins_with("music."))
	assert(music_ids.size()==8)
	for scene in ["day","dusk","night","rain","fireside","moon","dark","their"]:
		var id:String="music."+scene
		assert(audio.catalog.events.has(id))
		var clip:Dictionary=audio.catalog.events[id].variants.A
		var source:Dictionary=audio.catalog.sources[clip.source_id]
		assert(source.kind=="licensed_music" and source.license=="CC-BY-4.0")
		assert(source.parameters.author=="Kevin MacLeod" and FileAccess.get_sha256(clip.file)==clip.sha256)
	# Muted real music must never be reported as missing or dispatched.
	assert(not audio.trace.any(func(row):return row.get("action")=="scheduled" and str(row.get("event","")).begins_with("music.")))
	audio.queue_free();view.queue_free();helper.free()
	await process_frame;await create_timer(.2).timeout
	print("Audio v2: nearest speaker, priorities, cap, 240 non-repeating recorded steps and old tuning validated")
	quit()

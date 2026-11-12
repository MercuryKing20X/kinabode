extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"))
	var game:Node=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game)
	await create_timer(1.0).timeout
	game.set_process(false)
	var audio:Node=game.game_audio
	assert(audio!=null and audio.error.is_empty())
	var ids:Array=audio.catalog.events.keys();ids.sort()
	for id in ids:
		for item in audio.active:audio.recycle(item.player)
		audio.active.clear();audio.last_play.clear()
		var key:String="core-event:"+id
		assert(audio.play_event(id,Vector2.ZERO,"","",1,1,key))
		var stream:AudioStream=audio.active[-1].player.stream
		assert(stream is AudioStreamWAV and stream.format==AudioStreamWAV.FORMAT_16_BITS)
		for item in audio.active:
			if item.key==key and item.loop:item.gain=1.0;item.player.volume_db=float(audio.catalog.events[id].volume_db)
		await process_frame
		await create_timer(.12).timeout
		assert(audio.trace.any(func(e):return e.action=="native_start" and e.key==key))
	print("CORE_EVENT_COUNT ",ids.size())
	game.queue_free();await process_frame;await create_timer(.2).timeout
	quit()

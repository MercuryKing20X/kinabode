extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"))
	var game:Node=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game)
	await create_timer(1.0).timeout
	var audio:Node=game.game_audio
	assert(audio!=null and audio.error.is_empty())
	print("CORE_OUTPUT_DEVICE ",AudioServer.get_output_device())
	audio.test_sounds()
	await create_timer(4.5).timeout
	var starts:Array=audio.trace.filter(func(e):return e.action=="native_start" and str(e.key).begins_with("sound-test:"))
	print("CORE_TEST_NATIVE_STARTS ",JSON.stringify(starts))
	assert(starts.map(func(e):return e.event)==["voice.soft","step.grass","ambience.fire"])
	assert(not audio.sound_test_busy)
	game.queue_free();await process_frame;await create_timer(.2).timeout
	quit()

extends SceneTree
func _initialize()->void:call_deferred("run")
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"))
	var game:Node=preload("res://tests/barbecue_ui_fixture.gd").init_game(self)
	await process_frame;await process_frame
	var view:Node=game.view
	for cache in [view.static_ground,view.static_west,view.static_farms,view.static_decor]:
		assert(cache!=null and cache.get_child(0).zoom==1.0,"cached world must use exactly32 pixels per tile")
	for pair in [["east-forest",Vector2(128,80)],["home",Vector2(64,50)],["moon",Vector2(-60,78)]]:
		view.center=pair[1];view.zoom=1.25;view.queue_redraw()
		await process_frame;await process_frame;RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png(OS.get_environment("HABITAT_DARK_EVIDENCE").path_join(pair[0]+".png"))
	game.queue_free();await process_frame
	print("Four world caches use1:1 scale; three actual viewport captures saved")
	quit()

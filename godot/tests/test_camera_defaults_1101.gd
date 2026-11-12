extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"))
	var game:Node=UI.init_game(self);await process_frame
	var view:Node=game.view
	view.show_region("home")
	assert(is_equal_approx(view.zoom,1.5625),"daily home default uses shared config")
	view.update_ambience()
	assert(is_equal_approx(view.zoom,1.5625),"atmosphere must preserve configured fractional daily zoom")
	view.zoom=1.35;view.queue_redraw();await process_frame
	assert(is_equal_approx(view.zoom,1.35),"terrain draw must preserve fractional zoom too")
	var moon:Dictionary=game.world.catalog.regions.home.layout.moon
	var bounds:Rect2=game.world.catalog.rectangle(moon.bounds)
	assert(is_equal_approx(view.default_zoom("home",bounds.get_center()),1.6875),"moon defaults use actual home subregion coordinates")
	for pair in [[MOUSE_BUTTON_WHEEL_UP,2.0],[MOUSE_BUTTON_WHEEL_DOWN,1.0]]:
		var wheel:=InputEventMouseButton.new();wheel.position=Vector2(600,400);wheel.pressed=true;wheel.button_index=pair[0];root.push_input(wheel,true);await process_frame
		assert(is_equal_approx(view.zoom,pair[1]),"original wheel endpoints remain usable")
	# DIRECTION 2026-11-09 bottom contains only chat/lightning/manage/map.
	# The original camera-only Space entry remains the real host input.
	for down in [true,false]:
		var back:=InputEventKey.new();back.keycode=KEY_SPACE;back.pressed=down;root.push_input(back,true)
		if down:assert(view.follow_player,"real my-view Space input")
		await process_frame
	assert(view.follow_player and is_equal_approx(view.zoom,1.5625),"my-view restores closer configured default and tracking")
	assert(game.links.values().all(func(link):return link._pid<=0),"camera never launches model")
	game.queue_free();await process_frame
	print("Camera defaults: 9 checks passed")
	quit()

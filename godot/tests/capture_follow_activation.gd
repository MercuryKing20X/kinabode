extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
var game:Node
func _initialize()->void:call_deferred("run")
func mouse(at:Vector2)->void:
	for pressed in [true,false]:
		var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.pressed=pressed;e.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0;e.position=at;root.push_input(e,true);await process_frame
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"))
	game=UI.init_game(self);await process_frame;await process_frame
	game.set_process(true);game.view.set_process(true);game.island_hud.set_process(true)
	# Camera-only QA framing; the human reaches this point via actual ground click.
	game.view.center=Vector2(82,80);game.view.follow_player=false
	await process_frame;await mouse(game.view.screen(Vector2(82,80)))
	for tick in range(600):
		await create_timer(.1).timeout
		if not game.world._routes.has("human"):break
	assert(game.world.point(game.world.actors.human).distance_to(game.world.point(game.world.actors.codex))>15)
	assert(await UI.click(self,game.dialogue_button));await process_frame
	await mouse(game.chat_input.get_global_rect().get_center());await process_frame
	var focused:bool=game.chat_input.has_focus()
	assert(await UI.click(self,game.gathering_button))
	assert(await UI.click(self,game.follow_ui.checks.codex));await create_timer(.3).timeout
	var immediate:bool=game.world.activities.following.has("codex")
	var before_distance:float=game.world.point(game.world.actors.codex).distance_to(game.world.point(game.world.actors.human))
	assert(await UI.click(self,game.follow_ui.menu.get_ok_button()))
	await create_timer(6).timeout
	var after_distance:float=game.world.point(game.world.actors.codex).distance_to(game.world.point(game.world.actors.human))
	var result:Dictionary={"chat_focused_before":focused,"immediate_selected":immediate,"before_distance":before_distance,"after_distance":after_distance,"chat_focused_after":game.chat_input.has_focus(),"resident_held":game.world.director.routines.codex.held,"has_route":game.world._routes.has("codex"),"selected":game.world.activities.following.has("codex")}
	print(JSON.stringify(result))
	var out:FileAccess=FileAccess.open(OS.get_environment("HABITAT_DARK_EVIDENCE").path_join("activation.json"),FileAccess.WRITE);out.store_string(JSON.stringify(result,"\t"));out.close()
	var before:bool=OS.get_environment("HABITAT_FOLLOW_BASELINE")=="1"
	if not before:
		assert(immediate,"ticking one resident must immediately activate follow")
		assert(after_distance<before_distance-5,"far resident must actually approach after chat -> follow")
		assert(not game.chat_input.has_focus() and not game.world.director.routines.codex.held)
	game.queue_free();await process_frame;quit()

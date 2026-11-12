extends SceneTree
const R=preload("res://tests/relationship_reward_fixture.gd")
const F=preload("res://tests/cooking_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
var checks:=0
var failed:=false
var output: String
func _initialize() -> void:call_deferred("run")
func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok:failed=true;push_error(text)
func pair(game: Node,name: String) -> void:
	for size in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=size;game.view.queue_redraw();await process_frame;await process_frame
		if name=="stage4":
			game.resident_connections.details_scroll.ensure_control_visible(game.resident_connections.our_days);await process_frame
		check(root.get_visible_rect().encloses(game.resident_connections.get_global_rect()) if game.resident_connections.visible else game.view.speech_layout().all(func(entry):return root.get_visible_rect().encloses(entry.box)),"reward viewport fits "+str(size))
		if not output.is_empty():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join(name+"-%dx%d.png"%[size.x,size.y]))
func run() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	output=OS.get_environment("HABITAT_LIFE2_CAPTURE_DIR")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	for level in range(1,5):
		var game: Node=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
		await process_frame
		game.world.director.set_all_enabled(false);game.view.sound_enabled=false;game.chat.hide();game.chat_input.release_focus()
		check(Save.load_world(game.world,R.directory().path_join("stage"+str(level))).ok,"load genuinely earned viewport stage")
		game.world.hunger.enabled=false # Non-hungry relationship reward opportunity.
		R.prepare(game.world)
		check(R.camp(game.world),"explicit actual camp movement for viewport")
		R.ready(game.world);game.view.center=game.world.point(game.world.actors.human)+Vector2(1,-1);game.view.zoom=1.2
		game.resident_connections.open("codex");game.resident_connections.tabs.current_tab=1;game.resident_connections.refresh()
		check(game.resident_connections.address_edit.editable,"familiar address UI unlocked")
		game.resident_connections.address_edit.text="岛主";game.resident_connections.address_edit.text_submitted.emit("岛主")
		check(game.world.relationships.address("codex")=="岛主","actual nickname UI saves bound resident preference")
		if level<4:game.resident_connections.close_panel()
		if level==1:
			check(game.world.relationships.reward("codex","passing"),"familiar actual passing greeting");game._process(0)
		elif level==2:
			check(game.world.relationships.reward("codex","sit"),"close real nearby empty seat");R.step(game.world,10);game._process(0)
			check(game.world.director.routines.codex.kind=="rest","close physically seated")
		elif level==3:
			check(game.world.command("human",{"intent":"gather_wood","tree_count":1}).ok,"human explicitly starts actual wood work")
			R.step(game.world,1)
			check(game.world.relationships.reward("codex","work"),"attuned companion approaches own actual working human")
			R.step(game.world,1);game._process(0)
		else:
			check(game.resident_connections.our_days.visible and game.resident_connections.our_days.text.contains("我们的日子"),"family real memory book visible")
			game.resident_connections.details_scroll.scroll_vertical=120
		await pair(game,"stage"+str(level))
		check(game.links.values().all(func(link):return link._pid==-1),"no model calls in stage reward UI")
		for player in game.view.sounds.values():player.stop()
		game.queue_free();await process_frame;await create_timer(.1).timeout
	print("Relationship rewards controller: %d checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)

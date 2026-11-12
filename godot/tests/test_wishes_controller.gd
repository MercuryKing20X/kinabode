extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
var game: Node
var checks:=0
var failed:=false
var output: String
func _initialize() -> void:call_deferred("run")
func check(value: bool,text: String) -> void:
	checks+=1
	if not value:failed=true;push_error(text)
func advance(seconds: float) -> void:
	for tick in range(int(ceil(seconds/.5))):game._process(.5)
func pair(name: String) -> void:
	for size in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=size;await process_frame;await process_frame
		game.wish_panel.refresh();game.view.queue_redraw();await process_frame
		check(not game.wish_panel.visible or root.get_visible_rect().encloses(game.wish_panel.get_global_rect()),"wish fits actual viewport "+str(size))
		if not output.is_empty():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join(name+"-%dx%d.png"%[size.x,size.y]))
func run() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	output=OS.get_environment("HABITAT_LOCAL_LIFE_CAPTURE_DIR")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	await process_frame
	game.chat.hide();game.chat_input.release_focus();game.view.sound_enabled=false;game.world.director.set_all_enabled(false)
	var world: RefCounted=game.world
	world.hunger.enabled=false # Isolate wishes; hunger integration is tested separately.
	world.intelligence.compatibility=true # Test the original wish timing independently of context cadence.
	check(F.harvest(world,"turnip"),"harvest real crop for wish viewport")
	check(preload("res://tests/local_life2_fixture.gd").shared_catch(world),"second true shared activity for new familiar threshold")
	world.wishes.config.templates=[world.wishes.template("soup")];world.wishes.config.first_after=1
	world.days.config.greeting_after=world.days.day_seconds+1;world.days.config.small_after=world.days.day_seconds+1
	world.activities.default_follow_excluded["codex"]=true # Isolate the wish speech opportunity from following.
	var r: RefCounted=world.director.routines.codex;r.set_enabled(true);r.set_chatter(true)
	for key in r.preferences.weights:r.preferences.weights[key]=0
	advance(130)
	game.view.center=world.point(world.actors.human);game.view.zoom=1.1;game.wish_panel.refresh()
	check(world.wishes.active("codex").get("announced",false) and game.wish_panel.visible,"only real announced wish gets nonblocking card")
	await pair("wish-card")
	world.activities.default_follow_excluded["companion-2"]=true
	var other: RefCounted=world.director.routines["companion-2"];other.set_enabled(true);other.set_chatter(false)
	for key in other.preferences.weights:other.preferences.weights[key]=0
	advance(2);game.wish_panel.refresh()
	var unseen: Dictionary=world.wishes.active("companion-2")
	check(not unseen.is_empty() and not unseen.announced,"real unannounced second wish exists before close")
	var close_button: Button=game.wish_panel.find_children("*","Button",true,false)[0];close_button.pressed.emit()
	check(game.wish_panel.dismissed.get("codex","")==world.wishes.active("codex").id and not game.wish_panel.dismissed.has("companion-2"),"remember only visible announced card; never dismiss an unheard resident wish")
	game.resident_connections.open("codex");game.wish_panel.refresh(true)
	check(not game.wish_panel.visible,"wish drawer yields to explicit resident UI");game.resident_connections.close_panel()
	r.set_enabled(false)
	check(F.serve(world,"turnip-soup") and F.eat(world,"human") and F.eat(world,"codex") and F.eat(world,"codex") and F.cleanup(world),"viewport relation event follows actual shared meal")
	check(F.job(world,"codex",{"intent":"come_near"}),"return near player before local reaction")
	r.set_enabled(true)
	for tick in range(2000):
		game._process(.5)
		if world.director.events.any(func(event):return event.context=="relationship_stage"):break
	check(world.memories.records.any(func(entry):return entry.kind=="wish_completed") and world.memories.records.any(func(entry):return entry.kind=="relationship_stage"),"actual wish and familiar event committed")
	game.view.center=world.point(world.actors.human);game.view.zoom=1.1
	await pair("relationship-stage")
	check(game.links.values().all(func(link):return link._pid==-1),"local life never starts model process")
	game.queue_free();await process_frame
	print("Wishes controller: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)

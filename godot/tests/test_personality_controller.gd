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
func pair() -> void:
	for size in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=size;game.view.queue_redraw();await process_frame;await process_frame
		check(game.view.speech_by_actor.size()==4 and game.view.speech_by_actor.keys().all(func(id):return game.view.speech_by_actor[id].source=="local_rules" and game.view.speech_by_actor[id].text in game.world.personality.pool(id,"rain")),"four simultaneous retained local reaction bubbles "+str(size))
		if not output.is_empty():
			await RenderingServer.frame_post_draw
			root.get_texture().get_image().save_png(output.path_join("personalities-rain-%dx%d.png"%[size.x,size.y]))
func run() -> void:
	if not OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"):quit(1);return
	output=OS.get_environment("HABITAT_LOCAL_LIFE_CAPTURE_DIR")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	game=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	await process_frame
	var world: RefCounted=game.world;world.director.set_all_enabled(false);game.chat.hide();game.chat_input.release_focus();game.view.sound_enabled=false;game.view.set_process(false)
	world.hunger.enabled=false # This probe compares rain reactions, not hunger reactions.
	var p: Vector2=world.point(world.actors.human);var offsets: Array=[Vector2(-3,-2),Vector2(3,-2),Vector2(-3,3),Vector2(3,3)];var index:=0
	for id in world.director.routines:
		var target: Vector2=p+offsets[index];index+=1
		check(F.job(world,id,{"intent":"move","x":target.x,"y":target.y}),"explicit QA route real resident into common scene")
	for candidate in range(1000):
		world.weather.weather_seed=candidate
		if world.weather.current().id=="rain":break
	world.days.config.greeting_after=world.days.day_seconds+1;world.days.config.small_after=world.days.day_seconds+1;world.wishes.config.first_after=86400
	for r in world.director.routines.values():
		world.activities.default_follow_excluded[r.ID]=true # Explicit independent reaction fixture.
		r.set_enabled(true);r.set_chatter(true)
		for key in r.preferences.weights:r.preferences.weights[key]=0
	# Game time advances honestly; freeze only presentation time to compare the four actual utterances.
	for tick in range(1200):
		game._process(.5)
		for event in world.director.events:
			if event.context=="personality_rain":world.director.routines[event.actor_id].set_chatter(false) # Retain that actual utterance for visual comparison.
		if world.director.events.filter(func(event):return event.context=="personality_rain").size()==4:break
	var events: Array=world.director.events.filter(func(event):return event.context=="personality_rain")
	if events.size()!=4:print("PERSONA_VIEW_DEBUG ",world.director.events," states ",world.director.routines.values().map(func(r):return [r.ID,r.state(),r.time,r.next_speech,world.relationships.available(r.ID),world.days.defer_idle(r.ID)]))
	check(events.size()==4 and events.all(func(event):return event.text in world.personality.pool(event.actor_id,"rain")),"same real rain produces four own authored pools")
	game.view.center=p+Vector2(0,1);game.view.zoom=1.15
	await pair()
	game.resident_connections.open("codex");game.resident_connections.refresh()
	check(game.resident_connections.personality_label.text.contains(world.personality.summary("codex").name),"resident page shows read-only local personality")
	check(game.links.values().all(func(link):return link._pid==-1),"no model started for two model-controlled residents' local reactions")
	game.queue_free();await process_frame
	print("Personality controller: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)

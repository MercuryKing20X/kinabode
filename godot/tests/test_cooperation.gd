extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
const B=preload("res://tests/backpack_fixture.gd")
const C=preload("res://tests/cooperation_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
var checks:=0
var failed:=false
var directory: String
func _initialize() -> void:call_deferred("run")
func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok:failed=true;push_error(text)
func measure(enabled: bool) -> Dictionary:
	var world:=F.fresh();check(C.prepare(world,directory.path_join("art")),"two real eight-wood bundles and validated site routes")
	world.cooperation.config.enabled=enabled;check(C.begin(world),"builder and exact helper accepted")
	var elapsed:=0.0;var first:=0.0
	for frame in range(80):
		world.advance(.025);elapsed+=.025
		if first==0 and int(world.objects["home.house.01"].delivered.get("wood",0))>0:first=elapsed
		if int(world.objects["home.house.01"].delivered.get("wood",0))==16:break
	check(B.wood_total(world)==18 and int(world.objects["home.house.01"].delivered.get("wood",0))==16,"real sixteen-wood investment plus two-wood surplus conserves all eighteen harvested wood")
	return {"world":world,"first":first,"both":elapsed}
func run() -> void:
	directory=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	var solo:=measure(false);var pair:=measure(true)
	check(pair.first==solo.first and pair.both==solo.both,"actual delivery duration approximately half within one fixed frame")
	check(pair.world.work.CARRY_LIMIT==20 and pair.world.work.BUILD_SECONDS==3.0,"capacity and construction duration unchanged")
	var world:=F.fresh();check(C.prepare(world,directory.path_join("stop-art")) and C.begin(world),"stop case uses real accepted jobs")
	for frame in range(4):world.advance(.025)
	check(not world.cooperation.active("codex") and not world.cooperation.active("human"),"both present same target are cooperating")
	world.command("human",{"intent":"stop"})
	check(not world.cooperation.active("codex") and world.actors.human.carry.get("wood",0)==8,"partner stop immediately restores solo handling, preserves own bundle")
	var elapsed:=0.0
	for frame in range(40):
		world.advance(.025);elapsed+=.025
		if int(world.objects["home.house.01"].delivered.get("wood",0))==8:break
	check(elapsed>=0 and B.wood_total(world)==18 and world.actors.human.carry.get("wood",0)==8,"remaining delivery resumes solo speed and keeps total wood")
	check(Save.save_world(world,directory.path_join("stop")),"save cancelled cooperative delivery")
	var loaded:=F.fresh();check(Save.load_world(loaded,directory.path_join("stop")).ok and loaded.work.jobs.is_empty() and B.wood_total(loaded)==18,"reload conserves all material and never resumes cooperation/jobs")
	var job: Dictionary={"intent":"farm_take","target_id":"home.house.01","phase":"farm_work"}
	check(world.cooperation.factor("codex",job,world.objects["home.house.01"],"putting_down")==1,"unrelated jobs cannot borrow the bonus")
	# Existing homestead path uses same handling function; no second movement/resource implementation.
	var home:=F.fresh();check(B.wood(home,8),"real homestead wood")
	var chest: Dictionary={"id":"storage","items":home.storage._items,"capacity":9007199254740991,"kind":"storage","region_id":"home","position":home.actors.human.position};var pos: Vector2=home.interior._beside(chest)
	for id in ["human","codex"]:check(F.job(home,id,{"intent":"move","x":pos.x,"y":pos.y}),"real approach to source "+id)
	for id in ["human","codex"]:check(home.command(id,{"intent":"homestead_start","site_id":home.homestead.config.site.id,"wood_limit":8,"crop_limit":0}).ok,"own homestead contribution "+id)
	var cooperated:=false
	for frame in range(3000):
		home.advance(.025)
		cooperated=cooperated or home.cooperation.active("human") or home.cooperation.active("codex")
		if not home.work.jobs.has("human") and not home.work.jobs.has("codex"):break
	check(not cooperated and int(home.homestead.site.delivered.get("wood",0))==16 and B.wood_total(home)+16==24,"homestead delivery also cooperates with real receipt conservation")
	# Actual frozen moment in existing viewport/resident progress UI.
	var game: Node=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	await process_frame
	game.view.sound_enabled=false;game.chat.hide();game.chat_input.release_focus()
	check(C.prepare(game.world,directory.path_join("view-art")) and C.begin(game.world),"viewport uses real materials and jobs")
	for frame in range(3):game.world.advance(.025)
	game.view.follow_player=false;game.view.center=game.world.point(game.world.objects["home.house.01"])+Vector2(1,2);game.view.zoom=1.1
	game.resident_connections.open("codex");game.resident_connections.tabs.current_tab=1;game.resident_connections.refresh()
	check(not game.resident_connections.activity.text.contains("结伴交料"),"existing progress UI accurately labels cooperation")
	var output:=OS.get_environment("HABITAT_OVERNIGHT_CAPTURE_DIR")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	for size in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=size;await process_frame;await process_frame
		check(root.get_visible_rect().encloses(game.resident_connections.get_global_rect()),"cooperative viewport fits "+str(size))
		if not output.is_empty():
			await RenderingServer.frame_post_draw
			var image:=root.get_texture().get_image();check(image.get_size()==size,"actual cooperative image "+str(size));image.save_png(output.path_join("cooperation-%dx%d.png"%[size.x,size.y]))
	check(game.links.values().all(func(link):return link._pid==-1),"no inference in cooperation")
	game.queue_free();await process_frame
	print("Cooperation: %s checks, failed=%s; solo %.3f/%.3f paired %.3f/%.3f"%[checks,failed,solo.first,solo.both,pair.first,pair.both]);quit(1 if failed else 0)

extends SceneTree
const F=preload("res://tests/cooking_fixture.gd")
const Save=preload("res://scripts/save_store.gd")
var checks:=0
var failed:=false
var directory: String
func _initialize() -> void:call_deferred("run")
func check(ok: bool,text: String) -> void:
	checks+=1
	if not ok:failed=true;push_error(text)
func register(world: RefCounted,action: String,target: String,phase: String="morning") -> Dictionary:
	return world.command("codex",{"intent":"promise","action_type":action,"target_id":target,"day":world.days.day()+1,"phase":phase})
func plant(world: RefCounted) -> String:
	var farm: String="farm.home";var plot: Dictionary=world.farms.farm_plots(farm)[0]
	if not F.job(world,"human",{"intent":"assign_farm","farm_id":farm,"manager_id":"codex"}) or not F.job(world,"human",{"intent":"plant","target_id":plot.id,"crop_id":"turnip"}):return ""
	return plot.id
func arrive(world: RefCounted,key: String) -> void:
	world.advance(maxf(.1,float(world.promises.entries[key].due_at)-world.forest.clock+.1))
func until_carry(world: RefCounted) -> bool:
	for frame in range(6000):
		world.advance(.1)
		if world.work.jobs.get("codex",{}).get("step")=="harvest" and float(world.work.jobs.codex.get("field_time",0))>.1:return true
	return false
func reload_world(world: RefCounted,name: String) -> RefCounted:
	var path:=directory.path_join(name);check(Save.save_world(world,path),"save actual "+name)
	var loaded:=F.fresh();check(Save.load_world(loaded,path).ok,"reload "+name);return loaded
func run() -> void:
	directory=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	var world:=F.fresh();var plot:=plant(world)
	check(not plot.is_empty() and not world.farms.plots[plot].watered,"real planted dry crop")
	var made:=register(world,"water",plot)
	check(made.ok and world.promises.own("codex").size()==1 and world.work.jobs.is_empty(),"promise registration does not execute or infer")
	var human: Dictionary=world.actors.human.duplicate(true);arrive(world,made.promise_id)
	check(world.days.day()==2 and world.work.jobs.get("codex",{}).get("source")=="promise","crossing actual day starts owned existing water action")
	check(F.wait(world,"codex") and world.farms.plots[plot].watered and world.promises.entries.is_empty(),"actual task finishes before promise is credited")
	var result: Array=world.memories.records.filter(func(entry):return entry.kind=="promise_result")
	check(result.size()==1 and result[0].facts.outcome=="completed" and result[0].participants.size()==2 and world.actors.human==human,"completed fact true, no human operation")
	check(world.memories.valid_saved(world.memories.saved(),world.actors,world.world_id),"strict canonical promise fact validation")
	check(world.work.events.any(func(event):return event.get("source")=="promise" and event.status=="completed"),"promise Work event provenance suppresses autonomous inference")
	world.advance(121)
	check(not world.director.memory_reminders.text_for("codex",result[0]).is_empty() and world.director.memory_reminders.text_for("companion-2",result[0]).is_empty(),"existing reminders can recall only own genuine promise outcome")
	var promise_count:int=world.promises.entries.size();var before_cook:Dictionary=world.actors.duplicate(true)
	check(not register(world,"cook","turnip-soup").ok and world.promises.entries.size()==promise_count and world.actors==before_cook,"removed cook promise rejects without work human movement or fake entry")
	var bad:=register(world,"water","missing");check(not bad.ok and world.promises.entries.is_empty(),"invalid target rejects whole promise")
	bad=register(world,"teleport_human","human");check(not bad.ok,"arbitrary action rejected")
	bad=world.command("human",{"intent":"promise","action_type":"come_near","target_id":"human","day":3,"phase":"morning"});check(not bad.ok,"human cannot receive automatic promise operation")
	for phase in ["morning","afternoon","dusk"]:check(register(world,"come_near","human",phase).ok,"bounded future promise "+phase)
	check(not register(world,"come_near","human","night").ok,"fourth promise rejected")
	var key: String=world.promises.entries.keys()[0]
	check(not world.command("companion-2",{"intent":"promise_cancel","promise_id":key}).ok,"model cannot cancel another resident promise")
	check(world.command("codex",{"intent":"promise_cancel","promise_id":key}).ok,"owner may explicitly cancel")
	var original: Dictionary=world.promises.saved();var loaded:=reload_world(world,"pending")
	check(loaded.memories._canonical(loaded.promises.saved())==loaded.memories._canonical(original) and loaded.work.jobs.is_empty() and loaded.work.claims.is_empty(),"future commitments survive reload without jobs or claims")
	var corrupt: Dictionary=original.duplicate(true);corrupt.entries[0].target_id="missing"
	check(not world.promises.valid_saved(corrupt,world.actors,world.days.origin),"invalid saved target rejected")
	# Busy due time must preserve the real accepted job.
	world=F.fresh();made=register(world,"come_near","human")
	check(world.command("codex",{"intent":"gather_wood","tree_count":1}).ok,"real competing work accepted")
	var job_id: String=world.work.jobs.codex.id;arrive(world,made.promise_id)
	check(world.work.jobs.get("codex",{}).get("id")==job_id and world.promises.entries.has(made.promise_id) and not world.memories.records.any(func(entry):return entry.kind=="promise_result"),"busy promise defers without stealing work or inventing a failure")
	# Harvest has actual produce in hand before cancel/reload.
	world=F.fresh();plot=plant(world);check(F.job(world,"human",{"intent":"water","target_id":plot}),"real initial watering")
	world.advance(float(world.farms.crops.turnip.seconds)+1);made=register(world,"harvest",plot);arrive(world,made.promise_id)
	check(until_carry(world),"real promise harvest reaches carried produce and seed")
	var amount: int=F.amount(world,"turnip");var carry: Dictionary=world.actors.codex.carry.duplicate()
	check(world.command("codex",{"intent":"promise_cancel","promise_id":made.promise_id}).ok and world.actors.codex.carry==carry and F.amount(world,"turnip")==amount,"cancel preserves actual harvested bundle")
	loaded=reload_world(world,"cancelled-carry")
	check(loaded.memories._canonical(loaded.actors.codex.carry)==loaded.memories._canonical(carry) and F.amount(loaded,"turnip")==amount and loaded.work.jobs.is_empty(),"cancel/reload conserves produce and does not resume")
	world=F.fresh();plot=plant(world);F.job(world,"human",{"intent":"water","target_id":plot});world.advance(float(world.farms.crops.turnip.seconds)+1)
	made=register(world,"harvest",plot);arrive(world,made.promise_id);check(until_carry(world),"second actual harvest in flight")
	amount=F.amount(world,"turnip");carry=world.actors.codex.carry.duplicate();loaded=reload_world(world,"running-carry")
	check(loaded.memories._canonical(loaded.actors.codex.carry)==loaded.memories._canonical(carry) and F.amount(loaded,"turnip")==amount and loaded.work.jobs.is_empty() and loaded.promises.entries.is_empty(),"running reload keeps material and clears only interrupted commitment")
	check(loaded.memories.records.any(func(entry):return entry.kind=="promise_result" and entry.facts.outcome=="failed" and entry.facts.reason.contains("重载")),"reload interruption is honest, never completed")
	# Promise fishing must not turn its real fishing_catch memory into model inference.
	world=F.fresh()
	check(preload("res://tests/fishing_fixture.gd").coast(world,"codex"),"real route to sea for promised fishing")
	var prefs:=preload("res://scripts/resident_intelligence_preferences.gd").new();prefs.setup(directory.path_join("inference"),world.world_id);DirAccess.make_dir_recursive_absolute(prefs.path.get_base_dir());prefs.runtime_supported.codex=true;prefs.enable_autonomy("codex",true)
	var scheduler:=preload("res://scripts/autonomy_scheduler.gd").new()
	var sent: Array=[];scheduler.setup(world,prefs,func(_id,_context,_policy,_key):sent.append(true);return true,func(_id):return true)
	made=register(world,"fish",world.fishing.shore("codex").water_id);check(made.ok,"bounded engine fishing commitment")
	arrive(world,made.promise_id);scheduler.input_received();check(F.wait(world,"codex"),"promised fishing completes real engine catch")
	scheduler.advance(.1)
	check(sent.is_empty() and not scheduler.queues.get("codex",[]).any(func(event):return event.kind=="fishing_catch"),"engine commitment and catch never wake models or enqueue chained inference")
	# Optional old schema7 field missing.
	var path:=directory.path_join("old");check(Save.save_world(F.fresh(),path),"old fixture save")
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path.path_join("island-v2.json")));data.erase("promises")
	var file:=FileAccess.open(path.path_join("island-v2.json"),FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close()
	loaded=F.fresh();check(Save.load_world(loaded,path).ok and loaded.promises.entries.is_empty(),"old schema7 missing promises stays empty, no history or content grants")
	# Real viewport: existing resident page only, no extra top button.
	var game: Node=load("res://scenes/main.tscn").instantiate();root.add_child(game);game.save_enabled=false;game.set_process(false);root.content_scale_aspect=Window.CONTENT_SCALE_ASPECT_EXPAND
	await process_frame
	game.world.director.set_all_enabled(false);game.view.sound_enabled=false;game.chat.hide();game.chat_input.release_focus();register(game.world,"come_near","human")
	game.resident_connections.open("codex");game.resident_connections.tabs.current_tab=1;game.resident_connections.refresh()
	check(game.resident_connections.promise_rows.get_child_count()>=2,"existing resident page shows commitment and explicit cancel")
	var output:=OS.get_environment("HABITAT_OVERNIGHT_CAPTURE_DIR")
	if not output.is_empty():DirAccess.make_dir_recursive_absolute(output)
	for size in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=size;game.resident_connections.details_scroll.scroll_vertical=10000;await process_frame;await process_frame
		check(game.resident_connections.get_global_rect().encloses(game.resident_connections.footer.get_global_rect()),"promise page fits "+str(size))
		if not output.is_empty():
			await RenderingServer.frame_post_draw
			var image:=root.get_texture().get_image();check(image.get_size()==size,"actual image "+str(size));image.save_png(output.path_join("promises-%dx%d.png"%[size.x,size.y]))
	check(game.links.values().all(func(link):return link._pid==-1),"engine commitments never launch model processes")
	game.queue_free();await process_frame
	print("Promises: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)

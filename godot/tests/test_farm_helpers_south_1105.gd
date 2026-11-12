extends "res://tests/accept_gathered_signature_journey.gd"
## Standalone native acceptance: requires an actual previous earned checkpoint, never a player save.
## HABITAT_FARM_SOUTH_RESUME can select another explicitly isolated real journey checkpoint.
const IDS=["codex","companion-2","npc.mira","npc.nora"]
var samples:Array=[]
func save_evidence(name:String)->void:
	var value:Dictionary={"trace":trace,"samples":samples,"orders":game.world.farms.orders,"storage":game.world.storage.saved(),"actors":game.world.actors}
	var f:=FileAccess.open(OS.get_environment("HABITAT_DATA_DIR").path_join(name+".json"),FileAccess.WRITE);f.store_string(JSON.stringify(value,"  "));f.close()
func follow_all()->bool:
	game.farm_panel.hide();game.leisure_panel.hide();game.chat.hide()
	if not await UI.click(self,game.gathering_button):return false
	var ui:Node=game.follow_ui
	if not await UI.click(self,ui.all_box):return false
	if not await UI.click(self,ui.menu.get_ok_button()):return false
	return IDS.all(func(id):return game.world.activities.following.has(id))
func walk_south(at:Vector2)->bool:
	await click_world(at)
	var bridge:bool=false
	for i in range(2200):
		tick()
		if i%25==0:
			samples.append({"clock":game.world.forest.clock,"positions":IDS.map(func(id):return game.world.actors[id].position.duplicate()),"human":game.world.actors.human.position.duplicate()})
			await process_frame
		if not bridge and game.world.point(game.world.actors.human).y>150 and game.world.point(game.world.actors.human).y<180:
			bridge=true;await capture("south-follow-real-bridge",game.world.point(game.world.actors.human))
		if game.world.point(game.world.actors.human).distance_to(at)<1 and IDS.all(func(id):return game.world.actors[id].region_id=="home" and game.world.point(game.world.actors[id]).distance_to(at)<16):return true
	print("SOUTH_WALK_FAIL ",game.world.actors," follow=",game.world.activities.following);return false
func invite_field(fid:String)->bool:
	var w:RefCounted=game.world;var p:Dictionary=w.farms.farm_plots(fid)[0]
	await click_world(w.point(p));await process_frame
	if not game.farm_panel.visible or game.farm_panel.farm_id!=fid:return false
	if not await select_option(game.farm_panel.fill_picker,"mixed"):return false
	if not await UI.click(self,game.farm_panel.helpers_button):return false
	var dialog:Node=UI.shown(game,"res://scripts/farm_invitation.gd")
	if dialog==null:return false
	check(dialog.checks.size()==4,"south actual helper list has all four")
	if dialog.checks.values().any(func(c):return c.disabled):
		print("SOUTH_DISABLED ",dialog.checks.values().map(func(c):return c.text)," hunger=",w.hunger.states);return false
	if not await UI.click(self,dialog.all_box):return false
	await capture("south-"+fid+"-all",w.point(p))
	if not await UI.click(self,dialog.get_ok_button()):return false
	var scoped:Array=[]
	for id in IDS:
		if not w.farms.active(id):print("SOUTH_ORDER_MISSING ",id," ",game.farm_panel.note.text);return false
		scoped.append_array(w.farms.host_grants[id].plot_ids)
	check(scoped.size()==w.farms.farm_plots(fid).size(),"every south real plot allocated once using current actual seeds")
	for i in range(2000):
		tick()
		if i%40==0:await process_frame
		if IDS.all(func(id):return not w.farms.active(id) and not w.work.jobs.has(id)):break
	var good:bool=w.farms.farm_plots(fid).all(func(plot):return not plot.crop_id.is_empty() and plot.watered)
	good=good and IDS.all(func(id):return w.farms.orders.get(id,{}).get("status")=="completed" and not w.farms.host_grants.has(id))
	await capture("south-"+fid+"-watered",w.point(p))
	if not good:print("SOUTH_ORDER_FAIL ",w.farms.orders," jobs=",w.work.jobs)
	return good
func run()->void:
	var source:String=OS.get_environment("HABITAT_FARM_SOUTH_RESUME")
	if source.is_empty():source="/tmp/youqi-test-gathered-signature-finish2/complete"
	assert(source.begins_with("/tmp/youqi-test-"))
	game=UI.init_game(self);await process_frame;await process_frame
	var original:String=FileAccess.get_file_as_string(source.path_join("island-v2.json"))
	var copied:String=OS.get_environment("HABITAT_DATA_DIR").path_join("earned-source")
	DirAccess.make_dir_recursive_absolute(copied);check(DirAccess.copy_absolute(source.path_join("island-v2.json"),copied.path_join("island-v2.json"))==OK,"copy real temporary checkpoint without modifying source")
	var loaded:Dictionary=preload("res://scripts/save_store.gd").load_world(game.world,copied)
	check(loaded.get("ok",false) and game.world.opening_id=="showcase","strict load actual earned showcase checkpoint, no opening conversion")
	if failed:await stop("south-load-failed");return
	game.world.director.set_all_enabled(false)
	for pair in [["codex","ai-gpt"],["companion-2","ai-deepseek"],["npc.mira","ai-claude"],["npc.nora","ai-glm"]]:game.world.actors[pair[0]].appearance_id=pair[1]
	var w:RefCounted=game.world
	check(w.farms.ready("farm.theirs.white") and w.farms.ready("farm.theirs"),"original-cost flowerhouse and herbgarden already genuinely completed")
	if OS.get_environment("HABITAT_FARM_SOUTH_PLAN_ONLY")=="1":
		check(w.point(w.actors.human).y>200,"automatic-plan comparison uses actual retained south arrival, no actor position fixture")
		var automatic:Dictionary=w.farms.preview_host_orders(IDS,"plant","","mixed")
		check(automatic.rows.size()==4 and automatic.rows.all(func(row):return row.eligible and row.farm_id=="farm.theirs.white"),"unspecified farm chooses actual nearest built southern flowerhouse for all four")
		save_evidence("south-auto-preview");print("Farm south automatic preview: ",trace.size()," checks, failed=",failed);game.queue_free();await process_frame;quit(1 if failed else 0);return
	check(await follow_all(),"native Follow All selection")
	check(await walk_south(Vector2(33.5,229)),"human and four companions physically route across bridge to south garden")
	if failed:save_evidence("south-walk-failed");await stop("south-walk-failed-save");return
	var seeds_before:Dictionary=w.storage.saved().items.duplicate(true)
	check(await invite_field("farm.theirs.white"),"south built flowerhouse real plots: four selected companions plant and first-water")
	if failed:save_evidence("south-white-failed");await stop("south-white-failed-save");return
	check(await follow_all(),"native reselect following after completed farm task replaced previous follow")
	check(await walk_south(Vector2(105.5,229)),"native walk and followers between southern gardens")
	check(await invite_field("farm.theirs"),"south built herbgarden real plots: four selected companions plant and first-water")
	var spent:int=0
	for item in seeds_before:
		if str(item).begins_with("seed."):spent+=int(seeds_before[item])-w.storage.count(item)
	check(spent==12,"two south gardens deduct exactly twelve retained actual seeds")
	# Build an actual original outdoor flowerbed with real wood, then use its derived FarmSystem plot.
	game.farm_panel.hide()
	var old_sites:Array=w.leisure.sites.keys();var wood_before:int=w.storage.count("wood")+int(w.actors.human.carry.get("wood",0))
	check(await build_production("outdoor-flowers",Vector2(45,233)),"native original outdoor flowerbed foundation, selection and actual wood construction")
	if not failed:
		var added:Array=w.leisure.sites.keys().filter(func(id):return id not in old_sites)
		check(added.size()==1,"one actual outdoor flowerbed instance")
		if added.size()==1:
			var site:Dictionary=w.leisure.sites[added[0]];var fid:String="farm.bed."+str(site.id)
			check(site.complete and int(site.invested)==w.leisure.cost(site) and wood_before-(w.storage.count("wood")+int(w.actors.human.carry.get("wood",0)))==w.leisure.cost(site),"original flowerbed cost paid exactly once")
			check(w.farms.farms.has(fid) and w.farms.ready(fid),"actual built outdoor flowerbed exposes true one-plot FarmSystem")
			var plot:Dictionary=w.farms.farm_plots(fid)[0]
			await click_world(w.point(plot));await process_frame
			check(game.farm_panel.visible and game.farm_panel.farm_id==fid,"native actual flowerbed hit opens its true farm")
			if game.farm_panel.visible:
				check(await select_option(game.farm_panel.fill_picker,"tomato") and await UI.click(self,game.farm_panel.fill_button),"native explicit real seed planting in actual outdoor flowerbed")
				for i in range(2000):
					tick()
					if not w.farms.active("human") and not w.work.jobs.has("human"):break
				check(plot.crop_id=="tomato" and plot.watered,"actual built flowerbed stores living crop and first-water progress")
				await capture("south-outdoor-flowerbed-real-plot",w.point(plot))
	check(FileAccess.get_file_as_string(source.path_join("island-v2.json"))==original,"source checkpoint untouched")
	save_evidence("south-result");record("south-complete" if not failed else "south-failed")
	print("Farm south helpers: ",trace.size()," checks, failed=",failed)
	game.queue_free();await process_frame;quit(1 if failed else 0)

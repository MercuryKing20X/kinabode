extends SceneTree
## UI/Integration — production/evidence/barbecue-v4 — BLOCKING exact-station / read-only context.
const UI=preload("res://tests/barbecue_ui_fixture.gd")
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"));var game:Node=UI.init_game(self)
	var human_stable:=true
	for station_id in ["moon.barbecue","home.barbecue"]:
		# Navigation alone remains side-effect-free when already at this camp.
		# Separate mouse-controller coverage checks the newly authorized approach.
		game.world.actors.human.position=game.world.barbecues[station_id].station.position.duplicate()
		var human:Dictionary=game.world.actors.human.duplicate(true)
		game._show_barbecue_menu(station_id);await process_frame;await process_frame
		var panel:Node=UI.shown(game,"res://scripts/fireside_panel.gd")
		check(panel!=null and panel.life.station.id==station_id and UI.descendants(panel.body).filter(func(n):return n is Button).size()==2,"both camp entries expose the same two-action flow "+station_id)
		check(panel.feedback.visible and panel.feedback.text.contains("火边"),"on-site guidance remains visible")
		check(await UI.click(self,panel.roast_button),"native input opens selected camp invitation")
		var invitation:Node=UI.shown(game,"res://scripts/fireside_invitation.gd")
		check(invitation!=null and invitation.life.station.id==station_id and invitation.all_box.text=="所有人","invitation keeps exact camp identity")
		for size in [Vector2i(1280,800),Vector2i(960,640)]:
			root.size=size;invitation.fit();await process_frame;await process_frame
			check(Rect2(Vector2.ZERO,Vector2(size)).encloses(Rect2(Vector2(invitation.position),Vector2(invitation.size))),"actual invitation fits "+str(size))
		invitation.queue_free();await process_frame
		human_stable=human_stable and game.world.actors.human==human
	check(human_stable and game.world.work.jobs.is_empty(),"entry choices never operate human or start participants")
	var summary:Dictionary=game.world.read_map("codex",{"region_id":"home"})
	check(summary.ok and summary.region.walking_available and summary.region.walking_areas.id=="home.moon" and summary.region.land_extensions.size()==2,"read_map retains real walking area and bridge")
	var preview:Dictionary=game.world.read_map("codex",{"region_id":"moon"})
	check(preview.region.availability=="preview_only" and not preview.region.travel_available,"other Moon Reef remains unavailable")
	var context:Dictionary=game.world.autonomy_context("codex")
	check(context.ok and context.self.moon_island.platform_id=="play.moon.bench.1" and context.self.barbecues.size()==3 and context.self.barbecues.map(func(c):return c.id).has("home.barbecue") and context.self.barbecues.map(func(c):return c.id).has("moon.barbecue") and context.self.barbecues.map(func(c):return c.id).has("homelands.barbecue") and JSON.stringify(context).to_utf8_buffer().size()<=4096,"bounded read-only context includes exact camps and platform")
	context.self.barbecues[1].state="invented";check(game.world.barbecues["moon.barbecue"].station.state=="cold","context remains a deep copy")
	for link in game.links.values():check(link._pid<=0,"camp navigation launches no model")
	game.queue_free();await process_frame;print("Moon controller v4: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)

extends SceneTree
## UI — production/evidence/barbecue-v4 — BLOCKING explicit input / zero side effects.
const UI=preload("res://tests/barbecue_ui_fixture.gd")
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"));var game:Node=UI.init_game(self)
	var stable:=true;var stock:Dictionary=game.world.life.fireside.available()
	for station_id in ["home.barbecue","moon.barbecue"]:
		# This test verifies that panel navigation does not move anyone when the
		# host is already nearby. Remote clicks are covered separately.
		game.world.actors.human.position=game.world.barbecues[station_id].station.position.duplicate()
		var before:Dictionary=game.world.actors.duplicate(true)
		game._show_barbecue_menu(station_id);await process_frame;await process_frame
		var panel:Node=UI.shown(game,"res://scripts/fireside_panel.gd")
		check(panel!=null and panel.life.station.id==station_id and not game.chat.visible,"compact camp panel binds exact chosen station "+station_id)
		if panel==null:continue
		var actions:Array=UI.descendants(panel.body).filter(func(n):return n is Button)
		check(actions.size()==2 and panel.light_button.text.begins_with("生火") and panel.roast_button.text=="烧烤","exactly two camp actions and no old source/cook/feed/pack controls")
		check(await UI.click(self,panel.roast_button),"native input activates actual barbecue entry")
		var invitation:Node=UI.shown(game,"res://scripts/fireside_invitation.gd")
		check(invitation!=null and invitation.all_box.text=="所有人" and invitation.life.station.id==station_id,"barbecue first opens exact bound invitation")
		if invitation==null:continue
		check(await UI.click(self,invitation.all_box) and invitation.selected_ids().size()==4,"native All selects four existing companions")
		check(await UI.click(self,invitation.get_ok_button()),"native Next opens real menu")
		var menu:Node=UI.shown(game,"res://scripts/fireside_menu.gd")
		check(menu!=null and menu.life.station.id==station_id and menu.choices[0].id=="single:mushroom","menu reuses selected station and mushroom-first order")
		if menu!=null:menu.queue_free();await process_frame
		stable=stable and game.world.actors==before
	check(stable and game.world.work.jobs.is_empty() and game.world.life.fireside.available()==stock,"all navigation and invitation choices move nobody and debit no material")
	check(game.links.values().all(func(link):return link._pid<=0),"navigation launches zero model processes")
	game.queue_free();await process_frame;print("Fireside controller v4: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)

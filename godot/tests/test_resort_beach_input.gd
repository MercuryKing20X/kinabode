extends "res://tests/test_resort_holiday_input.gd"
## UI/Integration BLOCKING; preparation explicit original resource jobs, no grants.
const Cook=preload("res://tests/cooking_fixture.gd")
func run()->void:
	await fresh()
	var w:RefCounted=game.world
	check(Cook.job(w,"human",{"intent":"gather_wood","tree_count":3}),"real preparation wood")
	check(Cook.job(w,"human",{"intent":"forage","target_id":"home.mushrooms.1"}),"real preparation mushrooms")
	await text_input("大家跟我来");game.chat.hide()
	await click_point(Vector2(91,191));await advance_until_idle()
	for i in 200:game._process(.1)
	check(w.home_island.here(),"native reaches beach camp over bridge")
	await click_point(Vector2(91,187))
	var panel:Node=UI.shown(game,"res://scripts/fireside_panel.gd")
	check(panel!=null,"native opens beach fire")
	if panel==null:quit(1);return
	check(await UI.click(self,panel.light_button),"native light beach fire")
	for i in 100:game._process(.1)
	check(w.barbecues["homelands.barbecue"].fireside.burning(),"beach genuinely burns")
	check(await UI.click(self,panel.roast_button),"native beach BBQ action")
	for i in 50:game._process(.1)
	var invitation:Node=UI.shown(game,"res://scripts/fireside_invitation.gd")
	check(invitation!=null,"native invitation appears")
	if invitation==null:quit(1);return
	check(await UI.click(self,invitation.all_box),"native selects all guests")
	check(await UI.click(self,invitation.get_ok_button()),"native confirms exact guests")
	var menu:Node=UI.shown(game,"res://scripts/fireside_menu.gd")
	check(menu!=null,"native food menu appears")
	if menu==null:quit(1);return
	for b in UI.descendants(menu):
		if b is Button and b.has_meta("expand_basics"):await UI.click(self,b);break
	var chosen:Button
	for b in UI.descendants(menu):
		if b is Button and b.get_meta("menu_id","")=="single:mushroom":chosen=b;break
	check(chosen!=null and await UI.click(self,chosen),"native selects real mushroom")
	check(await UI.click(self,menu.start_button),"native starts beach meal")
	for i in 600:
		game._process(.1)
		if i%50==0:await process_frame
	var fire:RefCounted=w.barbecues["homelands.barbecue"].fireside
	check(fire.state.current.get("eaters",[]).size()==5,"all five eat real beach meal")
	check(fire.seats.size()==5,"five exact long-table seat assignments")
	await capture_scene("beach-five-eating",Vector2(91,190),1)
	fire.end_circle("acceptance meal complete")
	# Actual elapsed DayCycle time, no clock assignment or hunger changes.
	for i in 16000:
		if w.days.phase().id=="night":break
		game._process(.1)
		if i%500==0:await process_frame
	check(w.days.phase().id=="night","actual advance reaches night")
	await capture_scene("villa-night",Vector2(80,335),.45)
	await text_input("大家跟我来");game.chat.hide()
	# Interiors: actual native entrance, then camera follows the committed region.
	for id in ["resort.villa.human","resort.villa.companion-2"]:
		var v:Dictionary=w.resort.villa(id)
		await click_point(Vector2(v.door[0],v.door[1]))
		var ui:Node=game.get_node("ResortUI")
		var enter:Button=button_named(ui.menu,"进去坐坐") if is_instance_valid(ui.menu) else null
		if enter!=null:await UI.click(self,enter)
		await advance_until_idle()
		check(w.actors.human.region_id=="room."+id,"native original interior entrance "+id)
		game.view.show_region(w.actors.human.region_id);game.view.queue_redraw();await picture("actual-interior-"+v.key)
		w.command("human",{"intent":"exit"});await advance_until_idle();game.view.show_region("home")
	await text_input("小蓝去砍树");await picture("island-command-order")
	print("RESORT_BEACH_INPUT ",checks," failed=",failed)
	game.queue_free();await process_frame;quit(1 if failed else 0)

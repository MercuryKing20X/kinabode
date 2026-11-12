extends "res://tests/test_resort_holiday_input.gd"
## UI/Visual final two moments only, real resources/routes and native host invitations.
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
	var fire:RefCounted=w.barbecues["homelands.barbecue"].fireside
	var captured:bool=false
	for i in 600:
		game._process(.1)
		if i%30==0:await process_frame
		if fire.state.current.get("ready",false) and int(fire.state.current.get("eaten",0))<int(fire.state.current.get("total",0)) and w.actors.values().filter(func(a):return a.activity=="fire_eat").size()==5:
			captured=true;break
	check(captured,"five genuine eating poses before meal completion")
	await capture_scene("beach-five-mid-bite",Vector2(91,190),1)
	for i in 600:game._process(.1)
	check(fire.state.current.get("eaters",[]).size()==5,"five genuine meals complete")
	fire.end_circle("final scene complete")
	await text_input("大家自由活动");game.chat.hide()
	await text_input("小蓝跟我来");game.chat.hide()
	await click_point(Vector2(80,310));await advance_until_idle()
	for i in 150:game._process(.1)
	await text_input("大家自由活动");game.chat.hide()
	await choose_activity("resort.human.lounge",true)
	check(w.resort.using("human")=="lounge" and w.resort.using("companion-2")=="lounge","two actual lounge occupants")
	check(w.work.jobs.values().filter(func(j):return j.get("intent")=="resort" and j.get("target_id")=="resort.human.lounge").size()==2,"no uninvited lounger occupants")
	await capture_scene("blue-human-clean-lounge",Vector2(76,359),1)
	print("RESORT_FINAL_MOMENTS ",checks," failed=",failed)
	game.queue_free();await process_frame;quit(1 if failed else 0)

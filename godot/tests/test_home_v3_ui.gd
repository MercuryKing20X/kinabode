# DIRECTION 2026-11-07: 主角鱼直接入库；以原真实实例验证后续流程。
extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
const F=preload("res://tests/cooking_fixture.gd")
var game:Node
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");root.add_child(game)
	game.save_enabled=false;game.set_process(false);game.world.director.set_all_enabled(false);game.view.set_process(false);game.view.sound_enabled=false
	var hud:Control=game.island_hud;hud.set_process(false)
	# Model-only question/proposal fixtures explicitly install the optional controller; identity remains local.
	game.world.director.set_controller("codex","model")

	check(hud!=null and game.world.opening_id=="showcase","new entry loads showcase HUD")
	check(root.content_scale_size==Vector2i.ZERO,"live scene uses native pixel size")
	var original:Dictionary=game.world.actors.human.duplicate(true)
	for entry in hud.config.handbook:
		hud.open_entry(entry.id);await process_frame
		var visible_now:=false
		match entry.id:
			"recipes":
				var book:Node=UI.shown(game,"res://scripts/recipe_book.gd");visible_now=book!=null
				if book!=null:book.queue_free();await process_frame
			"map":visible_now=game.atlas.visible;game._toggle_atlas(false)
			"memories":visible_now=game.memory_panel.visible;game.memory_panel.hide()
			"workshop":visible_now=game.editor.visible;game.editor.hide()
			"journal":visible_now=game.journal_panel.visible;game.journal_panel.hide()
			"homestead":visible_now=game.homestead_panel.visible;game.homestead_panel.hide()
			"farms":visible_now=game.farm_panel.visible;game.farm_panel.hide()
			"facilities":visible_now=game.leisure_panel.visible;game.leisure_panel.hide()
			"fisheries":visible_now=game.fishing_panel.visible;game.fishing_panel.hide()
			"autonomy_records":visible_now=game.resident_connections.visible and game.resident_connections.tabs.current_tab==2;game.resident_connections.close_panel()
		check(visible_now,"handbook retains "+entry.id)
	for id in hud.avatar_buttons:
		hud.locate(id);check(game.view.region_id==game.world.actors[id].region_id,"avatar locates actual resident "+id)
		hud.show_card(id);check(hud.resident_card.visible and hud.card_id==id,"bound compact card "+id)
		hud.open_connections(id);check(game.resident_connections.selected_id==id,"intelligence uses exact selected identity "+id);game.resident_connections.close_panel()
	check(game.world.actors.human.position==original.position and game.world.work.jobs.is_empty(),"opening every entry and locating never moves or acts as human")
	check(game.links.values().all(func(link):return link._pid<=0),"UI navigation never starts model process")
	# B: DIRECTION “去掉 ⚡，内容并回‘对话/指令’”。 Reachability assertions retained.
	for size in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=size;await process_frame;await process_frame;hud.refresh()
		for control in [hud.avatars,game.dialogue_button,game.journey.map_button,hud.watch_button,hud.stock_button]:check(Rect2(Vector2.ZERO,Vector2(size)).encloses(control.get_global_rect()),"native viewport contains "+control.get_class()+" "+str(size))
		var bottom:Array=[game.dialogue_button,game.journey.map_button,hud.watch_button]
		for index in range(bottom.size()-1):check(not bottom[index].get_global_rect().intersects(bottom[index+1].get_global_rect()),"three bottom entries do not overlap")
		check(await UI.click(self,game.dialogue_button),"real dialogue opens unified commands")
		for control in [game.gathering_button,game.handbook_menu]:
			await UI.reveal(self,control)
			check(control.is_visible_in_tree() and Rect2(Vector2.ZERO,Vector2(size)).encloses(control.get_global_rect()),"moved utility stays reachable within native viewport "+control.get_class())
		check(await UI.click(self,game.dialogue_button) and not game.chat.visible,"real dialogue closes unified panel")
	hud.resident_card.hide()
	check(F.job(game.world,"human",{"intent":"move","x":game.world.life.station.position[0],"y":game.world.life.station.position[1]+3}),"explicit real walk to camp")
	hud.refresh_context();check(hud.context_signature.contains("light:home.barbecue") and hud.context_signature.contains("roast:home.barbecue") and not hud.context_signature.contains("cook"),"onsite camp exposes exactly light and barbecue")
	hud.activate_context("roast:home.barbecue");check(UI.shown(game,"res://scripts/fireside_invitation.gd")!=null,"onsite barbecue opens exact invitation");UI.shown(game,"res://scripts/fireside_invitation.gd").queue_free();await process_frame
	var shore:Array=game.world.map_anchor("dock.south.end")
	check(F.job(game.world,"human",{"intent":"move","x":shore[0],"y":shore[1]}),"explicit actual walk to coast")
	hud.refresh_context();check(hud.context_signature.contains("fish"),"only actual shore offers fishing")
	check(F.job(game.world,"human",{"intent":"fish"}),"actual fish becomes notification, no invented record")
	hud.refresh();check(hud.notification_data().size()==1 and hud.notifications.get_child_count()==1,"pending real fish has unified edge card")
	game.action_dock.refresh();check(not game.action_dock.strip.visible and not game.action_dock.reopen_button.visible,"child refresh never restores duplicate fishing strip")
	var gift_followers:Array=game.world.activities.following.keys();gift_followers.erase("codex")
	check(game.world.activities.set_followers(gift_followers,["codex"],false).ok,"player releases this giver before her separate inventory transaction")
	check(F.withdraw(game.world,"codex","turnip"),"gift source really picked from shared harvest")
	check(F.job(game.world,"codex",{"intent":"move","x":shore[0]+.5,"y":shore[1]}),"giver actually walks within range")
	for n in range(2):check(game.world.command("codex",{"intent":"give","receiver_id":"human","item_id":"turnip","quantity":1}).ok,"real atomic gift creates true notification")
	var made:Dictionary=game.world.command("codex",{"intent":"propose","text":"一起煮汤吧","activity":"cook_together","target_id":"turnip-soup","ttl_seconds":300})
	check(made.ok,"real proposal created without model call")
	game.proposal_panel.refresh();hud.refresh();check(hud.notification_data().size()==4 and hud.notifications.get_child_count()==3,"four real facts show only three unified cards")
	check(not game.proposal_panel.visible,"legacy child refresh never reopens embedded proposal details")
	hud.notices_collapsed=true;hud.refresh();check(not hud.notifications.visible and hud.notification_toggle.visible,"collapse preserves an accurate badge")
	hud.notices_collapsed=false
	for item in hud.notification_data():
		if item.kind!="fish":hud.dismissed[item.key]=true
	hud.notices_signature="";hud.refresh()
	var row:Dictionary=hud.notification_data()[0];hud.open_notice(row);check(game.fishing_panel.visible and game.fishing_panel.actor_id()=="human","pending card routes to exact owner's fish")
	var fish:Dictionary=preload("res://tests/fishing_fixture.gd").unplaced(game.world);check(game.world.command("human",{"intent":"release_fish","fish_id":fish.id}).ok,"explicit release existing instance")
	hud.refresh();check(hud.notification_data().is_empty(),"released fish removes notification")
	var move:Dictionary=game.world.command("human",{"intent":"move","x":shore[0],"y":shore[1]-2});game.world.advance(.1);hud.refresh()
	check(move.ok and hud.task.visible,"human route appears in current task panel")
	game.world.command("human",{"intent":"stop"});game.world.advance(.1);hud.refresh();check(not hud.task.visible,"no permanent stop-me button")
	var wheel:=InputEventMouseButton.new();wheel.pressed=true;wheel.button_index=MOUSE_BUTTON_WHEEL_UP;wheel.position=Vector2(450,300)
	game.view._unhandled_input(wheel);check(game.view.zoom==2,"wheel selects exact 2x")
	wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN;game.view._unhandled_input(wheel);check(game.view.zoom==1,"wheel selects exact 1x")
	game._clicked("human",game.world.point(game.world.actors.human));check(game.view.follow_player and not game.world.work.jobs.has("human"),"click self returns camera without issuing movement")
	print("Home v3 UI: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)

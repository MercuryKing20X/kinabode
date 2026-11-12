extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
var game:Node
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func mouse(at:Vector2)->void:
	for pressed in [true,false]:
		var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.pressed=pressed;e.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0;e.position=at;e.global_position=at;root.push_input(e,true);await process_frame
func settle(region:String="")->void:
	for tick in range(900):
		await create_timer(.1).timeout
		if (region.is_empty() or game.world.actors.human.region_id==region) and not game.world._routes.has("human") and game.world.dark.pending.is_empty() and not game.dark_ui.boat_pending:return
	check(false,"normal frames settle actual route/action "+region)
func press(text:String)->void:
	var matches:Array=UI.descendants(game.dark_ui.menu).filter(func(n):return n is Button and n.text==text)
	check(matches.size()==1 and await UI.click(self,matches[0]),"actual mouse "+text)
func shot(name:String)->void:
	await process_frame;await process_frame;RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("HABITAT_DARK_EVIDENCE").path_join(name+".png"))
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"))
	game=UI.init_game(self);await process_frame;await process_frame
	game.set_process(true);game.view.set_process(true);game.island_hud.set_process(true)
	check(game.gathering_button.text=="跟随" and await UI.click(self,game.gathering_button),"bottom follow opens selection")
	for id in ["codex","npc.mira"]:check(await UI.click(self,game.follow_ui.checks[id]),"select exact follower "+id)
	check(await UI.click(self,game.follow_ui.menu.get_ok_button()),"confirm exact followers")
	check(game.world.activities.following.keys().size()==2,"only two selected")
	check(await UI.click(self,game.dark_ui.entry_button),"visible dark entry")
	await press("出发");await settle("dark")
	for id in ["codex","npc.mira"]:check(game.world.actors[id].region_id=="dark","selected walks across bridge "+id)
	for id in ["companion-2","npc.nora"]:check(game.world.actors[id].region_id=="home","unselected remains home "+id)
	var camp:Vector2=game.world.dark.p(game.world.dark.config.camp)
	await mouse(game.view.screen(camp));await press("点火把");await settle("dark")
	check(game.world.dark.torch.remaining>0,"actual torch lit")
	var at:=Vector2(50,98)
	await mouse(game.view.screen(at))
	check(not is_instance_valid(game.dark_ui.menu) or not game.dark_ui.menu.visible,"ground click never opens walk confirmation")
	check(game.world._routes.has("human"),"ground click directly starts World route")
	await settle("dark")
	check(game.world.point(game.world.actors.human).distance_to(at)<.3,"walk reaches clicked dark ground")
	var before:int=game.world.dark.fires.size();var wood:int=int(game.world.dark.life.fireside.available().get("wood",0))
	check(await UI.click(self,game.dark_ui.fire_button),"bottom fixed fire button")
	await settle("dark")
	check(game.world.dark.fires.size()==before and game.world.dark.torch.remaining>0,"button holds torch without adding a fire")
	check(int(game.world.dark.life.fireside.available().get("wood",0))==wood-1,"torch consumes exactly one actual wood")
	for dimensions in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=dimensions;await process_frame;await process_frame
		var bounds:=Rect2(Vector2.ZERO,Vector2(dimensions))
		var buttons:Array=[game.dialogue_button,game.actions_button,game.gathering_button,game.dark_ui.fire_button]
		for b in buttons:check(bounds.encloses(b.get_global_rect()),"fixed bottom button fits "+str(dimensions)+b.text)
		for i in range(buttons.size()):
			for j in range(i+1,buttons.size()):check(not buttons[i].get_global_rect().intersects(buttons[j].get_global_rect()),"bottom buttons do not overlap")
		await shot("direct-ground-fixed-fire-follow-%dx%d"%[dimensions.x,dimensions.y])
	check(await UI.click(self,game.gathering_button),"reopen persistent follow")
	for id in ["codex","npc.mira"]:check(game.follow_ui.checks[id].button_pressed,"selected checkbox retained "+id)
	check(await UI.click(self,game.follow_ui.all_box) and await UI.click(self,game.follow_ui.all_box),"select all then clear all")
	check(await UI.click(self,game.follow_ui.menu.get_ok_button()) and game.world.activities.following.is_empty(),"explicit uncheck ends follow")
	game.queue_free();await process_frame
	print("Direct ground + fixed fire + selected persistent follow mouse: %d checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)

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
		var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.pressed=pressed;e.button_mask=MOUSE_BUTTON_MASK_LEFT if pressed else 0;e.position=at;root.push_input(e,true);await process_frame
func wait_human(region:String)->void:
	for i in range(900):
		await create_timer(.1).timeout
		if game.world.actors.human.region_id==region and not game.world._routes.has("human") and game.world.dark.pending.is_empty() and not game.dark_ui.boat_pending:return
	check(false,"actual human route settles "+region)
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"))
	game=UI.init_game(self);await process_frame;await process_frame
	game.set_process(true);game.view.set_process(true);game.island_hud.set_process(true)
	check(await UI.click(self,game.dark_ui.entry_button),"normal dark entry")
	var go:Array=UI.descendants(game.dark_ui.menu).filter(func(n):return n is Button and n.text=="出发")
	check(go.size()==1 and await UI.click(self,go[0]),"depart alone")
	await wait_human("dark")
	check(game.world.actors.codex.region_id=="home","companion actually left on original island")
	check(await UI.click(self,game.gathering_button),"open follow after reaching dark alone")
	check(await UI.click(self,game.follow_ui.checks.codex),"tick companion without another confirmation")
	check(game.world.activities.following.has("codex"),"checkbox immediately activates follow")
	check(await UI.click(self,game.follow_ui.menu.get_ok_button()),"close picker only")
	var came:=false
	for i in range(1200):
		await create_timer(.1).timeout
		if game.world.actors.codex.region_id=="dark" and game.world.point(game.world.actors.codex).distance_to(game.world.point(game.world.actors.human))<4.5:came=true;break
	check(came,"selected resident actually walks over bridge from other region and comes near")
	check(game.world.actors["companion-2"].region_id=="home","unselected resident stays home")
	for at in [Vector2(42,103),Vector2(50,104)]:
		check(game.view.get_viewport_rect().has_point(game.view.screen(at)),"ground target visible")
		await mouse(game.view.screen(at));await wait_human("dark")
		check(game.world.point(game.world.actors.human).distance_to(at)<.3,"actual ground walk reaches target")
	var d:RefCounted=game.world.dark;var before:int=int(d.life.fireside.available().get("wood",0))
	check(not d.torch.owned and d.torch.remaining==0,"never made or lit a torch")
	check(not d.fire_near(game.world.point(game.world.actors.human)),"standing away from existing fire sources")
	check(await UI.click(self,game.dark_ui.fire_button),"fixed bottom fire without torch or nearby source")
	await wait_human("dark")
	check(d.fires.is_empty() and d.torch.remaining>0,"wood-only button holds torch without new permanent fire")
	check(int(d.life.fireside.available().get("wood",0))==before-1,"exact one real wood debited")
	check(d.torch.owned and d.torch.remaining>0,"actual paid torch is held")
	for size in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=size;await process_frame;await process_frame;RenderingServer.force_draw(false)
		root.get_texture().get_image().save_png(OS.get_environment("HABITAT_DARK_EVIDENCE").path_join("crossed-follower-wood-only-fire-%dx%d"%[size.x,size.y]+".png"))
	game.queue_free();await process_frame
	print("Remote selected follow + wood-only ignition real mouse: %d checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)

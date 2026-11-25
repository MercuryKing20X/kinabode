extends SceneTree

const UI=preload("res://tests/barbecue_ui_fixture.gd")
const Pool=preload("res://scripts/connection_session_pool.gd")
const L=preload("res://scripts/localization.gd")
class Fake extends "res://scripts/companion_link.gd":
	func _start()->bool:return false
	func _send(_message:Dictionary)->bool:return false

var failures:=0
func _initialize()->void:run.call_deferred()
func check(ok:bool,label:String)->void:
	print("MOVE_IN ", "PASS " if ok else "FAIL ",label)
	if not ok:failures+=1

func spawn_game()->Node:
	set_meta("title_opening","standard")
	var game:Node=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return Fake.new()
	root.add_child(game)
	await process_frame;await process_frame
	return game

func run()->void:
	var data:=OS.get_environment("HABITAT_DATA_DIR")
	if not data.begins_with("/tmp/") and not data.begins_with("/var/folders/"):quit(2);return
	var out:=OS.get_environment("MOVE_IN_EVIDENCE")
	Pool.obtain(self,data).factory=func(_id):return Fake.new()
	var fixture:=OS.get_environment("MOVE_IN_TEST_KEY")
	if not fixture.is_empty():
		# Synthetic test input only; the fixture never prints or exports it.
		var file:=FileAccess.open(data.path_join("world-door-token"),FileAccess.WRITE)
		if file==null:quit(2);return
		file.store_string(fixture);file.close()
	set_meta("title_opening","standard")
	if OS.get_environment("MOVE_IN_RESTART_MOVIE")=="1":
		await restart_movie()
		return
	for lang in ["zh","en"]:
		L.select(data,lang)
		var game:=await spawn_game()
		game.save_enabled=false
		var hud:Control=game.island_hud
		var entry:Button=hud.get_node("WorldDoor")
		var place:Button=hud.get_node("WorldPlacement")
		var panel:Control=game.world_door_dialog
		for size in [Vector2i(1280,800),Vector2i(1440,900),Vector2i(1920,1080)]:
			root.size=size
			await process_frame;await process_frame
			hud.refresh()
			await process_frame;await RenderingServer.frame_post_draw
			var main_rects:Array=[entry.get_global_rect(),place.get_global_rect(),game.day_label.get_global_rect(),game.handbook_menu.get_global_rect()]
			if hud.residents_panel.visible:main_rects.append(hud.residents_panel.get_global_rect())
			var ok:=true
			for i in main_rects.size():
				for j in range(i+1,main_rects.size()):
					ok=ok and not main_rects[i].intersects(main_rects[j])
			check(ok,lang+" "+str(size)+" top controls and portrait strip")
			if not out.is_empty():
				root.get_texture().get_image().save_png(out.path_join("%s-%dx%d.png"%[lang,size.x,size.y]))
			check(await UI.click(self,entry) and panel.visible,"real input opened "+lang+" "+str(size))
			hud.refresh();await process_frame;await RenderingServer.frame_post_draw
			check(not hud.residents_panel.visible and not panel.get_global_rect().intersects(entry.get_global_rect()) and not panel.get_global_rect().intersects(place.get_global_rect()),"opened panel clear "+lang+" "+str(size))
			if not out.is_empty():
				root.get_texture().get_image().save_png(out.path_join("%s-%dx%d-panel.png"%[lang,size.x,size.y]))
			await UI.click(self,entry)
		if lang=="en":
			await UI.click(self,entry)
			check(await UI.click(self,panel.find_child("ProgramAccess",true,false)),"expand program access via UI")
			check(await UI.click(self,panel.toggle) and game.world_door.server.is_listening(),"enable door via UI")
			check(not panel.setup_text().contains(game.world_door.token) and not panel.codex_command().contains("KINABODE_TOKEN"),"AI copy contains no key; Codex requires no environment token")
			check(panel.claude_command().contains("--scope user"),"Claude user scope")
			if OS.get_environment("MOVE_IN_SERVE")=="1":
				print("MOVE_IN_READY")
				await create_timer(55).timeout
		game.queue_free();await process_frame;await process_frame
	var reopened:=await spawn_game()
	reopened.save_enabled=false
	check(reopened.world_door.server.is_listening(),"door automatically opens after scene exit")
	var original:String=reopened.world_door.token
	await UI.click(self,reopened.island_hud.get_node("WorldDoor"))
	check(await UI.click(self,reopened.world_door_dialog.find_child("ProgramAccess",true,false)),"expand program access after reopen")
	check(await UI.click(self,reopened.world_door_dialog.toggle) and not reopened.world_door.server.is_listening() and reopened.world_door.token==original,"close retains key")
	check(await UI.click(self,reopened.world_door_dialog.toggle) and reopened.world_door.token==original,"reopening retains key")
	check(reopened.world_door.rotate() and reopened.world_door.token!=original,"explicit rotation replaces key")
	reopened.queue_free();await process_frame
	quit(1 if failures else 0)

func restart_movie()->void:
	var first:=await spawn_game()
	first.save_enabled=false
	var entry:Button=first.island_hud.get_node("WorldDoor")
	check(await UI.click(self,entry),"opened move-in panel")
	check(await UI.click(self,first.world_door_dialog.find_child("ProgramAccess",true,false)),"expanded program access")
	check(await UI.click(self,first.world_door_dialog.toggle),"opened listener")
	var original:String=first.world_door.token
	var config:String=first.world_door_dialog.codex_command()
	await create_timer(2).timeout
	first.queue_free()
	await process_frame;await process_frame
	var second:=await spawn_game()
	second.save_enabled=false
	check(await UI.click(self,second.island_hud.get_node("WorldDoor")),"reopened move-in panel")
	check(second.world_door.server.is_listening() and second.world_door.token==original and second.world_door_dialog.codex_command()==config,"old configuration and listener survived scene restart")
	var request:=HTTPRequest.new();request.timeout=5;root.add_child(request)
	var headers:=PackedStringArray(["Content-Type: application/json","Authorization: Bearer "+original])
	var start:=request.request("http://127.0.0.1:17642/mcp",headers,HTTPClient.METHOD_POST,JSON.stringify({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","clientInfo":{"name":"Restart check","version":"1"}}}))
	if start==OK:
		var result:Array=await request.request_completed
		check(result[1]==200 and second.world_door.knocks[0].client=="Restart check","same key reconnects and logs the client")
	else:check(false,"restart request starts")
	await create_timer(3).timeout
	second.queue_free();request.queue_free();await process_frame
	quit(1 if failures else 0)

extends "res://tests/test_world_door.gd"

const UI=preload("res://tests/barbecue_ui_fixture.gd")
const Audit=preload("res://tests/visible_locale_audit.gd")
const Pool=preload("res://scripts/connection_session_pool.gd")

func run()->void:
	var data:=OS.get_environment("HABITAT_DATA_DIR")
	if not data.get_file().begins_with("youqi-r7-capture-") or DisplayServer.get_name()=="headless":quit(2);return
	root.size=Vector2i(1280,800)
	DisplayServer.window_set_size(root.size)
	set_meta("title_opening","standard")
	Pool.obtain(self,data).factory=func(_id):return Fake.new()
	game=load("res://scenes/main_v3.tscn").instantiate()
	game.dialogue_adapter_factory=func(_id,_scope):return Fake.new()
	root.add_child(game)
	for frame in 12:await process_frame
	check(game.world.opening_id=="standard","standard opening")
	var hud:Control=game.island_hud
	if hud.residents_collapsed:check(await UI.click(self,hud.collapse_residents),"expand resident roster")
	check(await UI.click(self,hud.appearance_buttons.codex),"open wardrobe")
	var wardrobe:Control=hud.wardrobe
	var choices:=UI.descendants(wardrobe).filter(func(n):return n is Button and n.get_meta("work_id","")=="ai-gpt")
	check(choices.size()==1 and await UI.click(self,choices[0]),"choose alternate appearance")
	var confirm:=UI.descendants(wardrobe).filter(func(n):return n is Button and n.text=="确定")
	check(confirm.size()==1 and await UI.click(self,confirm[0]),"confirm appearance")
	check(game.world.actors.codex.appearance_id=="ai-gpt","alternate appearance bound")
	check(await UI.click(self,hud.find_child("WorldDoor",true,false)),"open door panel")
	door=game.world_door
	check(await UI.click(self,game.world_door_dialog.find_child("DoorToggle",true,false)),"open world door by mouse")
	var claim:=await command("claim",{"resident":"codex","client":"Script Visitor"})
	check(claim.get("ok",false),"script client claimed Xiaobai")
	check(await UI.click(self,hud.find_child("WorldDoor",true,false)),"close door panel")
	if failures>0:quit(1);return
	var began:=Time.get_ticks_msec()
	var frames:=0
	while Time.get_ticks_msec()-began<123000:
		await process_frame
		frames+=1
		# MovieWriter uses a fixed step. Pace it against the actual wall time.
		var ahead:=began+roundi(frames*1000.0/12.0)-Time.get_ticks_msec()
		if ahead>0:OS.delay_msec(ahead)
		for row in Audit.texts(root):
			if Audit.raw_key(str(row.text)):check(false,"raw UI key "+str(row.text))
		for speech in game.view.speech_by_actor.values():
			if speech.source=="local_rules" and Audit.raw_key(str(speech.text)):check(false,"raw bubble key "+str(speech.text))
	check(game.world.actors.codex.get("world_door_client")=="Script Visitor","visitor still claimed after idle")
	check(await UI.click(self,game.dialogue_button) and game.chat.visible,"open chat after 123 wall seconds")
	check(not Audit.raw_key(game.chat_log.text),"visible chat has no raw keys")
	for scope in game.dialogue.histories.values():
		if Audit.raw_key(str(scope)):check(false,"raw key in dialogue history")
	print("IDLE_LOCALE elapsed_ms=",Time.get_ticks_msec()-began," checks=",checks," failures=",failures)
	await create_timer(2).timeout
	game.game_audio.shutdown()
	await process_frame
	game.queue_free()
	await process_frame
	quit(1 if failures else 0)

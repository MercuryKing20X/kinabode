extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
var failed:=false
func check(ok:bool,msg:String)->void:
	if not ok:failed=true;push_error(msg)
func _initialize()->void:call_deferred("run")
func mouse(at:Vector2)->void:
	for down in [true,false]:
		var e:=InputEventMouseButton.new();e.position=at;e.global_position=at;e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;e.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;root.push_input(e,true);await process_frame
func click(button:BaseButton)->bool:
	for i in range(2):await process_frame
	return await UI.click(self,button)
func run()->void:
	var dir:String=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-test-"));OS.set_environment("HABITAT_OPENING","legacy")
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO;DisplayServer.window_move_to_foreground()
	var w:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");w.residents.provision(w);w.library=preload("res://scripts/character_library.gd").new();w.library.configure(dir);assert(preload("res://scripts/world_opening.gd").apply(w,w.library,"showcase").ok);w.intelligence.activate_presets();w.hunger.start()
	w.world_id="playtest-speech-fixed-1031"
	for id in w.director.routines:w.director.routines[id].rng.seed=hash("speech-input:"+str(id))
	var g:Node=load("res://scenes/main_v3.tscn").instantiate();g.world=w;root.add_child(g);g.save_enabled=false;g.set_process(false);g.view.set_process(false);g.island_hud.set_process(false);g.chat.hide();print("speech input init");await process_frame;await process_frame
	g.view.center=w.point(w.life.station);g.view.follow_player=false;g.view.zoom=1
	await mouse(g.view.screen(w.point(w.life.station)))
	for i in range(5000):
		g._process(.05);g.view._process(.05)
		if UI.shown(g,"res://scripts/fireside_panel.gd")!=null:break
	print("speech input walked");var panel:Node=UI.shown(g,"res://scripts/fireside_panel.gd");check(panel!=null,"mouse fire route opens panel")
	if panel==null:quit(1);return
	check(await click(panel.light_button),"mouse lights real fire");check(await click(panel.roast_button),"mouse barbecue")
	print("speech input opened invitation");var invite:Node=UI.shown(g,"res://scripts/fireside_invitation.gd");check(invite!=null,"invitation opens")
	if invite==null:quit(1);return
	check(await click(invite.all_box) and await click(invite.get_ok_button()),"mouse invites all")
	print("speech input opened menu");var menu:Node=UI.shown(g,"res://scripts/fireside_menu.gd");check(menu!=null,"menu opens")
	if menu==null:quit(1);return
	var expand:Button=UI.descendants(menu).filter(func(n):return n is Button and n.get_meta("expand_basics",false))[0]
	check(await click(expand),"native expands basic grills")
	var mushroom_button:Button=UI.descendants(menu).filter(func(n):return n is Button and n.get_meta("menu_id","")=="single:mushroom")[0]
	menu.scroll.ensure_control_visible(mushroom_button);await process_frame;await process_frame
	check(await click(mushroom_button),"native selects exact real mushroom")
	check(not menu.start_button.disabled and await click(menu.start_button),"mouse confirms existing food")
	for i in range(5000):
		g._process(.05);g.view._process(.05)
		if w.life.fireside.state.get("current",{}).get("eaters",[]).size()>=5:break
	check(w.life.fireside.state.get("current",{}).get("eaters",[]).size()==5,"five real eaters")
	print("speech input ate");var audio:Node=g.game_audio;var serials:Dictionary={};var bubbles:Array=[];var old_blips:=0;var trace_start:int=audio.trace.size()
	for i in range(1200):
		g._process(.05);g.view._process(.05)
		for id in g.view.speech_by_actor:
			if id=="human":continue
			var b:Dictionary=g.view.speech_by_actor[id];var signature:String=str(b.until)+":"+str(b.text)
			if signature==str(serials.get(id,"")):continue
			serials[id]=signature
			if float(b.until)<=float(g.view.clock):continue
			var count:int=mini(8,maxi(1,ceili(float(str(b.text).length())/3)))
			old_blips+=count;bubbles.append({"at_seconds":i*.05,"actor":id,"text":b.text,"old_uncapped_estimate":count,"distance":w.point(w.actors[id]).distance_to(audio.listener)})
	var events:Array=audio.trace.slice(trace_start).filter(func(e):return e.action=="scheduled" and str(e.event).begins_with("voice."))
	var output:String=OS.get_environment("HABITAT_PLAYTEST_CAPTURE")
	if not output.is_empty():
		DirAccess.make_dir_recursive_absolute(output)
		var f:=FileAccess.open(output.path_join("speech-60s.json"),FileAccess.WRITE);f.store_string(JSON.stringify({"seconds":60,"new_scheduled_blips":events.size(),"new_per_minute":events.size(),"old_same_bubbles_upper_estimate":old_blips,"comparison":"old count is theoretical same-sequence upper bound, not old binary measurement; old global concurrency/closest speaker may further reduce it","bubbles":bubbles,"events":events},"\t"))
		await process_frame;RenderingServer.force_draw(false);root.get_texture().get_image().save_png(output.path_join("speech-60s.png"))
	check(not bubbles.is_empty(),"real fireside speech observed during sixty seconds")
	g.queue_free();await process_frame;print("Speech input 60s: bubbles=",bubbles.size()," new=",events.size()," old same-sequence upper=",old_blips," failed=",failed);quit(1 if failed else 0)

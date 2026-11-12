extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
const Text=preload("res://scripts/localization.gd")
var game:Node
var checks:=0
var failed:=false
var english:=false
func check(okay:bool,label:String)->void:
	checks+=1
	if not okay:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func enter_text(zh:String,en:String,send_button:bool=false)->void:
	if not game.chat.visible:check(await UI.click(self,game.dialogue_button),"native chat opens")
	await process_frame;await process_frame
	var at:Vector2=game.chat_input.get_global_rect().get_center()
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.position=at;event.global_position=at;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down;root.push_input(event,true);await process_frame
	var text:String=en if english else zh
	for i in range(text.length()):
		for down in [true,false]:
			var event:=InputEventKey.new();event.unicode=text.unicode_at(i);event.pressed=down;root.push_input(event,true);await process_frame
			game._process(.016)
	check(game.chat_input.text==text,"real input exact text")
	if send_button:check(await UI.click(self,game.chat_send_button),"real send click")
	else:
		for down in [true,false]:
			var event:=InputEventKey.new();event.keycode=KEY_ENTER;event.pressed=down;root.push_input(event,true);await process_frame
func confirm()->bool:
	return is_instance_valid(game.local_host_commands.card) and await UI.click(self,game.local_host_commands.card.get_ok_button())
func capture(label:String)->void:
	if DisplayServer.get_name()=="headless":return
	await process_frame;await process_frame;RenderingServer.force_draw(false)
	root.get_texture().get_image().save_png(OS.get_environment("HABITAT_DATA_DIR").path_join(label+".png"))
func run()->void:
	var opening:String=OS.get_environment("HABITAT_COMMAND_OPENING");if opening.is_empty():opening="showcase"
	english=OS.get_environment("HABITAT_COMMAND_LANG")=="en"
	var directory:String=OS.get_environment("HABITAT_DATA_DIR")
	OS.set_environment("HABITAT_OPENING",opening);root.size=Vector2i(960,640);root.content_scale_size=Vector2i.ZERO
	var w:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json");w.residents.provision(w);w.library=preload("res://scripts/character_library.gd").new();w.library.configure(directory)
	check(preload("res://scripts/world_opening.gd").apply(w,w.library,opening).ok,"official opening")
	w.intelligence.activate_presets();w.hunger.start()
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=w;root.add_child(game);game.save_enabled=false;game.set_process(false);game.view.set_process(false);game.island_hud.set_process(false)
	Text.select(directory,"en" if english else "zh_CN");game.chat.hide();await process_frame;await process_frame
	var original_human:Array=w.actors.human.position.duplicate();var original_stock:Dictionary=w.storage.saved()
	await enter_text("小蓝和小橙跟我来","Skye and Clem follow me")
	check(game.local_host_commands.pending.actor_ids==["companion-2","npc.mira"],"named pair parsed in real product")
	check(await UI.click(self,game.local_host_commands.card.get_cancel_button()),"native cancel")
	await process_frame;await process_frame
	check(game.chat_input.has_focus() and game.chat_input.text.is_empty(),"cancel restores real input focus without replay")
	check(w.activities.following.is_empty() and w.storage.saved()==original_stock,"cancel no action or material mutation")
	await enter_text("小蓝和小橙跟我来","Skye and Clem follow me",true)
	check(await confirm(),"native follow confirmation")
	check(w.activities.following.size()==2 and w.activities.following.has("companion-2") and w.activities.following.has("npc.mira"),"only named pair follows")
	await capture("follow-confirmed")
	for i in range(500):game._process(.1)
	await enter_text("大家别跟了","Everyone stop following")
	check(await confirm() and w.activities.following.is_empty(),"native group unfollow releases original followers")
	await enter_text("小蓝和小橙去小屋集合","Skye and Clem gather at the house")
	check(await confirm(),"native selected cottage gathering")
	for i in range(1500):
		game._process(.1)
		if w.activities.members.size()==2 and w.activities.members.values().all(func(m):return m.arrived):break
	check(w.activities.members.size()==2 and w.activities.members.values().all(func(m):return m.arrived),"selected pair actually arrives along World routes")
	check(w.activities.members.has("companion-2") and w.activities.members.has("npc.mira") and w.activities.members["companion-2"].position!=w.activities.members["npc.mira"].position,"unique original gathering spots for selected actors only")
	check(not w.activities.gathering.is_empty() and w.activities.gathering.remaining>0 and w.activities.gathering.remaining<=60,"original 60-second gathering hold retained")
	await capture("gather-arrived")
	for i in range(650):game._process(.1)
	check(w.activities.members.is_empty(),"original hold naturally ends")
	await enter_text("小蓝和小橙一起烧烤","Skye and Clem barbecue together",true)
	if opening=="showcase":
		check(await confirm(),"native barbecue handoff confirmation")
		var invitation:Node=UI.shown(game,"res://scripts/fireside_invitation.gd")
		check(invitation!=null,"original invitation opens without cooking")
		if invitation!=null:
			check(invitation.selected_ids()==["companion-2","npc.mira"],"exact selected pair prechecked in original invitation")
			await capture("barbecue-invitation")
			var close_at:Vector2=Vector2(invitation.position)+Vector2(invitation.size.x-18,-18)
			var motion:=InputEventMouseMotion.new();motion.position=close_at;motion.global_position=close_at;root.push_input(motion,true)
			for down in [true,false]:
				var event:=InputEventMouseButton.new();event.position=close_at;event.global_position=close_at;event.button_index=MOUSE_BUTTON_LEFT;event.button_mask=MOUSE_BUTTON_MASK_LEFT if down else 0;event.pressed=down;root.push_input(event,true);await process_frame
			check(not is_instance_valid(invitation) or not invitation.visible,"native title-close cancels original invitation")
			if is_instance_valid(invitation) and invitation.visible:game.queue_free();await process_frame;quit(1);return
	else:
		check(game.local_host_commands.pending.rows.all(func(row):return not row.allowed),"formal unbuilt camp remains unavailable")
		check(await UI.click(self,game.local_host_commands.card.get_cancel_button()),"cancel unavailable formal camp")
	check(w.actors.human.position==original_human and not w._routes.has("human") and w.storage.saved()==original_stock,"all conversational actions never move human or spend materials")
	await enter_text("云朵会唱歌吗","a cloud made of marmalade",true)
	check(game.chat_input.text.is_empty() and Text.text("local.commands.example_plant") in game.chat_log.get_parsed_text(),"unknown visible personality reply and actual localized examples")
	await enter_text("大家不要去收菜","Everyone do not harvest")
	check(not is_instance_valid(game.local_host_commands.card) and game.chat_input.text.is_empty(),"negative instruction never dispatches a harvest card")
	# Explicit isolated custom-name and highest-hunger fixtures, no parameter tuning.
	w.actors["npc.mira"].name="Amber";w.actors["npc.mira"].custom_name=true
	await enter_text("小蓝和Amber跟我来","Skye and Amber follow me")
	check(game.local_host_commands.pending.actor_ids==["companion-2","npc.mira"],"renamed resident exact identity in actual input")
	check(await UI.click(self,game.local_host_commands.card.get_cancel_button()),"cancel custom-name plan")
	w.hunger.ensure("npc.mira");w.hunger.states["npc.mira"].elapsed=float(w.hunger.config.thresholds[3])
	check(w.hunger.rank("npc.mira")==3,"temporary highest-hunger state fixture")
	await enter_text("小蓝和Amber跟我来","Skye and Amber follow me")
	var hungry_rows:Array=game.local_host_commands.pending.rows.filter(func(row):return row.actor_id=="npc.mira")
	check(hungry_rows.size()==1 and not hungry_rows[0].allowed and not str(hungry_rows[0].reason).is_empty(),"very hungry renamed resident grey with true reason")
	check(await UI.click(self,game.local_host_commands.card.get_cancel_button()),"cancel hungry plan")
	var already_manual:bool=w.work.jobs.has("npc.nora") and not w.director.routines["npc.nora"].owns_job()
	check(already_manual or w.command("npc.nora",{"intent":"watch"}).get("ok",false),"isolated real busy-job fixture accepted by original action")
	await enter_text("阿黑跟我来","Raven follow me")
	check(game.local_host_commands.pending.rows.size()==1 and not game.local_host_commands.pending.rows[0].allowed,"busy actor grey without interrupting her actual job")
	check(await UI.click(self,game.local_host_commands.card.get_cancel_button()) and w.work.jobs.has("npc.nora"),"cancel busy plan preserves original job")
	await capture("unknown-feedback")
	check(game.links.values().all(func(link):return link._pid<=0),"local command UI starts no real model process")
	game.queue_free();await process_frame
	print("LOCAL_COMMAND_ACTIONS ",opening," ","en" if english else "zh"," ",checks," failed=",failed);quit(1 if failed else 0)

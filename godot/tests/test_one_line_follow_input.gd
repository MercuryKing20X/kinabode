extends "res://tests/test_intelligence_core_input.gd"
const SaveFollow=preload("res://scripts/save_store.gd")
func run()->void:
	await fresh()
	var w:RefCounted=game.world
	# DIRECTION: “开局见面缩短、每个新档不同（谁先来，说什么，一开始想做什么由随机＋性格决定）”.
	check(w.open_life and w.activities.following.is_empty(),"new standard does not automatically enlist followers")
	await capture("standard-follow")
	var human:Array=w.actors.human.position.duplicate()
	var phrases:Array=["别跟了","自由活动","大家散了","你们不跟了","所有人自由活动","大家别跟着我","你们别跟","全部自由活动","所有伙伴散了","大家自由活动吧","你们别跟了吧","全部别跟了","stop following","everyone unfollow","all of you free time"]
	var returns:Array=["跟我来","大家跟我走","都跟着我","你们都跟牢我","所有人跟我来","跟着我","大家跟着你","全部跟过来","所有伙伴跟我走","大家跟着我吧","你们都跟着我走","大家跟我来吧","follow me","everyone come with me","all of you follow me"]
	for i in phrases.size():
		await text_input(phrases[i])
		check(w.activities.following.is_empty(),"native release "+phrases[i])
		await text_input(returns[i])
		if w.activities.following.size()!=4:print("ONE_LINE_FOLLOW_PROBE phrase=",returns[i]," parsed=",game.local_host_commands.parser.parse_command(w,returns[i],[])," selected=",game.command_page.selected," scope=",game.group_chat," actor=",game.chat_actor," following=",w.activities.following.keys()," optouts=",w.activities.default_follow_excluded," explicit=",w.activities.explicit_selected," last=",game.local_host_commands.last_execution," eligibility=",w.director.routines.keys().map(func(id):return {"id":id,"reason":game.local_host_commands.eligible(id,"follow"),"job":w.work.jobs.get(id),"route":w._routes.get(id)}))
		check(w.activities.following.size()==4,"native follow "+returns[i])
		check(not is_instance_valid(game.local_host_commands.card),"no confirmation for follow")
		for tick in 10:game._process(.1)
	# Name selection must never silently widen to the village.
	for phrase in ["所有人跟我来","全部跟过来","大家跟我走","小蓝跟我来","别跟了"]:
		w.activities.set_followers([])
		var actor:String="companion-2"
		var at:Vector2=w.point(w.actors[actor])
		var destination:Vector2=Vector2.INF
		for offset in [Vector2(3,0),Vector2(-3,0),Vector2(0,3),Vector2(0,-3)]:
			if w.walkable(w.actors[actor].region_id,at+offset) and not w.find_route(actor,at+offset).is_empty():destination=at+offset;break
		check(destination.is_finite() and w.host_command(actor,{"intent":"move","x":destination.x,"y":destination.y}).get("ok",false),"actual existing World route before "+phrase)
		var previous:Variant=w._routes.get(actor)
		await text_input(phrase)
		var expected:int=0 if phrase=="别跟了" else 1 if phrase=="小蓝跟我来" else 4
		check(w.activities.following.size()==expected,"exact recipients for "+phrase)
		if expected>0:
			check(w.activities.following.has(actor),"named/whole follow includes actual selected resident")
			check(not is_same(previous,w._routes.get(actor)),"explicit follow hands over previous World route")
	w.activities.set_followers(w.actors.keys().filter(func(id):return id!="human"))
	check(w.actors.human.position==human,"host text never moves human")
	var directory:String=OS.get_environment("HABITAT_DATA_DIR").path_join("follow-roundtrip")
	w.activities.release_follow("npc.nora")
	check(SaveFollow.save_world(w,directory),"save selected follow state")
	w.activities.following.clear()
	check(SaveFollow.load_world(w,directory).get("loaded",false),"strict save reload")
	check(w.activities.following.size()==3 and not w.activities.following.has("npc.nora"),"individual choices restored")
	var path:String=directory.path_join("island-v2.json")
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(path));data.erase("following")
	var file:=FileAccess.open(path,FileAccess.WRITE);file.store_string(JSON.stringify(data));file.close()
	check(SaveFollow.load_world(w,directory).get("loaded",false) and w.activities.following.is_empty(),"legacy missing field keeps original no follow")
	game.queue_free();await process_frame
	OS.set_environment("HABITAT_OPENING","showcase")
	game=load("res://scenes/main_v3.tscn").instantiate();game.world=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	# Separate empty data folder ensures this is a second genuinely new opening.
	OS.set_environment("HABITAT_DATA_DIR",OS.get_environment("HABITAT_DATA_DIR").path_join("showcase"))
	root.add_child(game);game.save_enabled=false
	await process_frame
	check(game.world.opening_id=="showcase" and game.world.activities.following.size()==4,"new showcase follows all four")
	await capture("showcase-follow")
	game.queue_free();await process_frame
	print("ONE_LINE_FOLLOW_INPUT ",checks," failed=",failed);quit(1 if failed else 0)

func capture(label:String)->void:
	if DisplayServer.get_name()=="headless":return
	game.chat.hide()
	for tick in 400:game._process(.1)
	game.view.zoom=.75
	var host_at:Vector2=game.world.point(game.world.actors.human)
	for offset in [Vector2(0,12),Vector2(-12,0),Vector2(12,0),Vector2(0,-12)]:
		var destination:Vector2=host_at+offset
		var click_at:Vector2=game.view.screen(destination)
		if not game.world.walkable(game.world.actors.human.region_id,destination) or not Rect2(Vector2.ZERO,Vector2(root.size)).has_point(click_at):continue
		for pressed in [true,false]:
			var input:=InputEventMouseButton.new();input.button_index=MOUSE_BUTTON_LEFT;input.position=click_at;input.global_position=click_at;input.pressed=pressed;root.push_input(input,true);await process_frame
		if game.world._routes.has("human"):break
	for tick in 300:game._process(.1)
	check(game.world.point(game.world.actors.human).distance_to(host_at)>5,"native viewport ground click really moves host before follow screenshot")
	game.view.center=game.world.point(game.world.actors.human);game.view.queue_redraw();await process_frame;await process_frame
	RenderingServer.force_draw(false)
	var directory:String="/tmp/youqi-one-line-screenshots"
	DirAccess.make_dir_recursive_absolute(directory)
	root.get_texture().get_image().save_png(directory.path_join(label+".png"))

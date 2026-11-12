extends "res://tests/test_dialogue_bar_input.gd"
func run()->void:
	OS.set_environment("HABITAT_OPENING","showcase")
	var game:Node=load("res://scenes/main_v3.tscn").instantiate();root.add_child(game);game.save_enabled=false
	root.size=Vector2i(1280,800);await frames()
	# In-memory edited appearances reproduce the protected atlas rejection.
	# Never read or write a player work.
	for id in (game.steward.Pool.IDS if OS.get_environment("HABITAT_RHYTHM_EDITED")!="0" else []):
		var visual:String=game.library.visual_appearance(game.world.actors[id])
		var art:Dictionary=game.library.artworks[visual]
		art.frames.down_0[0].pixels[0]=1;art.revision+=1
		check(game.view.play_frames.texture(game.library,game.world.actors[id],32)==null,"edited identity protected "+id)
	await UI.click(self,game.dialogue_button);await UI.tab(self,game.action_dock.action_tabs,1)
	var entries:Array=UI.descendants(game.watch_ui.menu_column).filter(func(n):return n is Button and n.text==preload("res://scripts/localization.gd").text("play.choose"))
	await UI.reveal(self,entries[0]);await UI.click(self,entries[0])
	var cards:Array=game.get_children().filter(func(n):return n.has_meta("play_selector"))
	var buttons:Array=UI.descendants(cards[0]).filter(func(n):return n.get_meta("play_kind","")=="rope")
	check(await UI.click(self,buttons[0]),"native mouse starts rope")
	game.chat.hide();game.view.follow_player=false;game.view.center=game.playground.anchor;game.view.zoom=1.3
	var expected_jumpers:Array=game.playground.rope_roles().slice(2,4)
	var air:Dictionary={};var land:Dictionary={};var samples:Array=[];var captured:Dictionary={}
	var deadline:int=Time.get_ticks_msec()+20000
	while Time.get_ticks_msec()<deadline:
		game.view.follow_player=false;game.view.peek_elapsed=0;game.view.center=game.playground.anchor
		await process_frame
		if game.playground.kind!="rope":break
		var phase:float=fposmod(game.playground.rope_time,1.6)/1.6
		var ids:Array=game.playground.rope_roles()
		if game.playground.rope_time<1 or game.playground.rope_pause>0:continue
		var bucket:int=mini(7,int(phase*8))
		if not captured.has(bucket):
			captured[bucket]=true
			await capture("cycle-"+str(bucket))
		if phase>.47 and phase<.53:
			var sample:Dictionary={"phase":phase,"actual":{}}
			for id in ids.slice(2,4):
				var rendered:Dictionary=game.view.play_rendered.get(id,{})
				sample.actual[id]=rendered.duplicate()
				if float(rendered.get("lift",0))<=-19:air[id]=true
			samples.append(sample)
		if phase>.82 and phase<.9:
			for id in ids.slice(2,4):
				if absf(float(game.view.play_rendered.get(id,{}).get("lift",100)))<1:land[id]=true
		if expected_jumpers.all(func(id):return air.has(id) and land.has(id)) and captured.size()==8:break
	for id in expected_jumpers:
		check(air.has(id),"actual rendered jump at rope crossing "+id)
		check(land.has(id),"actual rendered landing "+id)
	await capture("native-rhythm")
	var out:=FileAccess.open(OS.get_environment("HABITAT_UI_EVIDENCE").path_join("rhythm.json"),FileAccess.WRITE)
	out.store_string(JSON.stringify({"checks":checks,"failed":failed,"air":air,"land":land,"samples":samples}));out.close()
	game.queue_free();await frames();print("RHYTHM ",checks," failed=",failed);quit(1 if failed else 0)

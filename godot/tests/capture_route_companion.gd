extends "res://tests/capture_route_latched.gd"
func observe(label:String,expected:bool)->void:
	var w:RefCounted=game.world;var id:String="companion-2";var frames:=0;var runs:=0;var columns:Dictionary={}
	for i in range(900):
		await step();game.view.center=w.point(w.actors[id]);game.view.follow_player=false
		if w.motion_state(id).moving:
			frames+=1
			if w.display_running(id) and game.view.action_atlases.texture("run",game.library,w.actors[id],game.view.motion.run_column(id,w.intelligence.gait(id)))!=null:runs+=1;columns[game.view.motion.run_column(id,w.intelligence.gait(id))]=true
		if i%30==0 and i<=180:await shot(label+"-%03d"%i)
		if not w._routes.has(id) and i>15:break
	records.append({"label":label,"moving_frames":frames,"run":runs,"walk":frames-runs,"hunger":w.hunger.rank(id),"columns":columns.keys(),"appearance":w.actors[id].appearance_id})
	if expected and runs>12 and columns.size()<3:failed=true
	if frames==0 or (runs!=frames if expected else runs!=0):failed=true
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"));output=OS.get_environment("HABITAT_DARK_EVIDENCE");root.size=Vector2i(1280,800);root.gui_embed_subwindows=true
	game=UI.init_game(self);await process_frame;await process_frame
	await route("host-away-1",15,true);await route("host-away-2",15,true)
	await UI.click(self,game.gathering_button);await UI.click(self,game.follow_ui.checks["companion-2"]);await UI.click(self,game.follow_ui.menu.get_ok_button())
	await observe("blue-side",true)
	await UI.click(self,game.gathering_button);await UI.click(self,game.follow_ui.checks["companion-2"]);await UI.click(self,game.follow_ui.menu.get_ok_button())
	game.world.assign_appearance("companion-2","ai-claude",false,false)
	for n in range(5):
		await route("host-away-nondefault-%d"%n,15,true)
		if game.world.point(game.world.actors.human).distance_to(game.world.point(game.world.actors["companion-2"]))>20:break
	await UI.click(self,game.gathering_button);await UI.click(self,game.follow_ui.checks["companion-2"]);await UI.click(self,game.follow_ui.menu.get_ok_button())
	await observe("nondefault",true)
	await UI.click(self,game.gathering_button);await UI.click(self,game.follow_ui.checks["companion-2"]);await UI.click(self,game.follow_ui.menu.get_ok_button())
	for i in range(700):game._process(1)
	await route("host-away-hungry",15,true)
	await UI.click(self,game.gathering_button);await UI.click(self,game.follow_ui.checks["companion-2"]);await UI.click(self,game.follow_ui.menu.get_ok_button())
	await observe("hungry-nondefault",false)
	FileAccess.open(output.path_join("frames.json"),FileAccess.WRITE).store_string(JSON.stringify(records,"  "));print(JSON.stringify(records));game.queue_free();await process_frame;quit(1 if failed else 0)

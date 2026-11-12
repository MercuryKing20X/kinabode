extends SceneTree
const UI=preload("res://tests/barbecue_ui_fixture.gd")
const Layout=preload("res://scripts/home_layout.gd")
var failed:=false
var samples:Array=[]
func _initialize()->void:call_deferred("run")
func check(ok:bool,label:String)->void:
	if not ok:failed=true;push_error(label)
func click(g:Node,at:Vector2)->void:
	g.view.center=at;g.view.follow_player=false;await process_frame
	var screen:Vector2=g.view.screen(at)
	for down in [true,false]:
		var e:=InputEventMouseButton.new();e.button_index=MOUSE_BUTTON_LEFT;e.pressed=down;e.position=screen;e.global_position=screen;root.push_input(e,true);await process_frame
func walk(g:Node,at:Vector2,measure:bool=false)->void:
	await click(g,at)
	for i in range(6000):
		g._process(.1)
		if measure:
			for actor_id in g.world.activities.following:
				var p:Vector2=g.world.point(g.world.actors[actor_id])
				if p.y>183 and g.world.motion_state(actor_id).moving:samples.append({"actor":actor_id,"position":[p.x,p.y],"road":Layout.near_road({"roads":g.world.home_island.config.roads.map(func(r):return {"points":r.points,"width":2})},p,0)})
			var p:Vector2=g.world.point(g.world.actors.human)
			samples.append({"actor":"human","position":[p.x,p.y],"road":Layout.near_road({"roads":g.world.home_island.config.roads.map(func(r):return {"points":r.points,"width":2})},p,0)})
		if not g.world._routes.has("human"):break
	check(g.world.point(g.world.actors.human).distance_to(at)<1,"native walk arrived "+str(at))
func run()->void:
	var g:Node=UI.init_game(self);await process_frame
	g.world.cat.initialize()
	check(g.world.cat.discovered and g.world.cat.position.y<128,"pet begins on original mainland")
	var memory:Dictionary=g.world.cat.memories.duplicate()
	g.world.cat.restore({"version":1,"discovered":false,"memories":{}})
	check(g.world.cat.discovered and g.world.cat.position.y<128 and g.world.cat.memories.is_empty(),"undiscovered legacy cat moved without invented contact history")
	var fixed:=Vector2(79,180)
	g.world.cat.restore({"version":1,"discovered":true,"memories":memory,"region_id":"home","position":[fixed.x,fixed.y]})
	check(g.world.cat.position==fixed,"already discovered position unchanged")
	g.world.director.set_all_enabled(true)
	check(await UI.click(self,g.actions_button),"native lightning opens follow section")
	check(await UI.tab(self,g.action_dock.action_tabs,1),"native everyone tab")
	var follow:BaseButton=null
	for node in UI.descendants(g):
		if node is BaseButton and node.is_visible_in_tree() and node==g.gathering_button:follow=node;break
	check(follow!=null and await UI.click(self,follow),"native follow selection opens")
	if is_instance_valid(g.follow_ui.menu):
		check(await UI.click(self,g.follow_ui.all_box),"native all companions selected")
		check(await UI.click(self,g.follow_ui.menu.get_ok_button()),"native follow card closes")
	await walk(g,Vector2(93,208))
	for i in range(1000):g._process(.1)
	await walk(g,Vector2(75,208),true)
	var road_count:int=samples.filter(func(s):return s.road).size()
	var host_samples:Array=samples.filter(func(s):return s.actor=="human")
	var host_roads:int=host_samples.filter(func(s):return s.road).size()
	check(not host_samples.is_empty() and float(host_roads)/host_samples.size()>.7,"host native route predominantly follows authored road; moving companion samples reported separately")
	var out:String=OS.get_environment("HABITAT_PLAYTEST_CAPTURE")
	if out.is_empty():out=OS.get_environment("HABITAT_DATA_DIR")
	var f:=FileAccess.open(out.path_join("south-road-trace.json"),FileAccess.WRITE);f.store_string(JSON.stringify({"samples":samples,"road_samples":road_count,"total_samples":samples.size(),"failed":failed},"  "));f.close()
	print("south roads native host ratio ",road_count,"/",samples.size()," failed=",failed)
	g.queue_free();await process_frame;quit(1 if failed else 0)

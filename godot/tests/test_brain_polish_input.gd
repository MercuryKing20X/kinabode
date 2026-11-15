extends "res://tests/test_brain_input.gd"
func run()->void:
	base_directory=OS.get_environment('HABITAT_DATA_DIR');evidence=OS.get_environment('HABITAT_BRAIN_EVIDENCE');media=OS.get_environment('HABITAT_BRAIN_MEDIA')
	DirAccess.make_dir_recursive_absolute(media);root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	node_added.connect(func(node):
		if node.get_script()!=null and node.get_script().resource_path=='res://scripts/main.gd':node.set_process(false);node.dialogue_adapter_factory=func(_id,_scope):return Fake.new())
	await fresh_title(30)
	var physical:Dictionary=await preload('res://tests/brain_polish_fixture.gd').new(self).run()
	var file:=FileAccess.open(evidence.path_join('physical-input-results.json'),FileAccess.WRITE);file.store_string(JSON.stringify(physical,'\t'));file.close()
	game.view.follow_player=false;game.view.center=game.world.point(game.world.actors.human);game.view.zoom=1
	game.LocalText.select(game.data_dir,'zh')
	# Advance real time, never edit DayCycle, hunger, weather or speed settings.
	while game.world.days.within_day()<1175:game.world.advance(.25)
	for frame in 120:
		for tick in 2:game.world.advance(.25)
		game.view._process(.5);game.island_hud.refresh();await shot('dusk-night-%03d'%frame)
	var stars:Array=game.world.director.brains.values().filter(func(b):return b.current.get('action')=='stars' or b.history.any(func(row):return row.get('choice')=='stars'))
	check(not stars.is_empty(),'clear night actually selects stars after a real meal')
	var rested:=false
	while game.world.days.within_day()<1450:
		game.world.advance(.25)
		var blue:RefCounted=game.world.director.brains['companion-2']
		if blue.current.get('action')=='night_rest' and not game.world._routes.has('companion-2'):rested=true;break
	check(rested,'Blue really reaches a night-rest destination after a real meal')
	if rested:
		game.view.follow_player=false;game.view.peek_elapsed=0;game.view.center=game.world.point(game.world.actors['companion-2']);game.view._process(0);game.island_hud.refresh();await shot('blue-night-rest')
	var rest_file:=FileAccess.open(evidence.path_join('night-rest-arrival.json'),FileAccess.WRITE)
	rest_file.store_string(JSON.stringify({'actor':'companion-2','at':game.world.director.time,'position':game.world.actors['companion-2'].position,'current':game.world.director.brains['companion-2'].current,'real_houses':game.world.objects.values().filter(func(o):return o.kind=='construction_site' and int(o.get('stage_index',0))>=5),'arrived':rested},'\t'));rest_file.close()
	for link in game.links.values():check(link is Fake and link.sent.is_empty(),'zero model calls')
	game.queue_free();await process_frame;print('BRAIN_POLISH_INPUT ',checks,' failed=',failed);quit(1 if failed else 0)

func capture_committed_mind(who:String)->void:
	game.view.follow_player=false;game.view.center=game.world.point(game.world.actors[who]);game.view.zoom=1
	await process_frame
	var point:Vector2=game.view.screen(game.world.point(game.world.actors[who]))+Vector2(0,-40)
	for down in [true,false]:
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_RIGHT;event.position=point;event.global_position=point;event.pressed=down;root.push_input(event,true);await process_frame
	check(game.brain_panel.visible and game.brain_panel.actor_id==who,'real right click opens exact mind')
	for locale in ['zh','en']:
		game.LocalText.select(game.data_dir,locale);game.brain_panel.refresh();await shot('polish-mind-'+locale)
	game.brain_panel.hide();game.LocalText.select(game.data_dir,'zh')

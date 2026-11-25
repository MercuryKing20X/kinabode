extends "res://tests/probe_first_hour.gd"

func run()->void:
	var directory:String=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(2);return
	root.size=Vector2i(1280,800);root.content_scale_size=Vector2i.ZERO
	await prepare_scene(directory,true)
	await greeting()
	await provision_camp()
	check(w.storage.count("wood")>=2,"one true tree and construction leave cold fire fuel")
	await favorite_fish()
	check(actions.any(func(a):return a.action=="favorite_fish" and a.stage=="catch" and a.ok),"two real shore clicks and confirmation reach one catch")
	var bar:Control=g.island_hud.primary_actions
	check(await UI.click(self,g.dialogue_button) and g.chat.visible,"real nonmodal dialogue opens")
	await frames()
	check(not g.chat.get_global_rect().intersects(bar.get_global_rect()),"dialogue leaves the bottom buttons clear")
	check(await begin_steward(),"visible management starts while nonmodal dialogue is open")
	print("NEWCOMER_REPAIR ",JSON.stringify(actions)," failures=",failures)
	g.queue_free();await frames();quit(1 if failures else 0)

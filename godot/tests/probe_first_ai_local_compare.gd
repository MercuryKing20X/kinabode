extends "res://tests/test_intelligence_core_input.gd"
func run()->void:
	var rows:Array=[]
	for phrase in ["今天过得怎样？","帮我种萝卜","帮我砍两棵树","叫小蓝和你一起去浇水","帮我造个城堡"]:
		await fresh()
		check(await UI.click(self,game.dialogue_button),"native opens chat")
		check(await UI.click(self,game.command_page.tabs.get_child(1)),"native Talk")
		game._select_chat("companion-2")
		await text_input(phrase,true)
		for tick in 100:
			game._process(.1)
			if tick%20==0:await process_frame
		rows.append({"input":phrase,"status":game.status.text,"has_job":game.world.work.jobs.has("companion-2"),"has_farm_order":game.world.farms.orders.has("companion-2"),"history":game.dialogue.histories.get("direct:companion-2",[]).map(func(e):return {"kind":e.get("kind"),"text":e.get("text","")})})
		game.queue_free();await process_frame
	var file:=FileAccess.open(OS.get_environment("HABITAT_DATA_DIR").path_join("local-compare.json"),FileAccess.WRITE)
	file.store_string(JSON.stringify(rows,"  "));file.close()
	quit(1 if failed else 0)

extends SceneTree
const F=preload("res://tests/standard_observation_fixture.gd")
func _initialize()->void:call_deferred("run")
func run()->void:
	var dir:=OS.get_environment("HABITAT_DATA_DIR");assert(dir.contains("youqi-test-"))
	var output:=OS.get_environment("HABITAT_STANDARD_EVIDENCE");var results:Dictionary={}
	for mode in ["active","ordinary","novice"]:
		var f:=F.new();f.start(dir.path_join(mode));assert(f.build_first() and f.shared_meal())
		if mode!="novice":f.crop_cycle()
		var next_meal:float=f.elapsed+1200;var retry_after:=0.0;var next_harvest:float=f.elapsed+30;var next_activity:=f.elapsed
		while f.elapsed<3600:
			var hungry:bool=f.w.standard.config.companions.any(func(id):return f.w.hunger.rank(id)>=2)
			f.want_food=hungry
			if mode!="novice" and f.elapsed>=next_harvest:
				next_harvest=f.elapsed+(30 if mode=="ordinary" else 1200)
				if mode=="ordinary" or f.elapsed>=next_meal:f.crop_cycle()
			if mode=="active" and f.elapsed>=next_meal:
				f.crop_cycle();f.meal();next_meal+=1200
			elif mode=="ordinary" and hungry and f.elapsed>=retry_after:
				f.meal();retry_after=f.elapsed+60
			elif mode=="novice" and f.elapsed>=next_activity and f.elapsed<3450:
				next_activity=f.elapsed+120
				if not f.w.fishing.held("human").is_empty():f.w.command("human",{"intent":"release_fish","fish_id":f.w.fishing.held("human").id})
				if f.job({"intent":"gather_wood","zone_id":"home.forest","tree_count":1}):
					var shores:Array=f.w.fishing.nearby_shores("human")
					if not shores.is_empty():
						var at:Array=shores[0].position
						if f.job({"intent":"move","x":at[0],"y":at[1]}) and not f.w.fishing.shore("human").is_empty():f.job({"intent":"fish"})
			f.tick(.5)
		f.check(f.wood_audit().conserved and f.food_audit().conserved,"60-minute real materials conserved")
		results[mode]=f.result();print(mode," 3600s done, failed=",f.failed," first very=",f.first_very)
	var file:=FileAccess.open(output.path_join("simulation-60min.json"),FileAccess.WRITE);file.store_string(JSON.stringify(results,"  "));file.close()
	quit(1 if results.values().any(func(r):return r.failed) else 0)

extends SceneTree
func _initialize()->void:
	OS.set_environment("HABITAT_OPENING","standard")
	var w:=preload("res://scripts/world_state.gd").new("res://content/home-v3/world.json")
	var lib:=preload("res://scripts/character_library.gd").new();lib.configure(OS.get_environment("HABITAT_DATA_DIR"));w.library=lib;w.residents.provision(w)
	var target:String=""
	for site in w.objects.values():
		if site.kind=="construction_site" and int(site.get("stage_index",0))<5:target=site.id;break
	assert(not target.is_empty())
	var ids:Array=["codex","companion-2","npc.mira","npc.nora"]
	var results:Array=w.projects.invite_team(ids,target)
	for result in results:assert(result.ok,str(result))
	for id in ids:assert(w.projects.active(id))
	for tick in 20:w.advance(.1)
	for id in ids:assert(w.projects.active(id));assert(w.work.jobs.has(id) or w._routes.has(id),"each participant has real work or World route "+id)
	assert(w.projects.host_team_site.is_empty())
	print("BUILD_TEAM PASS four real plans/jobs/routes; completion not asserted")
	quit()

extends RefCounted
## Explicit host UI exception. No stock, receipts, contribution or memory grants.
static func apply(world:RefCounted)->Dictionary:
	if not preload("res://scripts/world_opening.gd").v3(world):return world._error("unsupported_world")
	# Do not rewrite anyone's accepted job or an in-flight construction receipt.
	for job in world.work.jobs.values():
		if job.get("intent") in ["build","build_house","build_facility","deliver_wood"]:return world._error("busy")
	for plan in world.projects.plans.values():
		if plan.get("status") in ["active","paused","blocked"]:return world._error("busy")
	if world.homestead.plans.values().any(func(p):return p.get("status") in ["active","paused","blocked"]):return world._error("busy")
	var count:=0
	for site in world.objects.values():
		if site.kind!="construction_site" or int(site.get("stage_index",0))==5:continue
		site.stage_index=5;site.status="complete";site.stage="complete";site["host_completed"]=true
		world.rescue_obstructed()
		world._grids.erase(site.region_id);count+=1
	for site in world.leisure.sites.values():
		if site.complete:continue
		if site.artwork.is_empty():site.artwork=world.leisure.art(site).duplicate(true)
		if site.artwork.is_empty():continue
		site.complete=true;site["host_completed"]=true;count+=1
		world.rescue_obstructed()
	if not world.homestead.completed():
		world.homestead.site["host_completion_source"]=world.homestead.site.state
		world.homestead.site.state="completed"
		world.rescue_obstructed()
		world.homestead.ensure_host_completion()
		world.recipes.recipes[world.homestead.config.unlock_recipe.id]=world.homestead.config.unlock_recipe.duplicate(true)
		count+=1
	world._grids.clear();world._terrain_solids.clear();world.revision+=1
	return {"ok":true,"count":count}

extends RefCounted
const F = preload("res://tests/cooking_fixture.gd")

static func wood(world: RefCounted, trees: int, actor: String = "codex") -> bool:
	return F.job(world, actor, {"intent":"gather_wood", "zone_id":"home.forest", "tree_count":trees})

static func held(world: RefCounted, actor: String, count: int) -> bool:
	for tick in range(18000):
		world.advance(.1)
		if world.life.item_count(world.actors[actor].carry) == count: return true
		if not world.work.jobs.has(actor): return false
	return false

static func wood_total(world: RefCounted) -> int:
	var total := F.amount(world, "wood")
	for drop in world.drops.values(): total += int(drop.wood)
	for site in world.objects.values():
		if site.kind == "construction_site": total += int(site.get("invested",0)) + int(site.delivered.get("wood",0))
	for item in world.interior.furniture.values(): total += int(item.invested)
	for site in world.leisure.sites.values(): total += int(site.invested)
	return total

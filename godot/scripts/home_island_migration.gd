extends RefCounted
## Validate the frozen original-coordinate world before translating any saved fact.
const OFFSET=Vector2(-19,150)
const LEGACY="res://content/migrations/home-island-v1/world.json"
static func shift(entry:Dictionary)->void:
	entry.region_id="home"
	entry.position=[entry.position[0]+OFFSET.x,entry.position[1]+OFFSET.y]
static func migrate(world:RefCounted,data:Dictionary)->bool:
	if world.home_island==null or world.home_island.legacy or not world.catalog.regions.home.get("layout",{}).has("homelands"):return true
	if data.has("home_map_version"):return (data.home_map_version is int or data.home_map_version is float) and is_finite(data.home_map_version) and data.home_map_version==2
	# Frozen old catalog authority, exact old coordinates, old inventories and receipts.
	var old:RefCounted=load("res://scripts/world_state.gd").new(LEGACY)
	if not old.error.is_empty():return false
	old.residents.provision(old)
	if data.get("opening_id")=="standard":old.standard.install_geometry()
	var validator:Script=load("res://scripts/save_store.gd")
	if not validator._valid(old,data):return false
	var cat:Dictionary=data.get("cat",{})
	if cat.get("region_id")=="homelands":shift(cat)
	for entry in data.get("actors",{}).values():
		if entry.region_id=="homelands":shift(entry)
	for entry in data.get("objects",{}).values():
		if entry.region_id=="homelands":shift(entry)
	for entry in data.get("drops",{}).values():
		if entry.region_id=="homelands":shift(entry)
	var extra:Dictionary=data.get("extra_barbecues",{}).get("homelands.barbecue",{})
	if not extra.is_empty():
		shift(extra.station)
		for patch in extra.patches.values():shift(patch)
	# Diary facts keep their canonical IDs and retained words, never replayed/rewarded.
	for entry in data.get("shared_memories",{}).get("records",[]):
		if entry.get("region_id")=="homelands":entry.region_id="home"
	data["home_map_version"]=2
	return true

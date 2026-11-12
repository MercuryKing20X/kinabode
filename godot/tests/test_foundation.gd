extends SceneTree
const Places=preload("res://scripts/map_locations.gd")
const World = preload("res://scripts/world_state.gd")
const Endpoint = preload("res://scripts/read_endpoint.gd")
var checks := 0
var failed := false

func check(value: bool, message: String) -> void:
	checks += 1
	if not value:
		failed = true
		push_error(message)

func _initialize() -> void:
	var world := World.new()
	check(world.error.is_empty(), "world content loads: " + world.error)
	if not world.error.is_empty(): quit(1); return
	check(world.world_id != World.new().world_id, "fresh worlds have independent identities")
	check(world.catalog.regions.size() == 3, "three sparse islands")
	check(world.catalog.objects.size() == 90 and world.catalog.objects.has("home.house.01"), "objects have stable IDs")
	check(world.catalog.regions.home.zones.size() == 15, "fifteen fixed-use zones including eastern farmland")
	var before := world.observe("codex")
	check(before.ok and before.self.id == "codex", "reader identity")
	check(before.objects.size() == 24 and not before.page.complete, "pagination is explicit")
	var page := world.observe("codex", {"offset": 24, "limit": 100, "revision": before.snapshot_revision})
	check(page.objects.size() == 100 and not page.page.complete, "second page")
	var last := world.observe("codex", {"offset":124,"limit":100,"revision":before.snapshot_revision})
	check(last.objects.size() == int(before.page.total)-124 and last.page.complete,"last page")
	check(world.observe("codex", {"offset": 24}).error == "stale_snapshot", "continuation must pin revision")
	var detail:Dictionary=world.storage.saved()
	check(world.storage.count("wood")==0,"no invented warehouse wood")
	detail.items["wood"]=999
	check(world.storage.count("wood")==0,"warehouse snapshot cannot mutate state")
	for i in range(2, 6): check(world.add_companion("reader-%s" % i, "伙伴"), "provision independent reader")
	var snapshot_revision: int = world.revision
	for id in world.actors:
		var snapshot := world.observe(id)
		check(snapshot.self.id == id and snapshot.snapshot_revision == snapshot_revision, "same world different self")
	check(world.observe("unknown").error == "unknown_resident", "unknown identities rejected")
	check(world.observe("codex", {"limit": -1}).error == "invalid_pagination", "invalid page")
	check(world.observe("codex", {"region_id": "unknown"}).error == "unknown_region", "invalid region")
	check(world.observe("codex", {"object_id": "missing"}).error == "unknown_object", "missing object")
	check(world.observe("codex", {"actor_id": "human"}).error == "invalid_query", "cannot override bound self")
	check(world.command("human", {"intent": "move", "x":Places.point("p_1_0_1_0").x,"y":Places.point("p_1_0_1_0").y}).error == "not_walkable", "ocean impassable")
	check(world.command("human", {"intent": "move", "x": NAN, "y": 1}).error == "invalid_position", "NaN rejected")
	check(world.command("human", {"intent": "unimplemented"}).error == "unsupported_action", "unimplemented build never pretends success")
	var codex_position: Array = world.actors.codex.position.duplicate()
	check(world.command("human", {"intent": "move", "x":Places.point("p_55_46").x,"y":Places.point("p_55_46").y}).status == "accepted", "real movement accepted")
	world.advance(0.1)
	check(world.actors.human.position != [51.0, 44.0] and world.actors.codex.position == codex_position, "movement never takes over other resident")
	check(world.revision > snapshot_revision, "movement increments snapshot version")
	check(world.observe("codex", {"offset": 24, "revision": snapshot_revision}).error == "stale_snapshot", "changed world rejects mixed pages")
	for i in range(100): world.advance(0.1)
	check(Vector2(world.actors.human.position[0], world.actors.human.position[1]).distance_to(Places.point("p_55_46")) < 0.001, "arrival")
	check(world.actors.human.activity == "idle", "movement completes without model")
	var bad_pack: Dictionary = world.catalog._json("res://content/examples/player-island.json")
	bad_pack.regions[0].erase("name")
	check(not world.catalog.validate_pack(bad_pack).is_empty(), "malformed content rejects before rendering")
	var pack: Dictionary = world.catalog._json("res://content/examples/player-island.json")
	check(world.catalog.validate_pack(pack).is_empty(), "player extension validates")
	pack.regions[0].origin = [4048, 4048]
	check(not world.catalog.validate_pack(pack).is_empty(), "overlapping extension rejected")
	var endpoint := Endpoint.new()
	endpoint.world = world
	endpoint.session = "test-session"
	endpoint.bindings = {"test-token": "codex"}
	var request := {"session": "test-session", "token": "test-token", "expires": Time.get_unix_time_from_system() + 10, "operation": "observe", "query": {}}
	check(endpoint.handle(request).self.id == "codex", "token-bound reader")
	request.operation = "act"
	check(endpoint.handle(request).error == "missing_request_id", "read endpoint cannot mutate")
	request.operation = "observe"
	request.token = "wrong"
	check(endpoint.handle(request).error == "unauthorized", "invalid binding rejected")
	request.session = "old-session"
	check(endpoint.handle(request).error == "stale_session", "stale session rejected")
	var data_dir := OS.get_environment("HABITAT_DATA_DIR")
	if not data_dir.is_empty():
		endpoint.configure(world, data_dir.path_join("heartbeat-check"))
		var heartbeat_file := endpoint.directory.path_join("heartbeat.json")
		var heartbeat_before: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(heartbeat_file))
		var world_before: float = world.forest.clock
		# A transport lease uses real time, including when simulation delta is zero.
		OS.delay_msec(1100)
		endpoint._process(0)
		var heartbeat_after: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(heartbeat_file))
		check(float(heartbeat_after.updated) > float(heartbeat_before.updated) + 1.0, "transport heartbeat refreshes by wall time with zero simulation delta")
		check(world.forest.clock == world_before, "transport heartbeat never advances gameplay")
	endpoint.free()
	print("Foundation: %s checks, %s" % [checks, "FAIL" if failed else "PASS"])
	quit(1 if failed else 0)

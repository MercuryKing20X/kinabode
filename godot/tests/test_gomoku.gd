extends SceneTree
const World=preload("res://scripts/world_state.gd")
const Library=preload("res://scripts/character_library.gd")
const Save=preload("res://scripts/save_store.gd")
const Rules=preload("res://scripts/gomoku_rules.gd")
var checks:=0
var failed:=false
func _initialize() -> void:call_deferred("run")
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failed=true;push_error(label)
func job(world: RefCounted,id: String,args: Dictionary) -> bool:
	if not world.command(id,args).ok:return false
	for i in range(18000):
		world.advance(.1)
		if not world.work.jobs.has(id) and not world._routes.has(id):return true
	return false
func seated(world: RefCounted,site: String="play.gomoku") -> bool:
	for i in range(1500):
		world.advance(.1)
		if world.gomoku.sessions[site].phase!="arriving":return world.gomoku.sessions[site].phase=="playing"
	return false
func action(world: RefCounted,id: String,intent: String,p:=Vector2i(-1,-1),site: String="play.gomoku") -> Dictionary:
	var game: Dictionary=world.gomoku.sessions[site]
	var args: Dictionary={"intent":intent,"site_id":site,"match_id":game.id,"revision":game.revision}
	if intent=="gomoku_move":args.merge({"x":p.x,"y":p.y})
	return world.command(id,args)
func timber(world: RefCounted) -> int:
	var count:=0
	for chest in [{"id":"storage","items":world.storage.saved().items,"capacity":9007199254740991,"kind":"storage"}]:count+=int(chest.items.get("wood",0))
	for actor in world.actors.values():count+=int(actor.carry.get("wood",0))
	for drop in world.drops.values():count+=int(drop.wood)
	for site in world.leisure.sites.values():count+=int(site.invested)
	return count
func run() -> void:
	var directory:=OS.get_environment("HABITAT_DATA_DIR")
	if not directory.contains("youqi-test-"):quit(1);return
	for direction in Rules.DIRECTIONS:
		var history: Array=[];var start:=Vector2i(4,8)
		for n in range(5):
			var p: Vector2i=start+direction*n;history.append([p.x,p.y])
			if n<4:history.append([n*2,14])
		check(Rules.replay(history).winner==1,"five in direction "+str(direction))
	var overline: Array=[]
	for x in [0,1,2,4,5,3]:
		overline.append([x,0])
		if x!=3:overline.append([overline.size()-1,14])
	check(Rules.replay(overline).line.size()==6,"six counts as win without forbidden moves")
	check(Rules.replay([[7,7],[7,7]]).is_empty() and Rules.replay([[true,7]]).is_empty() and Rules.replay([[15,0]]).is_empty(),"invalid and repeated intersections rejected")
	var blacks: Array=[];var whites: Array=[];var draw: Array=[]
	for y in range(15):
		for x in range(15):
			if (x+2*y)%4<2:blacks.append([x,y])
			else:whites.append([x,y])
	for index in range(225):draw.append(blacks.pop_front() if index%2==0 else whites.pop_front())
	check(Rules.replay(draw).draw,"full-board draw is actually replayable")
	var board: Array=Rules.replay([]).board
	for x in range(4):board[7*15+x+4]=1
	var settings: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/gomoku.json"));var rng:=RandomNumberGenerator.new();rng.seed=10
	for difficulty in ["easy","normal"]:
		var defend:=Rules.choose(board,2,difficulty,settings,rng)
		check(defend in [Vector2i(3,7),Vector2i(8,7)],"local brain blocks immediate five "+difficulty)
		var win:=Rules.choose(board,1,difficulty,settings,rng)
		check(win in [Vector2i(3,7),Vector2i(8,7)],"local brain takes immediate win "+difficulty)
	var world:=World.new();world.residents.provision(world);world.director.set_all_enabled(false)
	var library:=Library.new();library.configure(directory);world.library=library;library.resident_world=world
	check(world.error.is_empty() and library.valid(library.artworks["play-gomoku"]),"new editable chess template loads")
	check(not world.gomoku.begin_host("play.gomoku","npc.mira",true,"local","normal").ok,"unfinished table cannot start")
	var initial_materials:=timber(world)
	var initial_stumps: Array=world.objects.values().filter(func(obj):return obj.get("status")=="stump").map(func(obj):return obj.id)
	check(job(world,"codex",{"intent":"gather_wood","tree_count":10}),"gather real wood for table")
	var materials:=timber(world)
	var actual_yield:=0
	for tree in world.objects.values():
		if tree.get("status")=="stump" and tree.id not in initial_stumps:actual_yield+=int(world.forest.settings.large_wood if int(tree.wood_yield)>8 else world.forest.settings.normal_wood)
	check(materials==initial_materials+actual_yield and job(world,"codex",{"intent":"build_facility","target_id":"play.gomoku"}) and world.leisure.sites["play.gomoku"].complete,"table built through actual supply and construction")
	check(timber(world)==materials and world.leisure.sites["play.gomoku"].invested==26,"construction conserves wood and invests exact cost")
	check(not world.command("npc.mira",{"intent":"use_facility","target_id":"play.gomoku"}).ok,"ambient sit cannot occupy match seats")
	var before:=world.revision
	check(world.command("codex",{"intent":"gomoku_read","site_id":"play.gomoku"}).ok and world.revision==before,"public board read has no world mutation")
	check(world.gomoku.begin_host("play.gomoku","npc.mira",true,"local","normal").ok and seated(world),"social-only local resident can join and actually arrive")
	var game: Dictionary=world.gomoku.sessions["play.gomoku"]
	check(world.actors.human.activity=="seated" and world.actors["npc.mira"].activity=="seated","both residents sit at unique real seats")
	check(not action(world,"codex","gomoku_move",Vector2i(7,7)).ok,"uninvited model cannot place for another player")
	check(action(world,"human","gomoku_move",Vector2i(7,7)).ok,"human chooses real first move")
	var revision: int=game.revision
	check(not action(world,"human","gomoku_move",Vector2i(8,7)).ok and game.revision==revision,"double human turn rejected without changing board")
	for i in range(30):world.advance(.1)
	check(game.history.size()==2 and world.gomoku._turn(game)=="human","local brain advances one turn only, without inference")
	check(not action(world,"npc.mira","gomoku_move",Vector2i(8,8)).ok,"external tool cannot override explicitly selected local chess control")
	check(Save.save_world(world,directory.path_join("active")),"active match saves")
	var restored:=World.new();restored.library=library
	check(Save.load_world(restored,directory.path_join("active")).ok and restored.gomoku.sessions["play.gomoku"].phase=="paused" and restored.work.jobs.is_empty() and restored.work.claims.is_empty(),"reload preserves board but restores no seats/routes/AI work")
	check(restored.gomoku.sessions["play.gomoku"].history==game.history,"reload preserves exact move history")
	world.command("npc.mira",{"intent":"stop"})
	check(game.phase=="paused" and world.work.jobs.is_empty() and world.work.claims.is_empty(),"stopping one pauses both and releases owned seats")
	check(world.gomoku.resume_host("play.gomoku").ok and seated(world),"explicit host resume routes both back")
	# Finish one complete real game; human test policy also uses the local rule chooser.
	for turn in range(225):
		if game.phase=="finished":break
		if world.gomoku._turn(game)=="human":
			var state:=Rules.replay(game.history);var p:=Rules.choose(state.board,1+game.history.size()%2,"normal",settings,rng)
			if not action(world,"human","gomoku_move",p).ok:break
		for i in range(22):world.advance(.1)
	check(game.phase=="finished" and game.result in ["five","draw"],"complete game reaches real terminal result")
	check(world.work.jobs.is_empty() and world.work.claims.is_empty(),"finished game releases both seats")
	check(world.read_memories("human",{"kind":"gomoku_match"}).total==1 and world.read_memories("npc.mira",{"kind":"gomoku_match"}).total==1 and world.read_memories("codex",{"kind":"gomoku_match"}).total==0,"real completed game credits exactly actual players")
	check(Save.save_world(world,directory.path_join("finished")),"finished result and memory save")
	var loaded:=World.new();loaded.library=library
	check(Save.load_world(loaded,directory.path_join("finished")).ok and loaded.gomoku.memories.size()==1,"validated terminal board and memory reload")
	var invalid: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("finished/island-v2.json")))
	invalid.gomoku.sessions["play.gomoku"].history.append([7,7])
	DirAccess.make_dir_recursive_absolute(directory.path_join("invalid"));var file:=FileAccess.open(directory.path_join("invalid/island-v2.json"),FileAccess.WRITE);file.store_string(JSON.stringify(invalid));file.close()
	var rejected:=Save.load_world(World.new(),directory.path_join("invalid"))
	check(not rejected.ok and FileAccess.file_exists(rejected.get("backup","")),"illegal stored board keeps recoverable invalid save")
	check(world.gomoku.begin_host("play.gomoku","codex",false,"model","normal").ok and seated(world),"model mode starts without starting inference")
	game=world.gomoku.sessions["play.gomoku"]
	var stale: Dictionary={"intent":"gomoku_move","site_id":"play.gomoku","match_id":game.id,"revision":game.revision,"x":7,"y":7}
	check(world.command("codex",stale).ok and not world.command("codex",stale).ok,"bound model move works, duplicate exact revision rejects")
	check(not action(world,"human","gomoku_move",Vector2i(7,7)).ok,"occupied intersection rejects")
	check(action(world,"human","gomoku_leave").ok and game.phase=="paused","leave pauses without declaring a loss")
	check(action(world,"human","gomoku_resign").ok and game.result=="resign" and game.winner_id=="codex","explicit resignation is recorded as resignation")
	check(world.gomoku.memories.size()==2,"paused/reads/retries create no extra completion records")
	check(job(world,"codex",{"intent":"gather_wood","tree_count":10}),"collect real materials for second table")
	var placed: Dictionary={}
	for y in range(38,105,5):
		for x in range(16,105,5):
			var candidate: Dictionary={"id":"candidate","position":[x,y]}
			if not world.leisure.chess_space_clear(candidate,library.artworks["play-gomoku"].recreation):continue
			placed=world.leisure.place("play-gomoku",Vector2(x,y))
			if placed.ok:break
		if placed.get("ok",false):break
	check(placed.get("ok",false) and job(world,"codex",{"intent":"build_facility","target_id":placed.get("site_id","")}),"second independently placed table builds through same material rules")
	if placed.get("ok",false):
		var other: String=placed.site_id
		check(world.gomoku.begin_host("play.gomoku","npc.nora",true,"local","easy").ok and seated(world),"new first-table game begins")
		action(world,"human","gomoku_move",Vector2i(7,7))
		for i in range(25):world.advance(.1)
		action(world,"human","gomoku_leave")
		var history: Array=world.gomoku.sessions["play.gomoku"].history.duplicate(true)
		check(world.gomoku.begin_host(other,"companion-2",true,"local","easy").ok and seated(world,other),"second table has independent match identity")
		action(world,"human","gomoku_move",Vector2i(6,6),other)
		check(world.gomoku.sessions["play.gomoku"].history==history and world.gomoku.sessions[other].history==[[6,6]],"moves at second table never change paused first board")
		check(not world.gomoku.resume_host("play.gomoku").ok and world.gomoku.sessions[other].phase=="playing","one resident cannot occupy two tables and failed resume preserves current game")
		world.command("human",{"intent":"stop"})
		check(Save.save_world(world,directory.path_join("two-tables")),"two paused tables save")
	var legacy:=World.new();legacy.library=library;legacy.director.set_all_enabled(false)
	check(job(legacy,"codex",{"intent":"gather_wood","tree_count":1}) and Save.save_world(legacy,directory.path_join("legacy")),"old-world fixture obtains actual wood")
	var old: Dictionary=JSON.parse_string(FileAccess.get_file_as_string(directory.path_join("legacy/island-v2.json")))
	old.erase("gomoku");old.leisure.sites.erase("play.gomoku")
	file=FileAccess.open(directory.path_join("legacy/island-v2.json"),FileAccess.WRITE);file.store_string(JSON.stringify(old));file.close()
	var old_loaded:=World.new();old_loaded.library=library
	check(Save.load_world(old_loaded,directory.path_join("legacy")).ok and old_loaded.leisure.sites["play.gomoku"].invested==0 and not old_loaded.leisure.sites["play.gomoku"].complete and timber(old_loaded)==timber(legacy),"old save gains only an empty foundation, preserving real inventory")
	print("Gomoku: %s checks, %s"%[checks,"FAIL" if failed else "PASS"]);quit(1 if failed else 0)

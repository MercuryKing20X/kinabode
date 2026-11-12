extends SceneTree
## Integration/UI — production/evidence/barbecue-v4 — BLOCKING host consent / exact participant work.
const UI=preload("res://tests/barbecue_ui_fixture.gd")
const BBQ=preload("res://tests/barbecue_fixture.gd")
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"));var game:Node=UI.init_game(self);var w:RefCounted=game.world
	var human:Dictionary=w.actors.human.duplicate(true);var stock:Dictionary=w.life.fireside.available()
	game._invite_barbecue("home.barbecue");await process_frame;await process_frame
	var invitation:Node=UI.shown(game,"res://scripts/fireside_invitation.gd")
	check(invitation!=null and invitation.all_box.text=="所有人","replacement invite page first offers All")
	check(await UI.click(self,invitation.all_box) and invitation.selected_ids().size()==4,"actual native All input chooses all four companions")
	check(w.actors.human==human and w.work.jobs.is_empty() and w.life.fireside.available()==stock,"selection alone never moves anybody or withdraws food")
	check(await UI.click(self,invitation.get_ok_button()),"native Next opens real restaurant menu")
	var menu:Node=UI.shown(game,"res://scripts/fireside_menu.gd")
	check(menu!=null and menu.life.station.id=="home.barbecue" and not UI.descendants(menu).any(func(n):return n is SpinBox),"menu preserves exact station and has no quantity selector")
	check(w.work.jobs.is_empty() and w.actors.human==human,"waiting in menu is not permission for human or guest work")
	menu.queue_free();await process_frame
	check(BBQ.meal(w,"single:mushroom",["human","codex","companion-2","npc.mira","npc.nora"]),"host explicit real fire operations feed five actual people")
	var facts:Array=w.read_memories("human",{"kind":"shared_barbecue"}).memories
	check(facts.size()==1 and facts[0].participants.size()==5,"exactly five actual eaters committed to one event")
	check(w.work.jobs.is_empty() and w.work.claims.is_empty() and w.life.station.portions==0,"finished gathering leaves no duplicate jobs claims or leftovers")
	var count:int=w.memories.records.size();w.life.fireside.end_circle("old UI request");w.memories.sync()
	check(w.memories.records.size()==count,"stale old UI end cannot duplicate history")
	for size in [Vector2i(1280,800),Vector2i(960,640)]:
		root.size=size;game._invite_barbecue("moon.barbecue");await process_frame;await process_frame
		invitation=UI.shown(game,"res://scripts/fireside_invitation.gd");invitation.fit()
		check(Rect2(Vector2.ZERO,Vector2(size)).encloses(Rect2(Vector2(invitation.position),Vector2(invitation.size))),"actual replacement invite panel fits "+str(size))
		invitation.queue_free();await process_frame
	check(game.links.values().all(func(link):return link._pid<=0),"engine invite/roast/eat phases produce no model messages")
	game.queue_free();await process_frame;print("Shared activity controller v4: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)

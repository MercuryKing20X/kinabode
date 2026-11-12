extends SceneTree
## Integration/UI — production/evidence/barbecue-v4 — BLOCKING question/actor/material barriers.
const F=preload("res://tests/cooking_fixture.gd")
const BBQ=preload("res://tests/barbecue_fixture.gd")
const UI=preload("res://tests/barbecue_ui_fixture.gd")
class FakeAdapter extends "res://scripts/companion_link.gd":
	var sent:Array=[]
	func _start()->bool:return true
	func _send(message:Dictionary)->bool:sent.append(message.duplicate(true));return true
var checks:=0
var failed:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failed=true;push_error(label)
func _initialize()->void:call_deferred("run")
func run()->void:
	assert(OS.get_environment("HABITAT_DATA_DIR").contains("youqi-test-"));var game:Node=UI.init_game(self);var w:RefCounted=game.world
	# Model-only question/proposal fixtures explicitly install the optional controller; identity remains local.
	game.world.director.set_controller("codex","model")
	check(not game.get_property_list().any(func(p):return p.name=="cooking_panel") and not game.action_dock.has_signal("cooking_requested"),"independent cooking panel and action signal removed")
	var people:Dictionary=w.actors.duplicate(true);var raw:int=F.amount(w,"turnip")
	game._show_barbecue_menu();await process_frame;await process_frame
	check(w.actors==people and w.work.jobs.is_empty() and F.amount(w,"turnip")==raw,"opening replacement panel controls nobody and takes no resource")
	var panel:Node=UI.shown(game,"res://scripts/fireside_panel.gd");panel.queue_free();await process_frame
	check(F.amount(w,"turnip")>=3 and BBQ.approach(w),"real configured crop stock and explicit host approach")
	game._show_barbecue_menu("home.barbecue");await process_frame;await process_frame;panel=UI.shown(game,"res://scripts/fireside_panel.gd")
	check(await UI.click(self,panel.light_button),"native input lights actual camp")
	check(await UI.click(self,panel.roast_button),"native barbecue input opens invitation")
	var invitation:Node=UI.shown(game,"res://scripts/fireside_invitation.gd")
	check(await UI.click(self,invitation.checks.codex) and await UI.click(self,invitation.get_ok_button()),"native single-guest and Next inputs select exact diner")
	var menu:Node=UI.shown(game,"res://scripts/fireside_menu.gd");var soup:int=menu.choices.find_custom(func(c):return c.id=="recipe:turnip-soup")
	menu.scroll.scroll_vertical=int(menu.cards[soup].get_global_rect().position.y-menu.scroll.get_global_rect().position.y)+menu.scroll.scroll_vertical
	await process_frame;await process_frame
	var choose:Button=UI.descendants(menu.cards[soup]).filter(func(n):return n is Button)[0]
	check(await UI.click(self,choose) and menu.selected==soup,"native recipe-card input selects original soup in barbecue menu")
	raw=F.amount(w,"turnip");check(await UI.click(self,menu.start_button),"native start input commits actual recipe")
	check(F.amount(w,"turnip")==raw-3 and w.life.fireside.state.current.receipt.turnip==3,"actual UI debits exact original crop cost")
	for tick in range(1000):
		w.advance(.1)
		if w.life.fireside.jobs.has("codex"):break
	check(w.life.fireside.jobs.has("codex"),"real selected participant has owned arrival task")
	game._ensure_link("codex");game.link=game.links.codex
	game._bound_companion_event({"kind":"question","id":"barbecue-question","text":"先等等吗？","choices":["等等"]},"codex")
	check(not w.life.fireside.jobs.has("codex") and not w.work.jobs.has("codex") and w.work.claims.is_empty(),"bound question releases exact real gathering jobs and claims")
	check(game.chat.visible and F.amount(w,"turnip")==raw-3 and w.life.fireside.state.current.eaten+w.life.fireside.state.current.wasted==3,"question takes dialogue priority and conserves consumed recipe without leftover food")
	check(not w.life.fireside.invite(["codex"]).ok or w.life.fireside.held("codex"),"pending question prevents actual guest work")
	game._cancel_resident_turn("codex");game.chat.hide();game.chat_input.release_focus()
	check(F.serve(w,"turnip-soup") and F.eat(w,"human") and F.eat(w,"codex") and F.cleanup(w),"explicit new host choice cooks another actual batch after question")
	check(w.read_memories("human",{"kind":"shared_barbecue"}).total==1,"only completed real dinner becomes canonical shared experience")
	check(w.command("companion-2",{"intent":"chop","target_id":"home.tree.01"}).ok,"unrelated accepted guest work begins")
	var owned:String=w.work.jobs["companion-2"].id;var host:Dictionary=w.actors.human.duplicate(true)
	check(not w.life.fireside.invite(["companion-2"]).ok and w.work.jobs["companion-2"].id==owned and w.actors.human==host,"invitation cannot steal accepted work or act as human")
	w.life.fireside.end_circle("stale UI close");check(w.work.jobs["companion-2"].id==owned,"stale circle close cannot cancel unrelated work")
	check(game.links.values().all(func(link):return link._pid<=0),"all controller transitions use fake adapters and zero real model processes")
	game.queue_free();await process_frame;print("Cooking controller merged v4: %s checks, failed=%s"%[checks,failed]);quit(1 if failed else 0)

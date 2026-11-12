extends RefCounted
const LocalText=preload("res://scripts/localization.gd")
## Host routing over the original private channel and generation/cancel barriers.
var _owner: WeakRef
var game: Node:
	get:return _owner.get_ref()
var leases: Dictionary={}
var revoked: Array=[]
func setup(owner_node: Node) -> void:_owner=weakref(owner_node)
func retire(id: String) -> void:
	if not leases.has(id):return
	revoked.append(leases[id].key);leases.erase(id)
	if revoked.size()>64:revoked.pop_front()
func valid(id: String,event: Dictionary) -> bool:
	if not leases.has(id) or not game._valid_link(game.links,id):return false
	var link: Node=game.links[id];var lease: Dictionary=leases[id]
	return not link._cancelling and link._generation==lease.generation and event.get("turn_key")==lease.key and link.turn_key==lease.key
func stale(id: String,event: Dictionary) -> bool:
	return str(event.get("turn_key","")) in revoked or (leases.has(id) and event.get("kind") in ["action","assistant","edit_work"] and not valid(id,event))
func send(id: String,site: String,text: String,purpose: String) -> bool:
	var match_state: Dictionary=game.world.gomoku.sessions.get(site,{})
	if match_state.is_empty() or id not in game.world.gomoku.players(match_state) or not game.world.director.model_controlled(id) or game._resident_chat_busy(id):return false
	game._ensure_link(id)
	var link: Node=game.links[id];var before: int=link._generation
	game._send_direct(id,text)
	if link._generation==before:return false
	leases[id]={"key":link.turn_key,"generation":link._generation,"match_id":match_state.id,"site_id":site,"purpose":purpose,"accepted":false}
	game.chat.hide();game.chat_input.release_focus()
	return true
func request(id: String,site: String) -> bool:
	var g: Dictionary=game.world.gomoku.sessions.get(site,{})
	if g.get("phase")!="playing" or game.world.gomoku._turn(g)!=id or game.world.gomoku.source_for(g,id)!="model":return false
	return send(id,site,LocalText.text("ui.gomoku_dialogue_host.it_is_your_turn_look_at_our_gomoku_game")+str(game.world.leisure.sites[site].name)+LocalText.text("ui.gomoku_dialogue_host.and_play_only_this_turn_s_move_you_may"),"step")
func chat(site: String,text: String) -> bool:
	var g: Dictionary=game.world.gomoku.sessions.get(site,{})
	if g.is_empty() or "human" not in game.world.gomoku.players(g) or g.mode!="model" or g.phase!="playing":return false
	return send(game.world.gomoku.companion.opponent(g),site,text,"chat")
func guard(id: String,event: Dictionary) -> Dictionary:
	if not leases.has(id):return {}
	if not valid(id,event):return {"ok":false,"error":"stale_chess_dialogue"}
	var lease: Dictionary=leases[id];var args: Dictionary=event.get("command",{})
	if args.get("intent")=="gomoku_read":return {}
	if lease.purpose=="chat":return {"ok":false,"error":"chess_chat_cannot_act"}
	if lease.accepted or args.get("intent")!="gomoku_move" or args.get("site_id")!=lease.site_id or args.get("match_id")!=lease.match_id:return {"ok":false,"error":"one_chess_step_only"}
	return {}
func accepted(id: String,event: Dictionary,result: Dictionary) -> void:
	if not result.get("ok",false) or event.get("command",{}).get("intent")!="gomoku_move":return
	if leases.has(id):leases[id].accepted=true
	var args: Dictionary=event.command
	if not str(args.get("speech","")).is_empty():
		game.view.say(args.speech,"model",id)
		game._record_chat("direct:"+id,id,args.speech,"message")
func assistant(id: String,event: Dictionary) -> bool:
	if not leases.has(id):return false
	if not valid(id,event):return true
	var lease: Dictionary=leases[id]
	if lease.purpose=="chat":
		var g: Dictionary=game.world.gomoku.sessions.get(lease.site_id,{})
		if g.get("id")==lease.match_id and g.phase=="playing":
			game.world.gomoku.companion.model_speech(g,id,str(event.text).left(30))
			game.view.say(str(event.text).left(30),"model",id)
	return true # Step speech is attached only to an accepted move; never imply failed moves completed.
func event(id: String,event: Dictionary) -> void:
	if event.get("kind")=="state" and event.get("state") in ["ready","cancelled","error","disconnected"] and event.get("turnComplete",true):retire(id)

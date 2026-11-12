extends RefCounted
## Read-only presentation facts reconstructed from the canonical move record.
const Rules=preload("res://scripts/jieqi_rules.gd")
const Text=preload("res://scripts/localization.gd")
static func jieqi(seed_value:int,history:Array,mode:String="standard")->Dictionary:
	var state:Dictionary=Rules.initial(seed_value,mode)
	var captures:Array=[]
	var moments:Array=[]
	for index in history.size():
		var move:Array=history[index];var a:int=int(move[0]);var b:int=int(move[1])
		var actor:int=int(state.turn)
		var victim:Variant=state.board[b]
		var moving:Dictionary=state.board[a]
		var next:Dictionary=Rules.move(state,a,b)
		if next.is_empty():return {}
		if victim!=null:
			var color:int=int(victim.get("true_side",victim.side))
			captures.append({"capturer":actor,"side":color,"kind":str(victim.kind),"own":color==actor,"hand":index+1,"from":b})
			moments.append({"kind":"capture","piece":str(victim.kind),"hand":index+1,"score":100 if victim.kind=="K" else 40 if moving.kind=="S" else 20})
		if moving.hidden and next.board[b].side!=actor:
			moments.append({"kind":"opposite","piece":str(next.board[b].kind),"hand":index+1,"score":60})
		state=next
	var dramatic:Dictionary={}
	for moment in moments:
		if dramatic.is_empty() or int(moment.score)>=int(dramatic.score):dramatic=moment
	var decisive:Array=[]
	if not history.is_empty():decisive=history[-1].duplicate()
	if state.winner!=0:
		for at in range(90):
			if state.board[at]!=null and not state.board[at].hidden and state.board[at].kind=="K" and state.board[at].side!=state.winner:decisive.append(at)
	return {"captures":captures,"moments":moments,"dramatic":dramatic,"decisive":decisive,"moves":history.size(),"state":state}
static func summary(facts:Dictionary)->String:
	var mine:int=0;var hers:int=0
	for piece in facts.get("captures",[]):
		if piece.capturer==1:mine+=1
		else:hers+=1
	var result:String=Text.text("chess.summary.counts")%[int(facts.get("moves",0)),mine,hers]
	var moment:Dictionary=facts.get("dramatic",{})
	if not moment.is_empty():
		var piece:String=Text.content(Text.source("jieqi.piece."+str(moment.piece)))
		if TranslationServer.get_locale().begins_with("en"):piece=Text.text("chess.summary.piece."+str(moment.piece))
		result+="\n"+Text.text("chess.summary."+str(moment.kind))%[int(moment.hand),piece]
	return result

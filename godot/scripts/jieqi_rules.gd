class_name JieqiRules
extends RefCounted
const BACK := ["R","H","E","A","K","A","E","H","R"]
static func initial(seed_value: int, mode: String="standard", legacy: bool=false) -> Dictionary:
	var rng := RandomNumberGenerator.new(); rng.seed = seed_value
	var board: Array = []; board.resize(90); board.fill(null)
	for side in [1,2]:
		var slots: Array = []
		var identities: Array = []
		for x in range(9):
			if x != 4: slots.append([x,0 if side==2 else 9,BACK[x]]); identities.append(BACK[x])
		for x in [1,7]: slots.append([x,2 if side==2 else 7,"C"]); identities.append("C")
		for x in [0,2,4,6,8]: slots.append([x,3 if side==2 else 6,"S"]); identities.append("S")
		for i in range(identities.size()-1,0,-1):
			var j := rng.randi_range(0,i); var swap: String = identities[i]; identities[i]=identities[j]; identities[j]=swap
		for i in range(slots.size()):
			var p: Array = slots[i]; board[p[1]*9+p[0]]={"side":side,"kind":identities[i],"cover":p[2],"hidden":true}
		board[(0 if side==2 else 9)*9+4]={"side":side,"kind":"K","cover":"K","hidden":false}
	if mode=="chaos":
		var positions: Array=[]; var identities: Array=[]
		for i in range(90):
			if board[i]!=null and board[i].hidden:
				positions.append(i); identities.append({"kind":board[i].kind,"side":board[i].side})
		for i in range(identities.size()-1,0,-1):
			var j:=rng.randi_range(0,i); var swap: Dictionary=identities[i]; identities[i]=identities[j]; identities[j]=swap
		for i in range(positions.size()):
			board[positions[i]].kind=identities[i].kind; board[positions[i]].true_side=identities[i].side
	var state := {"seed":seed_value,"mode":mode,"board":board,"turn":1,"history":[],"captured":[],"quiet":0,"winner":0,"draw":false,"repetitions":{}}
	if legacy:state["legacy_chaos"]=true;state["extra_turn"]=false
	state.repetitions[key(state)] = 1
	return state
static func integer(value: Variant,low: int,high: int) -> bool:
	return (value is int or value is float) and is_finite(value) and value==floor(value) and value>=low and value<=high
static func inside(p: int) -> bool: return p>=0 and p<90
static func identity(piece: Dictionary) -> String: return piece.cover if piece.hidden else piece.kind
static func pseudo(board: Array, a: int, b: int) -> bool:
	if not inside(a) or not inside(b) or a==b or board[a]==null: return false
	var piece: Dictionary=board[a]
	if board[b]!=null and board[b].side==piece.side:return false
	var ax:=a%9; var ay:=a/9; var bx:=b%9; var by:=b/9
	var dx:=absi(bx-ax); var dy:=absi(by-ay)
	var k:=identity(piece)
	if k=="H":return (dx==2 and dy==1 and board[ay*9+ax+signi(bx-ax)]==null) or (dx==1 and dy==2 and board[(ay+signi(by-ay))*9+ax]==null)
	if k=="E":return dx==2 and dy==2 and board[((ay+by)/2)*9+(ax+bx)/2]==null and (not piece.hidden or (by>=5 if piece.side==1 else by<=4))
	if k=="A":return dx==1 and dy==1 and (not piece.hidden or (bx>=3 and bx<=5 and (by>=7 if piece.side==1 else by<=2)))
	if k=="S":return (dx==0 and by-ay==(-1 if piece.side==1 else 1)) or (dy==0 and dx==1 and (ay<=4 if piece.side==1 else ay>=5))
	if k=="K":
		if board[b]!=null and board[b].kind=="K" and ax==bx:
			for y in range(mini(ay,by)+1,maxi(ay,by)):
				if board[y*9+ax]!=null:return false
			return true
		return dx+dy==1 and bx>=3 and bx<=5 and (by>=7 if piece.side==1 else by<=2)
	if k not in ["R","C"] or (ax!=bx and ay!=by):return false
	var blockers:=0
	var step: int=signi(bx-ax) if ay==by else signi(by-ay)*9
	var p:=a+step
	while p!=b:
		if board[p]!=null:blockers+=1
		p+=step
	return blockers==(1 if k=="C" and board[b]!=null else 0)
static func checked(board: Array,side: int) -> bool:
	var king: int=-1
	for i in range(90):
		if board[i]!=null and board[i].side==side and identity(board[i])=="K":king=i;break
	if king<0:return true
	for i in range(90):
		if board[i]!=null and board[i].side!=side and pseudo(board,i,king):return true
	return false
static func legal(board: Array,a: int,b: int,side: int) -> bool:
	if not inside(a) or board[a]==null or board[a].side!=side or not pseudo(board,a,b):return false
	# Legality of an unrevealed first move must not depend on its secret identity.
	var next:=board.duplicate(true);next[b]=next[a];next[a]=null
	return not checked(next,side)
static func legal_moves(state: Dictionary) -> Array:
	var result: Array=[]
	if state.get("winner",0)!=0 or state.get("draw",false):return result
	for a in range(90):
		if state.board[a]==null or state.board[a].side!=state.turn:continue
		for b in range(90):
			if legal(state.board,a,b,state.turn):result.append([a,b])
	return result
static func key(state: Dictionary) -> String:
	var tokens: Array=[str(state.turn),str(state.get("extra_turn",false))]
	for piece in state.board:
		tokens.append("." if piece==null else str(piece.side)+identity(piece)+(str(piece.cover) if piece.hidden else "!"))
	return "|".join(tokens)
static func move(state: Dictionary,a: int,b: int) -> Dictionary:
	if state.get("winner",0)!=0 or state.get("draw",false) or not legal(state.board,a,b,state.turn):return {}
	var next:=state.duplicate(true);var captured: Variant=next.board[b]
	if captured!=null:
		if captured.hidden and captured.has("true_side"):captured.side=captured.true_side;captured.erase("true_side")
		captured.hidden=false;next.captured.append(captured);next.quiet=0
	elif not state.get("extra_turn",false):next.quiet+=1
	next.board[b]=next.board[a];next.board[a]=null
	if next.board[b].hidden and next.board[b].has("true_side"):
		next.board[b].side=next.board[b].true_side;next.board[b].erase("true_side")
	next.board[b].hidden=false
	next.history.append([a,b]);next.turn=3-int(state.turn)
	if state.get("legacy_chaos",false):next.extra_turn=false
	if state.get("mode","standard")=="chaos" and next.board[b].side!=state.turn and checked(next.board,int(state.turn)):
		if state.get("legacy_chaos",false):next.turn=state.turn;next.extra_turn=true
		else:next.winner=3-int(state.turn);next["terminal_reason"]="chaos_selfcheck";next["selfcheck_kind"]=next.board[b].kind
	if next.winner==0 and captured!=null and captured.kind=="K":next.winner=state.turn
	if next.winner==0 and legal_moves(next).is_empty():next.winner=3-int(next.turn)
	var position:=key(next);next.repetitions[position]=int(next.repetitions.get(position,0))+1
	if next.winner==0 and (next.quiet>=120 or next.repetitions[position]>=3):next.draw=true
	return next
static func public_state(state: Dictionary) -> Dictionary:
	var copy:=state.duplicate(true)
	for piece in copy.board:
		if piece!=null and piece.hidden:piece.kind="?";piece.erase("true_side")
	return copy
static func replay(seed_value: int,history: Variant,mode: String="standard",legacy: bool=false) -> Dictionary:
	if not history is Array or history.size()>4096:return {}
	if mode not in ["standard","chaos"]:return {}
	var state:=initial(seed_value,mode,legacy)
	for entry in history:
		if not entry is Array or entry.size()!=2:return {}
		for value in entry:
			if not (value is int or value is float) or not is_finite(value) or value!=floor(value) or value<0 or value>=90:return {}
		state=move(state,int(entry[0]),int(entry[1]))
		if state.is_empty():return {}
	return state

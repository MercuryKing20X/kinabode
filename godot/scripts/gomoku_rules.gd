class_name GomokuRules
extends RefCounted
const SIZE:=15
const DIRECTIONS: Array[Vector2i]=[Vector2i(1,0),Vector2i(0,1),Vector2i(1,1),Vector2i(1,-1)]
static func integer(value: Variant,low: int,high: int) -> bool:
	return (value is int or value is float) and is_finite(value) and value==floor(value) and value>=low and value<=high
static func inside(p: Vector2i) -> bool:return p.x>=0 and p.y>=0 and p.x<SIZE and p.y<SIZE
static func cell(board: Array,p: Vector2i) -> int:return int(board[p.y*SIZE+p.x]) if inside(p) else -1
static func line(board: Array,p: Vector2i) -> Array:
	var color:=cell(board,p)
	if color<1:return []
	for direction in DIRECTIONS:
		var points: Array=[[p.x,p.y]]
		for side in [-1,1]:
			var next: Vector2i=p+direction*side
			while cell(board,next)==color:
				points.append([next.x,next.y]);next+=direction*side
		if points.size()>=5:return points
	return []
static func replay(history: Variant) -> Dictionary:
	if not history is Array or history.size()>SIZE*SIZE:return {}
	var board: Array=[];board.resize(SIZE*SIZE);board.fill(0)
	var winning: Array=[];var winner:=0
	for index in range(history.size()):
		var move: Variant=history[index]
		if winner!=0 or not move is Array or move.size()!=2 or not integer(move[0],0,14) or not integer(move[1],0,14):return {}
		var p:=Vector2i(move[0],move[1]);var slot:=p.y*SIZE+p.x
		if board[slot]!=0:return {}
		board[slot]=1+index%2;winning=line(board,p)
		if not winning.is_empty():winner=1+index%2
	return {"board":board,"winner":winner,"line":winning,"draw":winner==0 and history.size()==SIZE*SIZE}
static func candidates(board: Array) -> Array[Vector2i]:
	var found: Dictionary={}
	for index in range(board.size()):
		if board[index]==0:continue
		var origin:=Vector2i(index%SIZE,index/SIZE)
		for y in range(-2,3):
			for x in range(-2,3):
				var p:=origin+Vector2i(x,y)
				if inside(p) and cell(board,p)==0:found[p]=true
	var result: Array[Vector2i]=[]
	for p in found:result.append(p)
	if result.is_empty() and cell(board,Vector2i(7,7))==0:result.append(Vector2i(7,7))
	return result
static func patterns(board: Array,p: Vector2i,color: int) -> Array:
	var result: Array=[]
	value(board,p,color,result)
	return result
static func value(board: Array,p: Vector2i,color: int,details: Variant=null) -> int:
	var total:=0
	for direction in DIRECTIONS:
		var count:=1;var open:=0
		for side in [-1,1]:
			var next: Vector2i=p+direction*side
			while cell(board,next)==color:count+=1;next+=direction*side
			if cell(board,next)==0:open+=1
		if details!=null:details.append({"count":count,"open":open})
		if count>=5:total+=1000000
		elif count==4:total+=25000 if open==2 else 6000 if open==1 else 0
		elif count==3:total+=2200 if open==2 else 300 if open==1 else 0
		elif count==2:total+=180 if open==2 else 30 if open==1 else 0
		elif open==2:total+=8
	return total
static func ranked(board: Array,color: int) -> Array:
	var result: Array=[]
	for p in candidates(board):
		var attack:=value(board,p,color);var defense:=value(board,p,3-color)
		result.append({"p":p,"attack":attack,"defense":defense,"score":attack+defense*.95-(p-Vector2i(7,7)).length_squared()*.05})
	result.sort_custom(func(a,b):return a.score>b.score or (a.score==b.score and a.p.y*15+a.p.x<b.p.y*15+b.p.x))
	return result
static func choose(board: Array,color: int,difficulty: String,config: Dictionary,rng: RandomNumberGenerator) -> Vector2i:
	var started:=Time.get_ticks_usec()
	var options:=ranked(board,color)
	if options.is_empty():return Vector2i(-1,-1)
	for option in options:
		if option.attack>=1000000:return option.p
	for option in options:
		if option.defense>=1000000:return option.p
	if difficulty=="easy":return options[rng.randi_range(0,mini(2,options.size()-1))].p
	var best: Vector2i=options[0].p;var score: float=-INF
	for option in options.slice(0,mini(int(config.root_limit),int(config.candidate_limit))):
		if Time.get_ticks_usec()-started>float(config.search_ms)*1000:break
		var p: Vector2i=option.p;var index:=p.y*15+p.x
		board[index]=color
		var replies:=ranked(board,3-color);var danger:=0.0
		for reply in replies.slice(0,int(config.reply_limit)):danger=maxf(danger,float(reply.attack))
		board[index]=0
		var candidate: float=option.score-danger*.8
		if candidate>score:score=candidate;best=p
	return best

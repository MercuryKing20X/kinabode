extends RefCounted
const Rules=preload("res://scripts/jieqi_rules.gd")
const VALUES={"K":10000,"R":9,"H":4,"C":5,"E":2,"A":2,"S":1,"?":2}
static func choose(visible: Dictionary,profile: Dictionary,seed_value: int) -> Array:
	var rng:=RandomNumberGenerator.new();rng.seed=seed_value
	var options:=Rules.legal_moves(visible)
	if options.is_empty():return []
	if rng.randf()<float(profile.get("random",0.35)):return options[rng.randi_range(0,options.size()-1)]
	var best: Array=[];var score: float=-INF
	for option in options:
		var a: int=option[0];var b: int=option[1];var piece: Dictionary=visible.board[a];var victim: Variant=visible.board[b]
		var current: float=rng.randf()*0.2
		if victim!=null:current+=float(VALUES.get(victim.kind,2))*float(profile.get("capture",1.0))
		if piece.hidden:current+=float(profile.get("reveal",0.7))
		# Evaluate only this move's visible exposure, never an opponent reply tree.
		var placed: Array=visible.board.duplicate(true);placed[b]=placed[a];placed[a]=null
		var exposed:=false
		for enemy in range(90):
			if placed[enemy]!=null and placed[enemy].side!=visible.turn and Rules.pseudo(placed,enemy,b):exposed=true;break
		if exposed:current-=float(VALUES.get(piece.kind,2))*float(profile.get("safety",0.0))
		var king: int=-1
		for index in range(90):
			if placed[index]!=null and placed[index].side==visible.turn and Rules.identity(placed[index])=="K":king=index;break
		if king>=0:
			var old_distance: int=absi(a%9-king%9)+absi(a/9-king/9)
			var new_distance: int=absi(b%9-king%9)+absi(b/9-king/9)
			current+=(old_distance-new_distance)*float(profile.get("guard",0.0))
		if victim!=null and float(VALUES.get(victim.kind,2))>=4 and rng.randf()<float(profile.get("big_chance",0.0)):current+=float(profile.get("big_bonus",0.0))
		current+=(a/9-b/9)*(1 if visible.turn==1 else -1)*float(profile.get("forward",0.1))
		if current>score:score=current;best=option
	return best

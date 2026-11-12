class_name LeisureRules
extends RefCounted
static func integer(n: Variant,low: int,high: int) -> bool:
	return (n is int or n is float) and is_finite(float(n)) and n==floor(n) and n>=low and n<=high
static func pair(p: Variant) -> bool:
	return p is Array and p.size()==2 and p.all(func(n):return (n is int or n is float) and is_finite(float(n)))
static func valid(config: Variant) -> bool:
	if not config is Dictionary or not integer(config.get("width"),3,12) or not integer(config.get("depth"),3,10):return false
	if config.get("behavior") not in ["swing","sit","dance"] or not integer(config.get("seconds"),5,300):return false
	if config.has("game") and (config.game!="gomoku" or config.behavior!="sit" or not config.get("slots") is Array or config.slots.size()!=2):return false
	if config.has("board_rect") and (not config.board_rect is Array or config.board_rect.size()!=4 or not config.board_rect.all(func(value):return integer(value,0,256)) or config.board_rect[2]<14 or config.board_rect[3]<14):return false
	if not pair(config.get("entry")) or not config.get("slots") is Array or config.slots.is_empty() or config.slots.size()>8:return false
	if not config.get("obstacles") is Array or config.obstacles.size()>16:return false
	for p in config.slots+[config.entry]:
		if not pair(p) or absf(p[0])>float(config.width)/2 or absf(p[1])>float(config.depth)/2:return false
	for i in range(config.slots.size()):
		for j in range(i):
			if Vector2(config.slots[i][0],config.slots[i][1]).distance_to(Vector2(config.slots[j][0],config.slots[j][1]))<1.2:return false
	for box in config.obstacles:
		if not box is Array or box.size()!=4 or not box.all(func(n):return (n is int or n is float) and is_finite(float(n))):return false
		var rect:=Rect2(box[0],box[1],box[2],box[3])
		if rect.size.x<=0 or rect.size.y<=0 or not Rect2(-float(config.width)/2,-float(config.depth)/2,config.width,config.depth).encloses(rect):return false
		for p in config.slots+[config.entry]:
			if rect.grow(.25).has_point(Vector2(p[0],p[1])):return false
	if config.has("rigs"):
		if not config.rigs is Array or config.rigs.size()>config.slots.size():return false
		for rig in config.rigs:
			if not rig is Dictionary or not pair(rig.get("pivot")) or not pair(rig.get("seat")) or not rig.get("rect") is Array or rig.rect.size()!=4:return false
			if not rig.rect.all(func(n):return integer(n,0,512)) or rig.rect[2]<=0 or rig.rect[3]<=0:return false
	# Use the same one-tile navigation resolution as WorldState. Reject enclosed slots.
	var grid:=AStarGrid2D.new()
	grid.region=Rect2i(-int(ceil(float(config.width)/2))-1,-int(ceil(float(config.depth)/2))-1,int(config.width)+4,int(config.depth)+4)
	grid.diagonal_mode=AStarGrid2D.DIAGONAL_MODE_NEVER;grid.update()
	for y in range(grid.region.position.y,grid.region.end.y):
		for x in range(grid.region.position.x,grid.region.end.x):
			for box in config.obstacles:
				if Rect2(box[0],box[1],box[2],box[3]).has_point(Vector2(x+.5,y+.5)):grid.set_point_solid(Vector2i(x,y),true);break
	var entry:=Vector2i(Vector2(config.entry[0],config.entry[1]).floor())
	if grid.is_point_solid(entry):return false
	for slot in config.slots:
		var target:=Vector2i(Vector2(slot[0],slot[1]).floor())
		if grid.is_point_solid(target) or grid.get_id_path(entry,target).is_empty():return false
	return true
static func cost(config: Dictionary) -> int:
	return int(ceil(float(config.width*config.depth)/3))+config.slots.size()*2+(8 if config.behavior=="swing" else 12 if config.behavior=="sit" else 4)

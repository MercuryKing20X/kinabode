extends RefCounted

# Attachment coordinates for the prop only. The retired composite atlas is never loaded.
static func hand(phase:float,right:bool,_appearance:String="",_facing:String="down")->Vector2:
	return Vector2(21 if right else -21,-34+sin(phase*TAU)*3)

extends SceneTree
var checks:=0
var failed:=false
func check(ok:bool,msg:String)->void:
	checks+=1
	if not ok:failed=true;push_error(msg)
func _initialize()->void:
	var audit:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://../production/evidence/barbecue-v2/B-direction-audit.json"))
	var lib:=preload("res://scripts/character_library.gd").new();lib.configure(OS.get_environment("HABITAT_DATA_DIR"))
	var motion:=preload("res://scripts/actor_motion.gd").new()
	for id in audit:
		var art:Dictionary=lib.artworks[id]
		for frame in audit[id].frames_sha256_int32le:
			var pixels:=PackedInt32Array()
			for layer in art.frames[frame]:pixels.append_array(PackedInt32Array(layer.pixels))
			var original_frame:String=frame
			if id=="ai-glm":
				var opposite:String=frame.replace("left","right") if frame.contains("left") else frame.replace("right","left")
				if opposite!=frame and audit[id].frames_sha256_int32le.has(opposite):original_frame=opposite
			check(digest(pixels.to_byte_array())==audit[id].frames_sha256_int32le[original_frame],"visually approved direction pixels "+id+" "+frame)
		for direction in ["down","left","right","up"]:
			var actor:Dictionary={"id":"probe","activity":"walking","region_id":"home","position":[10,10],"facing":direction,"carry":{}}
			var people:Dictionary={"probe":actor,"human":{"id":"human","region_id":"home","position":[11,10]}}
			motion.attend()
			for i in range(20):
				motion.advance(.05,{"probe":actor});var pose:Dictionary=motion.pose(actor,{},people)
				check(pose.frame.begins_with(direction+"_") and art.frames.has(pose.frame),"walking never replaced by idle attention "+id+" "+direction)
	print("Character directions: ",checks," checks, failed=",failed);quit(1 if failed else 0)

func digest(data:PackedByteArray)->String:
	var context:=HashingContext.new();context.start(HashingContext.HASH_SHA256);context.update(data);return context.finish().hex_encode()

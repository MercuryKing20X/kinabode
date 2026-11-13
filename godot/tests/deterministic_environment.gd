extends RefCounted
## Used only by the temporary source overlay created by the test runner.
## Noon keeps daily-budget probes away from midnight; simulations still advance
## ForestSystem.clock normally and explicitly crossed days still roll over.
static var streams:Dictionary={}
static func wall_time()->float:
	assert(OS.get_environment("HABITAT_TEST_SUITE")=="1" and OS.get_environment("HABITAT_DETERMINISTIC_TESTS")=="1")
	return 1794542400.0 # 2026-11-13 12:00 Asia/Shanghai.
static func stream(label:String)->RandomNumberGenerator:
	if not streams.has(label):
		var rng:=RandomNumberGenerator.new()
		rng.seed=int(OS.get_environment("HABITAT_TEST_SEED"))+absi(label.hash())
		streams[label]=rng
	return streams[label]
static func random_bytes(length:int,label:String)->PackedByteArray:
	var bytes:=PackedByteArray()
	for i in length:bytes.append(stream("crypto:"+label).randi_range(0,255))
	return bytes
static func seed_rng(rng:RandomNumberGenerator,label:String)->void:
	rng.seed=stream("rng:"+label).randi()
static func new_rng(label:String)->RandomNumberGenerator:
	var rng:=RandomNumberGenerator.new()
	seed_rng(rng,"new:"+label)
	return rng
static func global_rng()->RandomNumberGenerator:return stream("global")
static func global_seed(value:int)->void:global_rng().seed=value
static func time_zone()->Dictionary:return {"bias":480,"name":"Asia/Shanghai"}
static func system_date(utc:bool=false)->String:return Time.get_date_string_from_unix_time(int(wall_time())+(0 if utc else 28800))
static func system_datetime(utc:bool=false,use_space:bool=false)->String:return Time.get_datetime_string_from_unix_time(int(wall_time())+(0 if utc else 28800),use_space)

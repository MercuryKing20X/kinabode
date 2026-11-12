extends SceneTree
const Motion=preload("res://scripts/actor_motion.gd")
const Data=preload("res://scripts/intelligence_catalog.gd")
func _initialize()->void:
	var gait:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/gaits.json")).human
	for field in ["run_bounce","run_sway","run_lean","run_stretch","run_dust","run_frames_per_step"]:
		var bad:Dictionary=gait.duplicate();bad[field]=true;assert(not Data.valid_gait(bad))
		bad[field]=INF;assert(not Data.valid_gait(bad));bad[field]=-1;assert(not Data.valid_gait(bad))
	var m:=Motion.new();var actors:Dictionary={"fixture":{"id":"fixture","activity":"walking","facing":"right","carry":{}}}
	var moves:Dictionary={"fixture":{"moving":true,"distance":.125,"facing":"right","still_seconds":0}}
	var run:Dictionary={"fixture":true};var gaits:Dictionary={"fixture":gait}
	var columns:Dictionary={}
	for i in range(48):
		m.advance(.017 if i%2 else .2,actors,run,moves,gaits)
		columns[m.run_column("fixture",gait)]=true
		assert(is_equal_approx(m.states.fixture.step,(i+1)*4*gait.run_frames_per_step/96.0))
	assert(columns.size()==6,"running odometer cycles every authored column")
	var before:float=m.states.fixture.step;moves.fixture.distance=0
	m.advance(9,actors,run,moves,gaits);assert(m.states.fixture.step==before)
	moves.fixture.moving=false;m.advance(.01,actors,{},moves,gaits)
	assert(m.states.fixture.step==0)
	var pose:Dictionary=m.pose(actors.fixture,{},actors,{"motion":moves.fixture,"gait":gait})
	assert(pose.frame=="right_0" and pose.brake_dust>0)
	m.advance(.31,actors,{},moves,gaits);assert(m.run_transition("fixture").stop==0)
	print("Run v2: strict optional fields, unequal delta distance odometer, stationary and immediate standing/brake passed")
	quit()

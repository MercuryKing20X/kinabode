extends SceneTree
const System=preload("res://scripts/jieqi_system.gd")
const JieqiPanel=preload("res://scripts/jieqi_panel.gd")
const R=preload("res://scripts/jieqi_rules.gd")
const P=preload("res://scripts/jieqi_player.gd")
var failures:=0
func check(v: bool,s: String) -> void:
	if not v:failures+=1;push_error(s)
func _initialize() -> void:
	var s:=R.initial(42)
	check(s.board.filter(func(p):return p!=null).size()==32,"32 real pieces")
	check(s.board.filter(func(p):return p!=null and p.hidden).size()==30,"only kings are revealed")
	var moves:=R.legal_moves(s);check(not moves.is_empty(),"initial moves exist")
	var move: Array=moves[0];var n:=R.move(s,move[0],move[1]);check(not n.is_empty() and not n.board[move[1]].hidden,"first move reveals")
	check(R.replay(42,n.history).board==n.board,"seed history replay")
	var a:=R.public_state(s);var b:=s.duplicate(true)
	for piece in b.board:
		if piece!=null and piece.hidden:piece.kind="R"
	check(P.choose(a,{"random":0.3},99)==P.choose(R.public_state(b),{"random":0.3},99),"choice cannot inspect secrets")
	var profiles: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://content/jieqi.json")).profiles
	for profile_key in profiles:
		check(P.choose(a,profiles[profile_key],99)==P.choose(R.public_state(b),profiles[profile_key],99),"every profile cannot inspect secrets "+profile_key)
	var fixture:=R.initial(3)
	fixture.board.fill(null)
	fixture.board[85]={"side":1,"kind":"K","cover":"K","hidden":false}
	fixture.board[4]={"side":2,"kind":"K","cover":"K","hidden":false}
	fixture.board[49]={"side":1,"kind":"R","cover":"R","hidden":false}
	check(not R.legal(fixture.board,49,48,1),"cannot expose facing kings")
	fixture.board[4]=null;fixture.board[3]={"side":2,"kind":"K","cover":"K","hidden":false}
	fixture.board[49]={"side":1,"kind":"E","cover":"E","hidden":false}
	check(R.legal(fixture.board,49,29,1),"revealed elephant crosses river")
	fixture.board[49]={"side":1,"kind":"A","cover":"A","hidden":false}
	check(R.legal(fixture.board,49,39,1),"revealed advisor crosses river")
	fixture.board[49]={"side":1,"kind":"H","cover":"H","hidden":false}
	fixture.board[40]={"side":1,"kind":"S","cover":"S","hidden":false}
	check(not R.legal(fixture.board,49,30,1),"horse leg blocks")
	fixture.board[40]=null;fixture.board[49]={"side":1,"kind":"R","cover":"R","hidden":false}
	fixture.board[48]={"side":2,"kind":"C","cover":"A","hidden":true}
	var capture:=R.move(fixture,49,48)
	check(not capture.is_empty() and capture.captured[-1].kind=="C" and not capture.captured[-1].hidden,"captured hidden piece revealed")
	fixture.board[48]=null;fixture.quiet=119
	var draw:=R.move(fixture,49,50)
	check(draw.draw,"sixty rounds without capture draws")
	fixture.quiet=0;fixture.repetitions[R.key(draw)]=2
	check(R.move(fixture,49,50).draw,"third repetition draws")
	var checked:=R.initial(5);checked.board.fill(null)
	checked.board[85]={"side":1,"kind":"K","cover":"K","hidden":false}
	checked.board[3]={"side":2,"kind":"K","cover":"K","hidden":false}
	checked.board[76]={"side":2,"kind":"R","cover":"R","hidden":false}
	checked.board[72]={"side":1,"kind":"R","cover":"R","hidden":false}
	check(R.checked(checked.board,1) and not R.legal(checked.board,72,73,1),"must answer check")
	checked.board[76]=null
	checked.board[66]={"side":2,"kind":"R","cover":"R","hidden":false}
	checked.board[68]={"side":2,"kind":"R","cover":"R","hidden":false}
	checked.board[75]={"side":2,"kind":"R","cover":"R","hidden":false}
	checked.board[72]=null
	check(not R.checked(checked.board,1) and R.legal_moves(checked).is_empty(),"stalemate has no legal move")
	var horse:=R.initial(19)
	var first:=R.move(horse,82,63)
	check(not first.is_empty() and not first.board[63].hidden,"covered horse uses original horse slot then reveals")
	check(R.replay(19,first.history).board==first.board,"revealed identity survives replay")
	print("Jieqi rules failures: ",failures);quit(1 if failures else 0)

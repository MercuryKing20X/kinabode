extends Node
## AI plans use the same executor as a program connected to the island.
const CFG := "my-ai.cfg"
const GAP := 45000
const FIRST_CLI_SECONDS := 90
const LATER_CLI_SECONDS := 60
const HELPER_GRACE_MS := 3000
const CONNECTION_PROBE := "Reply with {\"ok\":true}"
const IDS := ["codex","companion-2","npc.mira","npc.nora"]
const PROVIDERS := {"codex":"Codex","claude":"Claude Code","api":"API","local":"Ollama"}
const Words = preload("res://scripts/localization.gd")
const Credentials = preload("res://scripts/api_credentials.gd")
const Personas = preload("res://scripts/persona_cards.gd")
var game:Node
var directory:String
var provider:=""
var residents:Array=[]
var rows:Dictionary={}
var check_at:=0
var generation:=0
var started:Dictionary={}
var follow_next:=false
const MAILBOX_POLL_MS:=250
var mailbox_reads:Dictionary={}
var retired_reads:Array[MailboxRead]=[]

class MailboxRead extends RefCounted:
	var task:int
	var result:Dictionary

	func read(path:String,pid:int)->void:
		var file:=FileAccess.open(path,FileAccess.READ)
		if file==null:
			if OS.is_process_running(pid):return
			file=FileAccess.open(path,FileAccess.READ)
			if file==null:
				result={"error":"exited"};return
		var value:Variant=JSON.parse_string(file.get_as_text()) if file.get_length()<=32768 else null
		result=value if value is Dictionary and not value.is_empty() else {"error":"exited"}

static func choice(path:String)->Dictionary:
	var cfg:=ConfigFile.new()
	cfg.load(path.path_join(CFG))
	var value:Variant=cfg.get_value("ai","residents",[])
	return {"provider":str(cfg.get_value("ai","provider","")),"residents":value if value is Array else []}

static func save_choice(path:String,source:String,ids:Array)->bool:
	var cfg:=ConfigFile.new()
	cfg.set_value("ai","provider",source)
	cfg.set_value("ai","residents",ids)
	var file:=path.path_join(CFG)
	return cfg.save(file+".tmp")==OK and DirAccess.rename_absolute(file+".tmp",file)==OK

func setup(host:Node)->void:
	game=host
	directory=host.data_dir
	generation=game.world.session_generation
	var saved:=choice(directory)
	apply(saved.provider,saved.residents)

func apply(source:String,ids:Array)->void:
	if source==provider and ids==residents and not rows.is_empty():
		retry();return
	for id in rows:
		cancel(id)
		if game.world.director.brains.has(id):
			var brain:RefCounted=game.world.director.brains[id]
			brain.island_plan_ready=Callable()
			if rows[id].get("owns_follow_exclusion",false):game.world.activities.default_follow_excluded.erase(id)
			if brain.current.get("origin")=="island_ai":brain.finish("interrupted","provider_changed")
	game.world_door.background.clear()
	rows.clear()
	provider=source if PROVIDERS.has(source) else ""
	residents=IDS.filter(func(id):return id in ids and game.world.director.brains.has(id)) if not provider.is_empty() else []
	for id in residents:
		started.erase(id)
		if game.world.director.model_controlled(id):
			if game.connection_pool!=null:game._simple_connection_action(id,"disconnect")
			else:game.world.director.set_controller(id,"local")
		if game.world_door.owners.has(id):game.world_door.release(game.world_door.owners[id])
		if game.world.activities.following.has(id) and not game.world.activities.explicit_selected.has(id):
			game.world.activities.release_follow(id)
		game.world_door.background[id]=weakref(self)
		rows[id]={"failures":0,"last":-1,"reason":"","error":"","events":[{"kind":"arrived"}],"receipt":{},"pending":{},"flight":{},"seen":game.world.flower_creation.creations.sequence,"hunger":game.world.hunger.rank(id)}
		if not game.world.activities.default_follow_excluded.has(id):
			game.world.activities.default_follow_excluded[id]=true
			rows[id].owns_follow_exclusion=true
		var brain:RefCounted=game.world.director.brains[id]
		brain.island_plan_ready=apply_pending.bind(id)
	follow_next=not residents.is_empty()

func notify(id:String,kind:String,data:Dictionary={})->bool:
	if not rows.has(id):return false
	var events:Array=rows[id].events
	events.append({"kind":kind,"data":data.duplicate(true)})
	if events.size()>8:events.pop_front()
	return true

static func python()->String:
	var configured:=OS.get_environment("HABITAT_PYTHON")
	if not configured.is_empty():return configured
	if OS.get_name()=="macOS":
		for path in ["/opt/homebrew/bin/python3","/usr/local/bin/python3","/usr/bin/python3"]:
			if FileAccess.file_exists(path):return path
	return "python" if OS.get_name()=="Windows" else "python3"

static func helper(base:String,kind:String,input:String="",first:bool=true)->Dictionary:
	var path:=ProjectSettings.globalize_path("res://../scripts/island_thinker.py").simplify_path()
	var bundled:="res://content/release/island_thinker.py"
	var needs_extraction:=OS.has_feature("template")
	if not FileAccess.file_exists(bundled if needs_extraction else path):return {}
	var mailbox:=base.path_join("ai-request-"+Crypto.new().generate_random_bytes(10).hex_encode())
	if DirAccess.make_dir_absolute(mailbox)!=OK:return {}
	if OS.get_name()!="Windows":
		if FileAccess.set_unix_permissions(mailbox,448)!=OK:
			DirAccess.remove_absolute(mailbox);return {}
	if needs_extraction:
		path=mailbox.path_join("island_thinker.py")
		var script:=FileAccess.open(path,FileAccess.WRITE)
		if script==null:
			DirAccess.remove_absolute(mailbox);return {}
		script.store_buffer(FileAccess.get_file_as_bytes(bundled));script.close()
	var file:=FileAccess.open(mailbox.path_join("input"),FileAccess.WRITE)
	if file==null:
		clear_helper({"path":mailbox});return {}
	file.store_string(input);file.close()
	var seconds:=5 if kind=="detect" else FIRST_CLI_SECONDS if first else LATER_CLI_SECONDS
	var job:={"pid":OS.create_process(python(),[path,kind,mailbox,"first" if first else "later"]),"path":mailbox,"deadline":Time.get_ticks_msec()+seconds*1000+HELPER_GRACE_MS}
	if job.pid<=0:
		clear_helper(job);return {}
	return job

static func poll(flight:Dictionary)->Dictionary:
	var read:=MailboxRead.new()
	read.read(flight.path.path_join("reply"),flight.pid)
	if read.result.is_empty() and Time.get_ticks_msec()>=int(flight.deadline):return {"error":"timeout"}
	return read.result

static func clear_helper(flight:Dictionary)->void:
	for name in ["input","reply","reply.tmp","island_thinker.py"]:
		DirAccess.remove_absolute(flight.path.path_join(name))
	DirAccess.remove_absolute(flight.path)

func send_prompt(id:String,row:Dictionary,now:int)->void:
	started[id]=now
	var scheduler:RefCounted=game.autonomy.scheduler
	var policy:Dictionary=scheduler.policy_for(id)
	var ledger:Dictionary=scheduler.usage(id)
	var reserve:int=policy.turn_tokens
	if reserve<=0 or ledger.times.size()>=policy.hourly or ledger.calls>=policy.daily or (int(policy.daily_tokens)>0 and int(ledger.tokens)+int(ledger.reserved)+reserve>int(policy.daily_tokens)) or (provider=="api" and game.connection_pool!=null and int(game.connection_pool.settings.get_value("openai","limit",10000000))>0 and game.connection_pool.api_tokens()>=int(game.connection_pool.settings.get_value("openai","limit",10000000))):
		if row.last<0:fail(id,row,"quota")
		else:row["budget_wait"]=true
		maybe_store_catch(id,row)
		return
	row.erase("budget_wait")
	var hour:float=scheduler.now()
	ledger.calls+=1;ledger.last_at=hour;ledger.times.append(hour);ledger.reserved+=reserve;ledger.unknown_turns+=1
	if not scheduler.preferences.save_accounting(id,ledger):fail(id,row,"quota");return
	row.charge={"day":ledger.day,"reserve":reserve,"at":hour}
	row.sent_events=row.events.duplicate(true)
	row.events.clear()
	var prompt:=context(id,row)
	if provider in ["api","local"]:
		send_http(id,row,prompt)
		return
	var bytes:=prompt.to_utf8_buffer()
	if bytes.size()>65536:finished(id,row,{"error":"input_too_large"});return
	var flight:=helper(directory,provider,prompt,row.last<0)
	if flight.is_empty():finished(id,row,{"error":"helper"});return
	row.flight=flight

func cancel(id:String)->void:
	var flight:Dictionary=rows[id].flight
	if flight.has("http"):
		flight.http.cancel_request()
		flight.http.queue_free()
	if flight.has("pid"):
		if mailbox_reads.has(id):retired_reads.append(mailbox_reads[id])
		mailbox_reads.erase(id)
		clear_helper(flight)
	rows[id].flight={}

func fail(id:String,row:Dictionary,code:String)->void:
	row.failures+=1
	row.error=code if ERROR_TEXT.has(code) else "unavailable"
	row.pending={}
	notify(id,"thinking_failed",{"reason":row.error})
	maybe_store_catch(id,row)

func maybe_store_catch(id:String,row:Dictionary)->void:
	var held:Dictionary=game.world.fishing.held(id)
	if held.is_empty() or row.get("own_catch","")!=held.id:return
	var brain:RefCounted=game.world.director.brains[id]
	if not can_apply(id,brain):return
	var result:Dictionary=game.world.fishing.host_stock_nearest(held.id)
	if result.ok:
		row.erase("own_catch")
		notify(id,"own_catch_stored",{"id":held.id})

func finished(id:String,row:Dictionary,value:Dictionary)->void:
	row.flight={}
	settle(id,row,value.get("usage",{}),value.get("error") in ["missing","helper","arguments","input_too_large","auth","invalid_key","model_missing","config","offline"])
	row.diagnostic={"exit_code":value.get("exit_code"),"stderr_summary":str(value.get("stderr_summary","")).left(96)}
	if value.has("error"):fail(id,row,str(value.error));return
	var plan:Variant=value.get("plan")
	if not plan is Dictionary or plan.size()!=2 or not preload("res://scripts/island_notes.gd").valid_text(plan.get("reason")) or not plan.get("steps") is Array:
		fail(id,row,"invalid_plan");return
	if game.world.director.brains[id].intention.basic.prepare(plan,"island_ai").has("error"):
		fail(id,row,"invalid_plan");return
	row.last=Time.get_ticks_msec()
	row.failures=0
	row.error=""
	row.erase("reconnecting")
	row.reason=plan.reason
	row.pending=plan

func settle(id:String,row:Dictionary,usage:Dictionary,unspent:bool)->void:
	var charge:Dictionary=row.get("charge",{})
	row.erase("charge")
	if charge.is_empty() or (usage.is_empty() and not unspent):return
	var scheduler:RefCounted=game.autonomy.scheduler
	var ledger:Dictionary=scheduler.usage(id)
	if charge.day!=ledger.day:return
	ledger.reserved=maxi(0,int(ledger.reserved)-int(charge.reserve))
	ledger.unknown_turns=maxi(0,int(ledger.unknown_turns)-1)
	if unspent:
		ledger.calls=maxi(0,int(ledger.calls)-1)
		ledger.times.erase(charge.at)
	else:
		ledger.tokens+=int(usage.total_tokens)
		ledger.input_tokens+=int(usage.prompt_tokens)
		ledger.output_tokens+=int(usage.completion_tokens)
	scheduler.preferences.save_accounting(id,ledger)

func _process(_delta:float)->void:
	for index in range(retired_reads.size()-1,-1,-1):
		var task:int=retired_reads[index].task
		if WorkerThreadPool.is_task_completed(task):
			WorkerThreadPool.wait_for_task_completion(task)
			retired_reads.remove_at(index)
	if rows.is_empty() or not is_instance_valid(game.world_door):return
	var now:=Time.get_ticks_msec()
	if generation!=game.world.session_generation:
		generation=game.world.session_generation
		var current:=provider
		provider=""
		apply(current,residents)
	if now<check_at:return
	check_at=now+100
	for id in rows:
		if not game.world.director.brains.has(id):continue
		var row:Dictionary=rows[id]
		var brain:RefCounted=game.world.director.brains[id]
		var hunger:int=game.world.hunger.rank(id)
		if hunger!=row.hunger:
			row.hunger=hunger;notify(id,"hunger_changed",{"rank":hunger})
		var changes:RefCounted=game.world.flower_creation.creations
		if row.seen!=changes.sequence:
			for entry in changes.changes.slice(-16):
				if entry.id>row.seen and entry.actor!=id and entry.region==game.world.actors[id].region_id and game.world.point(entry).distance_to(game.world.point(game.world.actors[id]))<=12:
					notify(id,"nearby_change",entry)
			row.seen=changes.sequence
		if row.flight.has("pid"):
			var f:Dictionary=row.flight
			var read:MailboxRead=mailbox_reads.get(id)
			if read!=null and WorkerThreadPool.is_task_completed(read.task):
				WorkerThreadPool.wait_for_task_completion(read.task)
				mailbox_reads.erase(id)
				if not read.result.is_empty():
					clear_helper(f)
					finished(id,row,read.result)
			elif read==null and now>=int(f.get("poll_at",0)):
				f.poll_at=now+MAILBOX_POLL_MS
				read=MailboxRead.new()
				read.task=WorkerThreadPool.add_task(read.read.bind(f.path.path_join("reply"),f.pid))
				mailbox_reads[id]=read
			if not row.flight.is_empty() and now>=int(f.deadline):
				cancel(id)
				finished(id,row,{"error":"timeout"})
		apply_pending(id)
		var initial:bool=row.last<0
		var ready:bool=initial or (now-int(started.get(id,-GAP))>=GAP and (row.get("reconnecting",false) or brain.eligible(true)))
		if row.flight.is_empty() and row.pending.is_empty() and not row.events.is_empty() and not row_disconnected(row) and ready:
			send_prompt(id,row,now)

func apply_pending(id:String)->bool:
	if not rows.has(id) or generation!=game.world.session_generation:return false
	var row:Dictionary=rows[id]
	if row.pending.is_empty():return false
	var brain:RefCounted=game.world.director.brains[id]
	if not can_apply(id,brain):return false
	var result:Dictionary=game.world_door.act(id,row.pending,"island_ai")
	if not result.ok:
		fail(id,row,"invalid_plan");return false
	var caught_before:String=game.world.fishing.held(id).get("id","")
	var tries_fishing:bool=row.pending.steps.any(func(step):return step.action=="fish")
	row.receipt={};row.pending={}
	var ref:WeakRef=weakref(self)
	brain.intention.basic.completed=func(outcome:Dictionary):
		var host:Node=ref.get_ref()
		if is_instance_valid(host) and is_same(host.rows.get(id),row):
			row.receipt=outcome
			if tries_fishing:
				var caught:String=host.game.world.fishing.held(id).get("id","")
				if not caught.is_empty() and caught!=caught_before:row.own_catch=caught
			host.notify(id,"action_finished",outcome)
	if follow_next:
		follow_next=false
		game._follow_world_door_resident(id)
	return true

func can_apply(id:String,brain:RefCounted)->bool:
	return brain.active() and brain.eligible(true) and not brain.busy() and not brain.current.has("basic_plan") and not brain.current.has("heart_guest") and not brain.current.has("ai_plan") and not brain.current.get("paired",false) and brain.intention.pending.is_empty() and (not game.world._routes.has(id) or brain.owns_local_route()) and not game.world.director.model_controlled(id)

func context(id:String,row:Dictionary)->String:
	var w:RefCounted=game.world
	var actor:Dictionary=w.actors[id]
	var around:Dictionary=game.world_door.surroundings(id)
	for person in around.people:
		person["doing"]=w.director.brains[person.id].current.get("action","") if w.director.brains.has(person.id) else w.work.jobs.get(person.id,{}).get("intent","")
	var play:Array=[]
	var build:Array=[]
	for site in w.leisure.sites.values():
		if site.region_id!=actor.region_id or w.standard.sites.has(site.id):continue
		var work:Dictionary=w.leisure.art(site)
		var recreation:Dictionary=work.get("recreation",{})
		if recreation.is_empty() or recreation.get("game")=="gomoku":continue
		var entry:={"id":site.id,"kind":site.template_id,"position":site.position,"distance":w.point(site).distance_to(w.point(actor))}
		if site.get("complete",false):play.append(entry)
		elif w.residents.supports(actor,"build_facility") and not w.resort.retired(site) and (not site.id.begins_with("play.moon.") or w.standard.ready("moon.lookout")):
			entry.wood=maxi(0,w.leisure.cost(site)-int(site.invested));build.append(entry)
	play.sort_custom(func(a,b):return a.distance<b.distance)
	build.sort_custom(func(a,b):return a.distance<b.distance)
	var language:="en" if TranslationServer.get_locale().begins_with("en") else "zh"
	var state:Dictionary={"name":Words.resident(w,id),"persona":Personas.card(id,language).get("text",""),"around":around,"actions":w.director.brains[id].intention.basic.card(),"warehouse":w.storage.saved().items,"hunger":w.hunger.summary(id),"mood":w.hearts.dominant(id),"project":w.flower_creation.creations.projects.get(id,""),"recent_memories":w.read_memories(id,{"limit":5}).get("memories",[]),"recent_changes":w.flower_creation.creations.changes.slice(-8),"catalog":w.flower_creation.creations.catalog(),"play_sites":play.slice(0,12),"build_sites":build.slice(0,8),"events":row.sent_events,"current_plan":row.reason,"language":language}
	if game.playground!=null and game.playground.kind.is_empty():
		var guests:Array=w.director.routines.keys().filter(func(guest):return guest!=id and game.playground.can_invite_guest(guest))
		if guests.size()>=2:
			state.actions.steps["invite_play"]=["game","guests"]
			state["group_play"]={"games":game.playground.GAMES.filter(func(kind):return kind!="rope" or guests.size()>=3),"guests":guests,"minimum_guests":2,"rope_minimum_guests":3}
	var prompt:="You are this resident, living your own life. Decide what you want to do. Alter the island with real warehouse materials; go play, explore or speak to nearby people. Vary what you do and follow up on real outcomes. You may only act as yourself. Never invent stock, targets or memories. Prefer nearby reachable targets. Use listed IDs and exact action shapes. fish can try the nearby shore; play_at uses a listed site; go_to then say can approach a person. No tools. Return only one JSON object with a short single-line reason in the chosen language and 1 to 6 steps, each containing action and its listed fields.\n"
	if state.has("group_play"):prompt=prompt.trim_suffix("\n")+" Use invite_play as the last step to invite listed available guests to a listed game, without the human.\n"
	return prompt+JSON.stringify(state)

func send_http(id:String,row:Dictionary,prompt:String)->void:
	if not OS.get_environment("HABITAT_THINKER_FAKE_DIR").is_empty():finished(id,row,{"error":"offline"});return
	var settings:=Credentials.read_settings(directory)
	var key:=Credentials.key(directory) if provider=="api" else ""
	var base:=Credentials.endpoint(OS.get_environment("HABITAT_OPENAI_BASE_URL") if not OS.get_environment("HABITAT_OPENAI_BASE_URL").is_empty() else str(settings.get_value("openai","base","https://api.openai.com/v1"))) if provider=="api" else "http://127.0.0.1:11434/v1"
	if base.is_empty() or (provider=="api" and (key.is_empty() or "\n" in key or "\r" in key)):
		finished(id,row,{"error":"auth"});return
	var model:=str(settings.get_value("openai","thinking","gpt-6.1-terra")) if provider=="api" else str(settings.get_value("openai","local_model","qwen2.5:3b"))
	var request:=HTTPRequest.new();add_child(request)
	request.timeout=40;request.body_size_limit=32768;request.max_redirects=0;request.use_threads=true
	row.flight={"http":request}
	request.request_completed.connect(func(status:int,code:int,_headers:PackedStringArray,body:PackedByteArray):
		request.queue_free()
		if rows.get(id,{})!=row:return
		if status!=HTTPRequest.RESULT_SUCCESS or code<200 or code>=300:
			finished(id,row,{"error":"timeout" if status==HTTPRequest.RESULT_TIMEOUT else "auth" if code in [401,403] else "network"});return
		var packet:Variant=JSON.parse_string(body.get_string_from_utf8())
		var choices:Variant=packet.get("choices",[]) if packet is Dictionary else []
		var first:Variant=choices[0] if choices is Array and not choices.is_empty() else {}
		var message:Variant=first.get("message",{}) if first is Dictionary else {}
		var line:Variant=message.get("content","") if message is Dictionary else ""
		var plan:Variant=JSON.parse_string(line) if line is String and (key.is_empty() or not line.contains(key)) else null
		var use:Variant=packet.get("usage",{}) if packet is Dictionary else {}
		var known:Dictionary={}
		if use is Dictionary and ["total_tokens","prompt_tokens","completion_tokens"].all(func(k):return game.world._integer(use.get(k)) and use[k]>=0) and use.total_tokens>=use.prompt_tokens+use.completion_tokens:known=use
		finished(id,row,{"plan":plan,"usage":known} if plan is Dictionary else {"error":"invalid_json","usage":known}))
	var headers:=PackedStringArray(["Content-Type: application/json"])
	if not key.is_empty():headers.append("Authorization: Bearer "+key)
	var data:=JSON.stringify({"model":model,"messages":[{"role":"user","content":prompt}],"stream":false,"max_tokens":1600})
	if request.request(base+"/chat/completions",headers,HTTPClient.METHOD_POST,data)!=OK:
		request.queue_free();finished(id,row,{"error":"network"})

func retry()->void:
	for id in rows:
		var row:Dictionary=rows[id]
		if not row_disconnected(row):continue
		row.failures=0
		row.error=""
		row.reconnecting=true
		notify(id,"reconnect")

const ERROR_TEXT := {
	"missing":["找不到命令","CLI not found"],
	"helper":["无法启动连接助手，请检查 Python 3","Couldn't start the connection helper. Check Python 3."],
	"arguments":["命令参数不被接受","CLI rejected its arguments"],
	"timeout":["等待超时","Timed out"],
	"invalid_json":["回复格式不对","Invalid reply format"],
	"exited":["连接进程意外退出","Connection process exited unexpectedly"],
	"invalid_plan":["打算不合规则","Plan rejected"],
	"auth":["未登录或登录已失效","Sign in to the provider"],
	"invalid_key":["服务商拒绝了 API 密钥","The provider rejected the API key"],
	"network":["连不上服务商","Could not reach the provider"],
	"model_missing":["服务商没有此模型","The provider does not offer this model"],
	"config":["无法安全读取 CLI 配置","Couldn't safely load the CLI configuration"],
	"quota":["额度已用完","Quota reached"],
	"input_too_large":["岛上状态太长","Island context is too large"],
	"unavailable":["暂不可用","Unavailable"],
}

static func error_text(code:String)->String:
	return ERROR_TEXT.get(code,ERROR_TEXT.unavailable)[int(TranslationServer.get_locale().begins_with("en"))]

const CODEX_RECOVERY := {
	"auth":["在终端运行 codex login；自定义服务商请检查其认证配置。","Run codex login in Terminal, or check your custom provider’s credentials."],
	"invalid_key":["检查 Codex 的服务商密钥，修正后点重接。","Check your Codex provider’s API key, then reconnect."],
	"network":["检查服务商地址、网络和代理，再点重接。","Check the provider address, network and proxy, then reconnect."],
	"model_missing":["在 Codex 配置中选一个服务商可用的模型，再点重接。","Choose a model available from your Codex provider, then reconnect."],
	"timeout":["检查服务商是否可用，或换一个响应更快的模型后重接。","Check provider availability or choose a faster model, then reconnect."],
}

static func recovery_text(source:String,code:String)->String:
	var en:=int(TranslationServer.get_locale().begins_with("en"))
	if source=="claude" and code=="auth":
		return ["Claude 命令行还没登录：打开终端运行 claude，按提示登录后点重接","Claude CLI isn't signed in: run claude in Terminal, follow the sign-in prompts, then reconnect."][en]
	return CODEX_RECOVERY.get(code,["",""])[en] if source=="codex" else ""

func connection_error()->String:
	for row in rows.values():
		if row_disconnected(row):return row.error
	return ""

static func row_disconnected(row:Dictionary)->bool:
	return row.failures>=3 or (row.last<0 and row.failures>0)

func disconnected()->bool:
	return rows.values().any(row_disconnected)

func status_text(full:bool=false)->String:
	var en:=TranslationServer.get_locale().begins_with("en")
	if rows.is_empty():
		var visitors:=PackedStringArray()
		for id in game.world_door.owners:
			if not game.world.actors.has(id):continue
			visitors.append(("Living here" if en else "住着")+" · "+str(game.world.actors[id].get("world_door_client",""))+" · "+Words.resident(game.world,id))
		if not visitors.is_empty():return "\n".join(visitors) if full else visitors[0]+(" +"+str(visitors.size()-1) if visitors.size()>1 else "")
		return "Not connected" if en else "没接"
	var lines:=PackedStringArray()
	var displayed:Array=rows.keys()
	if not full:
		var broken:=displayed.filter(func(id):return row_disconnected(rows[id]))
		if not broken.is_empty():displayed=broken
	for id in displayed:
		var row:Dictionary=rows[id]
		var broken:=row_disconnected(row)
		var connecting:bool=row.last<0 or row.get("reconnecting",false)
		var status:String=("Disconnected" if en else "断了") if broken else ("Connecting" if en else "正在接") if connecting else ("Living here" if en else "住着")
		var detail:=status+(" · "+error_text(row.error) if broken else "")+(" · " if full else "\n")+str(PROVIDERS[provider])+" · "+Words.resident(game.world,id)
		if not broken and not connecting:
			var seconds:=maxi(0,(Time.get_ticks_msec()-int(row.last))/5000)*5
			detail+=" · "+("%ds ago" if en else "%d 秒前")%seconds
		if row.get("budget_wait",false):detail+=" · "+("Quota paused" if en else "额度暂停")
		if not row.flight.is_empty() and row.last>=0 and (full or row.reason.is_empty()):
			detail+=" · "+("Thinking" if en else "在想")
		if not row.reason.is_empty() and not broken and not connecting:
			detail+=" · "+str(row.reason).left(160 if full else 45)
		if full or lines.is_empty():lines.append(detail)
	if not full and rows.size()>1:lines[0]+=" +"+str(rows.size()-1)
	return "\n".join(lines)

func _exit_tree()->void:
	for id in rows:cancel(id)
	for read in retired_reads:WorkerThreadPool.wait_for_task_completion(read.task)
	retired_reads.clear()

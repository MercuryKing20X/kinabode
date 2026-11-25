extends PanelContainer

var game:Node
var door:Node
var body:VBoxContainer
var state:Label
var toggle:Button
var log_text:Label
var feedback:Label
var copies:VBoxContainer
var static_words:Dictionary={}
var advanced:VBoxContainer
var sources:OptionButton
var picks:Dictionary={}
var detection:Dictionary={}
var available:Dictionary={}
var summary:Label
var multi:Label
var move_in:Button
var retry_button:Button
var test_button:Button
var test_status:Label
var cli_timeout:Label
var recovery:Label
var auth_copy:Button
var test_job:Dictionary={}
var test_source:=""
var test_result:=""
var api_options:VBoxContainer
var api_base:LineEdit
var api_model:LineEdit
var api_key:LineEdit
var local_model:LineEdit
var next_status:=0
const Brain=preload("res://scripts/island_ai.gd")
const Text=preload("res://scripts/localization.gd")

static func phrase(zh:String,en:String)->String:
	return en if TranslationServer.get_locale().begins_with("en") else zh

static func title_text()->String:return phrase("我的 AI","My AI")

static func install(parent:Control,host:Node)->Control:
	var panel:Control=load("res://scripts/world_door_panel.gd").new()
	parent.add_child(panel);panel.setup(host)
	return panel

func button(parent:Control,words:String,callback:Callable)->Button:
	var item:=Button.new();item.text=words;item.focus_mode=Control.FOCUS_NONE;parent.add_child(item);item.pressed.connect(callback)
	return item

func label(parent:Control,words:String)->Label:
	var item:=Label.new();item.text=words;item.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(item);return item

func bind_text(item:Control,zh:String,en:String)->void:
	static_words[item]=[zh,en]
	item.text=phrase(zh,en)

func refresh_locale()->void:
	for item in static_words:
		item.text=phrase(static_words[item][0],static_words[item][1])
	refresh_sources()
	if feedback!=null:feedback.text=""
	refresh()

func setup(host:Node)->void:
	game=host;door=game.get("world_door") if game.get("island_ai")!=null else null
	name="MoveInPanel";z_index=135
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT);anchor_bottom=1
	offset_left=-580;offset_right=-16;offset_top=76;offset_bottom=-100
	var scroll:=ScrollContainer.new();scroll.horizontal_scroll_mode=ScrollContainer.SCROLL_MODE_DISABLED;add_child(scroll)
	body=VBoxContainer.new();body.size_flags_horizontal=Control.SIZE_EXPAND_FILL;scroll.add_child(body)
	var header:=HBoxContainer.new();body.add_child(header)
	var heading:=label(header,title_text());heading.size_flags_horizontal=Control.SIZE_EXPAND_FILL
	bind_text(heading,"我的 AI","My AI")
	bind_text(button(header,"",hide),"关闭","Close")
	var saved:=Brain.choice(game.data_dir)
	bind_text(label(body,""),"1. 选一个 AI","1. Choose an AI")
	sources=OptionButton.new();sources.name="MyAIProvider";body.add_child(sources)
	for id in Brain.PROVIDERS:
		sources.add_item(Brain.PROVIDERS[id]);sources.set_item_metadata(sources.item_count-1,id)
		if saved.provider==id:sources.select(sources.item_count-1)
	sources.item_selected.connect(func(_index):refresh_fields())
	var settings:=Brain.Credentials.read_settings(game.data_dir)
	api_options=VBoxContainer.new();body.add_child(api_options)
	api_base=LineEdit.new();api_base.text=str(settings.get_value("openai","base","https://api.openai.com/v1"));api_options.add_child(api_base)
	api_model=LineEdit.new();api_model.text=str(settings.get_value("openai","thinking","gpt-6.1-terra"));api_options.add_child(api_model)
	api_key=LineEdit.new();api_key.secret=true;api_options.add_child(api_key)
	local_model=LineEdit.new();local_model.text=str(settings.get_value("openai","local_model","qwen2.5:3b"));body.add_child(local_model)
	bind_text(label(body,""),"2. 选住在哪位居民身上","2. Choose residents")
	var choices:=HFlowContainer.new();body.add_child(choices)
	for id in Brain.IDS:
		if door!=null and not game.world.director.brains.has(id):continue
		var pick:=CheckBox.new();pick.name="MyAI_"+id;choices.add_child(pick)
		picks[id]=pick;pick.button_pressed=id in saved.residents or (saved.residents.is_empty() and id=="codex")
		pick.toggled.connect(func(_value):refresh_fields())
	multi=label(body,"")
	move_in=button(body,"",connect_ai);move_in.name="MyAIMoveIn";bind_text(move_in,"3. 住进来","3. Move in")
	summary=label(body,"")
	retry_button=button(body,"",func():
		game.island_ai.retry()
		summary.text=game.island_ai.status_text(true)
		retry_button.hide())
	retry_button.name="MyAIRetry";bind_text(retry_button,"重接","Reconnect")
	retry_button.hide()
	recovery=label(body,"");recovery.hide()
	auth_copy=button(body,"",func():DisplayServer.clipboard_set("claude"))
	auth_copy.name="MyAICopyClaudeLogin"
	bind_text(auth_copy,"复制登录命令","Copy sign-in command")
	auth_copy.hide()
	test_button=button(body,"",test_connection);test_button.name="MyAITestConnection"
	bind_text(test_button,"测试连接","Test connection")
	test_status=label(body,"");test_status.name="MyAITestResult"
	cli_timeout=label(body,"")
	var timeout_words:=["首次连接和测试最多等 %d 秒，之后每次最多 %d 秒。","Allow up to %d seconds for the first connection or test, then %d seconds per request."]
	var deadlines:=[Brain.FIRST_CLI_SECONDS,Brain.LATER_CLI_SECONDS]
	bind_text(cli_timeout,timeout_words[0]%deadlines,timeout_words[1]%deadlines)
	bind_text(button(body,"",func():save_selection("",[])),"离开","Move out")
	advanced=VBoxContainer.new()
	var fold:=CheckButton.new();body.add_child(fold);bind_text(fold,"高级：让你自己的程序进来","Advanced: Connect your own program")
	fold.name="ProgramAccess"
	fold.toggled.connect(func(value):advanced.visible=value;refresh())
	body.add_child(advanced);advanced.hide()
	if door==null:
		fold.hide()
		finish_setup()
		return
	state=label(advanced,"")
	toggle=button(advanced,"",func():
		var ok:bool=door.set_enabled(not door.server.is_listening())
		feedback.text="" if ok else phrase("无法开启程序接入。","Couldn't start program access.")
		refresh())
	toggle.name="DoorToggle"
	copies=VBoxContainer.new();advanced.add_child(copies)
	bind_text(button(copies,"",func():copy_text(setup_text())),"复制给我的 AI","Copy for my AI")
	bind_text(button(copies,"",func():copy_text(claude_command())),"复制终端命令 · Claude Code","Copy terminal command · Claude Code")
	bind_text(button(copies,"",func():copy_text(codex_command())),"复制终端命令 · Codex","Copy terminal command · Codex")
	bind_text(button(copies,"",confirm_rotation),"换一把新钥匙","Rotate the key")
	feedback=label(advanced,"")
	bind_text(label(advanced,""),"接入记录","Connection history")
	log_text=label(advanced,"")
	door.changed.connect(refresh)
	finish_setup()

func finish_setup()->void:
	visibility_changed.connect(func():
		if visible and detection.is_empty():
			detection=Brain.helper(game.data_dir,"detect")
		refresh())
	Text.events.changed.connect(refresh_locale)
	refresh_sources()
	hide()

func _process(_delta:float)->void:
	if not test_job.is_empty():
		var reply:=Brain.poll(test_job)
		if not reply.is_empty():
			Brain.clear_helper(test_job)
			test_job={}
			var plan:Variant=reply.get("plan")
			test_result=str(reply.get("error","invalid_json"))
			if plan is Dictionary and plan.size()==1 and plan.get("ok") is bool and plan.ok:
				test_result="ok"
			refresh_fields()
	if not visible:return
	if detection.has("pid"):
		var result:=Brain.poll(detection)
		if not result.is_empty():
			available=result
			Brain.clear_helper(detection)
			detection={}
			refresh_sources()
	if Time.get_ticks_msec()>=next_status:
		next_status=Time.get_ticks_msec()+500
		if door!=null and summary.get_meta("save_error_until",0)<Time.get_ticks_msec():summary.text=game.island_ai.status_text(true)
		retry_button.visible=door!=null and game.island_ai.disconnected()
		refresh_recovery()

func _exit_tree()->void:
	if detection.has("pid"):Brain.clear_helper(detection)
	if test_job.has("pid"):Brain.clear_helper(test_job)

func refresh_sources()->void:
	var index:=0
	for id in Brain.PROVIDERS:
		var tail:=""
		if available.has(id):tail=phrase(" · 已安装"," · Installed") if available[id] else phrase(" · 未找到"," · Not found")
		sources.set_item_text(index,Brain.PROVIDERS[id]+tail);index+=1
	for id in picks:
		picks[id].text=Text.resident(game.world,id) if door!=null else Text.text("resident."+id)
		if picks[id].text=="resident."+id:
			var names:={"codex":phrase("小白","Xiaobai"),"companion-2":phrase("小蓝","Xiaolan"),"npc.mira":phrase("小橙","Mira"),"npc.nora":phrase("阿黑","Nora")}
			picks[id].text=names[id]
	api_key.placeholder_text=phrase("API 密钥（留空保留）","API key (blank keeps current key)")
	refresh_fields()

func refresh_fields()->void:
	var source:String=sources.get_selected_metadata()
	api_options.visible=source=="api"
	local_model.visible=source=="local"
	var count:=selected().size()
	move_in.disabled=count==0
	multi.text=phrase("多位居民会分别思考，消耗更多额度。","Each resident thinks separately and uses more quota.")
	multi.visible=count>1
	test_button.visible=source in ["codex","claude"]
	test_button.disabled=not test_job.is_empty()
	test_status.visible=test_button.visible and source==test_source
	cli_timeout.visible=test_button.visible
	var result:=phrase("正在测试…","Testing…") if not test_job.is_empty() else phrase("连接成功","Connection successful") if test_result=="ok" else Brain.error_text(test_result)
	test_status.text=result
	refresh_recovery()

func refresh_recovery()->void:
	var selected_source:String=sources.get_selected_metadata()
	var connection_source:String=game.island_ai.provider if door!=null else ""
	var connection_code:String=game.island_ai.connection_error() if door!=null else ""
	var diagnostic_code:=test_result if test_source==selected_source and test_job.is_empty() else ""
	var live_hint:=Brain.recovery_text(connection_source,connection_code)
	var test_hint:=Brain.recovery_text(selected_source,diagnostic_code)
	recovery.text=live_hint if test_hint.is_empty() or test_hint==live_hint else test_hint if live_hint.is_empty() else live_hint+"\n"+test_hint
	recovery.visible=not recovery.text.is_empty()
	auth_copy.visible=(connection_source=="claude" and connection_code=="auth") or (selected_source=="claude" and diagnostic_code=="auth")

func test_connection()->void:
	var source:String=sources.get_selected_metadata()
	if not test_job.is_empty() or source not in ["codex","claude"]:return
	test_source=source
	test_job=Brain.helper(game.data_dir,source,Brain.CONNECTION_PROBE)
	test_result="helper" if test_job.is_empty() else ""
	refresh_fields()

func selected()->Array:
	return picks.keys().filter(func(id):return picks[id].button_pressed)

func connect_ai()->void:
	var source:String=sources.get_selected_metadata()
	if source in ["api","local"]:
		var settings:=Brain.Credentials.read_settings(game.data_dir)
		if source=="api":
			if Brain.Credentials.endpoint(api_base.text).is_empty() or api_model.text.strip_edges().is_empty():
				show_error("请检查 API 地址和模型。","Check the API address and model.");return
			settings.set_value("openai","base",api_base.text.strip_edges());settings.set_value("openai","thinking",api_model.text.strip_edges())
			if not api_key.text.is_empty() and not Brain.Credentials.save_key(game.data_dir,api_key.text):
				show_error("无法保存密钥。","Couldn't save the key.");return
			api_key.clear()
		else:
			if local_model.text.strip_edges().is_empty():
				show_error("请填写本机模型名称。","Enter the local model name.");return
			settings.set_value("openai","local_model",local_model.text.strip_edges())
		if settings.save(game.data_dir.path_join("connection-mode.cfg"))!=OK:
			show_error("无法保存来源设置。","Couldn't save the provider settings.");return
		if door!=null and game.connection_pool!=null:game.connection_pool.settings=settings
	save_selection(source,selected())

func save_selection(source:String,ids:Array)->void:
	if not Brain.save_choice(game.data_dir,source,ids):
		show_error("保存失败。","Couldn't save the selection.");return
	summary.remove_meta("save_error_until")
	if door!=null:
		game.island_ai.apply(source,ids)
		summary.text=game.island_ai.status_text(true)
	else:summary.text=phrase("进入岛上后开始连接。","Connects when you enter the island.") if not ids.is_empty() else phrase("没接","Not connected")

func show_error(zh:String,en:String)->void:
	summary.text=phrase(zh,en)
	summary.set_meta("save_error_until",Time.get_ticks_msec()+5000)

func shell_word(value:String)->String:return "'"+value.replace("'","'\\''")+"'"

func claude_command(profile:String="kinabode")->String:
	var server:=shell_word(profile)
	var path:=shell_word(door.directory.path_join("world-door-token"))
	return "(set +x; kinabode_key=$(cat "+path+") && [ \"${#kinabode_key}\" -eq 64 ] && { claude mcp remove "+server+" --scope user >/dev/null 2>&1; claude mcp add --scope user --transport http "+server+" http://127.0.0.1:%d/mcp --header \"Authorization: Bearer $kinabode_key\"; })"%door.PORT

func codex_command(profile:String="kinabode")->String:
	var code:=CODEX_INSTALL.replace("@PORT@",str(door.PORT))
	return "python3 -c "+shell_word(code)+" "+shell_word(profile)+" "+shell_word(door.directory.path_join("world-door-token"))

# This runs in the user's terminal, never inside the game or a door action.
# Rewrite only the selected top-level MCP table and its descendants.
const CODEX_INSTALL := """import os
import re
import sys
import tempfile
from pathlib import Path

name, key_path = sys.argv[1:]
if not re.fullmatch(r'[a-zA-Z0-9_-]+', name):
    sys.exit('Invalid MCP server name.')
try:
    config = Path(os.environ.get('CODEX_HOME') or Path.home() / '.codex').expanduser()
    config.mkdir(mode=0o700, parents=True, exist_ok=True)
    target = (config / 'config.toml').resolve()
    key = Path(key_path).read_text(encoding='ascii')
    if not re.fullmatch(r'[0-9a-f]{64}', key):
        sys.exit('Open the game door before configuring Codex.')
    import subprocess
    result = subprocess.run(['codex', 'mcp', 'add', name, '--url',
                             'http://127.0.0.1:@PORT@/mcp'], capture_output=True)
    if result.returncode:
        sys.exit('Codex could not add the world door.')
    normalized = target.read_text(encoding='utf-8')
    heading = '[mcp_servers.' + name + ']'
    # Codex writes a canonical standalone table when it adds the server.
    if normalized.splitlines().count(heading) != 1:
        sys.exit('Codex wrote an unrecognized world door configuration.')
    start = re.search(r'^' + re.escape(heading) + r'$', normalized, re.M).start()
    end = normalized.find('\\n[', start)
    end = len(normalized) if end < 0 else end + 1
    table = heading + '\\nurl = "http://127.0.0.1:@PORT@/mcp"\\n'
    table += 'default_tools_approval_mode = "approve"\\n'
    table += 'http_headers = { Authorization = "Bearer ' + key + '" }\\n\\n'
    fd, temporary = tempfile.mkstemp(dir=target.parent, prefix='.kinabode-')
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as stream:
            stream.write(normalized[:start] + table + normalized[end:])
        if target.read_text(encoding='utf-8') != normalized:
            sys.exit('Codex configuration changed during setup. Run the command again.')
        os.replace(temporary, target)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)
    print('Kinabode world door configured. Open a new Codex session.')
except (OSError, UnicodeError):
    sys.exit('Could not read or save the world door setup.')
"""

func setup_text()->String:
	var zh:String="只用有栖世界门的 claim、look、act、say、events、release；旧的 ai-habitat 不是世界门。用 claim 认领小白（resident: codex；client 填你的客户端名）。用 look 的 surroundings 观察。第一件事是在小白旁边立一块写着「你好」的牌子；木材不够就先用 chop_and_haul 砍树并搬回仓库。用 suggested_sites.sign 的坐标替换下面的 X、Y，然后用 act 提交两步。用 events 带上上次最高 sequence 等到 action_finished；失败先观察，只补未完成的步骤。之后用 say 对 human 打招呼；太远就用 go_to 走到 human 附近再说。说完 release。如果没有世界门工具，请让我检查门是否打开、是否执行过对应的复制命令，以及是否打开了新会话。"
	var en:String="Use the Kinabode world door tools: claim, look, act, say, events, and release. The old ai-habitat server is separate. Claim Xiaobai (resident: codex; client: your client's name), then use look with view surroundings. Leave a little greeting sign beside Xiaobai with the exact label below. If you're short on wood, use chop_and_haul first to bring some back. Put the suggested_sites.sign coordinates in both steps below and submit them with act. Use events with the highest sequence you've seen and wait for action_finished. If something fails, look again and retry only what remains. Say hello to human; if they're out of earshot, go_to human first. Release afterward. If the door tools are missing, ask me to check that the game door is open, the setup command has run, and this is a new chat."
	var greeting:=String.chr(0x4f60)+String.chr(0x597d)
	return phrase(zh,en)+"\nsteps: [{\"action\":\"place_piece\",\"item\":\"sign\",\"position\":[X,Y]},{\"action\":\"name_place\",\"position\":[X,Y],\"label\":\""+greeting+"\"}]"

func copy_text(value:String)->void:
	DisplayServer.clipboard_set(value);feedback.text=phrase("已复制。","Copied.")

func confirm_rotation()->void:
	var confirm:=ConfirmationDialog.new()
	confirm.dialog_text=phrase("旧钥匙会失效，已接入的程序会离开。确定更换？","The old key will stop working and connected programs will leave. Rotate it?")
	add_child(confirm)
	confirm.confirmed.connect(func():
		feedback.text=phrase("已换新钥匙。请重新执行客户端的终端命令。","Key rotated. Run the setup command for your client again.") if door.rotate() else phrase("无法更换钥匙。","Couldn't rotate the key.")
		confirm.queue_free())
	confirm.canceled.connect(confirm.queue_free)
	confirm.popup_centered()

func refresh()->void:
	if not visible or door==null or not advanced.visible:return
	var listening:bool=door.server.is_listening()
	var count:int=door.owners.size()
	state.text=phrase("程序接入关闭","Program access off") if not listening else phrase("等待程序接入","Waiting for a program") if count==0 else phrase("已接入 %d 位","%d connected")%count
	toggle.text=phrase("关闭接入","Disable access") if listening else phrase("开启接入","Enable access")
	copies.visible=listening
	var words:Dictionary={"origin":phrase("来源不对","Origin rejected"),"key":phrase("钥匙不对","Key rejected"),"connected":phrase("连上了","Connected"),"claimed":phrase("已认领","Claimed")}
	var lines:=PackedStringArray()
	for entry in door.knocks:
		var who:String=entry.client if entry.actor.is_empty() else preload("res://scripts/localization.gd").resident(game.world,entry.actor)+(" · "+entry.client if not entry.client.is_empty() else "")
		lines.append(entry.at+" · "+words.get(entry.result,"")+(" · "+who if not who.is_empty() else ""))
	log_text.text="\n".join(lines) if not lines.is_empty() else phrase("还没有记录","No knocks yet")

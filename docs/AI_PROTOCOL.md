# v0.8 原生传输边界（2026-11-16）

OpenAI 兼容 API 从 CompanionLink 分流至 direct_api_transport.gd；不再写桥会话或派 Python。原 actor/scope/turn_key 屏障、Main 意图/记忆的 exact source 校验、World 唯一路线与物资流程均保持。SSE 只发布 speech_partial；intent_result 仅在 [DONE]、完整 JSON 与结构校验后发出。usage 先于意图校验记账；没有有效 usage 不造零消耗。原 MCP/schema/驱动不变，Codex 仍走可选旧桥。只发送游戏卡片，不提供文件/网络工具；密钥只在 Authorization，不进卡片。连接与安装说明见 AI_CONNECTION.md。

---

# 2026-11-12 v0.6收尾调度修正

托管邀请在全队沿原World走向活动地点时发出，保留15秒确认与只有明确同意才移动/加入人类。同一目标补料只是子步骤：先真实收尾归队，只有整条目标/活动结束才启动原歇息计时。采木优先选择附近能容下全队真实目标的树群，未改产量、速度或参数。免费烤蘑菇不再被规划器库存门槛拦住。


---

# 2026-11-12 v0.6 续轮托管收尾

导演结束一条目标后先进入closing：完成真实在途作业、撤销该总管所属旧意图，按原World路线全队归队后才启动原歇息计时与汇报。运行中的空闲成员同样跟随总管归队，不能把停稳改标赶路。建造过程有附近真实树时继续供料；为建设准备的原砍树单明确标注build_supply，其工作命令/产量/时间不变。没有当前可执行目标时安排原真实小游戏；小游戏先开真实一局同时邀请岛主，只有玩家明确同意才加入/导航人类。AI仍仅给偏好，不直接控制身体。


---

# 2026-11-09 管事权与托管（最新覆盖）

DIRECTION「看 AI 过日子：总管、托管与观看」授权：四位稳定ID codex / companion-2 / npc.mira / npc.nora 同级；旧npc角色读档规范为companion，controller保留真实连接状态，绝不自动连接、移动主角或变更记忆关系。

管事权是本机connection-mode.cfg中management/<ID>，默认false，连接ready且controller=model才生效。意图新增actor_ids（非主角伙伴ID数组，或["all"]）与assignments（最多四个同格式、不可再嵌套的分工）。例如 `{"action":"chop","actor_ids":["all"]}`；分工为 `{"action":"chop","assignments":[{"action":"chop","actor_ids":["companion-2"]},{"action":"harvest","actor_ids":["npc.mira"]}]}`。宿主先校验结构/身份，逐人拒绝忙碌、很饿等真实阻碍；不能把部分接受称全部完成。关权仍保留own_actor_only。实际执行者与sponsor分离，不改受派者controller；原World路线、LocalHostCommands与材料阈值确认、Fireside原扣料/邀请/入座保持。原动作v2加字段，旧native工具/schema/驱动不变。

托管每次只一位，开启/时段变化/饥饿跨档/一次失败重排/玩家原话才请求规划；原主动的在场/事件门槛不作为托管门槛，非托管主动仍保留。输入卡steward_request含day/phase/reasons/hunger/weather/reply_format，模型返回 `{"speech":"人设口吻旁白","intents":[],"planning":[{"phase":"now","reason":"真实理由","intents":[{"action":"chop","actor_ids":["all"]}]}]}`；planning必须3～6项，phase为now/morning/noon/afternoon/evening/dusk/night。引擎校验并执行本地队列；接单/完成/阻碍分列，不因推理回复或完成自动再想。主角不受控。玩家走路取消未来安排并回手动镜头；说“别管了”或再点托管收回。预留按resident×turn_key追踪，报错/取消后的迟到complete仍精确释放，未知用量保守预留，原账本只计一次token；达到新每日上限退本地作息。意图原线程8轮分段，记忆卡接续。

AI普通回复分段头顶气泡，每段最多30字符、本人至少8秒间隔，对话记录保留短句；棋局出口不变。队列/安排不进世界档，换源/撤权/读档不得续做未来步骤。外部规划通过原精确绑定信箱assistant的JSON返回，同一绑定校验仍在，规划信箱拒绝action/question；未知用量不冒称零成本。

---

# 2026-11-08 对话合一与 AI 放权

最新授权覆盖旧“指令/对话分两页”和仅主角张罗营火的限制。界面只有一套输入与消息记录；常用按钮调用同一发送入口，多选与按使用次数排序保留。空输入方向键移镜头，有字时移光标；Esc释焦保留面板，Enter回输入，打字不触发地图/全屏快捷键。连接页有三秒结果行、绿/红灯与头像轻跳；进入世界后首次在真实viewport看到已连接伙伴时再本地问候一次。初始菜单按可用高度布局，退出不藏入滚动区。

内置普通单聊/群聊、预算自主使用同一个 intent_companion 意图格式。普通明确指令本地能理解的先经真实系统开工，AI补短话；纯聊天（含“你喜欢泳池吗”）不授予工作。外部与旧原生会话保留原绑定和旧工具；v2追加 resident_plan，必须有当前明确主机原话的回合授权，或精确匹配已开启的预算自主回合。无上下文act不能绕过该入口，human不能作为执行者或guest。

多步格式：`{"speech":"短话","intents":[{"action":"fish"},{"action":"roast"},{"action":"invite"}]}`，最多5条结构化意图，宿主深拷贝后逐步推进。旧单条text/replace更正入口保留原范围检查。新计划不写存档，不增加永久劳动能力；停止/换源/问题/集合/读档取消未来步骤。实际任务仍归World、Work、FarmSystem、Fireside、Resort等原系统。每步观察真实位移/动作；3秒没有开始则记录真实原因并排本地说明，不额外推理。接单与完成分别记录，完成才进入后一步；农活/施工保留原收据与进度。

所有意图只能操作本人；guest_ids仅用于受邀吃饭、下棋、度假与带路，不接受human、不覆盖伙伴已有任务或待答。玩家多选的劳动仍逐人走原主机授权。很饿中断后续，正常劳动仍保留原“饿了拒绝新农活”等门槛。每人容量20、物资、关系、性格、日程、天气和预算数值不改。自主仍默认关、medium以上显式开；原事件/在场/冷却/日小时预算/工具数上限继续约束，无推理轮询、无完成连锁。

## 结构化意图参数与执行

共同可选text只为原劳动解析；target_id、item_id、crop_id、region_id是有界字符串，x/y须有限数，guest_ids为不重复的真实非主角居民ID。未知字段和身份覆盖拒绝。以下参数省略时只选择既有、可用的真实目标；没有目标或材料则说明，不造物。

| action | 参数 | 原执行 / 完成证据 |
|---|---|---|
| fish | 无；不指定鱼种/围网 | 本人最近有效自然岸位，World路线、Fishing原甩竿/等待/收竿；本人唯一pending鱼才算完成 |
| light | target_id可选营火 | 先走到5格内，Fireside.light_host(storage_only=true,本人)，冷2木/旺1木 |
| roast | target_id营火、item_id可选菜单ID/本人fish:ID | 先校验原菜单，再按原配方扣料开烤；本人鱼真实移到餐，不改所有权、不复制；放上烤架才记该步完成 |
| invite | target_id营火、guest_ids可选 | 只邀请原规则可来的人，真实座位与进食；无食物拒绝 |
| plant | crop_id可选、target_id可选农庄、text可选 | 原host_grants、真种子/首水/原路线，准确原订单completed |
| harvest | target_id农庄、text可选 | 只收真实成熟作物，原订单与仓库收据 |
| water | target_id农庄、text可选 | 原缺水田格及真实浇水订单 |
| chop | text可选原数量约束 | 原连续gather_wood，真实砍/捡/递交与job完成回执 |
| gather | text可选实际采集物 | 原forage/原材料点，不生成资源 |
| build | target_id可选既有岛模板 | 本人地界、既有占地/路线校验、原Leisure扣料施工；仅本轮计划授权，不给本地居民自建权 |
| chess | target_id可选棋桌、guest_ids可选对手 | 先本人走向棋桌，再原GomokuMatchHost预算校验和两位真实入座；模型棋不以本地棋力代替 |
| go_to | target_id真实对象/居民，或x/y/region_id；guest_ids可选 | 原World路线，本人及空闲受邀伙伴真实到达，绝不移动human |
| wander | 无 | 原World走向可达邻近位置 |
| sit | target_id可选已建座位设施 | 原Leisure认领/路线/坐姿 |
| lounge / pool / swing / stars | target_id可选活动、guest_ids可选 | 原Resort空闲槽位与路线，using才算到场 |
| hold_cat / pet_cat | 无 | 走近真实柚柚，原CatCompanion.interact；被占/走开/忙碌如实拒绝 |
| home | 无 | 原已建本人房屋入口，World路线 |
| follow / unfollow | 无 | 原ResidentActivity跟随/释放 |
| hand_over | text可选 | 本人已有真carry、原StorageDelivery到主角前递交入仓 |
| stop | 无 | 原本人stop，保留物资与进度 |

除菜谱原食材外，不在额外层扣库存。烤蘑菇仍为用户已授权无限供应，其余原配方、锁定与收据不变。默认钓鱼→直烤直接复用冷火2木流程，不隐式重复生火。若明确另外要求生火，则它是一项真实单独操作。指定料理不能替换为手中鱼；无效菜单不扣点火木。准备其他需空手活动时仅按原stock_fish把本人pending鱼放入真实空围网；无空位保留鱼并拒绝，不动他人的鱼。


---

# 2026-11-08 简化连接与完整人设


初始界面连接页和居民卡顶部提供连接 AI／断开；连接调用已有 Codex initialize、account/read、thread/start 或 resume 握手，不发送 turn/start。握手成功亮绿并用本地性格台词问候。根节点 ConnectionSessionPool 保存标题页会话，进入游戏继续使用；默认勾选下次自动连接，只对明确连接过且未断开的内置伙伴生效。灰本地、黄连接中、绿就绪、红失败；错误说明安装、登录、启动超时或额度处理方式。普通入口不再要求挑提供方；外部等待与复制配置放高级，标准档和主动默认关保持，档位入口改为更多设置。外部超过24小时没有实际回复时只提示一键改回，不偷偷切换。

人设权威是 `godot/content/personas/world.{zh,en}.json` 与 `{resident_id}.{zh,en}.json`，字段 `version:1`、`persona_id`、`language`、`sections`（按顺序的字符串数组），居民另有 `name`。固定文本是 world.sections + resident.sections 以两个换行连接；可编辑文件，下次连接生效，不动原性格／关系／饥饿数值。完整中英文见 PERSONAS.md。内置在会话建立参数的 baseInstructions 后附加固定人设，同一会话每轮不重发；原意图小卡保留 personality 并加 persona_id。外部 MCP initialize.instructions 和只读 habitat_persona(language=zh/en) 提供相同文本，成功 observe_world 也附 persona；默认跟随本机游戏语言。外部动作的宿主权限和精确回合校验不变，不能从人设取得行动权限。

宿主统一过滤内置意图 speech 及 native/external assistant/question 的代码围栏、网址、超过三句／280字符的长文及“作为 AI”等词；替换为本地短句并记 PERSONA_SPEECH_FILTER 日志，不重试、不额外推理。完整信件仍走独立信件验收，不当普通气泡过滤。

---

# 2026-11-08 内置单聊意图模式（部分验收）

内置普通单聊先用原 LocalHostCommands 执行明确主机指令，保留饥饿、真实材料、原路线与大单确认；本地短回复之后发送同一原话给独立的 intent_companion.py。模型回一次 JSON：`{"speech":"短句","intents":[{"text":"本地可解析指令","replace":false}]}`，最多三条。宿主再次解析、校验本人范围与原动作；已开工的同轮指令不会重复执行，replace 仅允许同类且其它约束一致的更正，不重写物资。未知或越权意图拒绝。意图参数目前由 text 经原解析器提取，尚非完整结构化的谁/什么/哪里/数量字段。

小卡片为 self（ID、饥饿词、当前活动）、同区域八格内最多十六个对象、最多十种非零仓库存量、可去地点、当前频道最近六句玩家原话、MemoryBooks.card、local_execution、频道/接收者及 forget_revision。没有完整农庄/建筑/作品像素，也不重复整段聊天历史。卡片/意图不授予新权限。详见 MEMORY.md。地点列表目前为通用类别，非完整动态可达地点目录。

意图驱动没有原生动态工具或 youqi_actions MCP；旧外部 MCP/schema/驱动 VERSION、旧线程文件保留。意图线程使用独立 youqi-intent-thread-v1.json，八轮后主动分段，恢复失败仍不偷偷替建线程。游戏内删除记忆后按 forget_revision 分段。显式自主回合和棋局保留原工具驱动路径，群聊也保留原驱动；这些路径尚未统一为单次意图模式。不是全部提供方都已改成无工具模式。


---

# 2026-11-05 一句话动作与回退

v2 补充 plant/harvest/water/chop/gather、follow/unfollow、go_to/gather_at、hand_over/query_state；fish/stop 保留。坐标、目标、真实库存、饥饿与现有任务仍由引擎校验，不接受 actor_id 覆盖。可选actor_ids只能等于本轮原话解析的完整名单，禁止human；调用时不传目标等其它参数，宿主从原话派原动作，不唤醒其它模型。自主回合不能委派。invite_barbecue/start_project/open_chess 为无参的当前主机指令入口：精确绑定原话、turn_key、generation，只执行原话已解析的活动，不能把跟随请求改成建设或替人类任意行动。多动作保持同轮绑定，不新增模型调用。旧 native 工具/schema/驱动不改。

原生 direct 的已解析主机命令保存一个内存回退记录。模型动作被接受后不重做；错误/结束却未接单或实际30秒超时，先撤销旧回合，再用原话走本地执行。停止/换源/代次改变撤销记录；不做存档恢复。direct/group当前已启动回合均有独立绑定；已排队尚未开始的消息仍缺完整回退证明，不称全覆盖。离线完整提示估算更新为4928参考token，预算政策数值不改。

---

# 2026-11-05 本地主机命令接手（部分实现）


---

# 2026-11-04 她们的岛 · v2 island_propose

`island_propose` 只提交待主机确认的卡片，不能动工或扣料。参数仅 `template_id`、`x`、`y`、`name`（单行≤40）、`reason`（单行≤128），不允许 actor/能力覆盖。`game_actions` 给出现有模板白名单和最多三条本人真实共同回忆摘要；模板完整占地必须在本人地内，拒绝占地及已接受路线段冲突。当前保守实现只接受一条提供过的摘要原文作为理由，拒绝未核实的自由往事叙述；理由不成为新历史。

主机点精确居民/卡ID的「好呀」后，再验证并原子扣系统仓库原费用，执行原 World/Leisure 施工。卡ID随机且不重载，换源/迟到输出仍受既有回合令牌与取消链约束；接单不等于完成。完成观察才记录真实具名事实，不因建成自动推理。社交居民没有永久劳动能力。断开回本地后清模型待定卡，原本地预设继续可用。

复用既有 v2 MCP 与会话，每日预算/原 native 动态工具/schema/驱动保持。离线信箱桩验证合法回执、取消令牌与身份覆盖拒绝；引擎桩验证真实回忆、合法提议/原施工/具名重载及非法拒绝。开发零真实模型。工具文本新增后按原脚本重算完整提示词离线估算为4539 token/参考回合，全部实际预算及策略字段逐项不变；估算不是实测账单。

具体范围见 HOME_ISLAND.md；六种现有 Leisure 模板以外的房屋/家具提议本轮不开放。

---

# 有栖协议 · 0.2 海岛小样

0.10：“共享测试 · 自动”为独立测试伙伴，Godot发送/真实回复自动返回，1轮处理中+最多3条本地排队，空闲不推理。身份、操作与取消沿用原校验；当前开发原会话未迁移。见 [AUTOMATIC_DIALOGUE.md](AUTOMATIC_DIALOGUE.md)。

**最新连接补充：** 原有 CompanionLink 是独立游戏会话，不能称作桌面原会话。0.9.1 提供明确绑定原会话的手动信箱与回执，游戏自动唤醒尚未接通；详见 [EXISTING_CONVERSATION.md](AI_CONNECTION.md)。

0.9.2：树桩→树苗→成熟树，observe.objects[].regrowth 提供阶段、剩余秒数和暂缓原因。成熟才可chop/gather_wood，剩余秒数为0但blocked_by非空时仍不可砍。详见 [FOREST_REGROWTH.md](FOREST_REGROWTH.md)。

日期：2026-10-22。工具执行真实 Godot 世界规则，接受任务和完成任务分开。

## 连接与身份

运行游戏后，用 `python3 scripts/habitat_godot.py mcp` 启动 stdio MCP；默认身份 codex。`--resident companion-2` 等只允许本地主机选择已配置的居民。游戏以 `-- --readers=5` 配置额外四个居民；这不启动五个模型。每位居民也拥有独立外观作品 ID，不能借外观编辑改别人。

默认数据目录 `~/Library/Application Support/Godot/app_userdata/有栖`；测试必须使用临时 HABITAT_DATA_DIR。引擎帧循环取快照，推理在独立进程内。连接令牌隔离协议身份，不是对同一系统账户文件权限的安全沙箱。

## observe_world

参数：region_id、object_id、offset、limit（1..100）、revision。默认自己所在区域与前 24 个对象；详情查询对象必须属于指定区域。page.complete=false 时，传 next_offset 与 snapshot_revision 作为 revision；世界改变则拒绝过期续页。

返回世界与模板 ID、UTC 时间、状态版本、self、residents、区域、对象、jobs、drops、events、capabilities。坐标是 region-local，世界坐标为区域 origin 加局部坐标。每次移动或工作进度变化更新 revision；读取返回深拷贝、不改变世界。

## act

参数始终包含 intent；不可传 actor 或 actor_id。

- move：region_id、x、y，固定速度走路；已有工作时拒绝替换。
- stop：停止自己的任务与移动，释放占用，保留携带物、地上木材和工地投入。
- chop：target_id 为成熟树，仅处理明确指定的一棵。自动接近、砍伐、掉落、限量搬运、存箱、返回搬余料。
- gather_wood：连续伐木委托，同一任务自动选择和搬运多棵树；参数和停止条件见0.5.1。
- collect：target_id 为现存地面木材，搬进箱子。
- store：将自己已携带的木材实际搬到箱子。
- build：target_id 为宅地，先分批搬运现有材料到工地；凑齐费用才完成下一个阶段。不足时保留delivered并报告waiting_materials，不宣称阶段完成。

接受返回 status=accepted / job_id，完成和阻塞在后续观察的 events 中。树和工地采用独占任务声明；五读者已测，多个独立模型自治尚未实现。不能自动重试不确定的动作超时：先 observe 判断结果。队列内动作带 request_id、会话与过期时间；重复提交同一请求 ID 拒绝。

## 角色作品

read_character：frame，如 down_0，返回自己的作品 ID、版本、画布、调色板、该帧图层和像素索引。

edit_character：base_revision、frame、layer、pixels（最多1024项，每项 x/y/color）。只改连接居民的作品；版本过期拒绝，原子写入后引擎使用新版本。玩家可在像素工坊撤回最近的应用（本次运行内最多10次）；保存作品可重新打开，跨重启完整编辑历史尚未保存。

格式与实现：`godot/content/characters/*.json`、`character_library.gd`。玩家和 AI 使用相同可编辑数据与校验。自由图层不意味着任何单幅图片会自动得到正确的全方向劳动动画。

## 游戏内模型

CompanionLink 仅在首条消息启动专用 Codex app-server。动态工具为 habitat_observe、habitat_request、habitat_ask；操作固定属于 codex。问题显示在游戏内，等真实回答；超时不是同意。取消屏障要求匹配确认，迟到工具和文本不执行。

模型回复失败显示实际错误，不使用关键词脚本假扮回答。游戏完成事件显示为“进度”，不伪装成模型自然语言。工作期间不轮询模型；当前工作完成后不会自动唤醒一轮新推理。凭据留在 Codex 自身账号处理里，不复制或修改全局配置。


## 0.3 共同创作与烧烤

当前v4只保留真实forage、建设与作品等原动作。烧烤由主机现场两按钮进入邀请与菜单，不向模型提供生火、开烤或代替人类吃饭的工具。旧native DYNAMIC_TOOLS/schema与驱动版本不改；旧barbecue/turn_food/eat/cleanup与独立cook/cook_read不执行，明确拒绝。观察可见每营火真实状态与采集点，快照不含像素。具体流程见SHARED_BARBECUE.md。

read_work允许共享作品cottage、cottage-large、camp-grill；参数artwork_id、frame、x/y、revision，返回24×24区块、画布尺寸、帧列表、调色板和结构。complete=false说明未返回全图；按坐标和同一版本继续读取。

edit_work可提交基准版本+frame/layer/pixels，或基准版本+structure（width/depth/floors/porch）。人物身份与共享建筑权限分开，不可借共享接口编辑人类角色。工地图纸在选择时冻结，修改源作品不影响已放置实例；未开工可重新选择，已开工拒绝替换。

内置Codex新增habitat_read_work、habitat_edit_work；工具版本变更时新建专用会话，不继续恢复没有新工具的旧会话。游戏共同用餐记忆仍由实际世界快照提供。取消屏障覆盖新工具事件。

### 0.3.2 座位与用餐

每点8席由原World/Work认领；主机开烤确认后只受邀伙伴与现场主角自动入座，每人实际吃满4秒才消费食物。没有模型手动eat/cleanup、打包、喂食、旧批次恢复或剩菜。移动150/携带125等原数值不变，动作/表现零模型请求。

### 0.3.3 本地生活状态

self.local_life返回source=local_rules、enabled、chatter、paused、behavior。这里是游戏规则驱动的日常行为，不能当作模型自己的推理或玩家指令。实际Codex命令抢占本地路线/座位，工作无需担心被闲逛覆盖。内置模型推理与等待回答期间暂停本地行为；外部模型仅在发出实际动作后取得控制，不推断外部推理是否正在运行。日常预设台词不作为用户同意，也不等于任何任务完成。没有新增自动推理或网络调用。

### 0.4 家园与区域

初晴岛扩大至160×128，14用途区。observe增加region.landmarks、region.water_obstacles和construction摘要，提供图纸、阶段、费用、存量、送达和施工占用，不附整幅作品像素。home.house.02与home.chest.02可按原规则使用。新增可编辑模板cottage-blue；结构费用与cottage相同，已开工图纸不能覆盖。不要把果园预留地/池塘/沙岸理解为种植、钓鱼或航海已经实现。地基里还有人时，build会保留材料并报告阻塞，等人离开后按用户指令再继续。

## 0.5 房间与实体家具

完工建筑暴露room_id，例如room.home.house.01。`observe(region_id=...)`返回独立房间坐标、interior.recipes、furniture及walkable_positions；self.region_id表示当前位置。室内不能直接用室外树木坐标，地图world-origin公式不适用于房间。

| intent | 参数 | 实际行为 |
|---|---|---|
| enter | target_id=宅地ID | 走到门口进入完工房间 |
| exit | 无 | 走到当前房间门口离开 |
| furnish | target_id=宅地ID, recipe_id, x, y, facing? | 出门取木材、制作、搬进房间摆放，一次任务 |
| pickup_furniture | target_id=家具ID | 走近搬起；拒绝占用或有库存的箱子 |
| place_furniture | x,y,facing? | 在当前房间放下实际携带家具 |
| rotate_furniture | target_id,facing=up/down | 走近改变朝向 |
| sit | target_id=椅子ID | 可跨室内外走到空椅，持续坐着直到stop |
| take | target_id=箱子ID | 从当前地域箱子实际拿最多20件材料；每人固定独立容量，以 self.carry_limit 为准 |
| store | target_id? | 存入当前地域指定或附近箱子 |

recipe_id: table/chair/chest/rug/lamp，费用6/3/6/2/3木材。朝向目前up/down。模型只控制绑定角色；已接单后不要提交多余搬运/进屋步骤。停止不销毁物料。家具作品为furniture-table/chair/chest/rug/lamp，使用read_work/edit_work统一版本校验；已制作实例冻结外观。


## 0.5.1 分批交料与连续采集

`build`不再要求接单时整阶段材料齐全。手中和箱子里有部分木材即可搬运，抵达并放下后才计入投入。比如1/10加手持2根→实际交付后3/10；若此时无更多可达材料，任务结束为waiting_materials并释放宅地占用，之后可再次build。多余手持材料保留；取消、重载不退回或重复扣除已交材料。

`gather_wood`接受可选target_id（起始树）、zone_id（资源区）、tree_count（1–100）。未给数量则持续到停止条件；默认在第一棵选中的树所属区域内采集，不跨岛清林。可从房间出门，先存手中木材、回收同区域未占用掉落，再采树。每次只占用当前树/掉落，搬完整棵后自动选下一棵；全程同一job_id。动作绑定当前居民。

停止条件：指定数量完成；玩家stop；可达箱子空间不足整棵产量；该区域无可达/未占用的树；游戏重启。中途箱满尽量换箱，无法存放则保留携带和掉落并报告阻塞。范围内目标被别的居民占用时不会抢占。连续推进由引擎完成，模型轮次结束不影响已有任务，但不在游戏关闭后继续，也不自行启动下一轮推理。

普通“去砍树/收集木材”应选gather_wood；明确“这棵/只砍一棵”选chop。旧selected_object_id不应把普通采集请求误解为仅一棵。任务观察包括zone_id、tree_count（0表示未指定数量）、trees_cut、trees_completed、wood_stored、当前phase/target_id。progress事件只在一棵的搬运完成后发出；已砍棵数与完整入箱棵数分开，accepted不是completed。连续采集已含store，不额外下达存储命令。


## 0.6 完整建屋计划

`build_house(target_id)`启动持续建屋目标；`build`仍仅交料/最多做下一阶段。“把房子盖好”使用build_house，无需另派采树或逐阶段任务。可先select_blueprint完成图纸选择再接单，不能更换已开工或已绑定计划的外观。

`pause_project(project_id)`、`resume_project(project_id)`、`cancel_project(project_id)`只控制自身当前稳定ID的计划；stop暂停整个活跃计划。重载不自动恢复工作。observe.self.project、projects、house_memories提供真实计划/投入/贡献/完成记录；接单不是完成。人类可用deliver_wood(target_id)协助送手持木材，走到现场才扣料，超额保留。

引擎按实际库存、投入、子任务结束和别的居民施工结果选择下一步；普通衔接无模型调用。只有用户请求商量/继续时产生新轮次。提问期间游戏暂停当前计划，不把等待当作继续授权。只记录真正交料和完成阶段的居民，既有房屋旧历史不编造。完整状态、持久化与边界见docs/SHARED_CONSTRUCTION.md。


## 农庄 0.7 接口补充

`observe.farming` 包含四片农庄的管理人、种子/收获箱、固定地块 ID、作物种类、剩余成熟秒数、当前委托和事实记录。`self.farm_order` 是本居民订单；所有动作由连接身份执行，不接受 `actor_id`。普通 objects 分页包含48个农场地块和8个私有箱，不再返回旧 home.plot.* 规划记录。

- `plant(target_id, crop_id)`：真实取种并播种；`water(target_id)` 开始生长；`harvest(target_id)` 采收并搬到所属农庄收获箱。
- `manage_farm(farm_id, crop_id, mode)`：mode 为 once、repeat、harvest 或 plant。repeat 必须有用户明确持续照料的授权；其他模式不隐含无限委托。stop 停整个订单；重启/提问后暂停。同作用域的 paused 订单再次 manage_farm 会继续。
- `farm_take(target_id, item_id)` / `farm_store(target_id)`：只取放自己的农庄物理箱，最多六件。初始种子用 seed.turnip 等 ID，收成用 turnip 等 ID。
- `farm_meal(farm_id, item_id)`：从收获箱取两份可食收成、搬到农庄休憩点食用；`decorate_farm(farm_id)` 消耗两朵雏菊装点田边。
- `assign_farm(farm_id, manager_id)` 仅主人 UI 可用，不进入模型工具 schema。

任务返回 accepted 不是完成。模型提交连续订单后结束本轮，不能循环 observe 等成熟，也不能声称离线会自动收成。游戏关闭后订单暂停。外部超时先观察，禁止自动重试。

原生对话默认两位伙伴使用各自的 app-server/模型会话，首次消息才启动。会话目录为 companion/<actor_id>/<world_id>。每次 UI 事件由对应连接绑定 actor，提问与取消分别维护。此配置不表示模型正在推理，也不意味着支持一次广播给五个伙伴。

0.7.1中plant模式只填满、浇水后结束；crop_id=mixed仅在此模式有效。农庄布局version2保留已有田块ID并新增18块。npc.mira/npc.nora是无模型的日常NPC，不接受外部控制、不发放连接令牌。两位模型伙伴身份保持codex与companion-2；后者使用独立蓝发蓝裙作品。


## 0.8 游玩与集合

observe新增leisure.sites与gathering；每个设施含稳定ID、完成状态、实际交料、规则报价、交互点与占位。build_facility(target_id)用实际箱内/手持木材施工，use_facility(target_id)独占预约一个位置并活动至结束。greet、come_near、dance、watch为本地社交动作。所有动作仍绑定本连接居民，集合期间普通动作被拒绝；不得通过指定他人ID越权。

共享read_work/edit_work按库中kind动态开放建筑、植物、设施，设施可提交recreation配置，既有实例固定原版本。添加模板不需要再修改固定枚举。NPC社交从主机参与者选择执行，未连接模型不假冒自由聊天。详见RECREATION_AND_RESIDENTS.md。


## 0.9 居民控制来源

self.control及其他residents[].control提供controller、effective、capabilities和local_life，区分模型绑定、本地活动、用户任务和集合。自主设施job.source=local_rules；正常用户/模型任务可以通过同一command入口抢占该居民自己的本地行为，不应把它误当成必须先停止的用户工作。social-only居民即使接入模型也不能伐木或管理农场。主机切换来源撤销该身份token，其他连接不变；模型工具不提供控制来源修改。没有新增定时推理、主动模型唤醒或假模型对白。

## 单聊与群聊接入（0.10.1）

对话通过 snapshot.dialogue 标记频道、消息、发送者和接收者；实际行动仍只控制绑定居民。主机可用 dialogue_adapter_factory 注入不同驱动，不依赖当前测试角色数量。单聊与群聊模型会话、问答及异步输出分别路由，详见 [DIALOGUE_CHANNELS.md](DIALOGUE_CHANNELS.md)。这不是允许模型调用主机注册接口或控制其他居民。

## 共同烧烤活动（0.10.4）

observe.shared_activity.session提供活动ID、真实参与者、当前阶段/暂停原因、实际到场与已吃完者；shared_activity.memories是实际收拾完成后的事件，shared_life.memories保留实际用餐及重叠伙伴，关联activity_id。名字来自居民配置，记录使用稳定ID。没有新增持续漂移的表现计时字段。

活动由玩家在游戏内邀请、分工并决定开饭，World执行已授权的真实搬料、翻面、用餐和收拾，不启动模型推理。普通模型动作不能抢占正在参加的活动；绑定居民自己的stop可使活动暂停。邀请/恢复/开饭不是外部模型工具，不得通过消息替其他居民或human选择。阶段接受不等于完成；只有实际消费及清理事件才支持回忆，取消或缺料不是一次已完成聚餐。现有工具名、驱动版本和会话目录保持不变。


## 群岛地图只读接口0.10.5

外部MCP/CLI新增read_map，World及已有read-api共用同一查询。只接受region_id、offset、limit、revision；首次返回有界岛屿目录，region_id追加轮廓、用途、来源包版本与可用状态。地图revision不随走路变化，续页仍要求精确匹配。现有observe协议和游戏模型动态工具保持兼容，不声称旧模型会自动获得新工具。没有导入/启用、热更新或跨岛出行命令。完整字段及示例见[群岛地图](ARCHIPELAGO_MAP.md)。


## 海边钓鱼与统一动作0.10.7

observe.fishing分别暴露pens养存场、seas可捕海域、nearby_shore/最多12个coast_targets、本人鱼/pending/held_fish_id及active任务。候选岸位只读，不自动移动；read_map只列静态渔场位置/容量。

fish无目标参数，在本人当前自然岸边抛竿，远处只提示。stock_fish(fish_id,pen_id)为本人待安置鱼专用即时入场，不移动人物；release_fish(fish_id)只处理本人鱼，手持放生需靠海；move可带同一鱼走动，工具劳动须先安置。accepted不是收获，真实pending/事件才是完成。外部fish_action兼容入口仍在。

新增game_actions/game_action为提供方无关v2发现/执行契约。旧原生动态工具/schema与VERSION保留，当前线程专用MCP追加动作，以本轮action_turn_token通过原精确绑定通道执行，不重建旧会话。外部模式用dialogue_poll/dialogue_reply准确绑定真实回复/动作；需当前六字段身份，不能无上下文act绕过取消。没有自动唤醒外部客户端或已完成所有提供方真实推理的承诺。详见[AI接入流程及契约](AI_CONNECTION.md)和[完整钓鱼规则](FISHING.md)。

## 五子棋0.10.9

observe.gomoku列出公共棋桌和本人对局，含当前history/board、phase、turn_actor_id、match.id/revision；未加入者不能落子。game_actions/game_action追加gomoku_read(site_id)、gomoku_join/leave/resign(site_id,match_id,revision)、gomoku_move(上述参数,x,y)，坐标0～14整数。读取不改变世界，写入校验准确桌/局/修订/绑定棋手与当前回合；原生已有任务保护允许对局控制动作通过，最终仍由引擎验证，不替代普通劳动。

主机明确开局/恢复才移动玩家与受邀伙伴；join只确认已受邀身份，不授权外部建立他人对局。local模式由内嵌棋力下，不允许模型代走；model模式只接受真实模型/客户端提交，不自动唤醒下一回合。本地棋力、日常短句、测试客户端和真实模型需要区分。暂停/提问/换源/重载不判输，旧修订不能继续落；明确认输才记录resign。read_memories支持gomoku_match，只返回本人实际参与的终局记录。具体契约和验证范围见[GOMOKU.md](GOMOKU.md)。

## 2026-11-03 中英显示兼容

既有kind+facts+source仍是记录权威。新提交条目仅增加可选text_version:1，严格校验为数值1；事实字段/容量/去重/信用规则不变。旧条目没有此字段时使用原中文整句模板与事实，不回填标记；新条目查询时以当前TranslationServer语言渲染。JSON整数/浮点1等价，schema仍7。用户/模型提案原话和旧历史原文不查表替换。详见 [LOCALIZATION.md](LOCALIZATION.md)。

# 共同记忆与只读接口

2026-10-27夜间补充：当前KINDS共9种，在原6种上新增proposal_decision（真实接受/拒绝）、promise_result（真实履约/失败/取消结果）、gift（真实双方物品转移）。新事件从引擎提交同一canonical记事簿，diary仍256；没有新增可重放原始流水，因此旧6组source_marks仍至多192，不需扩容、不读取淘汰历史。旧schema7缺promises为空，旧记忆不补发。旧事提起仅增本人promise_result模板，所有原门控保留。字段、作用域及测试见 PROPOSALS.md / PROMISES.md / GIFTS.md；下方旧6种说明保留为历史设计背景。

SharedMemories是已有事件记录的统一记事簿，不是模型推断、聊天摘要或好感度。规则：只有实际消费、共坐、建房完成和活动清理完成的既有事件可以入账；邀请、接单、暂停、作物成熟、房屋当前已经建成，不足以生成一段经历。

## 事实与持久化

- 当前六种kind：meal（实际吃完的份额或菜品）、sat_together（实际共坐）、house_completed（有完成事件及实际贡献的房屋）、shared_barbecue（全体吃完且收拾完成）、fishing_catch（实际钓获，只记钓获者）、gomoku_match（真实结束的棋局）。meal的同席者不等于也吃完；活动取消后已实际吃过的份额仍是事实。KINDS未因本地旧事提醒增加类型。
- 每条记录有世界范围内稳定ID、发生时间、区域、参与者ID、类型对应的结构化facts与source。名字查询时从居民配置读取，不把改名当作新人物；不存推测情绪或模型对白。
- fishing_catch保留真实fish_id、catcher_id、species_id、color_id、scale、water_id；放生/入场不删除已发生的钓获事实，路人不获得钓获归属。
- 默认最多256条，配置在content/memories.json。来源原有32条上限不变；记事簿不会跟随来源列表裁剪而立刻丢失旧记录。达到自身容量才淘汰最早入账记录。不是无限历史档案。
- 来源去重source_marks当前最多192个（六组来源各最多32）；记事簿默认256条、快照6条、分页上限50不变。本地旧事提醒不改这些容量或来源淘汰规则。
- schema7新增可选shared_memories；原始来源记录保留。旧存档仅导入仍实际存在、结构可确认的事件，缺失参与/时间/贡献的不猜。source_marks记录最近来源键，防止已淘汰事件在读档时反复复活。无效新记事簿走既有存档副本保护。
- 新用餐/共坐事件在真实提交点生成event_id；活动和房屋使用既有activity/project ID。旧记录使用序列化后结构事实的确定性键，导入幂等；不凭相近时间合并经历。
- 默认列表把已完成活动及其相关份额折叠成一条活动结果；按meal类型或确切memory_id查询仍能读到实际份额。未完成/已取消的活动没有完成记忆，实际吃过的份额仍可读。

## 读取

World.read_memories(bound_actor_id, query)及read-api的read_memories操作，统一只读。模型连接固定身份，结果只含该身份实际参与的记录；with_resident只做交集筛选，不能改绑定身份。旧快照来源字段保留兼容，不是私密聊天记录。默认observe.memories给最近6条本人记录；既有模型工具/提示/驱动版本和会话目录不变。外部MCP和CLI新增独立read_memories入口，不修改原工具定义。

query字段：kind、with_resident、region_id、after、before、memory_id、offset、limit、revision。after/before为包含边界的非负Unix秒，默认limit12，最大50；offset>0必须带首屏revision。revision来自匹配记录的内容，不是每帧变化的世界revision，走路不会使翻页失效；记事新增、淘汰或相关居民改名会使旧页失效。拒绝未知字段、非有限数字、布尔冒充整数、越界范围及冒充actor_id。返回分页总量、下一offset、稳定revision及结构化memories；没有写入接口。

顶部“回忆”供玩家查看自己参与的记录，可按伙伴、类型翻页和刷新。面板不启动模型、不移动居民、不暂停工作。日期按玩家设备时区显示；事实不完整时保留源记录而不编造故事。

## 验证

临时世界通过真实砍伐、施工、家具、共坐和烧烤形成事实；测试过滤/身份、类型区别、折叠及详情、跨世界ID、重载/幂等、来源裁剪后的保留、容量与淘汰、不复活旧记录、旧存档及无效副本、只读不变性、MCP契约和实际viewport。历史超过原来源留存上限的事件无法恢复，不虚构补齐。


## 本地旧事提醒 · 2026-10-26

这是纯引擎的记忆呈现，不调用模型、不更改会话，也不重新创建或导入任何事实。`memory_reminders.gd`挂在ResidentDirector下，仅在现有LocalCompanion的一次非显式发言机会中尝试，成功仍由 `ResidentDirector.say_local` 统一发出，source=local_rules、context=memory_reminder，原气泡标「日常」。失败回落原日常，不增加任务/路线，不移动人类，不把短句变成待答问题。

只从当前 `SharedMemories.records` 读取，不查看Work临时事件、旧来源流水、聊天记录或已被记事簿容量淘汰的事实。本轮采用更保守的身份范围：所有提醒都要求发言者本人在participants中；不启用“旁人转述玩家公开事实”的分支。

- **meal**：cooked必须本人和human都在实际ate名单，才可提起一起吃过的dish_name。老蘑菇份额只在本人实际吃完且human在overlapped_with时说「上次我吃蘑菇时，你也在桌边」，不假定玩家也吃完；单人的farm_meal不选。若该餐已有当前仍保留的shared_barbecue，份额不再单独提醒。
- **shared_barbecue**：本人和human都实际参与完成活动，才说一起烧烤、收拾烤架。
- **house_completed**：本人和human都有这条真实贡献完成记录，才说一起盖好的房子；不从当前房屋外观猜经历。
- **fishing_catch**：只说本人catcher_id的大鱼，scale至少2；不说玩家也在场，不断言鱼仍在手里、渔场或尚未被食用。
- **gomoku_match**：本人和human参加、真实结束且至少实际落过一手的棋局，才提起下过的棋。无手数的开局即认输不提醒；不编造胜负或过程。
- sat_together本轮不选；其他居民的经历和仅受邀但未实际吃完者不获得共同用餐提醒。

配置在 `godot/content/companions/local-life.json` 的 `memory_reminders`，本地模板也在此。默认首次允许在进入游戏90秒后，记忆至少过去120秒；个人间隔300秒、全村间隔90秒、检查间隔5秒、近玩家半径8格、大鱼scale阈值2。个体和全村仍共享原发言出口及间隔；没有额外日历，记忆年龄和持久冷却以已有ForestSystem.clock为准，日常检查复用现有routine/director计时。

仅空闲、空手、同区域且在半径内时可提起：本地活动和碎碎念启用、无held/待答问题、无集合/共同活动/工作/路线/农庄计划/建屋计划/棋局/持鱼。停止安静期直接读取已有FishingLife的quiet_until（stop后的120秒），不创建第二套停止计时。每日小事/作息原有defer_idle优先级保留。提醒不抢正在进行的本地路线或任何真实任务。

### 提过状态与重载

复用Main已经加载的**同一个ConfigFile对象**，写既有 `HABITAT_DATA_DIR/local-life.cfg`，不新增世界存档字段、schema仍7。按世界和居民分节：

- `memory_reminders:<world_id>:<resident_id>`：mentioned为已经提过的稳定memory ID列表，next_after为个人下次允许时间。
- `memory_reminders:<world_id>`：next_after为全村下次允许时间。

每名居民对同一条当前记忆只提一次，不同真实参与者仍各有一次机会，受全村间隔限制。只保存ID和冷却，不复制事实；下一次成功发言时清理已不在记事簿里的ID，列表不超过该记事簿容量。旧cfg缺字段从空开始，但没有实际记忆就不会发言，也不补造记忆。跨世界隔离；人物改名或切换本地/模型来源不清去重。重载读取标记与冷却，不重播已提过的经历。

先保存去重标记与冷却，成功后才交给共享发言出口；保存失败不发旧事提醒并还原内存值。无效去重元数据也不发提醒，不通过清空记录来猜历史。普通日常开关保存使用同一ConfigFile对象，保留这些键，避免两份配置缓存互相覆盖。此处只保证当前记事簿保留范围内的事实不会重复；不保存无限历史或被淘汰事实的内容。

### 验证

新增 `test_memory_reminders.gd`（69项）和 `test_memory_reminders_controller.gd`（15项），纳入默认全套。真实砍树/建房/烧烤/做菜吃完收拾/钓获放生/建棋桌及实际落子认输产生测试记忆，不注入虚构记忆或物资。覆盖无记忆、正确/错误身份、同一记忆去重、重载/设置保存不覆盖、独立开关/held/提问/个人及全村间隔/停止120秒/集合/真实工作、近人范围、容量淘汰、写入失败和畸形去重字段。


## 本地生活补充（2026-10-27）

新增relationship_stage、wish_completed，都是引擎在真实进阶/愿望反应实际发生后提交的canonical事实，严格本人+human；字段/源证明见RELATIONSHIPS.md、WISHES.md。沿用diary256/marks192，不扩大容量，不增加可重放原始流水，不补旧历史。wish_completed可由原memory_reminders在本人且仍保留时提起；进阶不作为重复聊天话题。人格瞬时反应不额外写记忆，不伪造共同经历。

## moon_viewing（2026-10-28）

夜晚且晴/多云，至少两名实际Leisure在座者、包含human、位于月台三椅范围，才提交一条moon_viewing；facts恰好place_id/site_id/day/phase/moon_phase/weather六项，participants为实际在座者。每游戏日最多一次，schema7可选moon_island.last_viewing_day仅防同夜重播；重载不恢复坐席/任务。未到场、白天、雨/雾或只有一人不伪造赏月。

直接进入原256条diary，沿用淘汰；没有新增源流水或扩大192 marks。防重日标记保留，即使当晚事实被容量淘汰也不回补。旧档缺标记从0开始，不补历史。赏月本轮未加新关系权重；月牙岛真实烧烤照旧给shared_barbecue关系进展，不重复给每份蘑菇加分。地点附加字段与现有meal/shared_barbecue校验和容量说明见SHARED_BARBECUE。

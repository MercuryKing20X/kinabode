# Persistent companion feelings

All companions, including offline ones, share the six axes originally used by the life archive: joy, tiredness, missing someone, curiosity, hurt and safety. `companion_heart.gd` owns these values. The life archive reads the same feelings; switching model tiers does not create a different emotional state.

`content/heart.json` defines initial values, slow return toward those values, real event effects, neglect and work/rest rates, visible symbols and candidate score adjustments. Feeling happy favors company, feeling hurt favors quiet activities, and tiredness favors the existing rest actions. World still validates every action. Feelings never change physical movement speed, production, success or relationship scores. No sleep requirement or new sleep gameplay is introduced.

Optional schema-7 `companion_hearts` saves values, the last reason, last actual contact and bounded daily mushroom counts. Missing legacy data starts at resting values. Retained memories are baselined on restore, so old meals and activities are never replayed for emotional credit. Invalid numbers and fractional counters reject the save through the original validator.

Only new real shared facts, actual meal completion, flower delivery, actual dialogue contact, current weather and elapsed work/rest/absence affect feelings. AI mood changes are limited to eight points per axis per accepted plan. The mind panel shows words and a reason; symbols and small procedural changes to existing poses communicate feelings in the world. These effects do not modify the original editable character art or World routes.

所有伙伴（包括完全本地的伙伴）共用六维持续心情。生命孕育档案读取同一状态，换智能或档位不换一颗心。心情只改变候选偏好与现有动作表现，不改速度、产量、成功率或关系分。存档兼容旧档，不重播旧经历，不恢复任务。参数集中在 `content/heart.json`；玩家在心里话面板看到心情词与真实原因。

## AI intentions

The native compatible API can return `intention` alongside a normal reply, or a bare intention object for a heart request. The host offers ready activities with their current prerequisites, current mood/hunger/place/weather, nearby companions and the last five actual outcomes. Fixed persona and the same MemoryBooks card accompany it. Only an exact offered ready activity is accepted. Optional places and peers are restricted to that option; unsupported coordinates, invented activities and human invitations grant no authority.

An accepted plan is a high scoring local executor candidate, below explicit player orders and very hungry behavior. A native heart request does not hold the body while the next idea loads. Every started plan settles as completed, failed, interrupted or timed out, enters the trace and the resident's memory book. Pending plans are session only; loading never resumes them. Mood deltas are bounded and cannot handle materials or change relationships.

Native autonomous requests reuse the existing enabled tier, presence, cooldown, hourly/daily token reservation and quota ledger. Low remains player-message only. The calm reminder falls between 90 and 120 seconds, subject to tier and presence gates. Completion, dialogue, proximity, hunger edges, mood reasons and invitations can request a new decision. Only one owned request runs at once, waiting at most 120 seconds, while the body continues its current or local activity. Malformed replies, network errors, unsupported choices and exhausted quotas leave local life running. Explicit stop/source changes retain their existing revocation barriers.

Round 3 adds named outings, optional company, player invitations, real gifts, roses and writing through their own systems. The host keeps the executable parts and returns reasons for discarded fields. Fishing proposals require the original player confirmation. Today's wishes share the Life Archive's previous wish records, and only real World and gameplay receipts can finish them. The mind panel shows today's status, the first completion is visible in Our Days, and unfinished goals can appear on the evening diary page.

接入原生兼容 API 后，AI 可以从宿主当前可做清单里决定去哪里、做什么、与谁同行。玩家命令和很饿优先；不支持的地点、同伴或物品逐项剔除，原因放回下张卡。钓鱼邀请仍走原确认，花朵扣真实仓库，所有路线由 World 执行。自动打算仍须按档位显式开启，低档只响应玩家消息；额度、在场和冷却规则不变。慢回复期间本地继续生活，失败不假装完成，读档不恢复打算。

今天的小心愿与原生命档案共用愿望记录。接入的伙伴可在晨间小卡选愿，未接时按性格选。心里话显示当前状态，真实首次完成记进「我们的日子」，未完成的当天夜里写进日记。


The current intention card also includes nearby people's actual activity, the current mood reason, recent retained MemoryBooks facts and unfinished intentions. Deleted book facts are excluded. Prompt guidance asks for a small, personal and context-grounded purpose while leaving activity selection to the model. Local idle cooperation and automatic idle providers yield to an accepted AI intention; player commands, stewardship and very hungry behavior keep priority. Host-generated unique IDs keep same-time outcomes distinct. Ending an island session records accepted unfinished intentions as interrupted; it never invents completion.

Round 4 separates a same-region invitation from permission to move. The recipient decides through her own native autonomous turn when available, or through local personality and current state. Only the exact recipient and active invitation may accept. Each participant owns her own World route; arrival, refusal, departure and the capped four-line exchange are separate receipts. The player's card expires after 15 seconds, and only a click on its explicit travel choice can start the human route. A timeout can continue the resident's outing alone.

The activity card includes the last 15 game minutes and current-day counts. A third accept for the same resident and activity in that rolling window is rejected with a reason. Player commands, held questions, hunger, assembly and stewardship still take precedence; continued native thinking does not hold the body.

第四轮把同区邀请、回复、路线和到场分别记回执。伙伴用自己的原生回合答复，不能出发时保留拒绝理由；本地按性格和当下状态决定。同一段最多四句，仍走村里的说话闸门。玩家卡限时 15 秒，只有点明确的同行选项才会给主角发原 World 路线。每位伙伴同一活动滚动 15 游戏分钟最多接单两次，第三次告诉她为什么不给接。

当前打算补充真实邻居状态、当前心情原因、统一记忆本仍保留的事实与未完成打算；删掉的事实不重新注入。提示鼓励自己的小目的，活动仍由AI从宿主清单选择。本地无物资合作场景和空闲provider让出已接受打算，玩家命令、托管、很饿仍优先；退出时记真实中断，不假装做完。

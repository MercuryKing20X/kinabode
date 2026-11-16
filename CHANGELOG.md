# Unreleased — v0.8 connection

- Added native OpenAI-compatible API connections and loopback URLs for Ollama/LM Studio, including incremental SSE, local credentials, provider-neutral resident cards and existing quota/cancel gates. Codex remains an optional local Python integration.
- Added player-selected AI quotes in the memory book, with retained provenance and bounded offline speech through the original Director gates.

# Changelog / 更新记录

## Unreleased — v0.7 round 6 / 未发布

- Restore natural need bubbles within the original ordinary speech opportunity; keep earned LocalDialogue turns, factual reminders and their existing gates. / 恢复原普通发言机会中的需求气泡，保留本地对话“三旧换新”额度、事实提醒与原闸门。
- Order equally old needs deterministically and restore true catch thanks while pending fish still blocks idle movement. Bubble clicks use original host commands and real fishing. / 同龄需求确定性排序，待安置真鱼仍阻止闲暇移动但可说真实感谢；点击仍走原指令和真实钓鱼。
- Admit ordinary host-interaction approaches only when the speech gate opens by the next decision; retain priority for committed host-event replies. Morning rhythm returns without changing scores or content parameters. / 普通主动互动只在原发言冷却将于下一决策前结束时参与候选，真实主角事件反馈仍优先；不调分值或内容参数恢复晨间节律。

Validation / 验证：first complete suite **405/406**; original health and brain failures passed. Restored the original earned-dialogue substitution after the remaining LocalDialogue regression; seven focused commands then passed. Second and final complete suite **406/406**, zero failures (5209.2s); no third full run. / 第二遍也是最后一遍完整全套406/406，零失败（5209.2秒），未启动第三遍。

Balance / 平衡：one-day banter **4.688%**, small cooperation **5.067%**; full/slightly hungry food waiting **0%**; signature activities remain in the top five; proactive host interactions **7/7/8/5** in one day; original exact same-seed checks pass. / 一天拌嘴4.688%、小合作5.067%，饱饱/有点饿等饭0%，招牌前五、主动互动7/7/8/5及原同种子完整一致断言通过。

No new content, balance tuning, real model calls, artwork or player-data edits. Not released or merged. / 无新内容、平衡调参、真实模型调用、美术或玩家档修改；未发布、未合并。

### Known issues / 已知问题

Three historical standalone brain probes outside the registered 406-command suite fail both in the round-five base and in the earlier round-six probe run, with matching assertions. They remain diagnostics to investigate, not passing acceptance evidence. / 三个未登记进406套件的历史独立探针，在第五轮基线与本轮收尾前探针版本均同断言失败，保留调查，不称验收通过。

| Probe / 探针 | Failing observation / 未通过观察 |
|---|---|
| `test_brain_interactions_input.gd` | Early idle/rain interaction window. / 早期站定互动窗口。 |
| `test_brain_polish_input.gd` | Blue's night-rest arrival after a real meal. / 真实用餐后小蓝夜休到达。 |
| `test_brain_social_contract.gd` | Legacy pair-sweep arrival, host-absent activity and peer comment. / 旧双人扫地会合、主角离开后的共同活动及点评。 |

## v0.7 round five validation history / 第五轮历史记录


- Restore legacy-save initialization and loading; reconstructed resort-v1 fixtures preserve owned carry, storage counts and retained memories. / 修复旧迁移World的大脑初始化与实际读档，复刻旧档核对本人背包、仓库及保留记忆。
- Reconnect daily gestures, schedules, relationship rewards, memory reminders, moods, return visits, cross-island following and hungry onlookers through the resident brain and original executors. / 每日小事件、日程、关系奖励、回忆、情绪、回访、跨岛跟随及火边旁观接回大脑，沿用原路线、座位和任务执行器。
- Preserve the follow queue and its small-movement still zone; nearby shelters respect the existing six-tile follow radius. Natural pair exchanges share speech validation without spending each other's quota. / 保留跟随队列及小幅移动不动区，跟随避雨遵守原6格范围；新旧双人对话共享验证、各守原额度。
- Synchronize the original personal clock before its speech window, and keep clickable need bubbles clear of the actual campfire target. / 原居民时钟先推进一次再开说话窗口，需求气泡避开真实营火点击区域。
- Skip disabled-brain sampling and restore exclusive scheduling for measured slow tests; original deadlines and content parameters remain. / 关闭日常时跳过无效大脑采样，恢复慢测隔离调度，原时限与内容参数不变。
- Recognize direct Chinese/English fields and paired arrays in translation checks; retain a deliberate missing-translation negative fixture. / 翻译检查识别中英字段及成对数组，并保留故意缺译的反例。

Validation / 验证：two complete suites: **401/406** and **404/406**, with five then 2 failures; no third full run. The original 36 failures now have 35 passing cases. All original deadlines and assertions remain. / 两次完整全套401/406与404/406，失败5→2项，无第三次全套；原36项中35项在最终全套通过，原时限与断言保留。

Balance / 平衡：banter 5.858%, small cooperation 5.250%; full/slightly hungry waiting-for-food time remains 0%; signature activities remain in the top five; proactive host interactions 7/8/9/7; identical same-seed traces and statistics. / 拌嘴5.858%、小合作5.250%，饱饱/有点饿等饭0%，招牌活动前五、主动互动7/8/9/7及同种子完整一致均达标。Morning top-three rhythm remains a separate failed assertion, listed below. / 晨间前三节律仍单独失败，见下表。

Performance / 性能：four brains 704.219→523.463 µs/frame; disabled daily life 175.384→10.560 µs/frame in the same isolated probe. Final camp click 71.638s versus v0.6.1 69.716s; original 90s deadline unchanged. / 同隔离探针四人大脑704.219→523.463微秒/帧，关闭日常175.384→10.560；最终营火点击71.638秒，对照v0.6.1为69.716秒，原90秒时限不变。

No new content, dialogue, artwork, model calls, player-data edits or content-parameter tuning. / 无新内容、台词、美术或真实模型调用，不改玩家数据及内容参数。

### Known issues / 已知问题

| Test / 测试 | Cause and next step / 原因及后续 |
|---|---|
| `test_brain_30min.gd` | The fixed-seed morning top three are cooperation, host interaction and banter; stretch and weather watching occur but rank fourth/fifth. This rhythm assertion passed in polish 4 and remains a regression. Review opportunity allocation within the original scores and repeat across seeds; retain the assertion. / 固定种子晨间前三为小合作、主角互动、拌嘴，伸懒腰和看天气真实发生但排第四/五；该节律断言第四轮通过，本轮仍回归。后续在原分值内核对机会分配并复验多种子，保留断言。 |
| `test_health_ai.gd` | The natural fish-need bubble is starved by competing idle speech, so real click/catch/thanks remains unverified. Stub dispatch, actual harvest and fallback explanations pass. Arbitrate old needs and brain interactions without changing the 180s need cooldown or the original reminder/speech gates. / 自然鱼需求气泡受闲暇发言竞争压制，真实点击、本人钓获和感谢仍未完成验收；桩派发、真实收成及退回说明已过。后续统一需求与互动的机会仲裁，保持180秒需求冷却及原回忆/说话闸门。 |

## v0.6.1 — 2026-11-13

- Downloadable Windows x86_64, universal macOS and Linux x86_64 packages, with licenses and bilingual launch/save instructions. Local play needs no Godot or Python. / 三平台可直接打开的游戏包，附授权及中英打开/存档说明；本地玩法无需Godot或Python。
- Bundle original translation text and validated audio in PCKs; load imported textures correctly in packaged games. / 修复打包后翻译原文、音频SHA验证及导入纹理读取。
- Added 256 bilingual barbecue scene pairs (eight per personality/scene); 80 use font-checked kaomoji. Meal/day/consecutive-scene variety preserves existing speech gates. / 新增256组中英烧烤场景台词，80组颜文字，原说话闸门保留。
- Removed stray pixels from Clem's first side-running frame and raised her running upper body slightly, preserving foot anchors and action order. / 清理小橙侧跑首帧杂线，身体略抬高，脚锚和动作次序不变。
- Test-only reproducible world/weather/RNG/simulation clocks, isolated data/user directories and stable real-mouse fixtures. IPC freshness/expiry retains real shared time. / 仅测试启用确定性输入与独立目录，修真实鼠标夹具；协议新鲜度与过期仍使用双方真实时钟。
- Added the GitHub link to About and README; start screen shows v0.6.1. / 关于与README补GitHub地址，开始页显示v0.6.1。

Validation / 验证：Mac package new-game 45/45 and restart/continue 39/39; quick checks 6/6; three package scans have zero findings. Windows/Linux archives and embedded PCKs verified, **not tested on those operating systems**. / Mac包新游戏45项与重启继续39项通过，快测6/6、三包扫描零命中。Windows/Linux仅结构与PCK验证，未实机测试。

Two consecutive complete suites on identical code: **395/400** and **397/400** (4009.5s / 3648.8s), source changes zero. Results were **not all green or identical**. Post-suite fixture corrections and focused results are reported separately below. / 同代码连续两次完整全套395/400、397/400，两轮源码变化0，未达到全绿或结果一致；收尾夹具修复与专项结果另列。

### Known issues / 已知问题

| Test / 测试 | Full 1 / 2 | Status / 状态 |
|---|---|---|
| `test_overnight_player_standard_moon.gd` | Fail / Pass | Intermittent real-world camp click; body hit is logged, signal/bubble interception was not. Cause unconfirmed; diagnostic logging added, assertions intact. / 正式月牙营火点击不稳定，原因未确证，追加诊断，原断言保留。 |
| `test_camp_click_approach.gd` | 90s timeout / Pass | Added explicit exclusive scheduling after deterministic order dropped the old timing-based isolation; 90s limit unchanged. / 固定排程丢失旧慢测隔离，已恢复显式独占，90秒不变。 |
| `test_about_document.gd` | Fail / Fail | Updated the obsolete author-heading fixture to the current unchanged document and added byte/head/tail checks. / 旧作者标题失配，夹具更新为现行原文并加完整字节及首尾检查，作者原文未改。 |
| `test_save_backup.gd`, `test_backup_main.gd` | Fail / Fail | Kept archive timestamps/calendar real in the test overlay; freezing them had created ordering ties. Production backup code unchanged. / 测试overlay归档时间保持真实，修固定时间造成排序并列；生产备份代码未改。 |

After the two complete suites, all six focused follow-up commands passed: import, About fallback (11 checks), archive backup (45 checks), backup/Main integration (8 checks), exclusive camp approach and diagnostic Crescent camp input. This was **not a third full suite**; complete-suite stability is still unproven. / 两完整轮后收尾6项全过：导入、关于回退11检查、备份45检查、主场景备份8检查、独占营火接近和月牙点击诊断。没有跑第三次全套，不声称最终全套稳定。

The original six v0.6.0 full-suite failures all passed in both complete v0.6.1 runs. All original gameplay thresholds remain. / v0.6.0原六项失败在本次两轮完整全套均通过，原玩法底线保留。

- Barbecue daily line history is session-only; restarting the application clears that speech history. No old dialogue is replayed. / 烧烤当日台词去重记录仅保留在当前应用会话，退出重开后清空，不回放旧句。
- Optional AI connections require Python 3 and your own credentials; model costs are yours. The complete local game remains available without Python or AI. / 可选AI需Python3与自己的密钥、费用自理，本地玩法完整可玩。
- Lifeblood has not had a long real-model soak test. Tested by the author only on a MacBook M1 with 8GB RAM. / 生命孕育未长期真实模型试跑；作者只在M1 8GB实测。
- Original artist/permission records for eight fan-derived appearance designs remain incomplete; see CREDITS. / 八套同人原设计作者与许可记录仍不完整，见CREDITS。

## v0.6.0 — 2026-11-13

- A connected island home, Crescent Island, the mist-covered Dark Island and a holiday island.
- Four distinct companions, hunger expressions, shared barbecues and real physical ingredients.
- Fishing, fish records and pens; farming, construction, furniture and editable pixel works.
- Gomoku, covered chess and local playground games.
- A local steward who coordinates physical jobs; optional AI provides bounded suggestions and speech.
- Private/group dialogue, retained memories, journals and optional Lifeblood intelligence.
- A bilingual introduction, versioned start screen and cross-platform quick-check entry point.
- Fixed group-follow command precedence and aliases, standard-opening mouse run/eat flow, and external adapter heartbeat timing.
- Fixed routes clipping farm-fence corners with continuous checks against the original collision boundary.
- Fixed isolated false terrain rejection at exact floating-point positions using the original polygon and double-precision containment verification.
- Fixed local dialogue repeatedly choosing host remarks while suppressing coastal observations: select the next type only after a line is actually delivered, preserving the original cooldowns and speech gates.

修复路线擦入原农栅圆角，以及精确浮点位置被原土地多边形错误判为不可走；不改变围栏碰撞半径、地图轮廓或人物速度。修后同批50个固定种子与默认随机连续20次全部通过。

修复本地短句有时一直谈岛主、海边感想始终出不来的问题：只在真实发言交付后选择下一类，原冷却、交付额度与发言门控保持。

Final focused validation passed all 50 fixed seeds, 20 sequential runs in the default random mode, and seven shared-system checks. / 最终修复树定向验证：固定50/50、默认随机串行20/20、相关系统7/7全部通过。

四座岛、四位伙伴、真实烧烤/钓鱼/种菜/建造、下棋与小游戏、本地托管、记忆与可选AI；修复群体跟随、正式开局跑吃输入和外部适配器心跳。

### Known issues / 已知问题

The last complete development suite, at source commit `8fcb32a`, passed **393 of 399 tests**. This export uses quick checks and release smoke validation; it does not claim a new full-suite pass. The six failures remain in the test source with their assertions and thresholds intact. / 最近一次完整开发全套（源码提交 `8fcb32a`）为 **393/399**；本次导出按快测试和发布冒烟验证验收，不声称重新跑过或通过全套。以下六项失败的测试及原断言、门槛全部保留。

| Test / 测试 | Last full-suite failure / 最近全套失败 |
|---|---|
| `test_local_life_15d.gd` | Clem spent 40.555556% of the measured time near the player, above the original 40% threshold (125 seconds over). Task interruptions and blocked work were zero. / 小橙近人40.555556%，超过原40%门槛125秒；任务中断和阻塞均为0。 |
| `test_their_island_story_input.gd` | Two arrival lines were missing, with dependent four-person fact summaries and plan memories also failing; the exact cause is unconfirmed. / 两人到达发言缺失，连带四人事实汇总与计划记忆失败，精确原因未确证。 |
| `test_fish_v3_input.gd` | The second fishing invitation/confirmation did not trigger the real fishing job. The first catch and stocking passed; the exact input cause is unconfirmed. / 第二次开钓邀请与确认未触发真实钓鱼任务；首次捕获与入塘通过，具体输入原因未确证。 |
| `test_orange_sunflower_input.gd` | Command and wardrobe UI entries did not trigger, with dependent chopping, old-work and reload branches failing. / 命令与衣柜入口未触发，连带真砍树、旧作品和读档旧外观分支失败。 |
| `test_title_fit_input.gd` | About Close and language/title switching failed at 960×640 at selected UI scales; later configurations passed. The exact input cause is unconfirmed. / 960×640部分缩放档关于关闭和语言/标题切换失败，后续配置通过，具体输入原因未确证。 |
| `test_health_ai_labor.gd` | The fixture expected today's call count to remain one after advancing across Shanghai midnight; the counter correctly reset to zero. Physical jobs and conservation checks passed; one fake turn was observed. / 夹具跨上海午夜仍预期今日调用数为1，计数实际正常清0；真实任务与守恒通过，仅观察到一个桩回合。 |

- Some tests vary with random worlds, weather and time, and input-heavy checks can be unstable. Stabilizing these tests is the first v0.6.1 task; this release does not remove or weaken them. / 部分测试受随机世界、天气与时间影响不稳定，真实输入检查也有波动；v0.6.1首先修测试稳定性，不删测、不放宽。
- Lifeblood has not had a long real-model soak test. Its long-term behavior, stability and costs are not yet validated. / 生命孕育未长时间真实试跑。
- Tested by the author only on a MacBook M1 with 8GB RAM. Other hardware is unverified. / 作者仅在M1 8GB上测试过。
- Eight fan-derived appearance designs lack complete original artist/permission records; see CREDITS. / 八套同人原设计作者/许可留档不完整，见CREDITS。

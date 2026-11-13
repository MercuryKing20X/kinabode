# Changelog / 更新记录

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

# Changelog / 更新记录

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

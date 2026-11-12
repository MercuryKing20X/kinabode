# 约定 · 无人值守阶段3

PromiseSystem是游戏引擎的有界日程，不是模型调度器。配置content/promises.json：每居民最多3条，未来最多7个游戏日，有效窗口默认600秒、最多600秒，且不越过所约时段结束，执行超时600秒。复用DayCycle的origin/day_seconds/phase.start计算到期点；无新增日历或作物时钟。

v2 `promise` 参数action_type、target_id、day、phase，可选valid_seconds；`promise_cancel`只接受本人promise_id。仅支持已有water/harvest（真实地块）、fish（真实海域且到期本人已在自然岸边）、come_near（human）。目标、日期、时段、身份和数量无效整条拒绝；登记只存约定，不移动或扣物资。不能登记/操纵human，不能改别人约定。旧原生工具/schema及VERSION0.4.0保持，仅v2扩展。

到期仅调用原World.command，接受后跟踪准确owned job_id；使用原Farm/Fishing/ResidentActivity动作，取料、路线、携带和份数全部沿原规则。到期忙碌/待答/集合时每30秒重试，最晚到该时段结束（显式更短有效期仍优先）；不抢已接受的工作。时段耗尽、控制源改变或条件不足才记“没能做到”，不抢活、不补做、不生成物资。完成必须有真实Work完成事件；来找玩家还要实际同区域且在距离内。停止/取消仅停止准确归属任务，真实carry/投入保留。游戏任务事件标source=promise，实际钓获等结果有因果屏障，完成/失败重新起算原自主冷却，绝不唤醒模型或连锁推理。

schema7新增可选promises.version1/entries，旧档缺字段为空，不补历史。保留未到期pending；重载中断running或离线错过的约定不恢复任务，写“未确认完成/未恢复”的真实结果；读档后的carry由原SaveStore规则恢复，不重取、不复制。

结果以promise_result直接写入现有SharedMemories：participants为承诺居民与接收约定的玩家，不代表玩家共同劳动；facts含resident_id/action_type/target_id/day/phase/outcome(completed/failed/cancelled)/reason。只记录真实终结，不记录虚构履约。沿原diary256，marks192不增，无额外旧结果流水可重导入。原回忆面板和只读kind过滤支持新类型。

memory_reminders只增加promise_result事实模板与本人类型分支；保留原身份过滤、近人、held/碎碎念/个人与全村冷却/停止安静期等全部规则，依然local_rules、不调用模型。没有重做情绪、旧事、家园、天数、背包或农作物行为。居民连接的生活页显示待办约定，并提供明确取消按钮，不新增顶栏按钮。


边界：钓鱼约定不会替居民自动选陌生海岸，须到期在约定自然海域岸边；独立做菜及cook约定已删除，旧可选cook约定读取时忽略，不补做或冒称完成。忙碌仅在本时段有界重试，过时不补做；重试时间仅内存态，重载仍按原中断规则，不恢复工作。未做真实提供方验证。



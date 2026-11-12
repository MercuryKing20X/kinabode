# 2026-11-10 烧烤计时与伙伴默认跑步

用户确认：蘑菇整场60秒、普通料理90秒、鱼料理120秒；底部按钮上方倒计时，到点结束围炉、保留真实实吃/浪费结算，后续安排解除围炉占用。新计时餐存档保留实际食物/剩余秒数，读档暂停、不续任务，火边明确“继续这顿烧烤”后恢复，不再扣料；旧无计时档沿原兼容。


---

# 2026-11-07 烤蘑菇无限供应

只有 `single:mushroom` 无限供应，选中时按实际邀请人数生成可食份数，食材收据为空，不消耗仓库或随身蘑菇；实际进食和浪费仍逐份核算。含蘑菇的料理仍扣真实蘑菇，其他单品不变。原有带真实蘑菇收据的存档仍有效。直烤鱼点火及添柴只从仓库扣原有木材数。

---

# 2026-11-04 邀请路线检修

已确认邀请的围炉参与者优先于闲置仓库递交和新的本地闲暇；仅撤回递交器本人拥有且没有真实工作任务的路线，携带物资保留。明确主人工作不打断。异岛、待安置鱼/家具、主人任务明确返回双语原因；原直烤很饿拒绝及就座held/安静期门控不变，邀请页显示本人姓名与原因。主岛房间可沿原门口路径出屋，不强行跨岛。原饥饿/权限/材料/速度/说话闸门不改。


---

# 2026-11-03 唯一系统仓库覆盖

生火2木材、燃着时续火1木材，均本人随身不足补唯一仓库，烧烤食材同接口；不再查箱权限。旧箱来源迁移的已付炉上食物读档保留；普通新档仍按原v4结算剩余食物。清邀请/任务/座位，由玩家重新邀请继续，不自动代人操作。 详见[SYSTEM_STORAGE.md](SYSTEM_STORAGE.md)。下方旧版箱子描述为历史，不覆盖本条。

---

# 共同烧烤（2026-10-30 v4）

烧烤是伙伴唯一吃饱的方式。主岛和月牙岛使用同一套 Fireside，所有操作绑定精确 station_id；World 唯一控制路线，Work 管真实就座任务。游戏内零模型调用。

## 玩家流程

1. 玩家点击已建营火或其按钮可授权主角经World路线走到5格内，抵达后再点击或自动执行「生火」或「续火」：扣2木材，增加180秒炉火。
2. 点击「烧烤」，在邀请页选择伙伴；最上方「所有人」选择当前四位伙伴，下面可逐个勾选。选择本身不移动任何人，也不扣料。
3. 下一步打开「今天吃什么」餐厅菜单。上区「基础烤物」一种食材，蘑菇第一且3秒完成；其余单品5秒。下区「料理」保留全部原菜谱和解锁条件，8秒烤好。缺料卡仍可见并置灰，逐项显示「有／还差」及获取提示。
4. 点击「开烤」才提交本次邀请、真实扣料。受邀伙伴经原 World 路线走来；主角仍在火边时自动一起坐下吃。未受邀者绝不吃，饿着仍可跟随玩家。实际吃满4秒才扣食物并恢复饱，随后围炉。

火边只有「生火／续火」与「烧烤」两个按钮。无独立做菜、搬料、翻面、手动吃、喂食、打包、数量加减、盘子、剩菜或旧批次恢复入口。

## 物资与不足

生火和开烤都先扣主角背包，再补足本人有权使用的共享箱、私人箱及本人管理的已开放农庄箱；排除伙伴私人箱、非本人管理的农庄箱和他人认领箱。主角必须在现场，箱子不用搬来；本地居民没有取箱权限。顶栏、菜单与实际扣料使用同一可用库存口径。木材不足明确显示「木材不够：背包 X + 箱子 Y，需要 2」。

不在界面显示份数。内部按受邀伙伴加现场主角自动计算：单品每人一件；料理以原完整配方批次做够人数，库存不足则只做真实可做的批次。分不到的人不吃、不恢复饱。料理多出的食物立即记真实浪费；取消、离开、熄火或重载时尚未吃掉的也记浪费，不留可恢复食物，不退回原食材。制作中拒绝重复开烤，不重复扣料。

鱼必须为主角实际举着的唯一实例。原体型产出1/2/4/8保持，鱼菜另扣原配方蘑菇；鱼实例只移除一次，吃不完同样浪费。没有复制、箱中取鱼或免费食物。

## 双营火、座位与中断

world.barbecues 注册每个 SharedLife；world.life 仅为主岛根记录。Fireside.near、邀请、就座、点火动画、火焰火星、夜光、语境和附近座位均按该点解析。主角可走桥到月牙岛，没有旅行或传送。

每点8席均匀一圈，按对面优先、分散象限入座，停稳后朝火；移动期间朝向始终服从实际位移。座位认领与任务精确绑定自有 job_id。停止、提问、集合、换来源仅结束所属围炉任务，保留无关真实工作与物资；新一轮必须再次明确邀请与开烤。主角离火超过30秒结束围炉；火灭也结束。

小蓝等吃货只有饿了及以上、被本次开烤确认邀请、空手且未受任务／held／提问／集合／停止限制时飞奔。普通聊天开饭词、仅看到火和未受邀旁观均不触发；保留原速度、冷却与 Director 发言闸门。

## 记忆与保存

真实围炉结束后仅实际吃完的人进入 canonical shared_barbecue（facts.version2），记录 station_id、真实食物与参与者；不把选择或到场冒充吃过，不伪造旧做菜记忆。沿用关系日／终身上限与 diary256／marks192，不重复奖励。围炉对话仍保留碎碎念、held、提问、集合、停止等闸门与气泡避让。

schema仍7，station.fireside.version4 保存实际燃料、食材收据、鱼来源、已吃／浪费审计，extra_barbecues 保存额外点。严格校验总量＝实吃＋浪费＋尚在炉上。重载不恢复任务、路线、邀请或座位，剩余食物结算浪费。用户明确允许不兼容已删玩法：旧 cooking、shared_activity、meal:* 携带和旧 fireside 可选字段加载前忽略，不补库存或历史；原箱子、原材料与玩家作品不受此处理。

## 验证


## 旧规则归档（已由2026-10-30用户授权替代）

以下仅保留逐字迁入记录，供来源追溯；不是当前玩法，不能恢复已删入口。现行规则仅以上方v4为准。

<a id="agents-migration-17"></a>

SharedActivity is a host-started engine coordinator over existing World/SharedLife jobs, not model inference. Participants and facility seats come from configuration; no fixed model roster. Never move or act as human without the matching explicit UI action. Preparation uses real2 wood plus1 mushroom per diner, fixed20 carried; default legacy grill remains2 portions. Questions/stop/assembly/source changes pause the activity; cancel only exact owned_job_id. Reload restores paused with no jobs/claims, explicit resume routes guests back before continuing; no work auto-resume. Meals and completion events credit actual consumption and finished cleanup only. Activity decisions are host-only, not new external model tools; keep existing model sessions/driver versions. Tests use temporary data and fake adapters; docs/SHARED_BARBECUE.md.
# 2026-11-04 邀请原因补验

邀请页逐人显示具名折行原因，提交后状态同样列出本人及原因；本人气泡仍受原Director门控，不强制同时发言。104状态组合208居民fixture通过（140实吃/68拒绝），忙碌/位置前置为明示夹具，非104条无设坐标原生全过程。另两开局四营火8条原生步行/跟随/邀请/实吃全过，此前历史保留。

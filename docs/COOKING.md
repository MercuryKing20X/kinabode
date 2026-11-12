# 2026-11-12 无限烤蘑菇菜单事实修正

DIRECTION 2026-11-07 的例外仍有效：仅 single:mushroom 永远可选、按真实受邀者供餐、食材收据为空。菜单 ingredients 现为空，避免托管候选把库存为零的免费烤蘑菇误判为不可用；菜单仍显示无限供应。其它单品和含蘑菇料理照原配方扣料。

---

# 2026-11-05 跨岛料理

保留原五道与蓝莓果酱解锁；新增22道六键配方和独立双语元数据、12种基础烤物。鱼种专属菜在菜单、付款前和保存校验均验证本人唯一真实鱼及指定鱼种，鱼干是实际晾制后的独立库存物品。四位主性格各一招牌，换外观不换口味；真实吃完时才记signature_taste，不加关系分。烤熟提交cooked记录，食材实际拿到后可发现菜谱，旧档不补历史。菜单按能做／只缺一种材料／其它排序、类别筛选，基础烤物可折叠；手册菜谱页只读现有事实，列所需唯一真鱼及指定鱼种，提示对应实际已建的产出设施，不补发现。

---

# 2026-11-03 唯一系统仓库覆盖

料理仍只在Fireside，由主角明确开烤；全部成本从本人随身不足补唯一仓库，来源backpack/storage。无实体箱、取箱、独立烹饪、自动取食。 详见[SYSTEM_STORAGE.md](SYSTEM_STORAGE.md)。下方旧版箱子描述为历史，不覆盖本条。

---

# 料理已并入烧烤（2026-10-30）

独立做菜按钮、CookingPanel、CookingSystem 与其准备／供餐流程已删除。原菜谱全部进入两个营火的餐厅菜单「料理」区，实际流程与授权边界见 [SHARED_BARBECUE.md](SHARED_BARBECUE.md)。

BarbecueRecipes 仅负责读取和严格校验原配方内容、解锁与鱼体型产出；不持有工作、灶台批次或取料权限。花圃真实完工仍是蓝莓果酱解锁门槛，配方六键、原材料成本与鱼体型产出不变。没有独立 cook/cook_read 入口或做菜约定；旧动态工具／驱动版本保持，发送已删动作只明确拒绝，不触发人类动作或扣料。

主角在营火3格内明确开烤，才从背包和有权箱子原子扣食材；受邀人数自动决定批次。配方多出的直接浪费、库存不足只烤真实可做的量，界面不显示份数，不留剩菜。主角和受邀伙伴真实吃完才恢复饱。取消和重载无退料、重复取料、打包或恢复旧批次。

schema7 读取旧料理可选字段时忽略，不执行旧任务，不给物资／记忆；新保存不写 cooking 对象。历史已提交的真实记忆保留只读验证，不作为再次制作或奖励来源。


## 旧规则归档（已由2026-10-30用户授权替代）

以下仅保留逐字迁入记录，供来源追溯；不是当前玩法，不能恢复已删入口。现行规则仅以上方v4为准。

<a id="agents-migration-11"></a>

M1 CookingSystem prepares fixed recipes at existing home.barbecue, using World/Work pickup, the fixed CARRY_LIMIT carry and actual station buffers; SharedLife alone owns seating, completed-portion debit, rising and cleanup. Original barbecue remains2 wood plus1 mushroom per diner. Cooked fish must be the chef's unique pending/pen instance: location=cooking while held/preparing, erased exactly once on serving; never put fish in chests or duplicate them. Stop/question/reload preserves ingredients, fish and portions; preparation reloads paused with no jobs/claims, original chef explicitly resumes the same batch. Single station/batch; no discard or chef reassignment. Human preparation/eating/cleanup requires the matching explicit UI action. One meal event after actual eating and cleanup separates invited/actually seated/actually finished diners; no passerby credit. farm_meal adds unified memory only at completed enjoyment; its legacy earlier debit remains unchanged. See docs/COOKING.md.

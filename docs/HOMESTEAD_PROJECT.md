# 2026-11-03 唯一系统仓库覆盖

唯一仓库提供真实木材和作物，开工直接按可用部分扣入site累计，不搬料；老receipt只换来源storage，本人carry和投入不重复退款。数量/配方/解锁/施工秒数不变。 详见[SYSTEM_STORAGE.md](SYSTEM_STORAGE.md)。下方旧版箱子描述为历史，不覆盖本条。

---

# M4 家园工程第一级 · 石砌花圃

2026-10-26完成。规格：`design/quick-specs/homestead-2026-10-26.md`。本专题与历史 `HOMESTEAD_AND_MAP.md` 分开；只实现一级，不开始M5。

## 入口与实际流程

顶部「家园→家园工程」、右上「居民连接→生活与安排→家园工程」或点击工程点打开面板。打开、选居民与查看只读，不移动任何人。人类只有点自己的取料、继续或施工按钮后才行动；主机可明确安排选中的有工作能力居民。外部模型只能操作绑定的本人，不能指定其他actor或操作human。

工程点由 `godot/content/homestead.json` 配置：home区域，矩形 `[26,38,4,3]` 格，入口 `[28,42.5]`。一级24木材＋10作物，作物混合按件累计，不用鱼。实际施工6秒，任务包含行走的总超时180秒。阶段为未开始、分批备料、材料齐备、施工中、花圃完工。费用、位置、阶段名及菜谱ID均在内容文件，不在逻辑写坐标或费用。

1. 选择本次木材/作物上限，明确开始。沿用ConstructionProjects的每人一个计划和Work引擎任务模式，没有复制房屋阶段或模型轮询。
2. 木材从家园公共仓库取；作物只从本人有管理权限的农庄收获箱取。种子箱、公共箱中的作物和无来源的原有携带物均不作为工程作物来源。不是免费库存，箱子空或缺料会拒绝/阻塞并说明。
3. World负责路线；Work负责携带空间及取放动作，每人独立固定20件。到箱边再核对实际物资，逐捆真实转入手中；到工程点后才从手中扣除并记入delivered/contributions。
4. 先交5木3作物就只记5/24、3/10。缺料保留投入；继续需本人现有plan_id。交齐后停止交料并显示等待明确施工，绝不自动完工。
5. 明确施工才申请唯一工程点认领，走到入口，推进6秒现有building动作。实际完成一次后显示静态花圃，解锁蓝莓果酱。完成、重复提交及重载不会再次扣料或解锁。

已开始工程的矩形和完工花圃均阻挡通行，并清理World导航缓存；渲染不移动居民。开工、取料和施工均复查地形、农田、农庄箱、树/树桩、旧宅地/房屋、设施、仓库、人物、已接受路线及未搬走掉落物。被占用明确拒绝并保留投入，不能覆盖旧内容。纯逻辑测试没有设施艺术库时采用保守的12×10格设施包围框，实际运行使用现有设施尺寸。

## 中断、并发和存档

每名居民一个持久计划，各人交付独立累计；只施工时申请工程点唯一认领。新的实际任务不会抢已有用户工作。真实提问、停止、集合/接管/切源沿用现有准确角色的停止/取消路径，只有本人owned_job_id会被停止，不唤醒模型或自动恢复工作。

暂停、取消、缺料、箱子变空、被抢物资、不可达与超时都保留已交物资。取出的材料留在手中，receipt记录本次真实来源和数量；已拿在手中的合法工程材料不需要塞回满箱才能继续交付。若恢复时材料需求已被别人补齐，多出来的材料仍留在手里。取消之后重新开计划需要先把原有携带物按现有规则存好；没有自动退料、毁料或凭空补料。

暂停后若明确去做其他物资操作，原receipt失效，但携带物不变；先存回收获箱，再从真实来源取出。这样不会拿旧凭据给替换物资充当来源。只读查询与stop不清来源。没有把新溯源字段塞入普通背包系统。

存档schema仍为7，新增可选 `homestead`：

- `version:1`。
- `site`：state、冻结的requirements、逐物品delivered、逐居民逐物品contributions、实际施工progress、completion。
- `plans[actor_id]`：id、actor_id、status、reason、budget、receipt（source_id/item_id/amount）。
- `completion` 只在真实完工生成一次：id、actor_id（实际完成施工者）、at（真实Unix时间）、recipe_id。

校验有限数量、总贡献等于总投入、预算、真实carry和来源、计划归属、完成条件；非法档沿用现有可恢复副本规则。旧档缺字段即未开始、无计划、无解锁，不补物资或历史。重载active计划变paused，building现场变ready并保留进度；owned_jobs、任务、路线与认领不恢复，必须明确继续。完工记录不伪装成house_completed，也未添加新SharedMemories种类。

## 解锁菜谱及既有系统边界

`godot/content/recipes.json` 保留原四道菜全部数值，新增蓝莓果酱 `blueberry-jam`：2蓝莓→2份，制作12秒，不含鱼、不额外收木材。锁映射放根级 `recipe_locks`，而非给每道菜增加字段；`valid_recipe` 仍要求恰好6个键，原数量上限和制作时长校验保留。

食材白名单集中为CookingSystem.INGREDIENT_IDS：turnip/pumpkin/tomato/mushroom/blueberry。SharedMemories的真实meal事实校验复用这个列表，防止做出果酱却无法记录真实用餐；不是放宽任意物品。未加入苹果、雏菊或虚构食材。

Cooking保留全量recipe_catalog，可制作recipes只列当前可用项。未解锁直接提交返回recipe_locked；加载完成工程才恢复解锁，没有免费菜谱历史。CookingPanel根据可用ID刷新原选择器，保留当前选择。果酱复用原取料、单灶台制作、上桌、SharedLife就座/吃完扣份数/起身/收拾和真实meal记忆，未复制第二套用餐；原烧烤仍2木材＋每人1蘑菇，鱼唯一实例规则不变。

图鉴、天计数、ForestSystem.clock、农作物生长、背包20上限、树产8木及箱容量未改。居民连接页面的智能程度仍仅前端，Ultra提醒和runtime_active=false保留。本轮没有M5伙伴偏好。

## v2接口

仅追加game_actions / action_contract.py的v2动作，契约版本仍2：

| 动作 | 参数 |
| --- | --- |
| homestead_read | 无 |
| homestead_start | site_id，选填wood_limit/crop_limit |
| homestead_resume | 本人plan_id，选填wood_limit/crop_limit |
| homestead_build | 本人plan_id |
| homestead_cancel | 本人plan_id |

暂停使用既有stop。限额只接收有限非负整数，协议层上限1000，引擎再限制为工程费用；拒绝布尔、小数、NaN、无穷、额外actor/fish和他人的plan_id。沿用准确actor/world/session/generation/request/scope/cancel绑定和工作能力授权。observe给工程摘要、本人计划与动作能力；不含像素数组，返回深拷贝。

`companion.py`及VERSION0.3.0、旧原生DYNAMIC_TOOLS/schema/会话处理未改。旧原生助手忙于已接受工作时的保护仍存在：用observe看摘要，需详细新操作时先stop暂停，再在空闲回合查询/继续；外部有效v2绑定已经实际测试。全为测试客户端和假适配器，不代表各真实模型已推理验证。

## 实现文件与素材

- 新增 `homestead_system.gd`、`homestead_panel.gd`、`homestead_renderer.gd`、`content/homestead.json`。
- 集成 `world_state.gd`、`work_system.gd`、`save_store.gd`、`resident_catalog.gd`、`main.gd`、`island_view.gd`，不把世界移动搬到渲染层。
- 菜谱边界：`cooking_system.gd`、`cooking_panel.gd`、`shared_memories.gd`、`content/recipes.json`。
- v2：`game_actions.gd`、`bridge/action_contract.py`；未改驱动。
- 专项：`tests/homestead_fixture.gd`、`homestead_adapter_host.gd`、`test_homestead.gd`、`test_homestead_controller.gd`、`scripts/test_homestead_adapter.py`；默认入口`run_godot_checks.py`已纳入。
- 手工像素花圃/基础石框和来源：[CREDITS.md](../CREDITS.md)、`build_assets.py`、`flowerbed.txt`、`godot/assets/island/homestead-*.png`。新Godot脚本的uid、PNG导入描述一并保存，不新增美术体系。

## 验证与证据

全部临时HABITAT_DATA_DIR，不碰玩家存档和人物作品，不调用真实模型、不导出或初始化Git。专项96项逻辑检查、35项控制器检查、2项实际外部适配器测试。覆盖真实时间推进和在途180秒超时、5/3分批、混合作物、空箱/缺料/不可达/五类几何占用、目标被取走、满箱、取消/暂停/重载、旧档缺字段、一次完工、锁定/解锁、真实果酱用餐记忆、角色隔离及摘要无像素。


## 未做及已知边界

仅一个固定点、一个等级；不拆除/搬迁、不扩渔场，不做M5。旧地图若该点被占用需在现有玩法内让开，系统不会覆盖或替玩家挪物品。施工人物复用旧building帧，花圃为静态手工像素，非完整新动作或可编辑内容模板。原生忙时v2保护见上；未验证真实模型推理。既有房屋ConstructionProjects的旧存档计划数上限仍是6，本轮家园工程使用居民目录容量，未扩大旧房屋系统范围。



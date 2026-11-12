# M2 · 鱼图鉴 / 海边发现册

2026-10-26。图鉴仅记录真实鱼类发现。保留 M1 做菜，不开始 M3～M5；作物图鉴、目击记录、奖励和伙伴偏好均未增加。

## 本轮体验

底部 **动作 → 功能动作 → 鱼图鉴** 打开“海边发现册”。打开、合上、切居民、切鱼种和查看卡片都只读，不移动人类或伙伴，也不改变已接受的工作。

左侧列现有八种鱼，每种右侧按四配色 × 四体型展示 16 张卡，共 128 种模样。未钓到的格子显示剪影与“还没遇见”，已发现格子显示原有原创像素鱼。点开已发现卡片显示真实的第一次钓获时间、海域和体型倍数。主持人可以分别翻看各居民的册子，模型查询只能读自己的册子。姓名和模型提供方不参与身份判定。

条目维度、排序、书名、短介绍、首次发现的本地短句及分页上限在 `godot/content/journal.json`；鱼种名称、颜色、体型范围和图像仍来自既有钓鱼内容。M2 不改变鱼种/配色/体型权重，也不重新生成鱼素材。

## 什么算发现

仅在 `FishingSystem` 的真实收线提交中：创建唯一 fish 实例、扣除对应海洋库存并标记该精确任务已经钓到之后，调用 `JournalSystem.record_catch(fish_id)`。它再次检查当前 pending 实例、本人身份、实际钓鱼任务及来源。首次发现按 `species_id:color_id:size_id` 去重，记录给实际钓获者。

每种组合只存第一条真实钓获，不累计捕捞次数，不反复弹发现提示；再次钓到同组合不会改写第一次。不会在抛竿/等待/咬钩、取消、失败、取渔场鱼、打开图鉴、谈及某条鱼、附近站着或别人钓到时增加记录。

**放生、安置、做菜消费的是物理鱼实例，图鉴保存的是既成事实。** 消费或删除原实例不会删除发现，也不会因为保留发现而再生成一条鱼。图鉴没有物资所有权、数值奖励、额外份数、好感收益或模型唤醒。

首次发现复用当前收获反馈，增加“发现册添了新的一页”。非人类钓获者可尝试一次本地发现短句，复用 FishingLife / ResidentDirector 原有发言限制：日常/碎碎念开关、近人范围、对话优先、停止安静期及村庄/个人冷却均继续生效。不会替人类发言；受限时不强行补播，也不会新建模型回合。

## 独立持久化

schema 仍为 **7**，新增可选字段：

```json
{
  "journal": {
    "version": 1,
    "discoveries": {
      "<stable-resident-id>": {
        "<species-id>:<color-id>:<size-id>": {
          "fish_id": "<actual-fish-id>",
          "species_id": "<species-id>",
          "color_id": "<color-id>",
          "size_id": "<size-id>",
          "scale": 1,
          "source_id": "<actual-sea-id>",
          "caught_at": 0
        }
      }
    }
  }
}
```

以上是字段示意，真实记录必须具有合法鱼 ID、正的真实时间、有效海域及匹配体型范围的 scale。零时间不能作为记录加载。存档验证维度与组合键、居民存在性、全册鱼 ID 唯一、上限和数值；非法记录拒绝加载并保留原档可恢复副本。

每位居民最多存内容目录中的组合数量，当前为 128 条，不保存无限增长的捕捞流水。图鉴不依赖 `FishingSystem.memories` 的最近 32 条回忆，也不新增 SharedMemories 类型。旧回忆滚动淘汰后，首次发现仍保留。JSON 整数/浮点数用既有事实 canonicalization 作等价处理，重载不会无故改变分页修订。

**旧档缺字段则为空。** 不从旧鱼、渔场、最近回忆或模型会话补造“第一次钓到”的历史。已有鱼与玩家作品、材料、进度不变；重新加载不会恢复钓鱼任务，也不会因尚在收线就自动补一次发现。

## 按需读取 / v2 契约

普通 `observe.journal` 仅有 `discovered/total/revision/tracking=own_catches` 摘要，不放 128 张卡、美术像素或完整来源。

新动作沿用 `game_actions / game_action` 与 `action_contract.py` **v2**，动作名 `journal_read`，所有参数可选：

| 参数 | 规则 |
|---|---|
| species_id / color_id / size_id | 现有内容目录中的 ID |
| status | all（默认）或 caught；本轮没有 seen 状态 |
| offset | 非负整数，当前目录上限 128 |
| limit | 1～32；默认 16 |
| revision | 查询返回的 64 位修订；后续页必须提供，且过滤条件保持一致 |

返回包含 `version=1/self_actor_id/world_id/catalog_revision/revision/discovered/catalog_total/total/offset/limit/next_offset/entries`。每个条目包含组合 ID、三个维度 ID 与名称、`caught` 和 `first_catch`。未发现条目的 first_catch 为空，不代表已有经历。结果深拷贝。

分页修订由目录、世界身份、本人发现集和过滤条件派生，独立于走路、世界时间及别人钓到鱼。本人有新发现时旧页返回 `stale_journal`，从第一页重读。摘要修订与某次过滤查询的修订用途不同，后续页应使用该查询的返回值。

查询不接受 actor_id、填入发现、奖励、伪造鱼或任何主机控制参数。World 在任务/本地生活动作分派前处理只读查询，避免读取抢占工作。原生 MCP 与外部适配器仍走原来的世界/居民/会话/代次/请求/作用域绑定及取消屏障。

**旧原生 DYNAMIC_TOOLS、schema 和 companion.py VERSION 0.3.0 未改；没有驱动升级。** 本轮只是 v2 动作注册表的增量查询。原生助手仍受既有“已接受任务不替换工作”保护，忙时可从旧 observe 读摘要，空闲时读详细图鉴；未为新查询改写旧会话保护。外部测试客户端在有效对话绑定下已验证边钓边读不会打断工作，不代表新增了真实提供方推理验证。

## 验证与证据

- `test_journal.gd`：真实到海边、完整钓获、取消/重载前未完成、首次记录、重复提交、放生/渔场、M1真实烤鱼消费后保留、36次实际钓获使32条来源回忆滚出、独立居民、JSON数值等价、分页/深拷贝/过期页、旧档和非法存档副本。全部推进实际 World 时间，未注入鱼或物资。
- `test_journal_controller.gd`：实际动作菜单按钮、只读 UI、8鱼种/16格、真实捕获形成彩色卡、点击卡片来源、切换另一居民、保存恢复、读取不抢工作、问题遮挡优先和两种窗口。
- `test_action_adapters.py`：原生 MCP 假驱动的 v2 参数、精确 turn token、旧 token 拒绝与不占工作槽。
- `test_journal_adapter.py` / `journal_adapter_host.gd`：临时真实 Godot 外部 v2 客户端，绑定身份/跨作用域/过期请求、真实时间钓获中读取、独立分页、放生后保留。专用测试宿主 time_scale=6，生产游戏时速不变，无真实模型调用。
- 纳入 `./scripts/test-godot.sh`，原 M1 及其他系统回归仍执行。


小窗口实机检查发现新增菜单项挤到了底部动作按钮，已把动作菜单上移并留出间隔。旧 `test_fishing.gd` 曾对 JSON 重载后的随机体型浮点数作精确相等比较，改为 `is_equal_approx`，并补充明确的 owner_id 断言；未修改实际体型、保存精度或迁移规则。

## 文件边界与后续

新增：`godot/content/journal.json`，`godot/scripts/journal_system.gd`、`journal_panel.gd`、`journal_card.gd`；两项 Godot 专项测试、外部测试宿主及 Python 测试。

接入：`world_state.gd`（摘要/只读动作）、`fishing_system.gd`（真实提交）、`fishing_life.gd`（受控本地反应）、`save_store.gd`（可选存档）、`resident_catalog.gd`（只读能力）、`game_actions.gd`、`action_dock.gd`、`main.gd`（入口/Escape/提问优先），以及 `godot/bridge/action_contract.py`、`scripts/test_action_adapters.py`、`godot/tests/test_fishing.gd` 和 `scripts/run_godot_checks.py`。

后续仍需另行明确实际目击条件后才做“见过”；本轮未做作物图鉴，也未伪造旧历史。未来若扩充每鱼种超过32个组合，界面应增加页切换，当前内容的16格已经完整呈现；引擎查询已有独立分页。



# 智能分层数据（2026-10-29 已接入）

本目录是本地性格内容权威：bindings.json按稳定ID配置四位伙伴，主机加载身份与偏好后启用预设/情境包和饥饿。legacy-profiles.json保留原内容的等价投影；预设不改变身份、记忆、关系、外观、模型连接或授权。细则见 docs/INTELLIGENCE.md。

- `units/speech/*.json`：`id/context/lines/autonomy_output`。
- `units/behavior/*.json`：`id/action/conditions/cooldown_seconds/requires_target`；可选 `weight/aspect`。
- `traits/*.json`：`id/name/description/speech_units/behavior_units/speech_multiplier/hunger_multiplier/activation`；可选 `weights/wish_weights/schedule_weights`。
- `presets/*.json`：`id/name/main_trait/context_traits/speech_style/mode`；model 模式必须有 `autonomy_level`，local 模式禁止此字段。预设的默认档位不代表玩家授权开启自主。

`id` 使用小写安全标识符并与文件名一致。校验拒绝未知键、非法类型、重复键/引用、非有限数字、布尔冒充数字、未知行为和悬空引用；整个目录成功才返回结果，不返回部分可用内容。所有校验读取均为深拷贝，不写入源文件。

行为只允许已有的 `nearby/wander/rest/facility/garden/watch/stretch/look/flower_gift`。条件为受控数据字典，仅允许 `hunger_at_least/player_idle/player_actions/relationship_below/interaction_age_at_least/nearby_count_at_least/phases/weather/task_active`，不接受脚本或表达式。行为条件可以为空；主性格 `activation=null`，情境性格必须有非空条件。

纯合成规则：最多两份不同情境包，按传入优先级分别覆盖其声明的权重键；未声明方面沿用主包。发言倍率为主包与情境包的乘积。饥饿倍率为主包加情境包倍率的乘积；没有情境包时只使用主包。合成仅输出数据，不执行行为或消耗物资。

运行 `python3 godot/tools/intelligence_catalog.py` 验证内容；运行 `python3 scripts/test_intelligence_content.py` 执行只使用临时目录的结构专项。保留 gentle-local 作为未绑定结构样例。原人格、钓鱼和五子棋台词逐字迁入语录；hunger.json为新机制配置，旧内容参数没有调优。

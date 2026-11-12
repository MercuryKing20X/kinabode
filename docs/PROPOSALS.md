# 建议卡 · 无人值守阶段2

模型以本人v2 `propose` 提议，字段text（≤40字）、activity、target_id、可选ttl_seconds（默认300、最多600）。配置在content/proposals.json，冷却读同一autonomy.json所选档位。每人同时1张，过期消失，重载不恢复旧待选卡。创建卡不暂停/替换工作、不移动人类、不消耗物资、不写共同经历。

仅有五种已有入口：fish_together（真实海域ID，玩家须在该海岸）、cook_together（兼容提议名，已解锁菜谱ID；接受只打开当前营火邀请页）、homestead_together（现有花圃工程ID）、sit_together（有坐姿行为的现有设施ID）、watch_fishery（真实渔场ID）。任意脚本、任意动作及不存在目标拒绝。新动作走game_actions/action_contract v2；旧原生DYNAMIC_TOOLS/schema、原会话及磁盘VERSION0.4.0保留，只对新增propose允许不打断已有任务的v2建议提交。

屏幕左侧边缘卡片“好呀/下次吧”，不拦截其余游戏操作。只有响应卡片的主机回调能开始活动，没有外部accept工具。接受前检查双方真实工作/集合/问题等，不抢活；条件不足保留卡片并说明，过期继续按原时间消失。接受取消该居民旧模型轮次并保留原代次屏障，再经原主机接口邀请钓鱼、打开烧烤邀请、双人家园交料、双人设施就座或打开渔场。人类只有本次明确点击后的相应动作才可能移动；料理提议仅打开现场邀请页，仍由主角逐步选人、选食物和开烤，不绕过该流程或冒充已做完。查看渔场仅打开真实面板/镜头，不假装已旅行。

真正接受/拒绝后写 `proposal_decision`：participants恰为human和发起居民；facts含resident_id/text/activity/target_id/decision。接受只说明决定和活动启动，不是完成经历。拒绝不惩罚、不停止原工作；过期不是玩家拒绝，不写假决定。纪念记录由主机直接提交至SharedMemories原记事簿并严格校验，稳定卡ID去重；卡片已被删除，不存在可重放旧流水。来源marks仍192、diary仍256，不新增第二份历史，也不增加存档schema版本。旧档无需迁移。


历史风险已于2026-10-27 polish阶段0修复：meal详情现在容错读取可选overlapped_with，真实做菜→吃完→收拾生成记忆后打开面板已回归；没有重做记忆UI。



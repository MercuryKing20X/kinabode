# 林地再生 · 0.9.2

按原来的树木位置再生，不额外随机刷树，不改地图、人物或已有物资。`ForestSystem` 管规则，`island_view.gd` 管树苗显示，`content/forest.json` 管节奏。无模型调用。

- 砍倒时写入时间：约3分钟后树桩发芽，砍倒后约30～45分钟成熟。各树采用稳定错峰，避免一整片同时弹出来。
- 小树苗显示原树种的缩小素材，不能砍、不阻挡人物；成熟恢复6次挥砍、原有8根木材产量。树种和对象ID不变。
- 游玩时生长只按帧增量推进。读档才用保存时的墙钟补离线时间，倒拨不减进度；离线可长到一轮成熟，不会自动伐木或增加材料。
- During play, tree growth follows elapsed game frames. Only loading applies offline time from the saved wall timestamp; a backward jump never removes progress.
- 旧存档没有砍伐时间：升级时原位开始恢复，有条件的旧树桩先显示树苗，再等完整30～45分钟成熟。不伪造过去时间或即时补木材。
- 道路、农庄范围、宅地（包括未施工）、游玩设施、箱子周边不再生。尚有地上木材、任务占用、附近有人或已接纳路线经过时暂缓；每5秒本地检查，不挤开居民或改其任务。
- 成熟才改变碰撞并清理动态寻路缓存；木材尚未搬走时不成熟，避免第二次砍伐覆盖同ID掉落物。

保存仍兼容schema2～7，新增`ecology_version=1`、`forest_clock`；非成熟树可含`sprout_at`与`mature_at`。验证成对有限非负时间且成熟晚于发芽；损坏存档照旧保留可恢复副本。迁移幂等，不重置成长截止时间。

外部observe的每棵树带`regrowth.stage/ready_in_seconds/blocked_by/offline_growth`。普通chop拒绝幼苗并提示正在生长，连续gather_wood只选成熟树。成长受阻时剩余时间可以为0，须结合blocked_by理解；0不等于现在可砍。

验证包括真实砍伐搬运→树苗→成熟→再次砍伐，离线成熟、旧版本迁移、路/房/田/人物/路线/木材阻挡与物资守恒；均在临时数据目录执行。视觉场景`forest_regrowth`通过实际采木任务和临时时钟推进，截图来自Godot viewport。



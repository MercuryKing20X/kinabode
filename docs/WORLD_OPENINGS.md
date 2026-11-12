# 世界模板与开局

默认Godot入口main_v3.tscn为home-v3/128×104展示开局；原main.tscn和core留给明确legacy入口/回归。展示预置只用于美术/UI验收，没有建造者、贡献、投入、完工记忆或关系分，不能当正式开局进度。standard.json只有禁用骨架，--opening=standard明确拒绝，不回退。

showcase.json：五房、每屋四家具共20件、八设施（含两棋桌和三长椅）、已完工花圃、48格不同生长比例。真实公共箱木24/蘑菇12，收获箱芜菁6/番茄4/南瓜2/蓝莓4，六类种子共20；私人箱为空，无初始鱼。果园花田是成熟景观，不新增采果产量。

--fresh-world先读取严格人物白名单（名字/版本、角色能力、外观ID/自定义标记、控制方式），调用原归档机制保留旧island-v2.json.before-farms-*；不删除人物作品/家具建筑模板，也不转移旧位置、资源或历史。性格沿用居民数据。普通更新不自动重开，外部/模型没有重置入口。

模板不同：load返回world_template_mismatch，保留原档与.wrong-template-*副本，safe_to_save=false。GUI明确要求“归档重开，保留人物”，取消不覆盖；headless明确失败退出。新旧世界不迁移坐标。schema仍7，只加template_id/opening_id及预置实例preset_origin等可选标记；旧缺模板字段按core处理。

WorldOpening.apply只给新空模板一次初始状态，重复调用不补物资。屋体冻结认可的完整原母版派生；工坊已编辑的同ID模板不被覆写。预置家具invested0只对已知原实例/配方合法，当前位置仍走普通室内校验；搬入后来实建的房间可以保存，不生成替代品。设施与花圃同样严格限制showcase来源。

室外私人箱与房间owner_id从稳定宅地归属得出，公共自动取料排除私人箱，所有操作经原World/Work。共享农箱物资共享不授予其他庄管理权。地图周边pine/moon读取原core的静态预览，未新增旅行/热加载/模型调用。


## 2026-11-04 南边家园岛并图

家园岛已归home连续坐标，由land_extensions与homelands.bridge连接；地图渲染新陆地和长桥，提供家园岛步行聚焦，read_map.summary.walking_areas增加home.homelands。不是新旅行API或预览岛开放。旧home/月牙坐标不变，旧homelands存档严格校验后统一(-19,+150)平移，见HOME_ISLAND.md。

## 2026-11-01 试玩后：比例与步行连接

群岛图按真实格数同一scale_factor绘制，home包含160格主岛及190格月牙扩展，dark160格；不会把350格家园宽度误当单个主岛宽度。默认周边优先fit(home,dark)，远处预览岛仍可用“全部”查看，不让远岛间距把可玩区域挤成小点。dark移至北岸相邻全局坐标[4143,3920]，桥两端共享全局接缝，画出的桥面与World可走多边形相同。原0.62地面缓存比例错位另已修正，游玩图和大地图现在都按真实格数对齐。

# 群岛地图与扩展边界

0.10.5，2026-10-25。复用WorldCatalog；地图只读，不控制居民、不调用模型、不暂停任务。当前初晴岛及桥接月牙岛可步行生活；远松岛/月牙礁仍是登记预览，不能前往。地图能看见不代表玩法已实现。

## 浏览

顶部“地图”首次打开显示家园及最近至多六座邻岛；“家园”聚焦初晴岛，“周边”按实际位置选邻岛，“全部”适配所有已登记岛屿。列表会自动包含加载的扩展区域，不固定三岛。滚轮围绕鼠标缩放，右/中键拖动，方向键平移；边界来自world.json。北向和格数比例尺帮助定位。

单击岛屿仅选择；侧栏显示名称、位置、尺寸、用途区、内容来源与可用状态。列表选择岛屿同时聚焦；未开放岛屿不能进入。初晴岛可单击具体位置，再明确点“查看家园地点”切换镜头，不移动玩家。“定位我”处理屋内独立坐标，在地图上定位屋外门口。Escape关闭地图；当前运行内重开保留视角/选择，不写玩家存档或连接会话。

## 只读接口

World.read_map(actor_id, query)；已有read-api身份校验后转发read_map；外部MCP新增read_map工具。既有游戏模型动态工具、提示、驱动版本与会话路径不变；旧模型仍可通过observe读取区域，专用地图读取提供给外部MCP/CLI调用者。

```sh
python3 scripts/habitat_godot.py read_map
python3 scripts/habitat_godot.py read_map --json '{"region_id":"pine"}'
python3 scripts/habitat_godot.py read_map --json '{"offset":1,"limit":1,"revision":"首屏返回的revision"}'
```

query只接受region_id、offset(0..10000)、limit(1..100，默认24)、revision(非空字符串)。offset>0要求当前revision，未知字段及冒充actor_id被拒绝。region_id指定详情，仍返回有界目录。未知岛屿返回unknown_region。

结果：schema_version、world_id、self_actor_id、revision、world_bounds、regions、total、next_offset和capabilities；目录条目含稳定ID、名称、origin/size、availability、travel_available、来源包ID/版本/名字及登记对象类型计数；详情region追加land与zones。计数不表示可收获库存，物资和施工状态请读observe。全部返回深拷贝，不附作品像素、私人对话或推测内容。

地图revision依据世界身份和内容目录生成，不随走路、劳动进度或树木状态变化；内容目录改变后旧续页返回stale_map。home表示家园，preview_only表示仅可查看；travel_available是跨岛出行能力，当前均false，不影响家园内步行。

## agent扩展到哪里了

当前可在开发入口创作JSON包，通过WorldCatalog.validate_pack检查，再在世界清单active_packs登记、重启加载。示例：godot/content/examples/player-island.json，默认未启用。目录记录来源包版本；新增已加载区域自动进入地图与read_map。

验证器已有ID、边界、区域占地重叠、轮廓三角化、用途区及对象归属校验；允许的包对象类型为tree/chest/farm_plot/construction_site。不是完整可玩岛屿认证；农田管理、户外渲染等仍有家园专用逻辑，不能仅凭包验证通过声称新岛可游玩。

当前没有运行中导入/启用/卸载、地图编辑器、热更新、跨岛航行或新岛完整生活接口。下一批应先建立草稿→校验→预览→启用/恢复及存档兼容，再解除非家园户外渲染假设、实现出行规则。不要将已保存家园的ID、地形或物资替换成示例包；普通内容包不执行任意脚本。

## 验证




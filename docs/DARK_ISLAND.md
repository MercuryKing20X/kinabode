## 2026-11-02第二轮：性格与发现（实现已接，验收未全部通过）

dark北扩size187×240/local_origin[0,-112]，原origin/旧点不动，陆地31384格²（原2.22054倍）。新增stars星空崖无灯、heather灯芯草原灯台[116,-75]，旧火/旧灯照旧。dark-discoveries.json列8旧物/4性格专属/星座位；dark_island.saved.discoveries为可选对象，found严格ID、catches按真实DayCycle日、loose0..2、lamps实际摆放region/point、star_days去重。旧档缺字段为空，schema仍7。

personality_motion在dark-island.json，tag决定前后队列/停看/警告/指向；dark_companions仅本地路由与原说话闸门，绝不取物/帮主角拾取。新上下文dark_beacon/relic/own/firefly/stars各6句/主性格。发现/捕虫必须玩家明确鼠标，World走到后原拾取姿提交；满包不吞第三只，3只合成carry.firefly.jar1格。旧物进手册/真实共同事实，无关系分。旧物图标复用微光蘑菇，生图接口失败未交新图。


## 2026-11-02：第一步扩大、底部点火举火把

当前dark本地范围[0,-64]到[187,128]，region.origin仍[4143,3920]；local_origin负y扩北，避开home/pine占地，旧营地/木桥/所有旧点不挪。陆地1.717倍；新增cedar幽光杉径beacon[52,-24]、tide静潮石湾[116,-22]，各原6木，旧grove/lake不改。新增六树/岔路/发光路标复用旧美术。config.local_origin给永久遮罩平移，shader map_origin换算取样；后续扩图必须同时维护size/local_origin/land/zones/areas，守原总览不重叠校验。旧fires/beacons无需迁移。


## 本轮追加：木材可直接点小火（2026-11-01）

底部点火不再需要已有火源或火把，原授权来源有2木材即可在脚边引燃；仍保留水/物件/间距/已亮区校验、原子扣料与永久光。没有免费火把。已选跟随者即使留在另一岛，也会独自经World走桥过接缝来找主角，实际到场才加入party；途中取消撤精确本人桥路，不移动人类。

## 本轮点地与点火（2026-11-01）

黑暗岛空地点击直接走，水中拒绝，不弹“走到这里”。探索小火改为底部固定“点火”，在主角脚边复用原扣2木材/插火把/引燃流程；不改变营火和灯台物件菜单。跟随名单选中的人会随主角走桥；详见FOLLOW_FIRE.md。

## 入口修复（2026-11-01，试玩再次反馈）

主岛左侧“黑暗岛 · 北岸木桥”是明确玩家入口，点后仍由原同行确认和World路线走桥，镜头跟随人。点击对岸可走地面时，dark_ui以两region.origin之差换算目标，先走本端桥头、同行到齐再跨接缝、继续走到目标；不能把对岸坐标当本岛地面。主岛按同一偏移画出远半桥和对岸暗色轮廓/营地，不改变dark未点亮状态；atlas仍仅永久亮区，额外标明营地属于黑暗岛。正常逐帧鼠标验收见ENTRY_FIX.md。

## 2026-11-01 试玩后：木桥步行取代小船

用户新授权改为从北岸走到黑暗岛。walking_connection是两端桥面多边形及home_end/dark_end；home origin[4048,4048]、dark origin[4143,3920]，home[129,0]与dark[34,128]全局完全相同。两区仍各自保留局部坐标/存档和dark迷雾。明确选同行后，每人经World真实走到本端桥头，全部到齐才跨相邻region边界，主角继续World走到营地；无小船与淡出航行动画。返程带回所有实际在dark的人。旧travel默认路径仅保留内部兼容探针，玩家UI使用walking=true。原人物、箱、树和已点亮位置不迁移。下面小船描述是初版历史。

# 黑暗岛第一段

黑暗岛是`dark`独立区域，不能把home/月牙/室内并进迷雾。方向权威为只读DIRECTION的黑暗岛节；World独占路径，SharedLife/Fireside独占烧烤和授权物资扣除，Main/DarkIslandUI只执行明确玩家选择。无游戏模型调用。

`content/home-v3/world.json`启用`content/packs/dark.json`。region的origin是群岛总览坐标，人物position仍是region-local格坐标。第一段size160×128、连续多边形land，不用逐格瓦片。zones是命名用途区；dark-island.json的areas是永久灯光边界，二者用途不同。ponds同时被World通行校验和renderer读取，不能只画水不阻挡。八棵树仍按原6次砍伐、产8木及原搬运规则。

`content/dark-island.json`是探索参数权威：bare_radius2、soft_edge1.5、torch_radius4、fire_radius5、camp_radius10；torch_seconds120、torch_warning_seconds20；首次torch_wood1、fire_wood2、beacon_wood6；fire_spacing8、interact_radius2.5、gesture_seconds0.5、beacon_spread_seconds2.6。home_dock/home_arrival/dock/arrival/camp绑定码头与落点，paths是表现岔路，glows是远处路标，areas每项含id/name/polygon，可选beacon（第一段仅一项有）。audio仅控制本区环境声相对音量，不改原总线与距离/并发限制。companion_behaviors将四个主性格映射到原格式的新行为单元，只由dark调度器读取，原主性格behavior_units列表保持原样。

主岛码头[129,17]、落点[129,20]避开北岸住宅与原路线。点击船→邀请（所有人/逐人）→出发，先通过World走到船旁，再淡出淡入切region。忙于真实任务/held或很饿者不被强带；原本地空闲活动按owned_job让位。返回带回所有实际在dark的伙伴。旅行不复制物资、鱼或工作；主角可携带同一唯一pending鱼上船，到营火按原流程直接烤，不新增本岛鱼资源池。所有落点先验证可走且互不重叠；不恢复任务。码头营火是旧营地既有设施（正式开局也能做饭），空箱无赠料、无建造贡献/记忆。原主岛/月牙的正式建造门槛不变。营火仍复用既有烧烤火候时长；永久探索光源（营地、小火堆、灯台）没有燃料倒计时。

火把仅主角拥有，是独立叠图，不写任何人物作品。torch-hands.json覆盖13套内置形象站立/走路/跑步各帧手位，素材来源见 [CREDITS.md](../CREDITS.md)。旧图集双哈希校验不放宽，编辑过人物仍走原回退。真实手部工作通过Work的hands_busy先插火把，插地计时和光源继续；随后原工作完成自动拔起，原路线开始前也必须拔起。插下与弯腰引燃各约0.5秒，有火星从插地火把传向目标的表现；动作可被新指令取消。读档不复活工作，保留插地状态直到玩家行动/取回。

迷雾由dark_overlay和dark_fog独立表现：永久光遮罩4像素/格，只在永久源变更时重建；shader每帧取永久遮罩、灯台铺开遮罩、主角实际显示位置及插地火把，不按30火堆逐像素循环。UI在原CanvasLayer，名字/气泡和发光路标在fog之后；主岛/月牙/室内不启用该层。手册只从永久光计算显示范围，不记录/显示逐格探索、不保留火把扫过的地面。

schema仍7，可选字段`dark_island={version:1,fires:[{id,position}],beacons:[area_id],torch:{owned,remaining,planted,position},party:[resident_id]}`；人物区域沿用actors[id].region_id。仅存永久源与工具剩余，不存每格探索、路线、待发指令或动画时间。离线不推进火把。缺字段旧档为空且仍在home；新目录物件introduce_in999使旧档可缺失，不补库存/历史；新增空箱和真实树属于新地图内容。严格拒绝未知灯台、重复火堆ID、无效位置/数字/超时；非法原存档沿原规则留副本。

点灯事实复用SharedMemories，kind=dark_beacon，固定真实area_id/name/beacon，参与者是当时实际在该片区域的同行伙伴与主角，key绑定单一area。容量仍diary256/marks192，不产生关系分值、奖励、模型唤醒或旧档回填。

扩第二段时，扩展dark.json的size/land/zones/objects，同时更新dark-island.json的size/areas/ponds/paths/glows与未来边界；每片新areas可增加唯一beacon坐标。校验所有多边形在land内、湖的通行与画面共用，区域不重叠；新物件用稳定新ID并标明introduced_in，不能重排旧ID/位置或挪动玩家。永久光由稳定灯台ID计算，所以旧光不需迁移。最终三主岛面积、黑沙滩等新区、区域计数、全岛围炉/起名均留第二段，本轮未实现。


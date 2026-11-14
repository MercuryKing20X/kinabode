# Kinabode design / 有栖设计

## A home, at your pace / 慢慢安家的海岛

You are the host of an island, with four companions who have distinct authored personalities. Farming, fishing, construction, meals and games create shared moments. There is no combat, currency, stamina or sleep lock. The game works entirely with local intelligence; model connections are optional.

玩家带四位性格不同的伙伴在岛上生活；种菜、钓鱼、建造、吃饭与游戏构成日常。没有战斗、货币、体力和睡眠锁；本地即可完整游玩，模型接入可选。

## Identity, intelligence, appearance / 居民、智能、形象

Stable resident IDs own memories and relationships. Intelligence is a named control preset; appearance is editable artwork. Changing either does not replace the resident or transfer another resident's history.

居民ID持有记忆与关系；智能与形象可换，身份和真实历史不随之迁移。

## Physical work / 真实物资与路线

World is the only route authority. Work, farming, construction and shared activities validate permissions and commit real materials. Carry capacity is a fixed independent 20 items per actor. Accepted work is not completed work. Stopping or reloading preserves invested materials and stops tasks rather than replaying them offline.

所有行动走原World路线，任务按权限真实扣料与提交。每人独立20容量，不升级；接单不等于完成，暂停/读档保留投入但不假续做。

## Hunger and meals / 饥饿与共餐

Hunger affects expressions, speech, following and limited movement behavior; it does not lower yield, success, work speed or relationship scores. Very hungry companions refuse new work and can abandon their own current task without losing material. Only a player-confirmed barbecue serves real food to invited residents. The player chooses the fire, invitations and menu; excess cooked food is recorded as waste.

饥饿影响表现、跟随与有限移动，不影响产量/成功率/工作速度/关系；很饿者拒绝新活并可放下本人任务，物资保留。只有玩家确认开烤才真实吃饭，未受邀不吃，多余食物记浪费。

## Steward / 托管

One director coordinates current jobs and keeps the squad near its leader. Real work and shared play are split among companions; task transitions have bounded rest and failure handling. Optional AI offers voice and preferences, never owns physical jobs or blocks the body's local execution. Player commands take priority. Host decisions and invitations remain explicit UI choices.

一个导演统一派活；伙伴分工、一起玩、有限歇息与失败收尾。AI只提供口吻和偏好，不阻挡身体。玩家命令优先；主角的移动与共同活动仍需明确点击。

## Islands / 岛屿

The home island is the main place to build and live. Crescent Island offers moon viewing and another fire. The Dark Island is explored through fog and permanently lit beacons, without combat or lost inventory. A holiday island provides a different setting for leisure. Visual terrain never becomes a second route or inventory system.

主岛安家，月牙岛赏月，黑暗岛逐步点亮，度假岛休闲。环境表现不取得路线/物资权。

## Memory and optional models / 记忆与可选模型

Only committed canonical facts become gameplay memories. Private and group histories stay bound to their channel. Model outputs require exact resident, world, session, generation and request identity; stale replies are rejected. Local routines do not imply inference or resource authority. Lifeblood is optional and costly; actual use and unknown usage must be shown honestly.

记忆来自已提交真实事实；私聊/群聊分离，输出精确绑定身份与回合，拒绝迟到结果。本地生活不等于模型推理。生命孕育可选，用量和未知状态如实显示。

## Local brain / 本地大脑

Each resident has one utility brain. Needs and authored preferences choose existing local activities; player commands and steward assignments take priority through the same entry point. Right-click a companion or click their detail portrait to see what they want and why. Hunger is read from the existing system, and local choices grant no work or food authority. See [Resident brain](RESIDENT_BRAIN.md).

每位伙伴用同一个大脑选择已有活动；玩家命令和托管派活优先。右键伙伴或点击居民详情头像可看“我现在想……因为……”。需要不显示数字，也不改变原饥饿、劳动和物资规则。

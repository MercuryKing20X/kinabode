## 2026-11-05 首批可商用背景音乐

运行时另读 `godot/content/audio/user-music.json`，只接受带精确哈希、作者、来源及CC0/CC BY 4.0授权的条目；缺文件/哈希不符保持静音。首次曲目来自 Kevin MacLeod 官方 Incompetech 曲库，署名与来源见 [CREDITS.md](../CREDITS.md)，当前文件哈希在音频清单中。这不是游戏内模型调用，也不使用合成音乐。

音乐沿用原四路Music总线、并发、4秒交叉淡化和说话/吃饭压低，只观察昼夜天气/相机地点/真实用餐。新增dark与their场景；设置“音乐·逐首试听与来源”可逐首播放、看作者/授权/源页，关闭试听即停止试听曲。用户可换原件后执行 `python3 tools/audio/prepare_user_music.py`，或改运行时清单和文件；无需修改代码。响度、峰值、接缝量测见 quality.json，不能当真人听感验收。公开版提供8首OGG音乐，原WAV/MP3原件不随源码发布。

---

## 2026-11-03 用户反馈尖短鸟叫/虫鸣刺耳频繁

用户明确指出是鸟叫/虫鸣。鸟叫改为35–65秒随机单声，不再12秒5声循环；单声0.65秒、低通柔化与-8dB不重新归一化。虫鸣1400Hz柔化并-14dB、不重新归一化。原WAV不变，衍生素材/脚本/哈希见audio/SOURCES.md与sounds.json。海浪/说话/脚步/玩法参数不改。

## 2026-11-02 去掉饥饿声（覆盖下方旧规则）

保留同区/屏内95、60、35秒的头顶咕～提示，不再调用 hunger.* 播放；素材和事件定义保留。主岛 wind 基线0.3/峰值0.6，黑暗岛0.22/0.4；阵风4–6秒，阵风起点间隔随机25–60秒，平滑升降，独立音频RNG，不改天气与玩法。参数分别在 audio/runtime.json 的 wind 与 dark-island.json 的 audio。原音量/距离/并发继续生效；测试为Dummy。当前补充探针通过，完整真实鼠标四组合验收未完成。

## 2026-11-02 咕噜声头顶提示


# 声音

GameAudio 只观察 World 已发生的事情和现有气泡，不产生任务、台词或玩法存档。Music、Ambience、Effects、Voices 四路汇入 Master；设置保存在数据目录的 audio.cfg，旧设置不会被覆盖。设置中的“测试声音”依次播放说话、脚步、火声，以及可用时的音乐；静音或音乐缺失会提示。


最多同时播放 5 个声音，优先级为说话、重要事件、主角脚步、环境、其他；环境目标循环最多占 3 位，优先附近火声及海浪和天气，给其他声音留出容量。丢弃原因和计数写入诊断。脚步只跟随主角实际位移和脚下地面，跑步沿用既有间距；伙伴脚步静音。只给离镜头最近的正在说话者播放嘀声，吃饭只给最近一至两人，普通按钮静音。声音不增加发言频率或改变运动规则。

清单 `godot/content/audio/sounds.json` 的事件含 bus、variants、selected、volume_db、pitch、并发、距离、循环和冷却。每个 A/B/C 版本有 file、sha256、source_id；可选 takes 是 2 至 3 个同格式录音，第一条与主文件一致，运行时避免连续选中相同哈希。无 takes 的旧清单保持可用。来源及授权见 `godot/content/audio/SOURCES.md`，参数在 `godot/content/audio/runtime.json`；GDScript 和 `scripts/validate_audio.py` 都校验，文件哈希不符时跳过。声音 RNG 独立于玩法随机。

脚步来自 OpenGameArt 上的 CC0 录音，草地暂用落叶和沙面录音近似，木地板暂用三条真实录音组成候选。合成素材做了低通和动态压缩；处理脚本保留来源参数和哈希。新 WAV 以 16 位 PCM 无损导入引擎，避免有损导入改变信号。运行 `python3 tools/audio/process_v2.py` 可重建合成声音；真实脚步由 `tools/audio/prepare_recorded_steps.py` 重建，需要来源清单列出的原始 CC0 下载文件。听感与循环接缝仍须实际试听核对。运行 `python3 tools/audio/quality_v2.py` 生成逐条数字统计。

## 换音乐

运行时音乐由 `godot/content/audio/user-music.json` 指定；替换为自己有权使用的WAV或OGG时，同步文件哈希、作者、来源与授权。只改文件不改精确哈希会被拒绝加载。保留循环时长与声道/采样率，并分别验证引擎加载、循环接缝与响度；数字量测不代替听感验收。所有第三方署名和授权应同步更新 [CREDITS.md](../CREDITS.md)。旧TimGM6mb录音不在当前运行时音乐表中，其保留许可另见CREDITS。

## 试玩降频（2026-10-31，历史；由下方一泡一声覆盖）

runtime 可选 `speech_max_blips=3`（整数1～3）、`speech_gap_seconds=6`（1～60秒）、`speech_near_tiles=12`（1～60格），旧清单缺字段采用同值默认，GDScript/Python同样拒绝布尔、非数、非有限值和越界值。只在近镜头、最近说话者的新气泡开始时安排嘀声；冷却中的新泡不延后补声，重复显示同文本不再响，原有发言闸门不变。每居民独立会话计时，不进世界档。

“说话声”偏好仅控制 voice.*，在本机 audio.cfg；咕噜及满足声仍属伙伴总线。四种嘀声事件统一 -5dB，源样本经2400Hz三阶低通幅频、25ms正弦平方起音和0.65压缩指数处理，素材约-12dBFS叠加事件后约-17dBFS，仍在说话目标区间内。源/目标哈希和数字统计在 sounds.json sources；脚本 tools/audio/soften_voice.py 从保留的sound-v2原件重建。试听台增加四种旧/新并排，新样含实际-5dB增益，避免浏览器忽略事件增益造成误判。响度数据不等于用户听感签收。

## 说话声降调（2026-11-01，历史素材保留试听）

用户反馈嘀嘀声“太高”。`tools/audio/deepen_voice.py` 重新合成四种说话声，基础音降约一个八度：bright 690→330、crisp 510→262、soft 425→208、low 235→147 Hz；性格包 `voice.pitch` 相对音高不变。A＝低沉圆润的哼声（默认），B＝同音色高约四个半音，C＝软拨弦。文件在 `godot/content/audio/voice-deep-1101/`。试听台“说话声”一行并排旧版与新 A/B/C。换版本：改 `sounds.json` 里 `events.voice.<种类>.selected`，再运行 `python3 tools/audio/audition.py`。

## 每个气泡一声（2026-11-01，当前规则）

每个通过原近镜头、最近说话者与 held 闸门的新气泡最多播放一声，短、软、闭口的“嗯/啵”。已删除按字数计数、重复音节计时与待播队列，voice 只接受 event/pitch/max_blips=1；同一居民两次出声默认至少8秒，冷却中的气泡只显示、不补播。原说话频率、开关、四总线、距离与并发限制保持。

`tools/audio/one_bubble_voice.py` 生成 `voice-single-1101/` 四家族×A/B/C单脉冲声音，基础频率仍为330/262/208/147Hz，四性格相对 pitch 未变。A是最柔和的单瓣圆润哼声（默认），B是轻啵，C是轻拨；每个样本约85–115毫秒，A去掉多余泛音、低通750Hz。试听台保留上一版与新三版，播放器包含实际-5dB事件增益。来源参数与哈希见 sounds.json/SOURCES.md；听感尚待用户最终试听。

## 黑暗岛声音（2026-11-01）

`dark-island.json.audio` 集中设置风/远浪/夜虫相对增益0.45/0.35/0.45；dark不播放鸟叫，抵达时立即移除主岛鸟声，仍遵守最多三路环境、总五声。第三营火的火声/烤制声按station.region_id绑定，原主岛/月牙行为保持。

`tools/audio/dark_island_audio.py` 用固定seed低通噪声与单包络生成点/插/拔火把、低火苗、小火堆，灯台为196/246.94/293.66Hz暖和弦渐入渐出；六个Effects事件、单并发、原空间衰减。只观察dark.events中真实提交且递增serial的事件，观察器创建时建立基线，不因读档补播。原始PCM、种子、时长、响度与SHA256记入sources。新增18条WAV导入显式compress/mode=0，保持16位无损。

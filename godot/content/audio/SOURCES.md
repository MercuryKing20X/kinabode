# 声音来源

新声音使用 `sounds.json` 的逐文件 SHA256、source_id 和参数记录；运行时只读取清单。

## 旧十个 WAV 排查（保留原件）

这些文件全部有本仓库的原创程序合成脚本，没有第三方录音或授权不明素材。另将五份生成脚本复制到临时目录运行，十个 WAV 全部与仓库原件逐字节相同（legacy-source-verification.json）。无需移到待确认目录。它们保留供 legacy 和原回归测试使用，不加入新声音清单；本轮新系统将使用单独生成的声音。字节哈希与时长见 `production/evidence/overnight-1031/legacy-audio.json`。

| 原文件（godot/assets/audio/） | 来源脚本 | 原挂点 |
|---|---|---|
| hit.wav、fall.wav、pickup.wav、deposit.wav | tools/generate_work_audio.py | 砍树/倒树/拾取/存放的视图事件 |
| breeze.wav、fire.wav | tools/generate_camp_effects.py | 风及真实燃烧营火循环 |
| fish_splash.wav、fish_bite.wav | scripts/make_fishing_sounds.py | 钓鱼落水/咬钩 |
| gomoku_stone.wav | scripts/make_gomoku_sound.py | 棋子落下 |
| moon_tide.wav | production/art/moon-island/audio.py | 月牙岛镜头范围潮声 |

旧播放器仅在 `island_view.gd` 创建，由 v3 视图继承调用。旧循环设为约 -23 至 -29 dB，短音效约 -20 dB 并继续按距离降低；声音本身峰值偏低，缺少 UI、脚步、说话、音乐等大部分反馈。原开关只改变当次视图状态，不是完整混音器。不能仅凭代码证明用户设备静音原因；本轮会用 Dummy 驱动事件轨迹验证新系统，不声称已听过。

## 本地音乐渲染所用音色库（历史参考，当前不用于运行时）

- TimGM6mb，Tim Brechbill（2004）、David Bolton（2010）；GPL-2.0，允许免费商用但有分发义务。本轮保守将用它渲染的 OGG 同样标为 GPL-2.0；不声称音色库或输出是 CC0。谱子仍为本项目原创，修改谱子不需要改变游戏参数。
- [Debian 授权记录](https://sources.debian.org/src/timgm6mb-soundfont/1.3-5/debian/copyright/)、[GNU GPL-2.0 全文](https://www.gnu.org/licenses/old-licenses/gpl-2.0.html)。授权记录确认采样来源由原作者自制、公有领域或 GPL 采样组成。
- [实际下载 Debian 1.3-5 包（清华镜像）](https://mirrors.tuna.tsinghua.edu.cn/debian/pool/main/t/timgm6mb-soundfont/timgm6mb-soundfont_1.3-5_all.deb)，日期 2026-10-31，包 SHA256 `034abdfb296d9353433513dad5dbdcab46425ee6008fc02fe7039b46e75edc54`。
- `TimGM6mb.sf2` SHA256 `c5378b62028c920cb11e4803327983fee2f2cdff5dc89c708e39da417e51c854`。SF2 和下载包仅在忽略的 tmp/audio-font/、tmp/audio-downloads/，不进仓库；只提取数据，没有运行包内维护脚本。
- 六首正式音乐都有 A/B/C 完整编配，`selection_key=music.sample30` 统一跟随30秒小样的选择，A原编配/B低八度回应/C轻柔变奏；不额外播放30秒片段。月牙三版都保留纯八音盒。
- General MIDI 0 起算 program 10 = Music Box（八音盒）、24 = Acoustic Guitar nylon（尼龙弦原声吉他）。无鼓、无人声、无模型。FluidSynth2.6.1 离线渲染24kHz；关闭混响和合唱以避免随机尾音，连续三遍取中间一遍，再编码 OGG。
- 本轮在忽略的 tmp/ 安装公认开源工具：micromamba2.10.0（官方 micro.mamba.pm 二进制）、FluidSynth2.6.1、FFmpeg9.0.2、Python3.12、numpy2.5.4、PySoundFile0.14.0（conda-forge 依赖环境）。准确版本以 `production/evidence/overnight-1031/audio-tools.json` 为准。没有全局安装、全局配置改动或付费服务。
<!-- GENERATED FILE SOURCES -->

## 当前运行时逐文件来源（自动生成）

精确处理参数、原始文件哈希和来源信息在清单 sources.parameters。TimGM6mb 音乐仅作历史参考，当前运行时不引用。

|ID/版本|来源/脚本|作者|授权|来源|文件 SHA256|
|---|---|---|---|---|---|
|voice.bright/A/1|tools/audio/one_bubble_voice.py · single1101.voice.bright.A|本项目|project-original|本项目原创|`241f7ca936a7532e114cce5e92bd6bcbf9521e67aca1766caabf5192ee7eed26`|
|voice.bright/B/1|tools/audio/one_bubble_voice.py · single1101.voice.bright.B|本项目|project-original|本项目原创|`abc0ba5f33677013b0da1426f81d09f8a6847e9ff8b81beefb8a840a99e840e7`|
|voice.bright/C/1|tools/audio/one_bubble_voice.py · single1101.voice.bright.C|本项目|project-original|本项目原创|`06b9668a52988e92ec7e4baae32b6552592c345a4a5538e54981b701bcd1c491`|
|hunger.hungry/A/1|tools/audio/process_v2.py · v2.hunger.hungry.A|本项目|project-original|本项目原创|`6f9f8033fe94f2d6271c5956ee803de08d9b22aa6c94094289fa8085ad03919a`|
|hunger.hungry/B/1|tools/audio/process_v2.py · v2.hunger.hungry.B|本项目|project-original|本项目原创|`f7272a84d162cf70297d226fe5d35ad5754ded8685d907f3cf754506c2368929`|
|hunger.hungry/C/1|tools/audio/process_v2.py · v2.hunger.hungry.C|本项目|project-original|本项目原创|`db0c4cc14641653e423351c35389088f7c18f47ba201de26a0686c6e81d60e3d`|
|ambience.fire/A/1|tools/audio/process_v2.py · v2.ambience.fire.A|本项目|project-original|本项目原创|`9f413f7fa8e5f8da5f162d2c0b808de42ea1f4467dba758695fb3dfb78984b86`|
|ambience.fire/B/1|tools/audio/process_v2.py · v2.ambience.fire.B|本项目|project-original|本项目原创|`9db2639b0a24ca2d4643a3cbc6c15396c9d32a267a34d9224eccbe474234da47`|
|ambience.fire/C/1|tools/audio/process_v2.py · v2.ambience.fire.C|本项目|project-original|本项目原创|`3ad75ae6b1aaeb7f7cf601c33095c8ee97e8e886ecf82db8b498f2f62d423785`|
|ui.click/A/1|tools/audio/process_v2.py · v2.ui.click.A|本项目|project-original|本项目原创|`0587de4004c8ee7a5528de3a71bf1f82fd3ae27b7f94250a90a253e5fa6ff224`|
|ui.click/B/1|tools/audio/process_v2.py · v2.ui.click.B|本项目|project-original|本项目原创|`f5afda96a058cfdc7a5f988f72901e9f44441259d665fa5783a25000e4db417b`|
|ui.click/C/1|tools/audio/process_v2.py · v2.ui.click.C|本项目|project-original|本项目原创|`16060f0a60d092b0ddb12ab82c1ead248243709c3916836a3162c8d7e7d11d5d`|
|voice.soft/A/1|tools/audio/one_bubble_voice.py · single1101.voice.soft.A|本项目|project-original|本项目原创|`bbe1ddea5e2f71cfc0f0e989ebd563a4cbc6c925829652f329860d9ba85c30cb`|
|voice.soft/B/1|tools/audio/one_bubble_voice.py · single1101.voice.soft.B|本项目|project-original|本项目原创|`146f864cbc9c65286211154f1c3aeadef9e1891a4daae3c5ed3ee494ef842548`|
|voice.soft/C/1|tools/audio/one_bubble_voice.py · single1101.voice.soft.C|本项目|project-original|本项目原创|`df6e71383f08ae469d20a4d541c6f84d76b55664eb1efdbfa401a89805bf0f40`|
|voice.crisp/A/1|tools/audio/one_bubble_voice.py · single1101.voice.crisp.A|本项目|project-original|本项目原创|`d54d18252806aeeabe0d546dfdc3e95dcab4e8f5953f885bd158e9f689b8630c`|
|voice.crisp/B/1|tools/audio/one_bubble_voice.py · single1101.voice.crisp.B|本项目|project-original|本项目原创|`00ccf794d3737909213d873c7a4258ccc0b83e0fbb64c129e122d4ad51d96391`|
|voice.crisp/C/1|tools/audio/one_bubble_voice.py · single1101.voice.crisp.C|本项目|project-original|本项目原创|`7d1e033f0085673e63b3d8bf9eddbb9e39d83d1ae28240b853d20126f3c9d5a1`|
|voice.low/A/1|tools/audio/one_bubble_voice.py · single1101.voice.low.A|本项目|project-original|本项目原创|`1d2b47bfdd437e9857affb9816ae8f4c444997f9d9081bb8d270eaea5be4ae61`|
|voice.low/B/1|tools/audio/one_bubble_voice.py · single1101.voice.low.B|本项目|project-original|本项目原创|`6a46b440a5285dcc79ae441d429044d24429bc8f6f7a341be7829c5e82895627`|
|voice.low/C/1|tools/audio/one_bubble_voice.py · single1101.voice.low.C|本项目|project-original|本项目原创|`b19ac72bde51b325dcbfeae16c074fd951fad8f83968cb1d310214a3411a52f7`|
|hunger.mild/A/1|tools/audio/process_v2.py · v2.hunger.mild.A|本项目|project-original|本项目原创|`19bf407fd926acbe988684c1744049c64b81f9ece32a87be58dd09f210687ec1`|
|hunger.very_hungry/A/1|tools/audio/process_v2.py · v2.hunger.very_hungry.A|本项目|project-original|本项目原创|`49f5a7a80901a7a62aaf09a4562e30125169bb6ac98e9a1d08862c6f7306661c`|
|meal.satisfied/A/1|tools/audio/process_v2.py · v2.meal.satisfied.A|本项目|project-original|本项目原创|`dc1be28ea319799691acf7f5c1dd4a559d957f4eedc3d5b394d312f91fc8d428`|
|tree.hit/A/1|tools/audio/process_v2.py · v2.tree.hit.A|本项目|project-original|本项目原创|`3d3e6079536f68fe1dfd92a9baed74cdb16194cddaf3d62bff9e0ada2c5f0b48`|
|wood.fall/A/1|tools/audio/process_v2.py · v2.wood.fall.A|本项目|project-original|本项目原创|`2433b485829138b6e4ae71b19fdfc07529c91db30d738385e0385c8587b9b5ac`|
|fire.ignite/A/1|tools/audio/process_v2.py · v2.fire.ignite.A|本项目|project-original|本项目原创|`24e732d1a0fa946e4157c3a8c7109a150cb414f5cd3c8d9712d3395e9c7036e7`|
|fire.refuel/A/1|tools/audio/process_v2.py · v2.fire.refuel.A|本项目|project-original|本项目原创|`14351bd0a3dab449700b3a6e50200e27aae794ea06c35dfe4fef8f34697b0816`|
|meal.bite/A/1|tools/audio/process_v2.py · v2.meal.bite.A|本项目|project-original|本项目原创|`f4a214e3f6d3c67f4f3fc87978dadffe8ddb1461b7613852a7b41bdee05413b8`|
|meal.chew/A/1|tools/audio/process_v2.py · v2.meal.chew.A|本项目|project-original|本项目原创|`dbb3af19039b2f865451fc043ed5fdefddac31de4d153addb328bee5d5b380df`|
|fishing.cast/A/1|tools/audio/process_v2.py · v2.fishing.cast.A|本项目|project-original|本项目原创|`9f594ab6c4b2e9fbb501f94476146303a39f2e4956c1da4133f8204bd185ba0f`|
|fishing.water/A/1|tools/audio/process_v2.py · v2.fishing.water.A|本项目|project-original|本项目原创|`1f9b15a06c1a9b1483680cb0c70ec35e818f86fbcd8f4c206be7313b7c5d40ad`|
|fishing.bite/A/1|tools/audio/process_v2.py · v2.fishing.bite.A|本项目|project-original|本项目原创|`a23e765f664d50cfa22aa0eca9df6c6620c2c1907e27bd52355315902b51ae5c`|
|fishing.reel/A/1|tools/audio/process_v2.py · v2.fishing.reel.A|本项目|project-original|本项目原创|`d7ef5852b467147caf9233ab002433313a4dd859ccdfc49ede73a06691a91c7a`|
|fish.flap/A/1|tools/audio/process_v2.py · v2.fish.flap.A|本项目|project-original|本项目原创|`9e9d86480ecdb9235a05d1a718a24a26855a2590c09661f27a89c2204fd1e025`|
|fish.stock/A/1|tools/audio/process_v2.py · v2.fish.stock.A|本项目|project-original|本项目原创|`f5c22ab9175a3537ef348c868706069ae9ab130d9c31fced52976bad912d9d42`|
|fish.release/A/1|tools/audio/process_v2.py · v2.fish.release.A|本项目|project-original|本项目原创|`d7e696a9be203ff078c189f14e528e624191e6b0b0fe4f6251c7c6b6a5b184d2`|
|ui.open/A/1|tools/audio/process_v2.py · v2.ui.open.A|本项目|project-original|本项目原创|`0587de4004c8ee7a5528de3a71bf1f82fd3ae27b7f94250a90a253e5fa6ff224`|
|ui.close/A/1|tools/audio/process_v2.py · v2.ui.close.A|本项目|project-original|本项目原创|`df59f5270c9456ace9e779bfa8aa5416528440bab775ccc86bf2e4ee0307e102`|
|ui.fish_card/A/1|tools/audio/process_v2.py · v2.ui.fish_card.A|本项目|project-original|本项目原创|`0587de4004c8ee7a5528de3a71bf1f82fd3ae27b7f94250a90a253e5fa6ff224`|
|ui.invite/A/1|tools/audio/process_v2.py · v2.ui.invite.A|本项目|project-original|本项目原创|`0587de4004c8ee7a5528de3a71bf1f82fd3ae27b7f94250a90a253e5fa6ff224`|
|work.pickup/A/1|tools/audio/process_v2.py · v2.work.pickup.A|本项目|project-original|本项目原创|`02fc36d376de86773a1cc2556d40e655ecc36fb0082985300902f9def14348f2`|
|work.deposit/A/1|tools/audio/process_v2.py · v2.work.deposit.A|本项目|project-original|本项目原创|`4174a650b8b3b6969d54c12b97d77ce3a75d49fc18cb362f034198339d862c0b`|
|gomoku.stone/A/1|tools/audio/process_v2.py · v2.gomoku.stone.A|本项目|project-original|本项目原创|`42da2fe4da8e5470498971fcb16856da74a226881ef3465c99c431b834a9a3a0`|
|ambience.waves/A/1|tools/audio/process_v2.py · v2.ambience.waves.A|本项目|project-original|本项目原创|`ef14ee50674d986ba834e7eee199626af13328d8bae77306a73bd93e93c7170a`|
|ambience.wind/A/1|tools/audio/process_v2.py · v2.ambience.wind.A|本项目|project-original|本项目原创|`4880e57204384368c3d64bc05f5971e5d221f4fedba73397543bab2d51b3f677`|
|ambience.birds/A/1|tools/audio/soften_nature.py · quietnature.ambience.birds.A|本项目|project-original|本项目原创|`943914231731c6c72421ec43dc3fa850e71da1bdfd35a14df470d9d12f99f0d4`|
|ambience.insects/A/1|tools/audio/soften_nature.py · quietnature.ambience.insects.A|本项目|project-original|本项目原创|`0bf2ab4f3af57a6a9ca7b10a5155d41752f0416ab3eba0e72dc0f1e2d2185a15`|
|ambience.rain/A/1|tools/audio/process_v2.py · v2.ambience.rain.A|本项目|project-original|本项目原创|`74e75f0aaa6b51fc41fa2a5c874d1be19ed391fc7f7c4d4e5c7c00bf92dc8780`|
|ambience.sizzle/A/1|tools/audio/process_v2.py · v2.ambience.sizzle.A|本项目|project-original|本项目原创|`696784744d334cceeca281bcc51202e871de7b91498ead7cb62d28e58bfcdcb8`|
|step.grass/A/1|tools/audio/prepare_recorded_steps.py · cc0.grass.A.1|TinyWorlds|CC0-1.0|https://opengameart.org/content/different-steps-on-wood-stone-leaves-gravel-and-mud|`9b67c0594b91dd98a51cb607502f385d6ff6c25f7b4071685dab36ab79208e83`|
|step.grass/A/2|tools/audio/prepare_recorded_steps.py · cc0.grass.A.2|TinyWorlds|CC0-1.0|https://opengameart.org/content/different-steps-on-wood-stone-leaves-gravel-and-mud|`a14a8ec452a458191b320f7e9ccdf7f8afde1addce9bb0d8c0e1e128fc070261`|
|step.grass/B/1|tools/audio/prepare_recorded_steps.py · cc0.grass.B.1|TinyWorlds|CC0-1.0|https://opengameart.org/content/different-steps-on-wood-stone-leaves-gravel-and-mud|`a14a8ec452a458191b320f7e9ccdf7f8afde1addce9bb0d8c0e1e128fc070261`|
|step.grass/B/2|tools/audio/prepare_recorded_steps.py · cc0.grass.B.2|Fantozzi|CC0-1.0|https://opengameart.org/content/fantozzis-footsteps-grasssand-stone|`dab791abf4b7daa8ec884137219e18283f22cf040614b201a507f0355608365a`|
|step.grass/C/1|tools/audio/prepare_recorded_steps.py · cc0.grass.C.1|Fantozzi|CC0-1.0|https://opengameart.org/content/fantozzis-footsteps-grasssand-stone|`f4b86cefb2decd2de1f00afb7c5cd56452730b2a4aba92713c2fdf3650683ab3`|
|step.grass/C/2|tools/audio/prepare_recorded_steps.py · cc0.grass.C.2|TinyWorlds|CC0-1.0|https://opengameart.org/content/different-steps-on-wood-stone-leaves-gravel-and-mud|`9b67c0594b91dd98a51cb607502f385d6ff6c25f7b4071685dab36ab79208e83`|
|step.sand/A/1|tools/audio/prepare_recorded_steps.py · cc0.sand.A.1|Fantozzi|CC0-1.0|https://opengameart.org/content/fantozzis-footsteps-grasssand-stone|`dab791abf4b7daa8ec884137219e18283f22cf040614b201a507f0355608365a`|
|step.sand/A/2|tools/audio/prepare_recorded_steps.py · cc0.sand.A.2|Fantozzi|CC0-1.0|https://opengameart.org/content/fantozzis-footsteps-grasssand-stone|`a6831f04889d2903315b7eced69ee4f9c654a4fc59acc27885f45d66df2d1268`|
|step.sand/B/1|tools/audio/prepare_recorded_steps.py · cc0.sand.B.1|Fantozzi|CC0-1.0|https://opengameart.org/content/fantozzis-footsteps-grasssand-stone|`1167b73fe581c81f6f6efd18cdf5c2c3d99e55a469409684b9aed03f023e3e55`|
|step.sand/B/2|tools/audio/prepare_recorded_steps.py · cc0.sand.B.2|Fantozzi|CC0-1.0|https://opengameart.org/content/fantozzis-footsteps-grasssand-stone|`f4b86cefb2decd2de1f00afb7c5cd56452730b2a4aba92713c2fdf3650683ab3`|
|step.sand/C/1|tools/audio/prepare_recorded_steps.py · cc0.sand.C.1|Fantozzi|CC0-1.0|https://opengameart.org/content/fantozzis-footsteps-grasssand-stone|`8d1f9fe26f1182f860581b2040710b4ed115f74cb9b6f4a3173895b72a54decc`|
|step.sand/C/2|tools/audio/prepare_recorded_steps.py · cc0.sand.C.2|Fantozzi|CC0-1.0|https://opengameart.org/content/fantozzis-footsteps-grasssand-stone|`fd5a65a8dcd0aaf18e40377f9a6a5ee75af2ff89cb19cbb1c275d8e854ccd957`|
|step.wood/A/1|tools/audio/prepare_recorded_steps.py · cc0.wood.A.1|TinyWorlds|CC0-1.0|https://opengameart.org/content/different-steps-on-wood-stone-leaves-gravel-and-mud|`518103f24419d7c17798cec079bd62fdaa4cec0677ae0bf6c70ba88bd696003a`|
|step.wood/A/2|tools/audio/prepare_recorded_steps.py · cc0.wood.A.2|TinyWorlds|CC0-1.0|https://opengameart.org/content/different-steps-on-wood-stone-leaves-gravel-and-mud|`20793c522f6696f4b19715bc6521c16e949057b498833e949399633d8414fa9a`|
|step.wood/B/1|tools/audio/prepare_recorded_steps.py · cc0.wood.B.1|TinyWorlds|CC0-1.0|https://opengameart.org/content/different-steps-on-wood-stone-leaves-gravel-and-mud|`20793c522f6696f4b19715bc6521c16e949057b498833e949399633d8414fa9a`|
|step.wood/B/2|tools/audio/prepare_recorded_steps.py · cc0.wood.B.2|TinyWorlds|CC0-1.0|https://opengameart.org/content/different-steps-on-wood-stone-leaves-gravel-and-mud|`70941bc4943cfef544acf3ae5dbb526e9ca29e935e423215aafcfba49dd3e2b9`|
|step.wood/C/1|tools/audio/prepare_recorded_steps.py · cc0.wood.C.1|TinyWorlds|CC0-1.0|https://opengameart.org/content/different-steps-on-wood-stone-leaves-gravel-and-mud|`70941bc4943cfef544acf3ae5dbb526e9ca29e935e423215aafcfba49dd3e2b9`|
|step.wood/C/2|tools/audio/prepare_recorded_steps.py · cc0.wood.C.2|TinyWorlds|CC0-1.0|https://opengameart.org/content/different-steps-on-wood-stone-leaves-gravel-and-mud|`518103f24419d7c17798cec079bd62fdaa4cec0677ae0bf6c70ba88bd696003a`|
|step.stone/A/1|tools/audio/prepare_recorded_steps.py · cc0.stone.A.1|Fantozzi|CC0-1.0|https://opengameart.org/content/fantozzis-footsteps-grasssand-stone|`b5505d41126df718cacd4b27413b7cf76b8b242f51127c9860e231d8266cd288`|
|step.stone/A/2|tools/audio/prepare_recorded_steps.py · cc0.stone.A.2|Fantozzi|CC0-1.0|https://opengameart.org/content/fantozzis-footsteps-grasssand-stone|`bd5c65ae4d6653391f722d6f79b910d9ab863c630d0bfbd4aa83c5a27f1cbb15`|
|step.stone/B/1|tools/audio/prepare_recorded_steps.py · cc0.stone.B.1|Fantozzi|CC0-1.0|https://opengameart.org/content/fantozzis-footsteps-grasssand-stone|`ffcda7ddc9119430f6eafd22cfe2f67e74da5e97126a08cf1133b7e352128894`|
|step.stone/B/2|tools/audio/prepare_recorded_steps.py · cc0.stone.B.2|Fantozzi|CC0-1.0|https://opengameart.org/content/fantozzis-footsteps-grasssand-stone|`1072737f674f4c8963cc5336b17de3c7f212b6f4babefd47095275d51168064d`|
|step.stone/C/1|tools/audio/prepare_recorded_steps.py · cc0.stone.C.1|Fantozzi|CC0-1.0|https://opengameart.org/content/fantozzis-footsteps-grasssand-stone|`75994f1050f090f48754abba181930f72c3b8534993c3ac33a74e3c51db41ab5`|
|step.stone/C/2|tools/audio/prepare_recorded_steps.py · cc0.stone.C.2|Fantozzi|CC0-1.0|https://opengameart.org/content/fantozzis-footsteps-grasssand-stone|`7c6cc87b2d2b5437816dff734983d21f6ffedcb19dfe85c40d304c1d41c5a49f`|
|torch.ignite/A/1|tools/audio/dark_island_audio.py · dark1101.torch.ignite|本项目|project-original|本项目原创|`a848a2ac935fd400f213ed8cb3e88fdd68f6839d47131a9c634b257edde9bae7`|
|torch.plant/A/1|tools/audio/dark_island_audio.py · dark1101.torch.plant|本项目|project-original|本项目原创|`4eef1379809a92e774174229ebfdcd6b8df99f1dbe572b02fc6f0819c78fa38e`|
|torch.lift/A/1|tools/audio/dark_island_audio.py · dark1101.torch.lift|本项目|project-original|本项目原创|`c8e3d7df1904a864c076a2aa43666f98cd1c7cee4fecb0381a92266e9d8f84bb`|
|torch.warning/A/1|tools/audio/dark_island_audio.py · dark1101.torch.warning|本项目|project-original|本项目原创|`1fb9b80f34d20c45a75f0daa3d6efadb07c127b956f002e45d875f1a6a53c93f`|
|dark.kindling/A/1|tools/audio/dark_island_audio.py · dark1101.dark.kindling|本项目|project-original|本项目原创|`7d23a7b5caf528c8af29901ce1aada0383797fb25cefd48e38bbc5b0eecac3ad`|
|dark.beacon/A/1|tools/audio/dark_island_audio.py · dark1101.dark.beacon|本项目|project-original|本项目原创|`0a48eec7a399bfe42f9e6a96e9834f7dc7207b9a2c5f0ce10c11444aecc4f6eb`|
|cat.meow/A/1|tools/audio/synthesize_cat.py · original.cat.meow|本项目|project-original|本项目原创|`4b965d97a955eb7523c125276d859d20d4bb3f1b65a479b79d586072dac00e85`|
|cat.purr/A/1|tools/audio/synthesize_cat.py · original.cat.purr|本项目|project-original|本项目原创|`7ce3f9ea8796ee5a744dca82e78d92554212b43609e2327ab090efdc8cc6c657`|
|music.day/A/1|tools/audio/prepare_user_music.py · music.day|Kevin MacLeod|CC-BY-4.0|https://incompetech.com/music/royalty-free/index.html?isrc=USUAN2300003|`8c1d353695f8c5c7fa2ecbdde6248928fdc05eae94ca2a49e912b85c638107f2`|
|music.dusk/A/1|tools/audio/prepare_user_music.py · music.dusk|Kevin MacLeod|CC-BY-4.0|https://incompetech.com/music/royalty-free/index.html?isrc=USUAN2300002|`045018248035d570d2afaa56ee9b4a973a46ab9c1c64b56345f6cb08e91f2ab1`|
|music.night/A/1|tools/audio/prepare_user_music.py · music.night|Kevin MacLeod|CC-BY-4.0|https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100859|`3487cc8755c29a6e0d309d1e46fa7c9bcb633558b95bdac980d71e0abd52d74c`|
|music.rain/A/1|tools/audio/prepare_user_music.py · music.rain|Kevin MacLeod|CC-BY-4.0|https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1400035|`e99bf105e99e6512e7696a35a3d8f917b0666e0ad10ce2c15c66c19d953325ba`|
|music.fireside/A/1|tools/audio/prepare_user_music.py · music.fireside|Kevin MacLeod|CC-BY-4.0|https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1400033|`9d4a3432d7a82fa3b89374fef12817c580450ffee4b5d8d6b5a26733d0767384`|
|music.moon/A/1|tools/audio/prepare_user_music.py · music.moon|Kevin MacLeod|CC-BY-4.0|https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100799|`5d28dd6b860456e5f0e733abb06037b2d189867fd94935123b42f3333add3756`|
|music.dark/A/1|tools/audio/prepare_user_music.py · music.dark|Kevin MacLeod|CC-BY-4.0|https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1900004|`8ef1f645dc36ee5be15340b6f9bcb1512e6369a84792dab86c708d32c34157b9`|
|music.their/A/1|tools/audio/prepare_user_music.py · music.their|Kevin MacLeod|CC-BY-4.0|https://incompetech.com/music/royalty-free/index.html?isrc=USUAN1100819|`664d7a8000243e6b9efdce021caed4a6fe98e51c443622b4b14f6e2ab86f7064`|

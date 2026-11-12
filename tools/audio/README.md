# 离线声音工具

试听优先用实际浏览器网页，避免聊天应用的HTML预览无法读取相对音频：运行 `python3 tools/audio/serve_audition.py`，打开终端打印的本机网址。仅监听127.0.0.1，只提供试听页和清单内音频，支持音频分段请求，不读取玩家数据。页面显示加载状态和实际时长，并提供“直接打开音频”。需要固定端口可传 `--port 8765`；退出该脚本即可关闭服务。

需要 Python3 + numpy。数字检查另需 PySoundFile；音乐需 FluidSynth、FFmpeg 和明确授权的 TimGM6mb.sf2。所有工具都是本地离线运行，不调用模型，不下载、不安装依赖，不访问游戏数据目录。

```sh
python3 tools/audio/synthesize.py --stage samples
python3 tools/audio/synthesize.py --stage effects
python3 tools/audio/synthesize.py --stage ambience
python3 tools/audio/render_music.py --soundfont /absolute/path/TimGM6mb.sf2 --samples
python3 tools/audio/render_music.py --soundfont /absolute/path/TimGM6mb.sf2
python3 tools/audio/quality.py
python3 tools/audio/audition.py
```

本轮隔离工具在忽略的 `tmp/audio-env/bin/`；可把上述 python3 换为 `tmp/audio-env/bin/python`，音乐命令追加 `--fluidsynth tmp/audio-env/bin/fluidsynth --ffmpeg tmp/audio-env/bin/ffmpeg`。这不是游戏运行时依赖。

`score.json` 是人工记谱的 12 小节主旋律、和弦与六份编配数据。MIDI 是渲染过程中的临时文件；同类音符数据 score.json 已纳入仓库。每首 BPM 在 `tracks.<day|dusk|night|rain|fireside|moon>.bpm`，BPM 降低即放慢，其他游戏时长不受影响。请保持完整曲长60～120秒。乐曲 repeat2；白天80秒、黄昏87.27秒、夜晚106.67秒、雨天92.90秒、围炉84.71秒、月牙110.77秒。

全部改为纯八音盒：重新执行音乐渲染命令，加 `--musicbox-only`。试听30秒版也用该选项另加 `--samples`。只改一首则把对应 `guitar_velocity` 设0。不要误把 GM 编号10/24改成鼓轨。

声音选择在 `godot/content/audio/sounds.json` 的 `events.<清单ID>.selected`，选已有 A/B/C。重新渲染保留当前选择、总线与音量等清单设置。单独换版本不需要重新渲染，只需运行 audition.py 更新试听台。

六首正式音乐各有 A/B/C 完整版本，统一由 `events.music.sample30.selected` 选择；六首条目的可选 `selection_key: "music.sample30"` 将版本连到小样选择。A 是原编配，B 加柔和的低八度回应，C 降低旋律力度并更换吉他分解顺序。月牙岛三版都只有八音盒。试听30秒音乐所选的版本会进入实际游戏音乐，不另造一套未使用的小样。

每个合成文件由清单 sources.parameters 的确定性种子、采样率、时长、音高和归一化参数生成。算法组合正弦泛音、音高滑动、圆滑包络、滤波噪声与周期脉冲。录音自然素材未使用，海浪、风、雨、鸟、虫和脚步全部按用户允许的程序合成回退，不声称真实采样。

所有输出与来源/授权/哈希自动同步到清单和 SOURCES.md。quality.py 解码 OGG/WAV 检查实际峰值、削波、RMS、循环接缝和头尾静音，写 audio-qc.json/md。它不能证明听感好，最终以用户试听为准。音乐编码预留3dB峰值余量，接缝使用8ms余弦归零；不通过改测试阈值消除异常。

新 WAV 的 Godot `.import` 描述符固定 `compress/mode=0`，保留 PCM，避免默认 IMA-ADPCM 在循环边界引入额外误差。重新生成已有文件不会覆盖描述符；新增文件首次导入后也应设为0再重新导入。OGG音乐保留Vorbis编码。

下载的音色库和原始包仅存忽略的 tmp/；提取了 SF2、授权文本，未运行包内任何脚本。下载网址、作者、授权和哈希见 godot/content/audio/SOURCES.md。十个旧WAV仍保留；新系统独立目录不会覆盖它们。

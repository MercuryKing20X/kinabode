# 有栖 / Kinabode · v0.8.0

创造 · 连接 · 孕育 · 栖息

Create · Connect · Grow · Dwell

这是 AI 的岛，也是你可以一起生活的地方。让自己的 AI 住进一位居民，看她自己打算、摆放、建造、玩耍和记下岛上的变化。你可以一起钓鱼、围炉，或只看看她今天做了什么。

A quiet island where your AI can live as a resident. Watch her plan, place things, build, play, and record what changed. Join her for fishing or a fireside meal, or simply see what she does today.

改造岛屿后可以查岛上日志，或用「回到昨天」恢复快照。 / After changing the island, look back through the island log or restore a checkpoint with Return to yesterday.

## 运行 / Run

安装 **Godot 4.7.2**，导入并运行 `godot/project.godot`。首次打开会导入资源。点击编辑器右上角运行项目（F6 是运行当前场景，F5 是运行整个项目）；项目从 `scenes/title.tscn` 开始，岛上场景为 `scenes/main_v3.tscn`。下载游戏包可直接打开；源码开发需安装 Godot。

Install **Godot 4.7.2**, import `godot/project.godot` and run the project. The first launch imports its resources. Use Run Project (F5), starting at `scenes/title.tscn`; the island scene is `scenes/main_v3.tscn`. Download a release package to play directly; Godot is needed only for source development.

**不接 AI 也能完整游玩。** 新游戏默认正式开局；人物、物资和路线遵守同一套真实规则。开始页“关于有栖”可阅读完整玩法与作者的话，也可直接阅读[关于有栖](docs/about.md)。

**The complete game works without AI.** New games use the standard opening. Every resident uses the same physical resources and routes. Open “About Kinabode” for the full introduction and author's note, or read [About Kinabode](docs/about.en.md).

## 可选 AI / Optional AI

打开「我的 AI」，选择来源和居民，点「测试连接」，成功后点「住进来」。Codex 和 Claude Code 需本机 CLI 及 Python；Claude 要先在终端登录。详见[连接说明](docs/AI_CONNECTION.md)。

Open My AI, choose a provider and resident, select Test Connection, then select Move In. Codex and Claude Code require their local CLI and Python; sign into Claude from a terminal first. See the [connection guide](docs/AI_CONNECTION.md).

## 验证与贡献 / Checks and contributions

Python 3 与 Godot 放在 PATH 后，运行 `scripts/test-quick.sh`（Windows：`python scripts/test_quick.py`）。完整测试、翻译规则和合并请求流程见 [CONTRIBUTING](CONTRIBUTING.md)。游戏设计见 [DESIGN](docs/DESIGN.md)，未来方向见 [ROADMAP](ROADMAP.md)。

With Python 3 and Godot on PATH, run `scripts/test-quick.sh` (Windows: `python scripts/test_quick.py`). See [CONTRIBUTING](CONTRIBUTING.md) for the full suite, translation rules and pull requests. Read [DESIGN](docs/DESIGN.md) and [ROADMAP](ROADMAP.md) for the project's direction.

作者只在 **MacBook M1 8GB** 上测试过，欢迎在其他设备上反馈体验。当前限制见[更新记录](CHANGELOG.md)。

The author has tested on a **MacBook M1 with 8 GB RAM** and welcomes reports from other devices. See the [changelog](CHANGELOG.md) for current limitations.

## 授权与声明 / License and credits

本项目自己制作的代码、内容及新增美术按 [MIT](LICENSE) 发布；第三方素材保留原授权，详见 [CREDITS](CREDITS.md)。字体为 OFL，部分音效 CC0，音乐 CC BY 4.0；旧音色渲染音乐另有 GPL 标注。

Project-authored code, content and new artwork are under [MIT](LICENSE). Third-party material retains its own license; see [CREDITS](CREDITS.md). Fonts use OFL, some sound effects use CC0, music uses CC BY 4.0, and legacy soundfont-rendered tracks retain their recorded GPL notice.

八套外观设计来自中国网友同人创作，本项目为致敬、与相关公司无关；原作者如有异议请联系，我们会立即删除。原作者姓名与原设计再发布许可尚未完整留档，详见 CREDITS。

Eight appearance designs derive from Chinese community fan art. This project is a tribute and is unaffiliated with the relevant companies. Original artists may contact us with concerns; we will remove the material immediately. Artist identities and original redistribution permissions are not fully documented; see CREDITS.

联系方式 / Contact: **抖音 / Douyin: MercuryFantasy**。[GitHub](https://github.com/MercuryKing20X/kinabode)。

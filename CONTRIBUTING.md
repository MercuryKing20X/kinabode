# Contributing / 参与

Use Godot 4.7.2 and Python 3. Import `godot/project.godot`, let resources import, then run the project. The game must remain fully playable with every resident set to local intelligence.

使用 Godot 4.7.2 与 Python 3。导入 `godot/project.godot` 后运行；所有伙伴为本地时也必须完整可玩。

## Checks / 检查

- Quick checks: `scripts/test-quick.sh`; Windows: `python scripts/test_quick.py`.
- Full mixed suite on POSIX: `scripts/test-godot.sh`. Windows can run the isolated Godot checks with `scripts/test-godot.ps1`. Some preserved historical migration/provenance checks require private development evidence that is intentionally excluded from the public repository; a public quick-check pass is not a claim that those private-history audits ran.
- Translation check: `python scripts/portable_godot_checks.py --script check_translations.gd`.
- Secret scan: `python scripts/scan_secrets.py --directory . --output secret-scan.json`.
- Tests use temporary game data, a private user directory, Dummy audio and offline/fake adapters injected before connections are built. Real model calls require a separate explicit opt-in.

快测试、完整测试、翻译与密钥检查如上。测试必须隔离玩家数据；不把真实调用当默认测试，不改玩家存档来造进度。

## Pull requests / 合并请求

Open an issue or a focused pull request explaining the problem, behavior and validation. Use a branch, preserve existing player progress and editable artwork, and include both Chinese and English for new player-facing text. Maintainers should protect the main branch and require checks and review before merging.

先说明具体问题与结果，再提交聚焦的合并请求。新文字必须中英都有，保留玩家进度与可编辑人物；主分支应开启保护，通过检查和审查后再合并。

Do not tune personality, relationships, hunger, schedules, weather, budgets or movement speeds to make tests pass. Do not lower thresholds or delete failing assertions. Character action frames need actual artwork; whole-image rotation does not count as drawing an action. Keep rendering separate from movement and resource ownership. Never add credentials, private endpoints, personal paths, saves or model conversation records.

不许为过测试改性格、关系、饥饿、日程、天气、预算或速度，不许放宽/删除断言。人物动作要真画，不许整图旋转冒充。renderer 不控制路线/物资。不要提交凭据、私人接口、个人路径、存档与模型会话。

By contributing, you confirm you can submit the material under the project's license. Preserve all third-party notices, and identify generated or adapted assets with reproducible source information.

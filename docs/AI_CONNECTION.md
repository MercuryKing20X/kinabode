# 我的 AI / My AI

1. 在开始页、岛上右上角或设置打开「我的 AI」。 / Open **My AI** from the title screen, the island status, or Settings.
2. 选择来源和居民。Codex、Claude Code 需要本机 CLI 和 Python 3.8 或更高版本；Claude 需先在终端运行 `claude` 登录。 / Choose a provider and a resident. Codex and Claude Code require their local CLI and Python 3.8 or newer; sign into Claude from a terminal first.
3. 点「测试连接」，成功后点「住进来」。右上角的「住着」表示居民收到有效打算。 / Select **Test Connection**, then **Move In**. The **Living here** status means the resident received a valid plan.

Codex 沿用本机配置的账号、模型和服务商。兼容 API 与本机模型可在同一面板配置。断开时本地生活继续；CLI/API 可能消耗你自己的额度。 / Codex uses the account, model, and provider from your CLI configuration. Set up a compatible API or local model in the same panel. Local life continues after a disconnect; AI use can count against your own quota.

## 高级 / Advanced

自己的程序可展开面板里的高级选项，按 [本机 MCP/HTTP 协议](WORLD_DOOR.md) 接入。游戏端始终校验居民、动作与物资。 / For your own program, expand Advanced and follow the [local MCP/HTTP protocol](WORLD_DOOR.md). The game validates the resident, actions, and materials.

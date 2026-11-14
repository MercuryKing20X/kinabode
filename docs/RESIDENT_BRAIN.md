# Resident brain / 伙伴大脑

The live game gives each stable resident one utility brain. `brain.json` holds new needs, rates, activity prerequisites, durations, preferences and text in Chinese and English. Existing hunger, personality packs, relationships, schedules, weather, work yield and movement speeds remain authoritative. Raw legacy engine fixtures retain the compatibility projection; Main activates the brain with the existing intelligence presets.

大脑每隔数秒按需要、性格、环境、社交、新鲜度和本人独立随机源挑选。跟随时保留原选择，在主角附近做小事；玩家安排和托管派活经同一入口，先让出原自主动作，任务结束后重新选择。很饿时只留下找主角等开饭；不会自行劳动、取食或加关系分。

World remains the sole route owner. Work, Farm, Fireside and the intention executor retain all permissions and physical commits. LocalCompanion retains speech and delegated executors; Playground and LivelyCompanions no longer run competing idle decisions in the live game. Original day events, island stories and Dark Island behavior enter through brain candidates. The steward retains its director and existing watchdogs for this release.

Right-click a companion, or click the portrait in their details, to open **On my mind**. It shows the current wish and reasons, needs as words and five recent choices. Lifeblood's existing inner voice page is separate. No model is called by a local decision or this panel.

右键伙伴或点击居民详情头像可看“心里话”，包含当前选择及原因、需要的文字状态、最近五次选择。面板不显示需要分数，不替生命孕育发言，不调用模型。

`brain-traces/brain-trace-YYYY-MM-DD.jsonl` in the game data directory records choices, the top three scores and outcomes. Only the latest three calendar days are retained. Logs contain activity IDs and local reasons, with no connection details or conversation content. Decisions are session-only and never resume work after loading. `HABITAT_BRAIN_SEED` optionally selects a reproducible per-resident seed; reproducing an entire simulation also requires identical initial world state, weather, elapsed steps and player input.

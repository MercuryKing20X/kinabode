# 2026-11-03 可见界面混排扫描

新增真实引擎输入扫描四组合test_visible_locale_{zh,en}_{960,1280}.gd，遍历可见控件/菜单/原生弹窗，英文禁CJK，中文禁翻译键及英文成段。例外仅显式玩家自定义名字/作品、外部原话、旧历史；不按整面板豁免。生产scene初始化不全或0记录直接失败。可见入口使用island_hud，隐藏旧top不算真实输入。仓库/揭棋新文字全部双语，数量/来源ID不翻译为动作权限。原生viewport输入按用户定义通过push_input，不需系统桌面解锁。

---

# Chinese and English localization

The runtime uses Godot TranslationServer with meaningful English IDs in standard UTF-8 CSV files (`keys,zh,en`). localization.gd reads all CSV resources in this directory, registers native Translation resources, and works without an editor CSV import. NotoSansSC is unchanged. The same loader can register additional locales later.

Chinese is the default. The local language.cfg under HABITAT_DATA_DIR stores the preference; it is never a World field. LocalText.events.changed refreshes existing panels with their stable keys while preserving selections, drafts, scrolls, and unconfirmed choices. User/model messages and custom names are never translated by scanning visible text.

- text(key): current language.
- source(key): canonical Chinese for legacy data, internal cfg enums, and parsing. Never use translated text as an action ID or permission.
- content(value): exact authored system content lookup through content.* sidecars. Only call for proven built-in content, never player input or old historical prose.
- resident(world,id): default display names by stable resident ID. New custom_name markers and unmatched old names keep player names unchanged.
- speech(world,id,value): display-only translation of accepted local_rules lines; preserves authored personality and full template parameters. Model and player text never enter this resolver. Session template bindings are bounded to512 and never saved.

Original content JSON, IDs, numerical values, editable works, palette data and art sources stay unchanged. Sidecar content.* keys carry exact Chinese source plus English; the checker scans every JSON string/key against covered sources. Input dictionaries still parse original Chinese independent of selected language; their English sidecar entries explain those tokens, not new permissions.

SharedMemories already stores kind + facts + source IDs. New committed records add optional text_version:1 and render complete language templates; old records without that marker render the original Chinese templates/facts. Existing root schema7, diary256/marks192, strict facts and source deduplication remain. No old marker backfill.

Run ./scripts/test-godot.sh --only check_translations.gd. It fails on CJK literals outside comments in scripts, missing bilingual JSON content, empty/duplicate keys, malformed CSV, or mismatched printf/named placeholders. Translation resources are the only data exclusion. New user-facing text must have both languages. The two existing locales share every key through the same CSV rows.


## Validation and boundaries

Tests use Dummy audio, temporary data and offline adapters. Native desktop input, engine input and viewport captures are different evidence sources and must be identified accurately. Never use player saves or editable works as test fixtures.

# Kinabode contributor guide

Godot 4.7.2, GDScript, Python 3. Open `godot/project.godot`; start scene is `scenes/title.tscn`; the island scene is `scenes/main_v3.tscn`.

- `godot/scripts/`: runtime systems and UI; `godot/content/`: authored rules, translations and editable works; `godot/assets/`: textures, fonts and audio; `godot/tests/`: Godot checks; `scripts/`: bridge tools and test runners; `docs/`: public design and technical documentation.
- World owns all routes. Work and shared-life systems own gameplay and material commits. Renderers present; Main owns UI. Add no second movement path or fake resources.
- Residents have stable identities independent of appearance/controller. Models control only their own bound resident. Human movement/actions require explicit player UI.
- Preserve saves, physical materials, original editable artwork and third-party licenses. Reload stops real tasks; never invent completion, items or memories.
- New player-facing strings need Chinese and English. Keep offline play complete. Do not alter personality, hunger, relationship, schedule, weather, speed or budget parameters to pass tests; never weaken tests.
- Use temporary HABITAT_DATA_DIR and isolated user directories for tests; Dummy audio; fake adapters injected before connection creation. No real model calls without explicit authorization.
- Run `scripts/test-quick.sh` (or `python scripts/test_quick.py`), relevant focused checks, and the full suite for runtime/controller/bridge changes. Do not read or modify player data to simulate a test.
- Do not commit credentials, private endpoints, personal absolute paths, caches, model transcripts or saves. No generated-image originals or private production records in this repository.
- Explain the concrete problem, fix and test evidence in each pull request. Use branches and reviewed pull requests; do not rewrite shared history.

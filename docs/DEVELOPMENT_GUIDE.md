# Development and validation / 开发与验证

Use Godot 4.7.2 and Python 3. Import `godot/project.godot`, let resources import and run the project with F5. Public design and contributor rules are in [DESIGN.md](DESIGN.md) and [CONTRIBUTING.md](../CONTRIBUTING.md).

World is the sole route authority. Work and shared-life systems own jobs and material commits; IslandView and renderers present state; Main and panels handle explicit player input. Current shared storage rules are in [SYSTEM_STORAGE.md](SYSTEM_STORAGE.md); never create a second inventory system.

Run `scripts/test-quick.sh` or `python scripts/test_quick.py` for quick checks. Godot is discovered through `HABITAT_GODOT`, then `godot` or `godot4` on PATH. POSIX full-suite entry is `scripts/test-godot.sh`. Windows can run isolated Godot checks with `scripts/test-godot.ps1`, or all systems can use `python scripts/portable_godot_checks.py --script test_foundation.gd`. Preserved historical evidence audits may require development records excluded from this public release; see CONTRIBUTING for that limit.

Tests use temporary `HABITAT_DATA_DIR`, isolated user directories, Dummy audio and offline/fake adapters injected before connection construction. Time assertions must advance real simulation time; visual checks must capture real Godot viewports. Never modify player saves or works to manufacture progress. Real model calls require separate explicit authorization, an isolated live-test directory and a defined budget.

New text needs Chinese and English. Preserve save compatibility, real materials, editable artwork, speech gates and model identity/cancellation bindings. Do not tune content parameters or weaken assertions to pass tests. Asset attribution is in [CREDITS.md](../CREDITS.md); release limitations are in [CHANGELOG.md](../CHANGELOG.md).

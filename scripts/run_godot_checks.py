"""Isolated Godot checks; stable report order, bounded parallelism and failure replay."""
import argparse
from concurrent.futures import ThreadPoolExecutor, as_completed
from contextlib import ExitStack, nullcontext, contextmanager
import json
import os
from pathlib import Path
from godot_runtime import godot_executable
from deterministic_godot import materialize
import subprocess
import sys
import tempfile
import time
import threading
import fcntl

ROOT = Path(__file__).resolve().parents[1]
os.environ["HABITAT_OPENING"] = "legacy"
os.environ.setdefault("HABITAT_DETERMINISTIC_TESTS", "1")
os.environ.setdefault("HABITAT_TEST_SEED", "1027")
# Offline is the suite default, including an accidentally unreplaced native
# adapter. A test can still select its own explicit fake executable locally.
os.environ.setdefault("HABITAT_CODEX", "habitat-offline-model-disabled")
# The GPT bridge uses urllib. Deny external HTTP in this process tree while
# retaining the local fake HTTP/WebSocket servers used by protocol tests.
for proxy_name in ["HTTP_PROXY","HTTPS_PROXY","ALL_PROXY","http_proxy","https_proxy","all_proxy"]:
    os.environ[proxy_name] = "http://127.0.0.1:1"
for bypass_name in ["NO_PROXY","no_proxy"]:
    os.environ[bypass_name] = "127.0.0.1,localhost,::1"
ENGINE = godot_executable()
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("--resume", action="store_true", help="Keep completed records and run only missing checks on the unchanged source tree")
parser.add_argument("--failed-only", action="store_true", help="Replay failed commands from --previous-results")
parser.add_argument("--previous-results", type=Path)
parser.add_argument("--only", action="append", default=[], help="Run only a script basename (repeatable)")
args = parser.parse_args()
# Concurrent suite invocations compete for CPU and the shared import cache.
# Serialize runners; individual checks retain their original execution limits.
suite_lock = open(Path(tempfile.gettempdir()) / "youqi-godot-suite.lock", "a")
fcntl.flock(suite_lock, fcntl.LOCK_EX)
report_path = Path(os.environ.get("HABITAT_SUITE_REPORT", str(ROOT / "godot/.godot/last-check-results.json")))
previous_path = args.previous_results or report_path
try:
    previous = json.loads(previous_path.read_text())
except (OSError, ValueError):
    if args.failed_only:
        parser.error("failure replay requires a readable previous result JSON")
    # Historical timings are optional scheduling hints, absent in public exports.
    hints = ROOT / "production/evidence/fishing-v2/full-results.json"
    previous = json.loads(hints.read_text()) if hints.is_file() else []
try:
    jobs = int(os.environ.get("HABITAT_TEST_JOBS", str(min(3, max(1, (os.cpu_count() or 2) // 2)))))
    if jobs < 1: raise ValueError()
except ValueError:
    parser.error("HABITAT_TEST_JOBS must be a positive integer")

def identity(command):
    return tuple(command[1:])

historical_weights = {identity(r["command"]): r.get("seconds", 0) for r in previous}
weights = {} if os.environ['HABITAT_DETERMINISTIC_TESTS'] == '1' else {identity(r["command"]): r.get("seconds", 0) for r in previous}
failed_keys = {identity(r["command"]) for r in previous if not r["passed"]}
pending = []
results = []
stack = ExitStack()
# Keep fixture directories alive until all queued checks finish.
def temporary_directory(**kwargs):
    class RetainedDirectory:
        def __enter__(self): return stack.enter_context(tempfile.TemporaryDirectory(**kwargs))
        def __exit__(self, *_): return False
    return RetainedDirectory()

runtime = Path(stack.enter_context(tempfile.TemporaryDirectory(prefix="youqi-test-suite-")))
palette_path = runtime / "palette-48.png"
subprocess.run([sys.executable,str(ROOT / "scripts/generate_island_v3_palette.py")],env=dict(os.environ,HABITAT_PALETTE_OUTPUT=str(palette_path)),check=True)
# Godot probes user:// for writability even when --log-file is supplied.
# Use a private project configuration with shared read-only source symlinks and
# the existing import cache; never let the engine resolve the player's user://.
shadow = runtime / "workspace"
shadow.mkdir()
for source in ROOT.iterdir():
    if source.name != "godot": (shadow / source.name).symlink_to(source, target_is_directory=source.is_dir())
private_fixtures = os.environ.get("HABITAT_PRIVATE_TEST_FIXTURES")
if private_fixtures:
    fixture_root = Path(private_fixtures).resolve()
    if not (fixture_root / "production").is_dir(): parser.error("HABITAT_PRIVATE_TEST_FIXTURES must contain production/")
    (shadow / "production").symlink_to(fixture_root / "production", target_is_directory=True)
    print("PRIVATE_TEST_FIXTURES enabled (read-only historical inputs; excluded from public source)", flush=True)
project = shadow / "godot"
project.mkdir()
for source in (ROOT / "godot").iterdir():
    if source.name not in {"project.godot", "scripts", "tests"}: (project / source.name).symlink_to(source, target_is_directory=source.is_dir())
if os.environ["HABITAT_DETERMINISTIC_TESTS"] == "1":
    injection_counts = materialize(ROOT / "godot", project)
    print("TEST_ENVIRONMENT " + json.dumps(dict(seed=os.environ["HABITAT_TEST_SEED"], epoch=1794542400, injections=injection_counts)), flush=True)
else:
    for folder in ["scripts", "tests"]: (project / folder).symlink_to(ROOT / "godot" / folder, target_is_directory=True)
user_name = runtime.name
engine_user = Path.home() / "Library/Application Support" / user_name
stack.callback(lambda: __import__('shutil').rmtree(engine_user, ignore_errors=True))
config = (ROOT / "godot/project.godot").read_text()
config = config.replace('[application]', '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="' + user_name + '"')
(project / "project.godot").write_text(config)
# Python integration tests launch Godot themselves. A private wrapper routes every
# nested engine log outside app_userdata, without changing recorded commands.
wrapper = runtime / "godot-test-engine"
wrapper.write_text("#!" + sys.executable + "\nimport os,sys,tempfile\n"
    + "fd,p=tempfile.mkstemp(prefix='engine-',suffix='.log',dir=" + repr(str(runtime)) + ");os.close(fd)\n"
    + "args=sys.argv[1:]\nif '--path' in args: args[args.index('--path')+1]=os.environ.get('HABITAT_TEST_PROJECT'," + repr(str(project)) + ")\n"
    + "os.execv(" + repr(ENGINE) + ",[" + repr(ENGINE) + ",'--audio-driver','Dummy','--rendering-method','gl_compatibility','--rendering-driver','opengl3','--log-file',p]+args)\n")
wrapper.chmod(0o700)

def run(command, env=None):
    if args.failed_only and identity(command) not in failed_keys: return
    if args.only and "--import" not in command and Path(command[-1]).name not in args.only: return
    pending.append((command, env))

visible_lock = threading.Lock()

@contextmanager
def visible_session():
    with visible_lock, open(Path(os.environ.get("HABITAT_TEST_VISIBLE_LOCK", "/tmp/youqi-godot-visible-check.lock")), "a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        try: yield
        finally: fcntl.flock(lock, fcntl.LOCK_UN)

def execute(item):
    command, env = item
    started = time.monotonic()
    timeout = 300 if 'tests/test_fish_v3_input.gd' in command or 'tests/test_life_archive.gd' in command or 'tests/test_local_dialogue.gd' in command or 'tests/test_orange_sunflower_input.gd' in command or 'tests/test_steward_day.gd' in command or 'tests/test_steward_long_host.gd' in command else 180 if 'tests/test_stuck_save_input.gd' in command or 'tests/test_island_recipe_save_contract.gd' in command or 'tests/test_island_recipe_meals_input.gd' in command or 'scripts/test_read_bridge.py' in command or 'tests/test_local_life_15d.gd' in command or 'tests/test_playtest_invitation_input.gd' in command or 'tests/test_their_island_story_input.gd' in command or 'tests/test_their_island_build_input.gd' in command else 90
    if "tests/test_steward_director_long.gd" in command: timeout = 600
    if "tests/test_brain_30min.gd" in command: timeout = 1500
    if "tests/test_brain_input.gd" in command: timeout = 600
    if Path(command[-1]).name in {"test_one_line_follow_input.gd","test_resident_intentions.gd","test_follow_play_input.gd"}: timeout = 300
    if "tests/probe_steward_squad.gd" in command: timeout = 300
    if "tests/probe_one_line_execution.gd" in command: timeout = 1800
    if "tests/test_intention_catalog.gd" in command or "tests/test_steward_async.gd" in command: timeout = 300
    with tempfile.TemporaryDirectory(prefix="youqi-check-", dir=runtime) as directory:
        # Give every engine process tree its own user:// as well as game data.
        # Source/imports are shared, writable user preferences are not.
        case_project = Path(directory) / "godot"
        for source in shadow.iterdir():
            if source.name != "godot": (Path(directory) / source.name).symlink_to(source, target_is_directory=source.is_dir())
        case_project.mkdir()
        for source in project.iterdir():
            if source.name != "project.godot": (case_project / source.name).symlink_to(source, target_is_directory=source.is_dir())
        case_user_name = user_name + "-" + Path(directory).name
        (case_project / "project.godot").write_text(config.replace(user_name, case_user_name))
        child_env = dict(env or os.environ, HABITAT_GODOT=str(wrapper), HABITAT_TEST_PROJECT=str(case_project))
        child_env.setdefault("HABITAT_DATA_DIR", directory)
        child_env["HABITAT_TEST_SUITE"] = "1"
        child_env["HABITAT_LIVE_TEST"] = "0"
        child_env["HABITAT_PALETTE_OUTPUT"] = str(palette_path)
        if command[-1] == "tests/test_local_life_15d.gd":
            child_env.setdefault("HABITAT_LOCAL_LIFE_SIMULATION_OUTPUT", str((report_path.parent / ("local-life-15d-" + report_path.stem + ".json")).resolve()))
        actual = command
        if command[0] == ENGINE:
            actual = [ENGINE, '--audio-driver', 'Dummy', '--rendering-method', 'gl_compatibility', '--rendering-driver', 'opengl3', '--log-file', str(Path(directory) / 'engine.log'), *command[1:]]
            if '--path' in actual: actual[actual.index('--path')+1] = str(case_project)
            if (os.environ.get('HABITAT_TEST_VISIBLE') == '1' or command[-1].split('/')[-1] in {'test_brain_30min.gd','test_brain_input.gd','test_local_dialogue.gd','test_life_archive.gd','test_daily_quota.gd','test_orange_sunflower_input.gd','test_orange_talk_input.gd','test_fish_v3_input.gd','test_two_villa_input.gd','test_home_island_input.gd','test_their_island_story_input.gd','capture_playtest_camera.gd','test_playtest_invitation_input.gd','test_playtest_gomoku_input.gd','test_speech_quiet_input.gd','test_island_recipe_input.gd','test_island_recipe_meals_input.gd','test_playtest_fishing_invitation_input.gd'}) and '--headless' in actual: actual.remove('--headless')
        try:
            with (visible_session() if command[0] == ENGINE and "--headless" not in actual and "--editor" not in actual else nullcontext()):
                started = time.monotonic()
                result = subprocess.run(actual, cwd=ROOT, env=child_env, text=True, capture_output=True, timeout=timeout)
            output = result.stdout + result.stderr
            passed = not (result.returncode or 'SCRIPT ERROR:' in output or '\nERROR:' in output)
            record = {'command': command, 'passed': passed, 'exit_code': result.returncode}
        except subprocess.TimeoutExpired as error:
            def decoded(value): return value.decode('utf-8', errors='replace') if isinstance(value, bytes) else (value or '')
            output = decoded(error.stdout) + decoded(error.stderr)
            record = {'command': command, 'passed': False, 'timeout_seconds': timeout}
        except OSError as error:
            output = str(error) + '\n'
            record = {'command': command, 'passed': False, 'error': str(error)}
    __import__('shutil').rmtree(Path.home() / 'Library/Application Support' / case_user_name, ignore_errors=True)
    if env and 'HABITAT_COVERAGE_START' in env:record['coverage_range']=[int(env['HABITAT_COVERAGE_START']),int(env['HABITAT_COVERAGE_END'])]
    record['seconds'] = round(time.monotonic() - started, 3)
    record['test_environment'] = {'deterministic': child_env.get('HABITAT_DETERMINISTIC_TESTS') == '1', 'seed': child_env.get('HABITAT_TEST_SEED')}
    if not record['passed']: record['failure_output'] = output
    return record, output

for script in ["test_flower_group.gd", "test_flower_guards.gd", "test_creation_quiet_night.gd", "test_flower_creation.gd", "test_flower_isle_migration.gd", "test_flower_panel_input.gd", "test_flower_creation_input.gd", "test_creation_writing.gd", "test_creation_writing_input.gd", "test_brain_legacy_init.gd", "test_command_delivery_unit.gd", "test_follow_play_input.gd", "test_brain_30min.gd", "test_brain_input.gd", "test_brain_contract.gd", "test_v06_delivery_input.gd", "test_v06_wardrobe_input.gd", "test_orange_chop_v06.gd", "test_steward_director_long.gd", "probe_steward_squad.gd", "test_tutorial_goals.gd", "test_local_steward_entry.gd", "test_steward_90s_lease.gd", "test_steward_async.gd", "test_local_dialogue_clock.gd", "test_follow_selection_boundary.gd", "test_carry_retention.gd", "test_orange_talk_input.gd", "test_life_archive.gd", "test_daily_quota.gd", "test_local_dialogue.gd", "test_fish_v3_input.gd", "test_orange_sunflower_input.gd", "test_connection_ownership.gd", "test_opening_connecting_body.gd", "test_meal_timer_running.gd", "test_connection_idle_twenty.gd", "test_steward_long_host.gd", "test_steward_opening_input.gd", "test_steward_human_input.gd", "test_connection_cancel_input.gd", "test_camera_points_input.gd", "test_flexible_queue_input.gd", "test_playground_input.gd", "test_dialogue_bar_input.gd", "test_steward_repair_input.gd", "test_steward_connections.gd", "test_steward_day.gd", "test_steward.gd", "test_resident_recipe_guard.gd", "test_empowered_autonomy.gd", "test_intention_catalog.gd", "test_empowered_input.gd", "test_empowered_cat.gd", "test_resident_intentions.gd", "test_command_page_input.gd", "test_command_delivery_input.gd", "test_first_ai_stub.gd", "test_unified_dialogue_input.gd", "test_persona_guard.gd", "test_memory_books.gd", "test_memory_migration.gd", "test_intent_input.gd", "test_resort_revision_migration.gd", "test_two_villa_input.gd", "test_two_villa_migration.gd", "test_health_ai.gd", "test_health_ai_labor.gd", "test_chat_composition_input.gd", "test_intelligence_core_input.gd", "test_farm_host_plan.gd", "test_farm_helpers_1105.gd", "test_local_host_command_parse.gd", "test_local_command_card_input.gd", "test_local_command_main_input.gd", "test_ui_scale_preferences.gd", "test_standard_seed_sources_input.gd", "test_island_recipe_save_contract.gd", "test_music_preview.gd", "test_cultivated_beds.gd", "test_cultivated_beds_input.gd", "test_fish_drying_input.gd", "test_island_ingredients.gd", "test_ingredient_native_input.gd", "test_ingredient_south_input.gd", "test_island_recipe_contract.gd", "test_island_recipe_input.gd", "test_island_recipe_meals_input.gd", "test_cat_mainland_openings.gd", "test_south_roads_cat.gd", "test_home_island_visited.gd", "test_bbq_walk_matrix.gd", "test_home_island_render.gd", "test_home_island_migration.gd", "test_home_island_parse.gd", "test_host_build_all.gd", "test_home_island_input.gd", "capture_playtest_camera.gd", "test_playtest_invitation_input.gd", "test_playtest_gomoku_input.gd", "test_companion_return.gd", "test_speech_quiet.gd", "test_speech_quiet_input.gd", "test_playtest_fishing_invitation_input.gd", "test_garden_command.gd", "test_dark_island.gd", "test_dark_audio.gd", "test_dark_companions.gd", "test_dark_direct_grill.gd", "test_camera_defaults_1101.gd", "test_player_follow.gd"]:
    if (ROOT / "godot/tests" / script).exists():
        with temporary_directory(prefix="youqi-test-") as directory:
            run([ENGINE]+([] if script=="test_meal_timer_running.gd" and os.environ.get("HABITAT_UI_EVIDENCE") else ["--headless"])+["--path","godot","--script","tests/"+script],dict(os.environ,HABITAT_DATA_DIR=directory))
with temporary_directory(prefix="youqi-test-") as directory:
    run([ENGINE]+([] if os.environ.get("STUCK_NATIVE") else ["--headless"])+["--path","godot","--script","tests/test_stuck_save_input.gd"],dict(os.environ,HABITAT_DATA_DIR=directory))
with temporary_directory(prefix="youqi-test-") as directory:
    run([ENGINE]+([] if os.environ.get("GUIDE_NATIVE") else ["--headless"])+["--path","godot","--script","tests/test_guide_layout_input.gd"],dict(os.environ,HABITAT_DATA_DIR=directory))
for coverage_begin in range(0,640,40):
    with temporary_directory(prefix="youqi-coverage-") as directory:
        run([ENGINE,"--headless","--path","godot","--script","tests/probe_one_line_execution.gd"],dict(os.environ,HABITAT_DATA_DIR=directory,HABITAT_COVERAGE_START=str(coverage_begin),HABITAT_COVERAGE_END=str(coverage_begin+40)))
run([sys.executable,"scripts/test_one_line_action_contract.py"])
run([ENGINE,'--headless','--editor','--path','godot','--import','--quit'])
run([sys.executable,"scripts/test_life_protocol.py"])
run([sys.executable,"scripts/test_intent_companion.py"])
run([sys.executable,"scripts/test_persona_cards.py"])
for visible_script in ["test_ai_quote_ui.gd", "test_simple_connection_input.gd", "test_title_fit_input.gd", "test_about_document.gd"]:
    with temporary_directory(prefix="youqi-simple-") as directory:
        run([ENGINE,"--path","godot","--script","tests/"+visible_script],dict(os.environ,HABITAT_DATA_DIR=directory))
for storage_script in sorted((ROOT / "godot/tests").glob("test_chess*.gd")) + sorted((ROOT / "godot/tests").glob("test_*storage*.gd")) + sorted((ROOT / "godot/tests").glob("test_jieqi*.gd")) + sorted((ROOT / "godot/tests").glob("test_visible_locale*.gd")):
    if storage_script.name in ["test_system_storage.gd","test_visible_locale_input.gd","test_jieqi_simulation.gd"]: continue
    with temporary_directory(prefix="youqi-test-") as directory:
        run([ENGINE,"--headless","--path","godot","--script","tests/"+storage_script.name],dict(os.environ,HABITAT_DATA_DIR=directory))

with temporary_directory(prefix="youqi-test-") as directory:
    run([ENGINE,"--headless","--path","godot","--script","tests/test_system_storage.gd"],dict(os.environ,HABITAT_DATA_DIR=directory))
for script in ['test_foundation.gd','test_slice.gd','test_editor.gd','test_shared_life.gd','test_barbecue_v2.gd','test_barbecue_v3.gd','test_barbecue_v3_resources.gd','test_barbecue_v3_ui.gd','test_barbecue_v4.gd','test_cat_companion.gd','test_lively_observation.gd','test_barbecue_invite_routes.gd','test_barbecue_ui_v4.gd','test_gait_v4.gd','test_campfire_v4_study.gd','test_fireside_tastes.gd','test_fireside_rng_v4.gd','test_fireside_chat.gd','test_fireside_glyphs.gd','test_barbecue_scenes.gd','test_fireside_motion.gd','test_fireside_controller.gd','test_fireside_receipts.gd','test_moon_barbecue_audit.gd','test_moon_map.gd','test_moon_viewing.gd','test_multiple_barbecues.gd','test_moon_controller.gd','test_moon_schedule.gd','test_moon_coast.gd','test_motion.gd','test_walk_v2.gd','test_motion_v4.gd','test_route_corner_v3.gd','test_fractional_chess_arrival.gd','test_camp_binding_v4.gd','test_camp_click_approach.gd','test_camp_remote_actions.gd','test_glm_legacy_direction.gd','test_glm_nondefault_motion.gd','test_character_directions.gd','test_think_motion.gd','test_run.gd','test_camp_motion.gd','test_intelligence_migration.gd','test_intelligence_activation.gd','test_hunger.gd','test_hunger_follow.gd','test_hunger_food.gd','test_hunger_tuning.gd','test_standard_opening.gd','test_standard_controller.gd','test_standard_polish.gd','test_intelligence_ui.gd','test_local_companion.gd','test_home_expansion.gd','test_workshop.gd','test_workshop_menu.gd','test_appearance_protection.gd','test_appearance_startup.gd','test_wardrobe.gd','test_ui_size.gd','test_spare_appearances.gd','test_outfit_rules.gd','test_outfit_editor.gd','test_character_assembler.gd','test_interior.gd','test_work_orders.gd','test_construction_projects.gd','test_farms.gd','test_farm_controller.gd','test_village.gd','test_recreation.gd','test_resident_director.gd']:
    with temporary_directory(prefix='youqi-test-') as directory:
        run([ENGINE,'--headless','--path','godot','--script','tests/'+script],dict(os.environ,HABITAT_DATA_DIR=directory))
with temporary_directory(prefix='youqi-test-') as directory:
    run([ENGINE,'--headless','--path','godot','--script','tests/test_conversation_link.gd'],dict(os.environ,HABITAT_DATA_DIR=directory))
for script in ['test_flower_action_contract.py','test_return_visit.py','test_speech_quiet.py','test_farm_commands.py','test_character_face_directions.py','test_intelligence_content.py','test_read_bridge.py','test_model_bridge.py','test_conversation_bridge.py','test_shared_companion.py','test_direct_api.py','test_codex_connection_probe.py','test_codex_unix_websocket.py','test_action_adapters.py','test_external_adapter.py','test_gomoku_adapter.py','test_cooking_adapter.py','test_journal_adapter.py','test_homestead_adapter.py','test_autonomy_bridge.py','test_overnight_prompt.py','test_proposals_adapter.py','test_promises_adapter.py','test_gifts_adapter.py','test_documentation_migration.py','test_gomoku_speech_contract.py','test_v3_reset.py']:
    run([sys.executable,'scripts/'+script])
with temporary_directory(prefix='youqi-test-') as directory:
    run([ENGINE,'--headless','--path','godot','--script','tests/test_forest.gd'],dict(os.environ,HABITAT_DATA_DIR=directory))
with temporary_directory(prefix='youqi-test-') as directory:
    run([ENGINE,'--headless','--path','godot','--script','tests/test_shared_dialogue.gd'],dict(os.environ,HABITAT_DATA_DIR=directory))

with temporary_directory(prefix='youqi-test-') as directory:
    run([ENGINE,'--headless','--path','godot','--script','tests/test_dialogue_channels.gd'],dict(os.environ,HABITAT_DATA_DIR=directory))

with temporary_directory(prefix='youqi-test-') as directory:
    run([ENGINE,'--headless','--path','godot','--script','tests/test_flower_gifts.gd'],dict(os.environ,HABITAT_DATA_DIR=directory))

with temporary_directory(prefix='youqi-test-') as directory:
    run([ENGINE,'--headless','--path','godot','--script','tests/test_life_acceptance.gd'],dict(os.environ,HABITAT_DATA_DIR=directory))

with temporary_directory(prefix='youqi-test-') as directory:
    run([ENGINE,'--headless','--path','godot','--script','tests/test_shared_activity.gd'],dict(os.environ,HABITAT_DATA_DIR=directory))

with temporary_directory(prefix='youqi-test-') as directory:
    run([ENGINE,'--headless','--path','godot','--script','tests/test_shared_activity_controller.gd'],dict(os.environ,HABITAT_DATA_DIR=directory))

with temporary_directory(prefix="youqi-test-") as directory:
    run([ENGINE,"--headless","--path","godot","--script","tests/test_atlas.gd"],dict(os.environ,HABITAT_DATA_DIR=directory))

with temporary_directory(prefix="youqi-test-") as directory:
    run([ENGINE,"--headless","--path","godot","--script","tests/test_shared_memories.gd"],dict(os.environ,HABITAT_DATA_DIR=directory))

for script in ["test_lifeblood_input.gd","test_lifeblood_memory.gd","test_memory_ai.gd","test_memory_life_input.gd","test_one_line_cloud_stub.gd","test_one_line_social_input.gd","test_one_line_water_input.gd","probe_one_line_coverage.gd","test_one_line_labor_input.gd","probe_one_line_speech.gd","test_one_line_follow_input.gd","test_fishing.gd","test_fishing_invite_v2.gd","test_fishing_invite_ui_v2.gd","test_fishing_animations_v2.gd","test_fishing_cards_ui_v2.gd","test_fishing_cards_standard_v2.gd","test_fishing_stock_capacity_v2.gd","test_fishing_speech_v2.gd","test_fishing_swim_v2.gd","test_fishing_outfit_ui_v2.gd","test_fishing_revision.gd","test_fishing_controller.gd","test_fishing_experience.gd","test_gomoku.gd","test_gomoku_controller.gd","test_cooking.gd","test_cooking_controller.gd","test_journal.gd","test_journal_controller.gd","test_days.gd","test_days_controller.gd","test_backpack.gd","test_backpack_controller.gd","test_resident_connections.gd","test_homestead.gd","test_homestead_controller.gd","test_memory_reminders.gd","test_memory_reminders_controller.gd","test_resident_moods.gd","test_resident_moods_controller.gd","test_autonomy_context.gd","test_autonomy_scheduler.gd","test_autonomy_controller.gd","test_autonomy_sources.gd","test_autonomy_simulation.gd","test_overnight_autonomy.gd","test_autonomy_records.gd","test_proposals.gd","test_promises.gd","test_gifts.gd","test_cooperation.gd","test_polish_fixes.gd","test_polish_usage.gd","test_polish_navigation.gd","test_relationships.gd","test_wishes.gd","test_wishes_controller.gd","test_schedules_weather.gd","test_weather_controller.gd","test_personality.gd","test_personality_controller.gd","test_local_life_simulation.gd","probe_relationship_pacing_compatibility.gd","test_local_life_15d.gd","test_relationship_rewards.gd","test_relationship_rewards_controller.gd","test_wish_feasibility.gd","test_personality_rhythm.gd","test_gift_idle.gd","test_gomoku_companion.gd","test_gomoku_dialogue.gd","test_gomoku_ai.gd","test_gomoku_match_host.gd","test_gomoku_ai_controller.gd","test_map_locations.gd","test_island_v3_style.gd","test_tile_terrain.gd","test_island_v3_sample.gd","test_polygon_study_ground.gd","test_art_plaza_layout.gd","test_study_house_works.gd","test_art_residential_layout.gd","test_art_study_scene.gd","test_art_comparison.gd","test_house_retrofits.gd","test_home_v3_data.gd","test_showcase_opening.gd","test_home_v3_systems.gd","test_home_v3_art.gd","test_home_v3_ui.gd","test_home_v3_simulation.gd","test_home_v3_conservation.gd","test_home_v3_distances.gd","test_home_v3_layout.gd","test_home_v3_polish.gd","test_home_v3_atmosphere.gd","test_home_v3_ui_polish.gd","test_resident_card_close_v2.gd"]:
    with temporary_directory(prefix="youqi-test-") as directory:
        run([ENGINE,"--headless","--path","godot","--script","tests/"+script],dict(os.environ,HABITAT_DATA_DIR=directory))

for script in ["test_moon_fishing_mouse.gd","test_rod_tip_binding.gd","test_run_distance_frames.gd","test_run_v2.gd","test_run_atlas_v4.gd","test_meal_timeline.gd","test_run_eat_mouse_standard.gd","test_run_eat_mouse_showcase.gd","test_motion_viewport_performance.gd","test_speech_rng_isolation.gd"]:
    with temporary_directory(prefix="youqi-test-") as directory:
        run([ENGINE,"--headless","--path","godot","--script","tests/"+script],dict(os.environ,HABITAT_DATA_DIR=directory))

for script in ["test_direct_grill.gd","test_direct_grill_mouse.gd","test_new_fish.gd","test_direct_grill_refuel.gd"]:
    with temporary_directory(prefix="youqi-test-") as directory:
        run([ENGINE,"--headless","--path","godot","--script","tests/"+script],dict(os.environ,HABITAT_DATA_DIR=directory))

for script in ["test_game_audio.gd","test_audio_environment.gd","test_audio_music.gd","test_audio_v2.gd","test_gesture_motion_v2.gd","test_hungry_onlooker.gd","test_save_backup.gd","test_backup_main.gd"]:
    with temporary_directory(prefix="youqi-test-") as directory:
        run([ENGINE,"--headless","--path","godot","--script","tests/"+script],dict(os.environ,HABITAT_DATA_DIR=directory))
for script in ["test_localization.gd", "test_localization_records.gd", "test_localization_legacy.gd", "test_audio_quiet.gd", "check_translations.gd"]:
    with temporary_directory(prefix="youqi-test-") as directory:
        run([ENGINE,"--headless","--path","godot","--script","tests/"+script],dict(os.environ,HABITAT_DATA_DIR=directory))
if os.environ.get('HABITAT_TEST_VISIBLE')=='1':
    with temporary_directory(prefix="youqi-test-") as directory:
        run([ENGINE,"--headless","--path","godot","--script","tests/test_gesture_visual_v2.gd"],dict(os.environ,HABITAT_DATA_DIR=directory))
run([sys.executable,"scripts/test_audio_content.py"])
run([sys.executable,"scripts/test_audio_v2.py"])
run([sys.executable,"scripts/test_gesture_motion_v2.py"])
run([sys.executable,"scripts/validate_hungry_onlooker.py"])
run([sys.executable,"scripts/validate_save_backup.py"])
for island_script in ["test_their_island_model.gd","test_their_island_ui.gd","test_their_island_story_input.gd","test_their_island_build_input.gd","test_their_island_progress.gd"]:
    with temporary_directory(prefix="youqi-theirs-") as directory:
        run([ENGINE,"--headless","--path","godot","--script","tests/"+island_script],dict(os.environ,HABITAT_DATA_DIR=directory))
for island_script in ["test_island_transport.py","test_island_proposal_contract.py"]:
    run([sys.executable,"scripts/"+island_script])
with temporary_directory(prefix="youqi-theirs-") as directory:
    run([ENGINE,"--headless","--path","godot","--script","tests/test_their_island.gd"],dict(os.environ,HABITAT_DATA_DIR=directory))
for script in ["test_overnight_player_standard_home.gd","test_overnight_player_standard_moon.gd","test_overnight_player_showcase_home.gd","test_overnight_player_showcase_moon.gd"]:
    with temporary_directory(prefix="youqi-test-") as directory:
        run([ENGINE,"--headless","--path","godot","--script","tests/"+script],dict(os.environ,HABITAT_DATA_DIR=directory))

with temporary_directory(prefix="youqi-house-appearance-") as directory:
    run([ENGINE,"--headless","--path","godot","--script","tests/test_house_appearance.gd"],dict(os.environ,HABITAT_DATA_DIR=directory))
if "test_bbq_state_matrix.gd" in args.only:
    with temporary_directory(prefix="youqi-bbq-matrix-") as directory:
        run([ENGINE,"--headless","--path","godot","--script","tests/test_bbq_state_matrix.gd"],dict(os.environ,HABITAT_DATA_DIR=directory))
if "capture_cat_lively_natural.gd" in args.only:
    with temporary_directory(prefix="youqi-cat-life-") as directory:
        run([ENGINE,"--path","godot","--script","tests/capture_cat_lively_natural.gd"],dict(os.environ,HABITAT_DATA_DIR=directory))
if "capture_cat_contact.gd" in args.only:
    with temporary_directory(prefix="youqi-cat-input-") as directory:
        run([ENGINE,"--path","godot","--script","tests/capture_cat_contact.gd"],dict(os.environ,HABITAT_DATA_DIR=directory))
if "capture_house_personal.gd" in args.only:
    with temporary_directory(prefix="youqi-house-input-") as directory:
        run([ENGINE,"--path","godot","--script","tests/capture_house_personal.gd"],dict(os.environ,HABITAT_DATA_DIR=directory))
with temporary_directory(prefix="youqi-outdoor-") as directory:
    run([ENGINE,"--headless","--path","godot","--script","tests/test_outdoor_building.gd"],dict(os.environ,HABITAT_DATA_DIR=directory))
with temporary_directory(prefix="youqi-outdoor-input-") as directory:
    run([ENGINE,"--headless","--path","godot","--script","tests/test_outdoor_input.gd"],dict(os.environ,HABITAT_DATA_DIR=directory))
with temporary_directory(prefix="youqi-redraw-art-") as directory:
    run([ENGINE,"--headless","--path","godot","--script","tests/test_redraw_art.gd"],dict(os.environ,HABITAT_DATA_DIR=directory))
if "capture_redraw_sheet.gd" in args.only:
    with temporary_directory(prefix="youqi-redraw-sheet-") as directory:
        run([ENGINE,"--path","godot","--script","tests/capture_redraw_sheet.gd"],dict(os.environ,HABITAT_DATA_DIR=directory))
if "capture_cat_redraw_gameplay.gd" in args.only:
    with temporary_directory(prefix="youqi-redraw-gameplay-") as directory:
        run([ENGINE,"--path","godot","--script","tests/capture_cat_redraw_gameplay.gd"],dict(os.environ,HABITAT_DATA_DIR=directory))
suite_started = time.monotonic()
results = [None] * len(pending)
if args.resume:
    completed_records = json.loads(previous_path.read_text())
    for index,(command,environment) in enumerate(pending):
        coverage = [int(environment['HABITAT_COVERAGE_START']),int(environment['HABITAT_COVERAGE_END'])] if environment and 'HABITAT_COVERAGE_START' in environment else None
        matches = [record for record in completed_records if identity(record['command'])==identity(command) and record.get('coverage_range')==coverage]
        if matches:results[index]=matches[-1]
    print(f"Resuming unchanged source: keeping {sum(record is not None for record in results)} completed checks; jobs={jobs}",flush=True)
def completed(index, outcome):
    record, output = outcome
    results[index] = record
    print(f"[{sum(r is not None for r in results)}/{len(pending)}] {record['command'][-1]}: {'PASS' if record['passed'] else 'FAIL'} ({record['seconds']}s)", flush=True)
    if not record['passed'] or os.environ.get('HABITAT_TEST_VERBOSE') == '1': print(output, flush=True)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(json.dumps([r for r in results if r is not None], ensure_ascii=False, indent=2) + '\n')

try:
    # Import updates a shared .godot cache. Python bridges can own servers and
    # repository evidence; moon_map writes fixed B-distances.json. Keep these
    # exclusive, with no overlap with the parallel engine group.
    # Previous long checks contend for the same renderer/pathfinding resources.
    # Give measured >=40s checks exclusive execution; the 1800s command-coverage
    # batches keep their original bounded parallelism. No test deadline changes.
    def needs_exclusive(c):
        measured_heavy = historical_weights.get(identity(c), 0) >= 40 and Path(c[-1]).name != 'probe_one_line_execution.gd'
        return ('--import' in c or c[0] != ENGINE or 'tests/test_moon_map.gd' in c
                or measured_heavy or Path(c[-1]).name in {'test_brain_30min.gd','test_brain_input.gd','test_steward_director_long.gd','test_one_line_follow_input.gd','test_resident_intentions.gd','test_follow_play_input.gd','test_local_life_15d.gd','test_home_v3_simulation.gd','test_companion_return.gd','test_intention_catalog.gd','test_camp_click_approach.gd'}
                or Path(c[-1]).name.startswith('test_overnight_player_'))
    exclusive = [i for i,(c,_) in enumerate(pending) if results[i] is None and needs_exclusive(c)]
    imports = [i for i in exclusive if '--import' in pending[i][0]]
    serial = [i for i in exclusive if i not in imports]
    parallel = [i for i in range(len(pending)) if i not in exclusive and results[i] is None]
    for i in imports: completed(i, execute(pending[i]))
    if any(not results[i]['passed'] for i in imports):
        raise SystemExit("Godot import failed; checks were not started")
    # Start expensive simulations first using the previous report's timings.
    parallel.sort(key=lambda i: weights.get(identity(pending[i][0]), 0), reverse=True)
    # The slow read bridge also starts early, inside its exclusive group.
    for i in sorted(serial, key=lambda i: weights.get(identity(pending[i][0]), 0), reverse=True):
        completed(i, execute(pending[i]))
    with ThreadPoolExecutor(max_workers=jobs) as pool:
        futures = {pool.submit(execute, pending[i]): i for i in parallel}
        for future in as_completed(futures): completed(futures[future], future.result())
finally:
    stack.close()
failed = [entry for entry in results if entry is not None and not entry['passed']]
print(f"Complete suite: {len(results)} commands, {len(results)-len(failed)} passed, {len(failed)} failed; {time.monotonic()-suite_started:.1f}s; jobs={jobs}", flush=True)
for entry in failed: print('FAILED:', ' '.join(entry['command']), flush=True)
raise SystemExit(1 if failed else 0)

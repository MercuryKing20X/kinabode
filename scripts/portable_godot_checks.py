#!/usr/bin/env python3
"""Portable isolated Godot test entry point (also used by test-godot.ps1).

Runs chosen Godot scripts directly, without POSIX wrappers or symlinks. The
complete mixed Python/Godot suite remains scripts/test-godot.sh on POSIX.
"""
import argparse
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import uuid
from godot_runtime import godot_executable
from deterministic_godot import materialize

ROOT = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--script', action='append', default=[])
a = p.parse_args()
scripts = a.script or ['test_foundation.gd', 'test_slice.gd', 'test_work_orders.gd', 'test_farms.gd', 'test_barbecue_v4.gd']
for script in scripts:
    if Path(script).name != script or not (ROOT / 'godot/tests' / script).is_file():
        p.error('Unknown test basename: ' + script)
engine = godot_executable()
failed = []
with tempfile.TemporaryDirectory(prefix='youqi-test-portable-') as directory:
    runtime = Path(directory)
    project = runtime / 'godot'
    shutil.copytree(ROOT / 'godot', project, ignore=shutil.ignore_patterns('.godot', '*.tmp'))
    deterministic = os.environ.get('HABITAT_DETERMINISTIC_TESTS', '1')
    if deterministic == '1':
        print('TEST_ENVIRONMENT ' + str(materialize(ROOT / 'godot', project)), flush=True)
    # About documents are outside res:// by design.
    (runtime / 'docs').mkdir()
    for source in (ROOT / 'docs').glob('about*.md'):
        shutil.copy2(source, runtime / 'docs' / source.name)
    for script in ['IMPORT', *scripts]:
        name = 'youqi-test-portable-' + uuid.uuid4().hex
        config = (ROOT / 'godot/project.godot').read_text(encoding='utf-8')
        config = config.replace('[application]', '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="' + name + '"')
        (project / 'project.godot').write_text(config, encoding='utf-8')
        data = runtime / name
        data.mkdir()
        env = dict(os.environ, HABITAT_DATA_DIR=str(data), HABITAT_TEST_SUITE='1', HABITAT_DETERMINISTIC_TESTS=deterministic, HABITAT_TEST_SEED=os.environ.get('HABITAT_TEST_SEED','1027'), HABITAT_LIVE_TEST='0', HABITAT_OPENING='legacy', HABITAT_CODEX='habitat-offline-model-disabled')
        for key in ['HTTP_PROXY', 'HTTPS_PROXY', 'ALL_PROXY', 'http_proxy', 'https_proxy', 'all_proxy']:
            env[key] = 'http://127.0.0.1:1'
        env['NO_PROXY'] = env['no_proxy'] = '127.0.0.1,localhost,::1'
        command = [engine, '--headless', '--audio-driver', 'Dummy', '--rendering-method', 'gl_compatibility', '--rendering-driver', 'opengl3', '--log-file', str(data / 'engine.log'), '--path', str(project)]
        command += ['--editor', '--import', '--quit'] if script == 'IMPORT' else ['--script', 'tests/' + script]
        try:
            result = subprocess.run(command, env=env, capture_output=True, text=True, encoding='utf-8', errors='replace', timeout=300)
            output = result.stdout + result.stderr
            passed = result.returncode == 0 and 'SCRIPT ERROR:' not in output and '\nERROR:' not in output
            print(script + ': ' + ('PASS' if passed else 'FAIL'), flush=True)
            if not passed:
                print(output)
                failed.append(script)
        except subprocess.TimeoutExpired:
            print(script + ': TIMEOUT')
            failed.append(script)
        finally:
            # Only this test's random custom user directory is ever removed.
            roots = [Path.home() / 'Library/Application Support', Path(os.environ.get('APPDATA', runtime)), Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share'))]
            for root in roots:
                shutil.rmtree(root / name, ignore_errors=True)
        if script == 'IMPORT' and failed:
            break
print(str(len(failed)) + ' failed')
raise SystemExit(bool(failed))

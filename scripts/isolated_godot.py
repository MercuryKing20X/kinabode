#!/usr/bin/env python3
"""Run a Godot probe with private user://, logs and HABITAT_DATA_DIR."""
import os
from pathlib import Path
from godot_runtime import godot_executable
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='youqi-probe-') as directory:
    base = Path(directory)
    project = base / 'godot'
    project.mkdir()
    (base / 'scripts').symlink_to(ROOT / 'scripts', target_is_directory=True)
    for source in (ROOT / 'godot').iterdir():
        if source.name != 'project.godot':
            (project / source.name).symlink_to(source, target_is_directory=source.is_dir())
    config = (ROOT / 'godot/project.godot').read_text().replace('[application]', '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="'+base.name+'"')
    (project / 'project.godot').write_text(config)
    env = dict(os.environ)
    env.setdefault('HABITAT_DATA_DIR', str(base / 'data'))
    if 'youqi-' not in env['HABITAT_DATA_DIR']:
        raise SystemExit('Probe data directory must contain youqi-')
    Path(env['HABITAT_DATA_DIR']).mkdir(parents=True, exist_ok=True)
    arguments = sys.argv[1:]
    if '--path' in arguments:
        index = arguments.index('--path')
        del arguments[index:index+2]
    command = [godot_executable(), '--audio-driver','Dummy','--log-file',str(base/'engine.log'),'--path',str(project),*arguments]
    try:
        import signal
        child = subprocess.Popen(command, env=env)
        def terminate(signum, frame):
            child.terminate()
        signal.signal(signal.SIGTERM, terminate)
        result = child.wait()
    finally:
        import shutil
        shutil.rmtree(Path.home()/'Library/Application Support'/base.name, ignore_errors=True)
    raise SystemExit(result)

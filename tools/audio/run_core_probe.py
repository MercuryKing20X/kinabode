"""CoreAudio probe in a private Godot project and temporary game data directory."""
import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
ENGINE = '/Applications/Godot.app/Contents/MacOS/Godot'
EVIDENCE = ROOT / 'production/evidence/sound-v2'
parser = argparse.ArgumentParser()
parser.add_argument('--all-events', action='store_true')
args = parser.parse_args()
prefix = 'core-events' if args.all_events else 'core-audio'

with tempfile.TemporaryDirectory(prefix='youqi-test-sound-v2-') as tmp:
    runtime = Path(tmp)
    project = runtime / 'godot'
    project.mkdir()
    for source in (ROOT / 'godot').iterdir():
        if source.name != 'project.godot':
            (project / source.name).symlink_to(source, target_is_directory=source.is_dir())
    private_name = runtime.name
    config = (ROOT / 'godot/project.godot').read_text()
    config = config.replace('[application]', '[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="' + private_name + '"')
    (project / 'project.godot').write_text(config)
    private_user = Path.home() / 'Library/Application Support' / private_name
    trace = runtime / 'core-audio-events.jsonl'
    env = dict(os.environ, HABITAT_DATA_DIR=str(runtime), HABITAT_OPENING='standard',
               HABITAT_AUDIO_TRACE=str(trace))
    command = [ENGINE, '--audio-driver', 'CoreAudio', '--log-file', str(runtime / 'engine.log'),
               '--path', str(project), '--script', 'res://tests/audio_core_events_v2.gd' if args.all_events else 'res://tests/audio_core_probe_v2.gd']
    try:
        result = subprocess.run(command, cwd=ROOT, env=env, capture_output=True, text=True, timeout=90)
        output = result.stdout + result.stderr
        (EVIDENCE / (prefix + '-probe.log')).write_text(output)
        rows = []
        if trace.exists():
            rows = [json.loads(line) for line in trace.read_text().splitlines()]
            shutil.copyfile(trace, EVIDENCE / (prefix + '-events.jsonl'))
        starts = [r for r in rows if r.get('action') == 'native_start' and r.get('key', '').startswith('core-event:' if args.all_events else 'sound-test:')]
        expected = sorted(json.loads((ROOT / 'godot/content/audio/sounds.json').read_text())['events']) if args.all_events else ['voice.soft','step.grass','ambience.fire']
        ok = result.returncode == 0 and 'SCRIPT ERROR:' not in output and '\nERROR:' not in output and [row['event'] for row in starts] == expected
        summary = {'driver': 'CoreAudio', 'temporary_data': True, 'actual_mouse': False,
                   'exit_code': result.returncode, 'native_starts': starts, 'pass': ok,
                   'notes': ('Programmatic event starts check real driver dispatch; they do not replace player mouse acceptance or system-loopback recording.' if args.all_events else 'Programmatic button action checks real driver dispatch; it does not replace player mouse acceptance or system-loopback recording.')}
        (EVIDENCE / (prefix + '-probe.json')).write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n')
        print(json.dumps(summary, ensure_ascii=False, indent=2))
        if not ok:
            raise SystemExit(1)
    finally:
        if private_user.name == private_name and private_name.startswith('youqi-test-sound-v2-'):
            shutil.rmtree(private_user, ignore_errors=True)

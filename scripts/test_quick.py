#!/usr/bin/env python3
"""Small portable offline checks. Every Godot process uses Dummy and private data."""
from pathlib import Path
import subprocess,sys
root=Path(__file__).resolve().parents[1]
command=[sys.executable,str(root/'scripts/portable_godot_checks.py')]
for script in ['test_foundation.gd','test_slice.gd','test_work_orders.gd','test_farms.gd','test_barbecue_v4.gd','test_audio_music.gd']:
    command += ['--script',script]
raise SystemExit(subprocess.call(command,cwd=root))

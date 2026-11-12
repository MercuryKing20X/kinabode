"""Isolate viewport capture from all player data and normal user:// logs."""
import os, shutil, subprocess, tempfile
from pathlib import Path
from godot_runtime import godot_executable
ROOT=Path(__file__).resolve().parents[1]
out=ROOT/'production/evidence/2026-11-01-黑暗岛'/os.environ.get('MOTION_CASE','motion-before')
out.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='youqi-test-motion-1101-') as directory:
 runtime=Path(directory);project=runtime/'godot';project.mkdir()
 for src in (ROOT/'godot').iterdir():
  if src.name!='project.godot':(project/src.name).symlink_to(src,target_is_directory=src.is_dir())
 config=(ROOT/'godot/project.godot').read_text().replace('[application]','[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="'+runtime.name+'"')
 (project/'project.godot').write_text(config)
 env=dict(os.environ,HABITAT_DATA_DIR=str(runtime/'data'),HABITAT_MOTION_EVIDENCE=str(out),HABITAT_OPENING='legacy')
 try:
  selected=os.environ.get('MOTION_SCRIPT','capture_motion_camera_1101.gd')
  status=subprocess.call([godot_executable(),'--path',str(project),'--audio-driver','Dummy','--log-file',str(out/'engine.log'),'--script','res://tests/'+selected],env=env)
 finally:shutil.rmtree(Path.home()/'Library/Application Support'/runtime.name,ignore_errors=True)
 raise SystemExit(status)

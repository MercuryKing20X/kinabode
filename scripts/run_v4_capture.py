"""Launch only this round's viewport/observer scenes in a disposable project/data dir."""
import argparse,os,shutil,subprocess,tempfile
from pathlib import Path
from godot_runtime import godot_executable
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('--script',choices=['capture_run_v3.gd','observe_run_v3.gd','capture_run_v4.gd','observe_run_v4.gd'],default='capture_run_v3.gd');p.add_argument('--import-only',action='store_true');p.add_argument('--case',default='program');p.add_argument('--opening',choices=['standard','showcase'],default='showcase');a=p.parse_args()
out=ROOT/'production/evidence/run-v4'/a.case;out.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='youqi-test-run-v3-') as directory:
 runtime=Path(directory);workspace=runtime/'workspace';workspace.mkdir()
 for src in ROOT.iterdir():
  if src.name!='godot':(workspace/src.name).symlink_to(src,target_is_directory=src.is_dir())
 project=workspace/'godot';project.mkdir()
 for src in (ROOT/'godot').iterdir():
  if src.name!='project.godot':(project/src.name).symlink_to(src,target_is_directory=src.is_dir())
 config=(ROOT/'godot/project.godot').read_text().replace('[application]','[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="'+runtime.name+'"')
 (project/'project.godot').write_text(config)
 env=dict(os.environ,HABITAT_DATA_DIR=str(runtime/'data'),HABITAT_STAGE2_EVIDENCE=str(out),HABITAT_RUN_CASE=a.case,HABITAT_OPENING='legacy' if a.opening=='showcase' else 'standard')
 try:
  imported=subprocess.call([godot_executable(),'--headless','--editor','--import','--path',str(project),'--audio-driver','Dummy','--log-file',str(out/'import.log')],env=env,stdout=subprocess.DEVNULL,stderr=subprocess.STDOUT)
  if imported:raise SystemExit(imported)
  if a.import_only:raise SystemExit(0)
  status=subprocess.call([godot_executable(),'--path',str(project),'--audio-driver','Dummy','--log-file',str(out/'engine.log'),'--script','res://tests/'+a.script,'--','--opening='+a.opening],env=env)
 finally:shutil.rmtree(Path.home()/'Library/Application Support'/runtime.name,ignore_errors=True)
 raise SystemExit(status)

"""Isolated current-round Godot imports and real viewport/input evidence."""
import argparse,os,shutil,subprocess,tempfile
from pathlib import Path
from godot_runtime import godot_executable
ROOT=Path(__file__).resolve().parents[1]
p=argparse.ArgumentParser();p.add_argument('script',nargs='?');p.add_argument('--headless',action='store_true');p.add_argument('--import-only',action='store_true');p.add_argument('--case',default='probe');p.add_argument('--resume-data',type=Path);p.add_argument('--opening',default='showcase');a=p.parse_args()
out=ROOT/'production/evidence/2026-11-01-黑暗岛'/a.case;out.mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='youqi-test-dark-') as directory:
 runtime=Path(directory);workspace=runtime/'workspace';workspace.mkdir()
 for src in ROOT.iterdir():
  if src.name!='godot':(workspace/src.name).symlink_to(src,target_is_directory=src.is_dir())
 project=workspace/'godot';project.mkdir()
 for src in (ROOT/'godot').iterdir():
  if src.name!='project.godot':(project/src.name).symlink_to(src,target_is_directory=src.is_dir())
 config=(ROOT/'godot/project.godot').read_text().replace('[application]','[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="'+runtime.name+'"')
 (project/'project.godot').write_text(config)
 env=dict(os.environ,HABITAT_DATA_DIR=str(runtime/'data'),HABITAT_DARK_EVIDENCE=str(out),HABITAT_OPENING='legacy' if a.opening=='showcase' else 'standard')
 if a.resume_data:
  source=a.resume_data.resolve()
  if 'youqi-test-' not in str(source) or not source.is_dir():raise SystemExit('resume source must be an isolated youqi-test- directory')
  shutil.copytree(source,runtime/'data',dirs_exist_ok=True)
 common=[godot_executable(),'--path',str(project),'--audio-driver','Dummy','--log-file',str(out/'engine.log')]
 try:
  cmd=common+(['--headless','--editor','--import','--quit'] if a.import_only else (['--headless'] if a.headless else [])+['--script','res://tests/'+a.script])
  r=subprocess.run(cmd,env=env,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True,timeout=900)
  (out/'output.log').write_text(r.stdout);print(r.stdout[-9000:]);raise SystemExit(r.returncode or (1 if 'SCRIPT ERROR:' in r.stdout else 0))
 finally:shutil.rmtree(Path.home()/'Library/Application Support'/runtime.name,ignore_errors=True)

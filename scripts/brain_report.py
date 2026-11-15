#!/usr/bin/env python3
"""Run an isolated, reproducible 30-minute source/editor simulation. No player save or model call."""
import argparse,json,os,shutil,subprocess,tempfile
from pathlib import Path
from deterministic_godot import materialize
from godot_runtime import godot_executable
ROOT=Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('--output',type=Path);p.add_argument('--visible',action='store_true');p.add_argument('--speed',type=float,default=0,help='0: run as fast as possible; 1: real time; 60: sixty times faster');a=p.parse_args()
 if a.speed<0:p.error('--speed must be zero or positive')
 run=Path(tempfile.mkdtemp(prefix='youqi-test-brain-report-'));project=run/'godot';data=run/'data';data.mkdir()
 shutil.copytree(ROOT/'godot',project,ignore=shutil.ignore_patterns('.godot','*.tmp'));materialize(ROOT/'godot',project)
 config=(project/'project.godot').read_text().replace('[application]','[application]\nconfig/use_custom_user_dir=true\nconfig/custom_user_dir_name="'+run.name+'"')
 (project/'project.godot').write_text(config+'\n[threading]\nworker_pool/max_threads=2\n')
 env=dict(os.environ,HABITAT_DATA_DIR=str(data),HABITAT_BRAIN_REPORT_ISOLATED='1',HABITAT_BRAIN_REPORT_SPEED=str(a.speed),HABITAT_TEST_SUITE='1',HABITAT_DETERMINISTIC_TESTS='1',HABITAT_TEST_SEED=str(json.loads((ROOT/'godot/content/brain.json').read_text())['developer_report']['world_seed']),HABITAT_LIVE_TEST='0',HABITAT_CODEX='habitat-offline-model-disabled')
 for key in ['HTTP_PROXY','HTTPS_PROXY','ALL_PROXY','http_proxy','https_proxy','all_proxy']:env[key]='http://127.0.0.1:1'
 cmd=[godot_executable(),'--audio-driver','Dummy','--rendering-method','gl_compatibility','--rendering-driver','opengl3','--path',str(project)]
 if not a.visible:cmd+=['--headless']
 try:
  subprocess.run(cmd+['--editor','--import','--quit'],env=env,check=True,timeout=300)
  subprocess.run(cmd+['--script','tools/brain_report_runner.gd'],env=env,check=True,timeout=max(600,int(1800/a.speed)+300) if a.speed>0 else 600)
  output=data/'brain-reports'
  if a.output:
   a.output.mkdir(parents=True,exist_ok=True)
   shutil.copytree(output,a.output,dirs_exist_ok=True)
   output=a.output
  print('Report:',output)
 finally:shutil.rmtree(Path.home()/'Library/Application Support'/run.name,ignore_errors=True)
if __name__=='__main__':main()

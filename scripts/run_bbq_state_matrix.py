"""104 disposable state-fixture UI checks; prelude is NOT an input-only playthrough.
Original test runner supplies Dummy audio and isolated youqi directories.
"""
import os,json,subprocess,time
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor,as_completed
root=Path(__file__).resolve().parents[1];out=root/'production/evidence/2026-11-04-家园岛并图与房子重画/bbq-matrix';out.mkdir(exist_ok=True)
states=['idle','return_visit','storage_delivery','chess','after_chess','bridge','other_island','very_hungry_follow','full','indoors','fishing','farm_command','just_loaded']
cases=[(o,s,t) for o in ['standard','showcase'] for s in ['home.barbecue','moon.barbecue','homelands.barbecue','dark.barbecue'] for t in states]
def run(c):
 o,s,t=c;key=f'{o}-{s}-{t}';env=dict(os.environ,BBQ_MATRIX_OPENING=o,BBQ_MATRIX_STATION=s,BBQ_MATRIX_STATE=t,BBQ_MATRIX_OUTPUT=str(out),HABITAT_SUITE_REPORT=str(out/(key+'-check.json')))
 started=time.monotonic();p=subprocess.run(['./scripts/test-godot.sh','--only','test_bbq_state_matrix.gd'],cwd=root,env=env,capture_output=True,text=True)

 if p.returncode:(out/(key+'.log')).write_text(p.stdout+p.stderr)
 elif (out/(key+'.log')).exists():(out/(key+'.log')).unlink()
 return {'opening':o,'station':s,'state':t,'code':p.returncode,'seconds':round(time.monotonic()-started,3)}
results=[]
with ThreadPoolExecutor(max_workers=2) as pool:
 for f in as_completed([pool.submit(run,c) for c in cases]):
  r=f.result();results.append(r);(out/'run-summary.json').write_text(json.dumps(results,indent=2));print(r,flush=True)

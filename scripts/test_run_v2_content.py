"""Strict optional run presentation fields; original gait remains valid."""
import sys,json,copy,math
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'godot/tools'))
from intelligence_catalog import validate_gait
fields={'run_bounce':16,'run_sway':2,'run_lean':.3,'run_stretch':.12,'run_dust':3,'run_frames_per_step':2}
gait=json.loads(Path('godot/content/gaits.json').read_text())['human']
legacy={k:v for k,v in gait.items() if k not in fields};validate_gait(legacy)
count=1
for field,maximum in fields.items():
 for value in [True,False,'1',None,-1,maximum+1,float('inf'),float('nan')]:
  candidate=copy.deepcopy(gait);candidate[field]=value
  try:validate_gait(candidate)
  except (ValueError,TypeError):pass
  else:raise AssertionError((field,value))
  count+=1
validate_gait(gait);print(f'Run optional fields Python: {count+1} checks')

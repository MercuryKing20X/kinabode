"""Full-suite gate for the current island stage; disposable data and no live inference."""
import datetime,json,os,re,subprocess,sys,tempfile
from pathlib import Path
root=Path(__file__).resolve().parents[1];out=root/'production/evidence/island-v3-stage2';stage=sys.argv[1]
start=datetime.datetime.now(datetime.timezone.utc)
with tempfile.TemporaryDirectory(prefix='youqi-test-v3-'+stage.lower()+'-suite-') as data:
 with (out/(stage+'-suite.log')).open('w') as log:
  result=subprocess.run(['./scripts/test-godot.sh'],cwd=root,env=dict(os.environ,HABITAT_DATA_DIR=data,HABITAT_LIVE_TEST='0',PYTHONUNBUFFERED='1'),stdout=log,stderr=subprocess.STDOUT)
text=(out/(stage+'-suite.log')).read_text();report=dict(exit_code=result.returncode,started_utc=start.isoformat(),finished_utc=datetime.datetime.now(datetime.timezone.utc).isoformat(),godot_checks=sum(map(int,re.findall(r'(\d+) checks',text)))+sum(map(int,re.findall(r'Interior checks: (\d+)',text))),python_tests=sum(map(int,re.findall(r'Ran (\d+) tests?',text))),real_model_calls=0)
(out/(stage+'-result.json')).write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report));sys.exit(result.returncode)

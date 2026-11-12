"""Run one isolated full acceptance stage and retain timestamps/evidence, never a live model."""
import datetime,hashlib,json,os,re,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1];OUT=ROOT/'production/evidence/island-v3-stage1b';stage=sys.argv[1];status_path=OUT/f'{stage}-result.json'
old=json.loads(status_path.read_text()) if status_path.exists() else {};start=datetime.datetime.now(datetime.timezone.utc)
with tempfile.TemporaryDirectory(prefix='youqi-test-island-art-suite-') as temp:
 with (OUT/f'{stage}-suite.log').open('w') as log:
  result=subprocess.run(['./scripts/test-godot.sh'],cwd=ROOT,env=dict(os.environ,HABITAT_DATA_DIR=temp,HABITAT_LIVE_TEST='0',PYTHONUNBUFFERED='1'),stdout=log,stderr=subprocess.STDOUT)
end=datetime.datetime.now(datetime.timezone.utc);text=(OUT/f'{stage}-suite.log').read_text()
status={'stage':stage,'exit_code':result.returncode,'started_utc':start.isoformat(),'finished_utc':end.isoformat(),'first_failure_utc':old.get('first_failure_utc') or (end.isoformat() if result.returncode else None),'godot_checks':sum(map(int,re.findall(r'(\d+) checks',text)))+sum(map(int,re.findall(r'Interior checks: (\d+)',text))),'python_tests':sum(map(int,re.findall(r'Ran (\d+) tests?',text)))}
status_path.write_text(json.dumps(status,indent=2)+'\n');print(json.dumps(status));sys.exit(result.returncode)

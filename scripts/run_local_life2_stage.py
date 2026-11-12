"""Run the authorized default suite with a temporary root and persist failure time."""
import datetime,json,os,subprocess,sys,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
stage=int(sys.argv[1]);out=ROOT/'production/evidence/local-life-2-2026-10-27'
status_path=out/f'stage{stage}-result.json'
old=json.loads(status_path.read_text()) if status_path.exists() else {}
with tempfile.TemporaryDirectory(prefix='youqi-test-local-life-suite-') as directory:
    with (out/f'stage{stage}-suite.log').open('w') as log:
        result=subprocess.run(['./scripts/test-godot.sh'],cwd=ROOT,env=dict(os.environ,HABITAT_DATA_DIR=directory,PYTHONUNBUFFERED="1",HABITAT_LIVE_TEST="0"),stdout=log,stderr=subprocess.STDOUT)
now=datetime.datetime.now(datetime.timezone.utc).isoformat()
status={'stage':stage,'exit_code':result.returncode,'finished_utc':now,'first_failure_utc':old.get('first_failure_utc') or (now if result.returncode else None)}
status_path.write_text(json.dumps(status,indent=2)+'\n');print(json.dumps(status));sys.exit(result.returncode)

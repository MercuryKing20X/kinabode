import tempfile,pathlib,subprocess,os,time,json,sys
with tempfile.TemporaryDirectory(prefix='youqi-heartbeat-') as d:
 p=pathlib.Path(d)
 for name in ['inbox','processing','outbox']:(p/name).mkdir()
 helper=p/'slow.py';helper.write_text('import time\ntime.sleep(45)\n')
 child=subprocess.Popen([sys.executable,'godot/bridge/file_transport.py','--session-dir',d,'--data-dir',d,'--nonce','test','--parent-pid',str(os.getpid()),'--helper',str(helper)],stdout=subprocess.DEVNULL,stderr=subprocess.PIPE)
 try:
  start=time.monotonic();count=0
  while time.monotonic()-start<40:
   (p/'client-heartbeat.json').write_text('{}');time.sleep(1)
   if time.monotonic()-start>2:
    assert child.poll() is None
    assert time.time()-(p/'bridge-heartbeat.json').stat().st_mtime<3
    count+=1
  print('PASS: 40 seconds blocked helper; heartbeat samples',count)
 finally:child.terminate();child.communicate(timeout=10)

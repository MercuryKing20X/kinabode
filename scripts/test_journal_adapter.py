#!/usr/bin/env python3
"""Real temporary engine, exact external v2 binding and asynchronous catch; no inference."""
import json,os,subprocess,tempfile,time,unittest
from pathlib import Path
from habitat_godot import Reader
ROOT=Path(__file__).resolve().parents[1]
ENGINE=os.environ.get('HABITAT_GODOT',str(ROOT/'scripts/isolated_godot.py'))
class JournalAdapter(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.temp=tempfile.TemporaryDirectory(prefix='youqi-test-journal-api-');cls.log=open(Path(cls.temp.name)/'engine.log','w+')
  cls.process=subprocess.Popen([ENGINE,'--headless','--path',str(ROOT/'godot'),'--script','tests/journal_adapter_host.gd'],env=dict(os.environ,HABITAT_DATA_DIR=cls.temp.name),stdout=cls.log,stderr=cls.log)
  cls.addClassCleanup(cls.cleanup);cls.reader=Reader(cls.temp.name,timeout=3)
  deadline=time.monotonic()+20
  while time.monotonic()<deadline:
   if cls.process.poll() is not None:cls.log.seek(0);raise RuntimeError(cls.log.read()[-4000:])
   try:
    packet=cls.reader.request('dialogue_poll',{}).get('pending',{})
    if packet:cls.packet=packet;break
   except Exception:pass
   time.sleep(.05)
  else:cls.log.seek(0);raise RuntimeError(cls.log.read()[-4000:])
 @classmethod
 def cleanup(cls):
  cls.process.terminate()
  try:cls.process.wait(timeout=5)
  except subprocess.TimeoutExpired:cls.process.kill();cls.process.wait(timeout=5)
  cls.log.close();cls.temp.cleanup()
 def call(self,action,args,identity):
  response=self.reader.handle({'id':9,'method':'tools/call','params':{'name':'game_action','arguments':{'action':action,'arguments':args,'dialogue':identity}}})
  return json.loads(response['result']['content'][0]['text'])
 def test_bound_read_during_real_fishing_and_release(self):
  identity={k:self.packet[k] for k in ('world_id','resident_id','scope','session','generation','request_id')}
  page=self.call('journal_read',{'limit':3},identity)
  self.assertTrue(page['ok']);self.assertEqual(page['self_actor_id'],'codex');self.assertEqual(page['catalog_total'],368);self.assertEqual(page['discovered'],0)
  self.assertFalse(self.call('journal_read',{'actor_id':'human'},identity)['ok'])
  self.assertFalse(self.call('journal_read',{},dict(identity,resident_id='human'))['ok'])
  self.assertFalse(self.call('journal_read',{},dict(identity,scope='group'))['ok'])
  accepted=self.call('fish',{},identity);self.assertTrue(accepted['ok']);self.assertEqual(accepted['status'],'accepted')
  read=self.call('journal_read',{'status':'caught'},identity)
  self.assertTrue(read['ok']);self.assertEqual(read['total'],0)
  self.assertEqual(self.reader.observe()['self']['job']['id'],accepted['job_id'])
  deadline=time.monotonic()+25
  while time.monotonic()<deadline:
   snap=self.reader.observe()
   if snap['fishing']['pending']:break
   time.sleep(.05)
  else:self.fail('actual fishing did not finish')
  caught=snap['fishing']['pending'][0]
  discovered=self.call('journal_read',{'status':'caught'},identity)
  self.assertEqual(discovered['total'],1);self.assertEqual(discovered['entries'][0]['first_catch']['fish_id'],caught['id'])
  self.assertFalse(self.call('journal_read',{'offset':3,'limit':3,'revision':page['revision']},identity)['ok'])
  fresh=self.call('journal_read',{'limit':3},identity)
  second=self.call('journal_read',{'offset':3,'limit':3,'revision':fresh['revision']},identity)
  self.assertTrue(second['ok']);self.assertEqual(second['offset'],3)
  self.assertTrue(self.call('release_fish',{'fish_id':caught['id']},identity)['ok'])
  remaining=self.call('journal_read',{'status':'caught'},identity)
  self.assertEqual(remaining['entries'],discovered['entries'])
  self.assertFalse(self.call('journal_read',{},dict(identity,request_id='stale'))['ok'])
if __name__=='__main__':unittest.main()

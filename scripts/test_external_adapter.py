#!/usr/bin/env python3
"""Real local MCP + Godot external adapter; text is explicit test data, no model calls."""
import json,os,subprocess,tempfile,time,unittest
from pathlib import Path
from habitat_godot import Reader
ROOT=Path(__file__).resolve().parents[1]
ENGINE=os.environ.get('HABITAT_GODOT',str(ROOT/'scripts/isolated_godot.py'))
class ExternalAdapter(unittest.TestCase):
 @classmethod
 def setUpClass(cls):
  cls.temp=tempfile.TemporaryDirectory(prefix='youqi-test-external-');cls.log=open(Path(cls.temp.name)/'engine.log','w+')
  cls.process=subprocess.Popen([ENGINE,'--headless','--time-scale','6','--path',str(ROOT/'godot'),'--script','tests/external_adapter_host.gd'],env=dict(os.environ,HABITAT_DATA_DIR=cls.temp.name),stdout=cls.log,stderr=cls.log)
  cls.addClassCleanup(cls.cleanup)
  cls.reader=Reader(cls.temp.name,timeout=3)
  deadline=time.monotonic()+12
  while time.monotonic()<deadline:
   if cls.process.poll() is not None:cls.log.seek(0);raise RuntimeError(cls.log.read()[:4000])
   try:
    packet=cls.reader.request('dialogue_poll',{})
    if packet.get('pending'):cls.packet=packet['pending'];break
   except Exception:pass
   time.sleep(.05)
  else:cls.log.seek(0);raise RuntimeError(cls.log.read()[:4000])
 @classmethod
 def cleanup(cls):
  cls.process.terminate()
  try:cls.process.wait(timeout=5)
  except subprocess.TimeoutExpired:cls.process.kill();cls.process.wait(timeout=5)
  cls.log.close();cls.temp.cleanup()
 def call(self,name,args):
  result=self.reader.handle({'id':5,'method':'tools/call','params':{'name':name,'arguments':args}})
  return json.loads(result['result']['content'][0]['text'])
 def test_real_external_roundtrip_and_stale_rejection(self):
  packet=self.packet
  self.assertIn('契约测试',packet['text']);self.assertEqual(packet['resident_id'],'codex')
  identity={key:packet[key] for key in ('world_id','resident_id','scope','session','generation','request_id')}
  self.assertTrue(self.call('game_actions',{})['dialogue_context_required'])
  self.assertEqual(self.call('game_action',{'action':'fish'})['error'],'dialogue_identity_required')
  result=self.call('game_action',{'action':'fish','dialogue':identity});self.assertTrue(result['ok'],result);self.assertEqual(result['status'],'accepted')
  deadline=time.monotonic()+25;pending=[]
  while time.monotonic()<deadline:
   snap=self.reader.observe();pending=snap['fishing']['pending']
   if pending:break
   time.sleep(.1)
  self.assertEqual(len(pending),1);fish=pending[0]
  result=self.call('game_action',{'action':'stock_fish','arguments':{'fish_id':fish['id'],'pen_id':snap['fishing']['pens'][0]['id']},'dialogue':identity})
  self.assertTrue(result['ok'],result)
  wrong=dict(identity,scope='group')
  self.assertFalse(self.call('game_action',{'action':'stop','dialogue':wrong})['ok'])
  reply=dict(identity,event_id='actual-test-response',event={'kind':'assistant','text':'外部MCP客户端验收回复；没有模型调用。'})
  self.assertTrue(self.call('dialogue_reply',reply)['ok']);self.assertFalse(self.call('dialogue_reply',reply)['ok'])
  self.assertTrue(self.call('dialogue_reply',dict(identity,event_id='complete-test',event={'kind':'complete'}))['ok'])
  self.assertFalse(self.call('game_action',{'action':'stop','dialogue':identity})['ok'])
  self.assertFalse(self.call('dialogue_reply',dict(reply,event_id='late-response'))['ok'])
if __name__=='__main__':unittest.main()

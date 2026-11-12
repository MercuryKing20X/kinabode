"""Owned mailbox fake-model replay for island_propose. No model process or inference."""
import json,sys,tempfile,time,unittest,uuid
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'godot/bridge'))
from companion import Companion
from action_contract import command
class IslandTransport(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory(prefix='youqi-island-transport-');self.addCleanup(self.temp.cleanup)
  self.events=[];self.calls=[];self.client=Companion(self.temp.name,self.events.append,self.calls.append)
  self.client.thread_id='11111111-1111-1111-1111-111111111111';self.client.ready=True
 def submit(self,value,token):
  key=uuid.uuid4().hex
  (self.client.actions_dir/'inbox'/(key+'.json')).write_text(json.dumps({'id':key,'tool':'game_action','expires':time.time()+15,'arguments':dict(value,turn_token=token)}))
  self.client.tick();return key
 def response(self,key):return json.loads((self.client.actions_dir/'outbox'/(key+'.json')).read_text())
 def test_bound_legal_and_revoked_turn(self):
  self.client.client({'kind':'chat','text':'Suggest a place','world':{'self_actor_id':'codex','self':{}}})
  token=self.client.action_token
  value={'action':'island_propose','arguments':{'template_id':'outdoor-chair','x':33,'y':226,'name':'Cloud Seat','reason':'An actual offered memory summary'}}
  key=self.submit(value,token)
  event=next(e for e in self.events if e.get('kind')=='action')
  self.assertEqual(event['command'],command(value))
  self.client.client({'kind':'tool_result','id':event['id'],'result':{'ok':True,'status':'proposed','proposal_id':'exact-host-card'}})
  response=self.response(key);self.assertEqual(response['proposal_id'],'exact-host-card');self.assertEqual(response['action_turn_token'],token)
  before=len(self.events);self.client.cancel('stop')
  stale=self.submit(value,token)
  self.assertEqual(self.response(stale)['error'],'stale_action_turn')
  self.assertFalse(any(e.get('kind')=='action' for e in self.events[before:]))
 def test_actor_override_never_reaches_engine(self):
  self.client.client({'kind':'chat','text':'Suggest','world':{'self_actor_id':'codex','self':{}}})
  before=len(self.events)
  value={'action':'island_propose','arguments':{'actor_id':'human','template_id':'outdoor-chair','x':33,'y':226,'name':'N','reason':'R'}}
  key=self.submit(value,self.client.action_token)
  self.assertFalse(self.response(key)['ok']);self.assertFalse(any(e.get('kind')=='action' for e in self.events[before:]))
if __name__=='__main__':unittest.main()

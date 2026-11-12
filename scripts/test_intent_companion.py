"""Offline intent driver isolation and protocol rotation checks. No model processes."""
import sys,tempfile,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'godot/bridge'))
from intent_companion import Companion
class Tests(unittest.TestCase):
 def test_single_reply_and_validation(self):
  with tempfile.TemporaryDirectory(prefix='youqi-intent-stub-') as d:
   events=[];c=Companion(d,events.append,lambda _:None)
   p=c.thread_params();self.assertNotIn('mcp_servers.youqi_actions',p['config'])
   c.emit_event({'kind':'assistant','text':'{"speech":"hi","intents":[]}'})
   c.emit_event({'kind':'assistant','text':'{"speech":"duplicate","intents":[]}'})
   self.assertEqual([e['kind'] for e in events],['intent_result'])
   c.intent_delivered=False;c.emit_event({'kind':'assistant','text':'{"speech":"bad","intents":[{"actor_id":"human"}]}'})
   self.assertEqual(events[-1]['kind'],'error')
 def test_five_structured_intents_and_boundaries(self):
  import json
  with tempfile.TemporaryDirectory(prefix='youqi-intent-five-') as d:
   events=[];c=Companion(d,events.append,lambda _:None)
   steps=[{'action':a} for a in ['wander','fish','light','roast','invite']]
   c.emit_event({'kind':'assistant','text':json.dumps({'speech':'ok','intents':steps})})
   self.assertEqual(events[-1]['intents'],steps)
   c.intent_delivered=False
   c.emit_event({'kind':'assistant','text':json.dumps({'speech':'bad','intents':steps+[{'action':'stop'}]})})
   self.assertEqual(events[-1]['kind'],'error')
   c.intent_delivered=False
   c.emit_event({'kind':'assistant','text':json.dumps({'speech':'bad','intents':[{'action':'fish','actor_id':'human'}]})})
   self.assertEqual(events[-1]['kind'],'error')
 def test_v2_resident_plan_keeps_actor_boundary(self):
  from action_contract import command
  steps=[{'action':'fish'},{'action':'roast'},{'action':'invite'}]
  self.assertEqual(command({'action':'resident_plan','arguments':{'steps':steps}}),{'intent':'resident_plan','steps':steps})
  with self.assertRaises(ValueError):command({'action':'resident_plan','arguments':{'steps':[{'action':'fish','actor_id':'human'}]}})
  with self.assertRaises(ValueError):command({'action':'resident_plan','arguments':{'steps':[{'action':'pool','guest_ids':['human']}]}})
 def test_rotation_binds_new_turn(self):
  with tempfile.TemporaryDirectory(prefix='youqi-intent-stub-') as d:
   calls=[];c=Companion(d,lambda _:None,calls.append);c.ready=True;c.rounds=8
   c.client({'kind':'chat','text':'hi','turn_key':'new-turn','world':{'intent_card':{}}})
   self.assertEqual(c.turn_key,'new-turn');self.assertEqual(calls[-1]['method'],'thread/start')
   self.assertEqual(c.queued_chat['turn_key'],'new-turn')
 def test_first_ready_turn_with_unknown_usage_does_not_crash(self):
  with tempfile.TemporaryDirectory(prefix='youqi-intent-first-') as d:
   calls=[];c=Companion(d,lambda _:None,calls.append);c.ready=True;c.thread_id='owned';c.turn_usage=None
   c.client({'kind':'chat','text':'hello','world':{},'turn_key':'first'})
   self.assertEqual(calls[-1]['method'],'turn/start')
   self.assertEqual(c.turn_token_limit,0)
 def test_rotation_renews_expired_handshake_deadline(self):
  with tempfile.TemporaryDirectory(prefix='youqi-intent-deadline-') as d:
   c=Companion(d,lambda _:None,lambda _:None);c.ready=True;c.rounds=6;c.boot_deadline=0
   c.client({'kind':'chat','text':'hello','turn_key':'rotated','world':{'intent_card':{}}})
   self.assertGreater(c.boot_deadline,c.now())
   self.assertFalse(c.closed)
 def test_loaded_input_history_rotates_before_send(self):
  import json
  from pathlib import Path
  with tempfile.TemporaryDirectory(prefix='youqi-intent-persisted-') as d:
   Path(d,'youqi-intent-thread-v1.json').write_text(json.dumps({'threadId':'old','rounds':1,'last_input_tokens':21000}))
   calls=[];c=Companion(d,lambda _:None,calls.append);c.ready=True
   c.client({'kind':'chat','text':'hello','turn_key':'new','world':{'intent_card':{}}})
   self.assertEqual(calls[-1]['method'],'thread/start')
   self.assertEqual(c.queued_chat['turn_key'],'new')
if __name__=='__main__':unittest.main()

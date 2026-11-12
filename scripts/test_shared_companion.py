import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'godot/bridge'))
from shared_companion import SharedCompanion, OWNER

THREAD='11111111-2222-3333-4444-555555555555'


class SharedCompanionTests(unittest.TestCase):
    def setUp(self):
        self.directory=tempfile.TemporaryDirectory(prefix='youqi-shared-test-')
        self.addCleanup(self.directory.cleanup)
        self.events=[];self.calls=[]
        self.client=SharedCompanion(self.directory.name,self.events.append,self.calls.append)
        self.client.thread_id=THREAD;self.client.ready=True

    def start_turn(self):
        self.client.client({'kind':'chat','text':'你好','world':{'self':{'id':'codex','name':'小白'}}})
        self.client.server({'method':'turn/started','params':{'threadId':THREAD,'turn':{'id':'turn-1'}}})

    def test_idle_never_starts_inference(self):
        for _ in range(100):self.client.tick()
        self.assertEqual(self.calls,[])

    def test_private_session_and_credentials_not_copied(self):
        self.client.save_thread()
        data=json.loads(self.client.state_path.read_text())
        self.assertEqual(data,{'owner':OWNER,'threadId':THREAD})
        self.assertEqual(self.client.state_path.name,'shared-test-thread.json')
        status=json.loads((Path(self.directory.name)/'shared-status.json').read_text())
        self.assertEqual(status['messages_submitted'],0)

    def test_resume_failure_never_creates_replacement(self):
        self.client.open_thread()
        request=self.calls[-1]
        self.client.server({'id':request['id'],'error':{'message':'not found'}})
        self.assertTrue(self.client.closed)
        self.assertFalse(any(x.get('method')=='thread/start' for x in self.calls))

    def test_developer_thread_record_is_rejected(self):
        path=Path(self.directory.name)/'shared-test-thread.json'
        path.write_text(json.dumps({'owner':OWNER,'threadId':THREAD}))
        with patch.dict(os.environ,{'CODEX_THREAD_ID':THREAD}):
            client=SharedCompanion(self.directory.name,self.events.append,self.calls.append)
            client.start()
        self.assertTrue(client.closed);self.assertFalse(self.calls)

    def test_bad_binding_preserved_and_not_replaced(self):
        path=Path(self.directory.name)/'shared-test-thread.json';path.write_text('broken')
        client=SharedCompanion(self.directory.name,self.events.append,self.calls.append)
        client.start()
        self.assertTrue(client.closed);self.assertEqual(path.read_text(),'broken');self.assertFalse(self.calls)

    def test_chat_context_is_small_and_identity_bound(self):
        self.client.client({'kind':'chat','text':'聊聊','world':{'world_id':'island','self_actor_id':'codex','self':{'id':'codex','name':'小白','job':{}},'objects':[{'pixels':'x'*90000}],'farming':{'secret':'large'}}})
        prompt=self.calls[-1]['params']['input'][0]['text']
        self.assertLess(len(prompt),1000);self.assertIn('小白',prompt);self.assertNotIn('pixels',prompt)
        self.assertEqual(self.client.messages_submitted,1)

    def test_group_context_survives_compact_bridge(self):
        dialogue={'channel_id':'group:all','mode':'group','message_id':'group-1','sender_id':'human','recipient_ids':['codex','companion-2'],'recent_messages':[{'sender_id':'companion-2','text':'一起散步吧','kind':'message'}]}
        self.client.client({'kind':'chat','text':'出发','world':{'self_actor_id':'codex','self':{'id':'codex'},'dialogue':dialogue}})
        prompt=self.calls[-1]['params']['input'][0]['text']
        self.assertIn('group:all',prompt)
        self.assertIn('一起散步吧',prompt)
        self.assertIn('companion-2',prompt)

    def test_completed_turn_replay_does_not_finish_next_turn(self):
        self.start_turn()
        done={'method':'turn/completed','params':{'threadId':THREAD,'turn':{'id':'turn-1','status':'completed'}}}
        self.client.server(done)
        self.client.client({'kind':'chat','text':'第二轮','world':{}})
        count=len(self.events)
        self.client.server(done)
        self.assertTrue(self.client.active);self.assertEqual(len(self.events),count)

    def test_other_thread_does_not_speak_or_complete(self):
        self.start_turn();count=len(self.events)
        self.client.server({'method':'item/completed','params':{'threadId':'other','turnId':'turn-1','item':{'type':'agentMessage','id':'msg','text':'wrong'}}})
        self.client.server({'method':'turn/completed','params':{'threadId':'other','turn':{'id':'turn-1','status':'completed'}}})
        self.assertEqual(len(self.events),count);self.assertTrue(self.client.active)

    def test_cancel_ack_only_after_matching_turn_completion(self):
        self.start_turn();self.client.client({'kind':'cancel','cancelId':'cancel-exact'})
        self.client.server({'method':'item/completed','params':{'threadId':THREAD,'turnId':'turn-1','item':{'type':'agentMessage','id':'late','text':'stale'}}})
        self.assertFalse(any(e['kind']=='assistant' for e in self.events))
        self.assertTrue(self.client.active)
        self.client.server({'method':'turn/completed','params':{'threadId':THREAD,'turn':{'id':'turn-1','status':'interrupted'}}})
        self.assertEqual(self.events[-1]['cancelId'],'cancel-exact')
        self.assertEqual(self.events[-1]['state'],'cancelled')

    def test_owned_thread_restores_same_tools_and_readonly_policy(self):
        self.client.save_thread()
        client=SharedCompanion(self.directory.name,self.events.append,self.calls.append)
        client.open_thread()
        self.assertEqual(self.calls[-1]['params']['threadId'],THREAD)
        self.assertEqual(self.calls[-1]['params']['sandbox'],'read-only')
        self.assertIn('独立会话',self.calls[-1]['params']['developerInstructions'])

    def test_name_failure_does_not_fail_conversation(self):
        request=self.client.request('thread/name/set',{'threadId':THREAD,'name':'test'})
        self.client.server({'id':request,'error':{'message':'metadata not flushed'}})
        self.assertFalse(self.events);self.assertFalse(self.client.closed)

    def test_inference_error_closes_instead_of_untracked_background_work(self):
        self.start_turn()
        self.client.server({'method':'error','params':{'threadId':THREAD,'error':{'message':'provider unavailable'}}})
        self.assertTrue(self.client.closed)
        self.assertTrue(any(e['kind']=='error' for e in self.events))

    def test_startup_readiness_is_not_a_turn_completion(self):
        self.client.state('ready','connected')
        self.assertFalse(self.events[-1]['turnComplete'])
        self.start_turn()
        self.client.server({'method':'turn/completed','params':{'threadId':THREAD,'turn':{'id':'turn-1','status':'completed'}}})
        ready=[e for e in self.events if e.get('state')=='ready']
        self.assertTrue(ready[-1]['turnComplete'])


if __name__=='__main__':unittest.main()

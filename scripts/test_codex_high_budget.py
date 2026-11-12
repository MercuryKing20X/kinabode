"""Scoped Codex high budgets and lossless explicit detail access."""
import sys, tempfile, unittest
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / 'godot/bridge'))
import companion

class CodexHighBudget(unittest.TestCase):
    def client(self, directory, events):
        link = companion.Companion(directory, events.append, lambda _: None)
        link.ready = True
        link.thread_id = 'isolated-test'
        link.model_efforts = ['low', 'medium', 'high', 'xhigh']
        return link

    # DIRECTION 2026-11-09: 每日/单回合默认“不限”，连接页可手动设回。
    def test_default_unlimited_and_explicit_autonomy_cap(self):
        for level, kind, expected in [('high','chat',0), ('medium','chat',0), ('low','chat',0), ('ultra','chat',0), ('high','autonomy_event',100000)]:
            with self.subTest(level=level, kind=kind), tempfile.TemporaryDirectory() as directory:
                events=[]; link=self.client(directory, events)
                message={'kind':kind, 'text':'hello', 'world':{}, 'level':level}
                if kind=='autonomy_event': message['limits']={'tools':2,'turn_tokens':expected}
                link.client(message)
                self.assertEqual(link.turn_token_limit,expected)
                self.assertTrue(link.active)

    def test_other_adapter_subclass_keeps_original_limit(self):
        class OtherAdapter(companion.Companion): pass
        with tempfile.TemporaryDirectory() as directory:
            link=OtherAdapter(directory,lambda _:None,lambda _:None)
            link.ready=True;link.thread_id='test';link.model_efforts=['high']
            link.client({'kind':'chat','text':'hi','world':{},'level':'high'})
            self.assertEqual(link.turn_token_limit,0)

    def test_above_authorized_autonomy_cap_rejects(self):
        with tempfile.TemporaryDirectory() as directory:
            events=[]; link=self.client(directory,events)
            link.client({'kind':'autonomy_event','world':{},'level':'high','limits':{'tools':2,'turn_tokens':100000001}})
            self.assertFalse(link.active)
            self.assertTrue(any(e['kind']=='error' for e in events))

    def test_summary_copies_real_inventory_and_marks_omission(self):
        original={'self_actor_id':'codex','self':{'carry':{'wood':2}},'storage':{'wood':3},'memories':[{'fact':'real'}],'objects':[{'id':str(i)} for i in range(20)]}
        summary=companion.compact_snapshot(original)
        self.assertEqual(summary['self'], original['self'])
        self.assertEqual(summary['storage'], original['storage'])
        self.assertEqual(summary['memories'], original['memories'])
        self.assertTrue(summary['objects_summary_truncated'])
        self.assertEqual(len(original['objects']),20)
        summary['self']['carry']['wood']=99
        self.assertEqual(original['self']['carry']['wood'],2)

    def test_owned_thread_tool_approval_only(self):
        with tempfile.TemporaryDirectory() as directory:
            link=self.client(directory,[]); params=link.thread_params()
            self.assertEqual(params['approvalPolicy'],'never')
            self.assertEqual(params['config']['mcp_servers.youqi_actions']['default_tools_approval_mode'],'approve')
            self.assertEqual(params['sandbox'],'read-only')

if __name__=='__main__': unittest.main()

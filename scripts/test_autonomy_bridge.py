"""Zero inference: fake protocol callbacks, real transport and driver validation."""
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
def load(name,file):
    spec=importlib.util.spec_from_file_location(name,ROOT/'godot/bridge'/file)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
helper=load('autonomy_companion','companion.py')
transport=load('autonomy_transport','file_transport.py')
class AutonomyBridge(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='youqi-test-autonomy-');self.addCleanup(self.temp.cleanup)
        self.events=[];self.calls=[]
        self.client=helper.Companion(self.temp.name,self.events.append,self.calls.append)
        self.client.ready=True;self.client.thread_id='owned';self.client.model='fake-model'
        self.client.model_efforts=['low','medium','high','xhigh']
    def start(self,level='medium',**extra):
        self.client.client(dict(kind='autonomy_event',level=level,world={'self':{'id':'codex'},'events':[{'kind':'meal','text':'实际共餐'}]},limits={'tools':2,'turn_tokens':8000},turn_key='auto-1',**extra))
        self.client.turn_id='turn-1'
    def tool(self,call='a',args=None):
        self.client.server_request({'id':call,'method':'item/tool/call','params':{'threadId':'owned','turnId':'turn-1','callId':call,'tool':'habitat_request','arguments':args or {'intent':'greet'}}})
    def usage(self,total=150,input=100,output=50):
        amount={'totalTokens':total,'inputTokens':input,'outputTokens':output}
        self.client.server({'method':'thread/tokenUsage/updated','params':{'threadId':'owned','turnId':'turn-1','tokenUsage':{'total':amount,'last':amount}}})
    def test_low_never_autonomous(self):
        self.start('low');self.assertFalse(any(call.get('method')=='turn/start' for call in self.calls))
    def test_prompt_is_event_not_user_and_effort_is_real(self):
        self.start();call=self.calls[-1];self.assertEqual(call['params']['effort'],'medium')
        prompt=call['params']['input'][0]['text'];self.assertIn('游戏事件，非玩家发言',prompt);self.assertNotIn('用户说：',prompt)
        self.assertEqual(self.client.turn_tool_limit,2);self.assertEqual(self.client.turn_token_limit,8000)
    def test_ultra_is_advertised_maximum_not_fake_literal(self):
        self.start('ultra');self.assertEqual(self.calls[-1]['params']['effort'],'xhigh')
    def test_capabilities_are_read_without_starting_inference(self):
        self.client.model_efforts=None;self.start('ultra')
        request=self.calls[-1];self.assertEqual(request['method'],'model/list')
        self.assertFalse(any(x['method']=='turn/start' for x in self.calls))
        self.client.server({'id':request['id'],'result':{'data':[{'model':'fake-model','supportedReasoningEfforts':[{'reasoningEffort':'ultra'}]}]}})
        self.assertEqual(self.calls[-1]['params']['effort'],'ultra')
    def test_unsupported_level_is_error_not_silent_downgrade(self):
        self.client.model_efforts=['low'];self.start('high')
        self.assertFalse(any(x.get('method')=='turn/start' for x in self.calls))
        self.assertEqual(self.events[-1]['code'],'autonomy_unsupported')
    def test_tool_budget_counts_real_native_and_mcp_dispatch(self):
        self.start();self.tool('a');self.tool('b');self.tool('c')
        self.assertTrue(self.client.cancelled);self.assertLessEqual(sum(e['kind']=='action' for e in self.events),2)
    def test_oversized_context_or_invalid_budget_never_infers(self):
        self.client.client({'kind':'autonomy_event','level':'medium','world':{'text':'汉'*2000}})
        self.assertFalse(self.client.active)
        self.client.client({'kind':'autonomy_event','level':'medium','world':{},'limits':{'tools':99}})
        self.assertFalse(self.client.active)
    def test_usage_is_per_turn_cumulative_not_session_total(self):
        self.client.total_tokens=1000;self.start()
        self.usage(150);self.usage(200,130,70)
        updates=[e for e in self.events if e['kind']=='usage'];self.assertEqual(updates[-1]['total_tokens'],200)
        self.assertEqual(updates[-1]['turn_key'],'auto-1')
        self.client.server({'method':'turn/completed','params':{'threadId':'owned','turn':{'id':'turn-1'}}})
        self.assertTrue([e for e in self.events if e['kind']=='usage'][-1]['complete'])
    def test_cancel_stale_actions_and_usage_final(self):
        self.start();self.client.cancel(cancel_id='cancel-exact');self.tool('late')
        self.assertFalse(any(e['kind']=='action' for e in self.events))
        self.usage();self.assertTrue(any(e['kind']=='usage' for e in self.events))
        self.client.server({'method':'turn/completed','params':{'threadId':'owned','turn':{'id':'turn-1'}}})
        self.assertEqual(self.events[-1]['cancelId'],'cancel-exact')
    def test_transport_autonomy_and_cancel_boundary(self):
        published=[];sent=[];bridge=transport.FileTransport(self.temp.name,'session',sent.append,published.append)
        bridge.client({'session':'session','generation':1,'id':'a','message':{'kind':'autonomy_event'}})
        self.assertEqual(sent[-1]['kind'],'autonomy_event')
        bridge.client({'session':'session','generation':2,'id':'b','message':{'kind':'cancel'}})
        bridge.helper({'kind':'assistant','text':'late'});bridge.helper({'kind':'action','id':'late'})
        bridge.helper({'kind':'state','state':'cancelled','cancelId':'wrong'})
        self.assertTrue(bridge.cancelling)
        bridge.helper({'kind':'state','state':'cancelled','cancelId':bridge.cancel_id})
        self.assertFalse(bridge.cancelling);self.assertFalse(any(x['event']['kind'] in ('action','assistant') for x in published))
    def test_old_owned_thread_survives_version_bump(self):
        Path(self.temp.name,'youqi-thread-v2.json').write_text(json.dumps({'owner':'youqi-companion-v2','version':'0.3.0','threadId':'original-owned'}))
        client=helper.Companion(self.temp.name,self.events.append,self.calls.append)
        self.assertEqual(client.thread_id,'original-owned');client.open_thread()
        self.assertEqual(self.calls[-1]['method'],'thread/resume')
        self.assertNotIn('dynamicTools',self.calls[-1]['params'])
    def test_autonomy_cannot_create_blocking_question(self):
        self.start()
        self.client.server_request({'id':'ask','method':'item/tool/call','params':{'threadId':'owned','turnId':'turn-1','callId':'ask','tool':'habitat_ask','arguments':{'text':'现在干什么？'}}})
        self.assertFalse(any(event['kind']=='question' for event in self.events))
        result=json.loads(self.calls[-1]['result']['contentItems'][0]['text'])
        self.assertEqual(result['error'],'autonomy_cannot_open_question')
    def test_warm_connection_errors_belong_to_new_turn(self):
        self.client.client({'kind':'chat','text':'hello','world':{},'turn_key':'old'})
        self.client.turn_id='turn-1'
        self.client.server({'method':'turn/completed','params':{'threadId':'owned','turn':{'id':'turn-1'}}})
        self.client.model_efforts=['low']
        self.client.client({'kind':'chat','level':'high','text':'hello','world':{'intent_card':{'steward_request':True}},'turn_key':'new'})
        self.assertEqual(self.events[-1]['turn_key'],'new')
        self.assertEqual(self.events[-1]['code'],'autonomy_unsupported')
    def test_model_capability_read_failure_has_current_turn_identity(self):
        self.client.model_efforts=None
        self.client.client({'kind':'chat','level':'high','text':'hello','world':{},'turn_key':'new'})
        request=self.calls[-1]
        self.client.server({'id':request['id'],'error':{'message':'metadata unavailable'}})
        self.assertEqual(self.events[-1]['turn_key'],'new');self.assertFalse(self.client.active)
    def test_new_driver_keeps_dynamic_tool_schema_identical(self):
        frozen=json.loads((ROOT/'production/evidence/autonomy/native-tools-0.3.0.json').read_text())
        self.assertEqual(helper.DYNAMIC_TOOLS,frozen)
if __name__=='__main__':unittest.main()

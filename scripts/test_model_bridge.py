import importlib.util
from pathlib import Path
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[1]
def load(name,file):
    spec=importlib.util.spec_from_file_location(name,ROOT/'godot/bridge'/file)
    module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
helper=load('slice_companion','companion.py')
transport=load('slice_transport','file_transport.py')

class ModelContract(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory(prefix='youqi-model-test-');self.addCleanup(self.temp.cleanup)
        self.events=[];self.calls=[]
        self.client=helper.Companion(self.temp.name,self.events.append,self.calls.append)
        self.client.ready=True;self.client.thread_id='owned-game-thread'

    def start(self):
        self.client.client({'kind':'chat','text':'砍树','world':{'self':{'job':{}}}})
        self.client.turn_id='turn-1'

    def tool(self,name,args,call_id='unique'):
        self.client.server_request({'id':10,'method':'item/tool/call','params':{'threadId':'owned-game-thread','turnId':'turn-1','callId':call_id,'tool':name,'arguments':args}})

    def test_farm_commands_and_isolated_sessions(self):
        command = {'intent':'manage_farm','farm_id':'farm.hill','crop_id':'apple','mode':'once'}
        self.assertEqual(helper.validate_command(command), command)
        for bad in ({**command, 'actor_id':'human'}, {**command, 'mode':True}, {'intent':'assign_farm','farm_id':'farm.home','manager_id':'companion-2'}):
            with self.assertRaises(ValueError): helper.validate_command(bad)
        other_events, other_calls = [], []
        other = helper.Companion(str(Path(self.temp.name)/'other'), other_events.append, other_calls.append)
        self.assertNotEqual(other.state_path, self.client.state_path)
        other.ready = True; other.thread_id = 'separate-resident-thread'
        self.start()
        other.client({'kind':'chat','text':'照料果园','world':{'self_actor_id':'companion-2','self':{'id':'companion-2','job':{}}}})
        self.assertEqual(other_calls[-1]['params']['threadId'], 'separate-resident-thread')
        self.assertEqual(self.calls[-1]['params']['threadId'], 'owned-game-thread')
        calls = len(other_calls)
        other.tick()
        self.assertEqual(len(other_calls), calls)

    def test_farm_wait_is_active_and_question_answer_can_resume(self):
        self.client.client({'kind':'chat','text':'继续聊聊','world':{'self':{'job':{},'farm_order':{'status':'waiting'}}}})
        self.client.turn_id='turn-1'
        self.tool('habitat_request',{'intent':'chop','target_id':'home.tree.01'},'blocked')
        self.assertFalse(any(e['kind']=='action' for e in self.events))
        self.tool('habitat_ask',{'text':'继续照顾菜园吗？'},'question')
        event=next(e for e in self.events if e['kind']=='question')
        self.client.client({'kind':'tool_result','id':event['id'],'result':{'answer':'继续','farm_order':{'status':'paused'}}})
        self.tool('habitat_request',{'intent':'manage_farm','farm_id':'farm.home','crop_id':'turnip','mode':'once'},'resume')
        self.assertTrue(any(e['kind']=='action' and e['command']['intent']=='manage_farm' for e in self.events))

    def test_idle_does_not_infer(self):
        self.client.tick();self.client.tick()
        self.assertEqual(self.calls,[])

    def test_active_observation_roundtrip(self):
        self.start();self.tool('habitat_observe',{'object_id':'home.tree.01'})
        event=next(e for e in self.events if e['kind']=='observe')
        self.client.client({'kind':'tool_result','id':event['id'],'result':{'ok':True,'self':{'id':'codex'}}})
        self.assertTrue(self.calls[-1]['result']['success'])

    def test_question_needs_actual_answer(self):
        self.start();self.tool('habitat_ask',{'text':'先做哪一边？','choices':['左边','右边']})
        pending=next(e for e in self.events if e['kind']=='question')
        count=len(self.calls);self.client.tick()
        self.assertEqual(len(self.calls),count)
        self.client.client({'kind':'tool_result','id':pending['id'],'result':{'answer':'左边'}})
        self.assertTrue(self.calls[-1]['result']['success'])

    def test_accepted_not_finished_and_no_double_haul(self):
        self.start();self.tool('habitat_request',{'intent':'chop','target_id':'home.tree.01'})
        action=next(e for e in self.events if e['kind']=='action')
        self.client.client({'kind':'tool_result','id':action['id'],'result':{'ok':True,'status':'accepted'}})
        count=sum(e['kind']=='action' for e in self.events)
        self.tool('habitat_request',{'intent':'store'},'second')
        self.assertEqual(sum(e['kind']=='action' for e in self.events),count)

    def test_cancel_rejects_stale_actions(self):
        self.start();self.client.cancel(cancel_id='cancel-1')
        self.tool('habitat_request',{'intent':'chop','target_id':'home.tree.01'})
        self.assertFalse(any(e['kind']=='action' for e in self.events))

    def test_transport_matches_cancel_ack(self):
        emitted=[];sent=[];bridge=transport.FileTransport(self.temp.name,'nonce',sent.append,emitted.append)
        bridge.client({'session':'nonce','generation':1,'id':'c','message':{'kind':'chat','text':'hi'}})
        bridge.client({'session':'nonce','generation':2,'id':'x','message':{'kind':'cancel'}})
        bridge.helper({'kind':'action','id':'late','command':{'intent':'chop'}})
        bridge.helper({'kind':'state','state':'cancelled','cancelId':'wrong'})
        self.assertTrue(bridge.cancelling)
        bridge.helper({'kind':'state','state':'cancelled','cancelId':bridge.cancel_id})
        self.assertFalse(bridge.cancelling)
        self.assertFalse(any(e['event']['kind']=='action' for e in emitted))

    def test_no_actor_override_or_nonfinite_positions(self):
        for command in ({'intent':'chop','target_id':'home.tree.01','actor_id':'human'}, {'intent':'move','x':float('nan'),'y':0}):
            with self.assertRaises(ValueError):helper.validate_command(command)

    def test_only_game_tools_are_allowed(self):
        self.start();self.tool('exec_command',{'cmd':'anything'})
        self.assertFalse(self.calls[-1]['result']['success'])


    def test_shared_work_requests_roundtrip(self):
        self.start();self.tool('habitat_read_work',{'artwork_id':'cottage','frame':'stage_4'})
        event=next(e for e in self.events if e['kind']=='read_work')
        self.client.client({'kind':'tool_result','id':event['id'],'result':{'ok':True,'revision':1}})
        self.assertTrue(self.calls[-1]['result']['success'])
        self.tool('habitat_edit_work',{'artwork_id':'cottage','base_revision':1,'structure':{'width':9,'depth':7,'floors':1,'porch':0}},'edit')
        self.assertTrue(any(e['kind']=='edit_work' for e in self.events))

    def test_barbecue_commands_validate(self):
        for intent in ['forage','barbecue','turn_food','eat','cleanup']:
            self.assertEqual(helper.validate_command({'intent':intent,'target_id':'target'})['intent'],intent)
            with self.assertRaises(ValueError):helper.validate_command({'intent':intent,'actor_id':'human','target_id':'target'})

    def test_room_actions_validate_and_keep_identity_bound(self):
        commands = [
            {'intent':'enter','target_id':'home.house.01'}, {'intent':'exit'},
            {'intent':'furnish','target_id':'home.house.01','recipe_id':'chair','x':6.5,'y':6.5},
            {'intent':'place_furniture','x':4.5,'y':6.5},
            {'intent':'sit','target_id':'furniture.3'},
            {'intent':'take','target_id':'furniture.5'},
            {'intent':'store','target_id':'furniture.5'}]
        for command in commands:
            self.assertEqual(helper.validate_command(command), command)
            with self.assertRaises(ValueError): helper.validate_command(dict(command,actor_id='human'))
        for invalid in [dict(commands[2], x=float('nan')),dict(commands[2],recipe_id='free_house'),dict(commands[3],facing='sideways')]:
            with self.assertRaises(ValueError): helper.validate_command(invalid)

    def test_furnishing_acceptance_does_not_dispatch_extra_work(self):
        self.start()
        self.tool('habitat_request', {'intent':'furnish','target_id':'home.house.01','recipe_id':'table','x':8.5,'y':5.5})
        action=next(e for e in self.events if e['kind']=='action')
        self.client.client({'kind':'tool_result','id':action['id'],'result':{'ok':True,'status':'accepted','job_id':'job-1'}})
        count=sum(e['kind']=='action' for e in self.events)
        self.tool('habitat_request',{'intent':'sit','target_id':'furniture.3'},'extra')
        self.assertEqual(sum(e['kind']=='action' for e in self.events),count)

    def test_continuous_wood_order_schema_matches_mcp(self):
        spec=importlib.util.spec_from_file_location('wood_reader',ROOT/'scripts/habitat_godot.py')
        reader=importlib.util.module_from_spec(spec);spec.loader.exec_module(reader)
        self.assertEqual(helper.REQUEST_SCHEMA['properties']['intent']['enum'], reader.ACTION_SCHEMA['properties']['intent']['enum'])
        for field in ('zone_id','tree_count'):
            self.assertEqual(helper.REQUEST_SCHEMA['properties'][field], reader.ACTION_SCHEMA['properties'][field])
        for command in ({'intent':'gather_wood'}, {'intent':'gather_wood','zone_id':'home.forest','tree_count':3}, {'intent':'gather_wood','target_id':'home.tree.01'}):
            self.assertEqual(helper.validate_command(command),command)
        for extra in ({'tree_count':0},{'tree_count':1.5},{'tree_count':True},{'tree_count':101},{'tree_count':float('nan')},{'zone_id':[]},{'target_id':''},{'actor_id':'human'}):
            with self.assertRaises(ValueError): helper.validate_command(dict(intent='gather_wood',**extra))

    def test_continuous_order_runs_after_model_turn_without_polling(self):
        self.start();self.tool('habitat_request',{'intent':'gather_wood','zone_id':'home.forest','tree_count':3})
        action=next(e for e in self.events if e['kind']=='action')
        self.client.client({'kind':'tool_result','id':action['id'],'result':{'ok':True,'status':'accepted','job_id':'job-1'}})
        self.assertEqual(self.client.accepted_job,'gather_wood')
        self.tool('habitat_request',{'intent':'store'},'included-haul')
        self.assertEqual(sum(e['kind']=='action' for e in self.events),1)
        count=len(self.calls)
        self.client.active=False;self.client.tick();self.client.tick()
        self.assertEqual(len(self.calls),count)
        self.assertEqual(sum(e['kind']=='action' for e in self.events),1)

    def test_general_felling_is_distinct_from_explicit_single_tree(self):
        self.assertIn('去砍树',helper.INSTRUCTIONS)
        self.assertIn('use gather_wood',helper.INSTRUCTIONS)
        self.assertIn('Only use chop for explicitly one tree',helper.INSTRUCTIONS)
        self.start();self.tool('habitat_request',{'intent':'gather_wood'})
        action=next(e for e in self.events if e['kind']=='action')
        self.client.client({'kind':'tool_result','id':action['id'],'result':{'ok':True,'status':'accepted'}})
        self.client.cancel(cancel_id='stop-forestry')
        self.tool('habitat_request',{'intent':'gather_wood'},'stale-forestry')
        self.assertEqual(sum(e['kind']=='action' for e in self.events),1)

    def test_build_house_schema_and_pause_identity(self):
        for command in ({'intent':'build_house','target_id':'home.house.01'}, {'intent':'deliver_wood','target_id':'home.house.01'}, {'intent':'pause_project','project_id':'project-owned'}, {'intent':'resume_project','project_id':'project-owned'}, {'intent':'cancel_project','project_id':'project-owned'}):
            self.assertEqual(helper.validate_command(command),command)
            with self.assertRaises(ValueError): helper.validate_command(dict(command,actor_id='human'))
        for command in ({'intent':'build_house'},{'intent':'resume_project'},{'intent':'pause_project','project_id':5}):
            with self.assertRaises(ValueError): helper.validate_command(command)

    def test_blueprint_selection_does_not_consume_long_task_slot(self):
        self.start();self.tool('habitat_request',{'intent':'select_blueprint','target_id':'home.house.01','blueprint_id':'cottage-blue'})
        action=next(e for e in self.events if e['kind']=='action')
        self.client.client({'kind':'tool_result','id':action['id'],'result':{'ok':True,'status':'completed'}})
        self.assertIsNone(self.client.accepted_job)
        self.tool('habitat_request',{'intent':'build_house','target_id':'home.house.01'},'house')
        self.assertEqual(sum(e['kind']=='action' for e in self.events),2)
        action=[e for e in self.events if e['kind']=='action'][-1]
        self.client.client({'kind':'tool_result','id':action['id'],'result':{'ok':True,'status':'accepted','project_id':'project-owned'}})
        self.assertEqual(self.client.accepted_job,'build_house')
        self.tool('habitat_request',{'intent':'build','target_id':'home.house.01'},'redundant-stage')
        self.assertEqual(sum(e['kind']=='action' for e in self.events),2)
        self.tool('habitat_request',{'intent':'pause_project','project_id':'project-owned'},'pause')
        action=[e for e in self.events if e['kind']=='action'][-1]
        self.assertEqual(action['command']['intent'],'pause_project')
        self.client.client({'kind':'tool_result','id':action['id'],'result':{'ok':True,'status':'completed'}})
        self.assertIsNone(self.client.accepted_job)

    def test_active_project_blocks_replacement_between_child_jobs(self):
        self.client.client({'kind':'chat','text':'你好','world':{'self':{'job':{},'project':{'status':'active'}}}})
        self.client.turn_id='turn-1'
        self.tool('habitat_request',{'intent':'chop','target_id':'home.tree.01'})
        self.assertFalse(any(e['kind']=='action' for e in self.events))

    def test_answer_after_engine_project_pause_allows_explicit_resume(self):
        self.client.client({'kind':'chat','text':'商量一下','world':{'self':{'job':{},'project':{'status':'active'}}}})
        self.client.turn_id='turn-1'
        self.tool('habitat_ask',{'text':'材料够了，继续吗？'})
        question=next(e for e in self.events if e['kind']=='question')
        before=len(self.calls);self.client.tick()
        self.assertEqual(len(self.calls),before)
        self.client.client({'kind':'tool_result','id':question['id'],'result':{'answer':'继续','project':{'id':'project-owned','status':'paused'}}})
        self.tool('habitat_request',{'intent':'resume_project','project_id':'project-owned'},'continue-plan')
        self.assertTrue(any(e['kind']=='action' and e['command']['intent']=='resume_project' for e in self.events))

if __name__=='__main__':unittest.main(verbosity=2)

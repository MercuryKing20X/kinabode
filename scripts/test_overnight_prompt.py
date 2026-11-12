"""Offline fake-adapter replay of the actual native prompt shape, no server process."""
import sys,json,math,tempfile,unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
sys.path.insert(0,str(ROOT/'godot/bridge'))
import companion
import model_actions_mcp

def measure(context):
    with tempfile.TemporaryDirectory(prefix='youqi-test-prompt-') as directory:
        calls=[];client=companion.Companion(directory,lambda event:None,calls.append)
        client.ready=True;client.thread_id='fake-owned';client.model_efforts=['ultra']
        client.client({'kind':'autonomy_event','level':'ultra','world':context,'limits':{'tools':6,'turn_tokens':16000},'turn_key':'fake-estimate'})
        turn=next(call for call in calls if call.get('method')=='turn/start')
        payload={'instructions':companion.INSTRUCTIONS,'developer_instructions':client.thread_params()['developerInstructions'],'native_tools':companion.DYNAMIC_TOOLS,'v2_tools':model_actions_mcp.tools(),'input':turn['params']['input']}
    text=json.dumps(payload,ensure_ascii=False,separators=(',',':'))
    ascii_chars=sum(ord(c)<128 for c in text);other=len(text)-ascii_chars
    return {'characters':len(text),'ascii_characters':ascii_chars,'non_ascii_characters':other,'estimated_input_tokens':math.ceil(ascii_chars/4+other/1.5)+64,'estimated_output_tokens':256,'estimated_tokens_per_turn':math.ceil(ascii_chars/4+other/1.5)+64+256,'method':'ASCII/4 + non-ASCII/1.5, ceil + 64 protocol tokens + 256 output tokens; estimate only','real_model_calls':0}
class PromptReplay(unittest.TestCase):
    def test_complete_prompt_estimate_replaces_placeholder(self):
        path=ROOT/'production/evidence/overnight-2026-10-27/prompt-context.json'
        context=json.loads(path.read_text())
        self.assertLessEqual(len(json.dumps(context,ensure_ascii=False).encode()),4096)
        actual=measure(context)
        saved=json.loads((ROOT/'production/evidence/autonomy/ultra-30min.json').read_text())
        self.assertEqual(saved['reference_prompt_tokens'],saved['prompt_measurement']['estimated_tokens_per_turn'])
        reference=json.loads((ROOT/'production/evidence/2026-11-08-对话合一与AI放权/prompt-reference.json').read_text())
        self.assertEqual(reference,actual)
        self.assertGreater(actual['characters'],len(companion.INSTRUCTIONS))
if __name__=='__main__':unittest.main()

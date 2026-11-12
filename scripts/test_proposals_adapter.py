import sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'godot/bridge'))
import action_contract as contract
class ProposalsAdapter(unittest.TestCase):
    def test_propose_uses_v2_without_actor_override(self):
        args={'text':'一起做菜吧','activity':'cook_together','target_id':'turnip-soup','ttl_seconds':300}
        self.assertEqual(contract.command({'action':'propose','arguments':args}),dict(args,intent='propose'))
        for bad in [dict(args,actor_id='human'),dict(args,ttl_seconds=601),dict(args,ttl_seconds=True)]:
            with self.assertRaises(ValueError):contract.command({'action':'propose','arguments':bad})
    def test_accept_is_not_model_action(self):
        with self.assertRaises(ValueError):contract.command({'action':'accept_proposal','arguments':{'proposal_id':'x'}})
if __name__=='__main__':unittest.main()

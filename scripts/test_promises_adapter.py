import sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'godot/bridge'))
import action_contract as contract
class PromisesAdapter(unittest.TestCase):
    def test_registration_is_v2_and_identity_is_not_overridable(self):
        args={'action_type':'water','target_id':'farm.home.plot.01','day':2,'phase':'morning'}
        self.assertEqual(contract.command({'action':'promise','arguments':args}),dict(args,intent='promise'))
        for bad in [dict(args,day=True),dict(args,day=2.5),dict(args,actor_id='human')]:
            with self.assertRaises(ValueError):contract.command({'action':'promise','arguments':bad})
    def test_cancel_still_requires_own_id_at_engine(self):
        self.assertEqual(contract.command({'action':'promise_cancel','arguments':{'promise_id':'id'}}),{'intent':'promise_cancel','promise_id':'id'})
        with self.assertRaises(ValueError):contract.command({'action':'promise_cancel','arguments':{}})
if __name__=='__main__':unittest.main()

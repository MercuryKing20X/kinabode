import sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'godot/bridge'))
import action_contract as contract
class GiftsAdapter(unittest.TestCase):
    def test_give_is_atomic_owned_v2(self):
        args={'receiver_id':'human','item_id':'turnip','quantity':2}
        self.assertEqual(contract.command({'action':'give','arguments':args}),dict(args,intent='give'))
        for bad in [dict(args,giver_id='human'),dict(args,quantity=0),dict(args,quantity=True),dict(args,quantity=1.5)]:
            with self.assertRaises(ValueError):contract.command({'action':'give','arguments':bad})
    def test_cannot_take_from_target(self):
        with self.assertRaises(ValueError):contract.command({'action':'take_gift','arguments':{'giver_id':'human'}})
if __name__=='__main__':unittest.main()

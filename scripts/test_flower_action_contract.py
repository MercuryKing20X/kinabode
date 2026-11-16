import sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'godot/bridge'))
import action_contract as C
class Flowers(unittest.TestCase):
 def test_commands(self):
  for name in C.FLOWERS:
   self.assertEqual(C.command({'action':name,'arguments':{'color':'red','position':[30,40]}})['intent'],name)
  C.validate_intention({'action':'arrange_flowers','text':'HI','color':'red','position':[30,40]})
 def test_rejections(self):
  for args in [{'actor_id':'human'},{'text':'TOOLONG'},{'position':[float('nan'),0]},{'quantity':-1},{'quantity':1.5},{'position':[1]}]:
   with self.assertRaises(ValueError):C.command({'action':'arrange_flowers','arguments':args})
if __name__=='__main__':unittest.main()

"""New aliases retain argument validation and never accept another actor ID."""
import sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'godot/bridge'))
from action_contract import command
class Contract(unittest.TestCase):
 def test_real_engine_names(self):
  for action,args,intent in [('plant',{'target_id':'plot','crop_id':'turnip'},'plant'),('harvest',{'target_id':'plot'},'harvest'),('water',{'target_id':'plot'},'water'),('chop',{'target_id':'tree'},'chop'),('gather',{'target_id':'mushroom'},'gather'),('go_to',{'x':1,'y':2},'move'),('gather_at',{'x':1,'y':2},'gather_at'),('follow',{},'follow'),('unfollow',{},'unfollow'),('hand_over',{},'hand_over'),('query_state',{},'query_state')]:
   self.assertEqual(command({'action':action,'arguments':args}),dict(args,intent=intent))
   with self.assertRaises(ValueError):command({'action':action,'arguments':dict(args,actor_id='human')})
 def test_explicit_delegation(self):
  self.assertEqual(command({"action":"plant","arguments":{"actor_ids":["codex","npc.mira"]}}),{"intent":"plant","actor_ids":["codex","npc.mira"]})
  for ids in [["human"],["codex","codex"],[],"codex"]:
   with self.assertRaises(ValueError):command({"action":"follow","arguments":{"actor_ids":ids}})
 def test_invalid_arguments(self):
  for action,args in [('plant',{'target_id':'p'}),('water',{}),('go_to',{'x':float('nan'),'y':2}),('follow',{'target_id':'human'})]:
   with self.assertRaises(ValueError):command({'action':action,'arguments':args})
if __name__=='__main__':unittest.main()

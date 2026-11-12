"""Offline contract boundary tests; never opens a model session."""
import sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'godot/bridge'))
import action_contract
class IslandProposal(unittest.TestCase):
    def test_valid(self):
        self.assertEqual(action_contract.command({'action':'island_propose','arguments':{'template_id':'outdoor-chair','x':33,'y':226,'name':'Cloud seat','reason':'A supplied memory summary'}})['intent'],'island_propose')
    def test_reject(self):
        for change in ({'name':'x'*41},{'name':'two\nlines'},{'reason':'x'*129},{'x':float('nan')},{'actor_id':'human'}):
            with self.subTest(change=change),self.assertRaises(ValueError):
                action_contract.command({'action':'island_propose','arguments':dict(template_id='outdoor-chair',x=33,y=226,name='N',reason='R',**{})|change})
if __name__=='__main__':unittest.main()

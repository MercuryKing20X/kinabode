"""The optional v2 chess line never changes legacy native tool definitions."""
import sys,unittest
from pathlib import Path
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'godot/bridge'))
import action_contract as contract
class SpeechContract(unittest.TestCase):
    def move(self,**extra):
        return contract.command({'action':'gomoku_move','arguments':dict(site_id='play.gomoku',match_id='match-fixture',revision=1,x=7,y=7,**extra)})
    def test_optional_compatible(self):
        self.assertNotIn('speech',self.move())
        self.assertEqual(self.move(speech='我先放在这里。')['speech'],'我先放在这里。')
    def test_bounded(self):
        for value in [None,42,'鱼'*31,'一\n二','一\r二']:
            with self.subTest(value=value),self.assertRaises(ValueError):self.move(speech=value)
    def test_no_cross_action_field(self):
        with self.assertRaises(ValueError):contract.command({'action':'stop','arguments':{'speech':'绕过'}})
if __name__=='__main__':unittest.main()

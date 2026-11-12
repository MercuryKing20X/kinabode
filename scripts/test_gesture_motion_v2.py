import copy
import json
import unittest
from validate_gesture_motion import ROOT, valid

class GestureMotion(unittest.TestCase):
    def test_current_and_invalid(self):
        v=json.loads((ROOT/'godot/content/gesture_motion.json').read_text());self.assertTrue(valid(v))
        for key,value in [('duration',0),('bounce_pixels',11),('lean',float('nan'))]:
            wrong=copy.deepcopy(v);wrong['wave'][key]=value;self.assertFalse(valid(wrong))
        wrong=copy.deepcopy(v);wrong['stretch']['extra']=1;self.assertFalse(valid(wrong))
        wrong=copy.deepcopy(v);wrong['version']=True;self.assertFalse(valid(wrong))

if __name__=='__main__':unittest.main()

import copy,json,unittest
from validate_audio import ROOT,tuning
class SpeechQuiet(unittest.TestCase):
 def test_strict_optional(self):
  rules=json.loads((ROOT/'godot/content/audio/runtime.json').read_text())
  for key in ['speech_gap_seconds','speech_max_blips','speech_near_tiles']:
   for bad in [True,'6',float('nan'),float('inf'),0,61]:
    data=copy.deepcopy(rules);data[key]=bad;self.assertFalse(tuning(data),(key,bad))
  for bad in [1.5,2,3,4]:
   data=copy.deepcopy(rules);data['speech_max_blips']=bad;self.assertFalse(tuning(data))
  for key in ['speech_gap_seconds','speech_max_blips','speech_near_tiles']:rules.pop(key)
  self.assertTrue(tuning(rules))
if __name__=='__main__':unittest.main()

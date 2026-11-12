"""Independent checks for new optional audio metadata and recorded variants."""
import copy
import hashlib
import json
import unittest
from pathlib import Path
from validate_audio import ROOT, manifest, tuning, music_slots


class AudioV2(unittest.TestCase):
    def setUp(self):
        self.data=json.loads((ROOT/'godot/content/audio/sounds.json').read_text())
        self.rules=json.loads((ROOT/'godot/content/audio/runtime.json').read_text())

    def test_targets_and_old_data(self):
        self.assertTrue(tuning(self.rules))
        old=copy.deepcopy(self.rules);del old['targets_dbfs'];self.assertTrue(tuning(old))
        for value in ([0,-2],[-18,float('nan')],['bad',-14]):
            bad=copy.deepcopy(self.rules);bad['targets_dbfs']['voice']=value;self.assertFalse(tuning(bad))

    def test_recorded_groups_and_hashes(self):
        self.assertTrue(manifest(self.data))
        for material in ('grass','sand','stone','wood'):
            event=self.data['events']['step.'+material]
            self.assertEqual(set(event['variants']),{'A','B','C'})
            for clip in event['variants'].values():
                self.assertEqual(len(clip['takes']),2)
                self.assertNotEqual(clip['takes'][0]['sha256'],clip['takes'][1]['sha256'])
                for take in clip['takes']:
                    path=ROOT/'godot'/take['file'].removeprefix('res://')
                    self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(),take['sha256'])
                    source=self.data['sources'][take['source_id']]
                    self.assertEqual(source['kind'],'recording');self.assertEqual(source['license'],'CC0-1.0')
        old=copy.deepcopy(self.data);del old['events']['step.grass']['variants']['A']['takes'];self.assertTrue(manifest(old))
        bad=copy.deepcopy(self.data);take=bad['events']['step.grass']['variants']['A']['takes'];take[1]=copy.deepcopy(take[0]);self.assertFalse(manifest(bad))
        bad=copy.deepcopy(self.data);take=bad['events']['step.grass']['variants']['A']['takes'];take[1]['file']='res://content/audio/../../outside.wav';self.assertFalse(manifest(bad))
        bad=copy.deepcopy(self.data);bad['events']['step.grass']['selected']=[];self.assertFalse(manifest(bad))
        bad=copy.deepcopy(self.data);bad['events']['step.grass']['variants']['A']['source_id']=[];self.assertFalse(manifest(bad))

    def test_music_slots(self):
        slots=json.loads((ROOT/'godot/content/audio/music-slots.json').read_text());self.assertTrue(music_slots(slots))
        good=copy.deepcopy(slots);good['slots']['day']=['day-song.mp3'];self.assertTrue(music_slots(good))
        for name in ['../day-song.mp3','night-song.mp3','day-song.exe']:
            bad=copy.deepcopy(slots);bad['slots']['day']=[name];self.assertFalse(music_slots(bad))
        bad=copy.deepcopy(slots);bad['version']=True;self.assertFalse(music_slots(bad))


if __name__=='__main__':unittest.main()

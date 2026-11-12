"""Audio presentation contracts: strict boundaries, source hashes and old-safe defaults."""
import copy, hashlib, json, unittest
from pathlib import Path
from validate_audio import ROOT, manifest, tuning, voice
class AudioContent(unittest.TestCase):
    def setUp(self):
        self.data=json.loads((ROOT/'godot/content/audio/sounds.json').read_text())
        self.rules=json.loads((ROOT/'godot/content/audio/runtime.json').read_text())
    def test_current_data_and_hashes(self):
        self.assertTrue(manifest(self.data));self.assertTrue(tuning(self.rules))
        for event in self.data['events'].values():
            for clip in event['variants'].values():
                path=ROOT/'godot'/clip['file'].removeprefix('res://')
                self.assertEqual(hashlib.sha256(path.read_bytes()).hexdigest(),clip['sha256'])
    def test_no_unknown_or_nonfinite_params(self):
        for k,v in [('speed',999),('duck_db',1),('crossfade_seconds',float('nan')),('global_oneshot_limit',1.5)]:
            data=copy.deepcopy(self.rules);data[k]=v;self.assertFalse(tuning(data))
        for field,v in [('pitch',9),('event','provider.gpt'),('max_blips',1.5),('max_blips',2),('max_blips',3),('interval_seconds',float('inf')),('characters_per_blip',3)]:
            data=copy.deepcopy(self.rules['voice_default']);data[field]=v;self.assertFalse(voice(data))
    def test_manifest_boundaries(self):
        key=next(iter(self.data['events']))
        for field,v in [('max_instances',99),('pitch_min',0),('far_tiles',-1),('loop',1),('selected','Z'),('cooldown_seconds',-1),('extra',0)]:
            data=copy.deepcopy(self.data);data['events'][key][field]=v;self.assertFalse(manifest(data))
    def test_music_selection_link_contract(self):
        data=copy.deepcopy(self.data)
        # Local music contract fixture; no dependency on shipped music slots.
        source=copy.deepcopy(data['events']['ui.click'])
        source.update(bus='Music', loop=True, volume_db=-22)
        data['events']['music.sample30']=source
        event=copy.deepcopy(source)
        event['variants']=copy.deepcopy(source['variants'])
        event['selection_key']='music.sample30'
        data['events']['music.day']=event
        for scene in ('dusk', 'night'):
            data['events']['music.'+scene]=copy.deepcopy(event)
        self.assertTrue(manifest(data))
        for key in ['music.day','missing','voice.bright',[],1]:
            wrong=copy.deepcopy(data);wrong['events']['music.day']['selection_key']=key
            self.assertFalse(manifest(wrong))
        wrong=copy.deepcopy(data);wrong['events']['music.sample30']['selection_key']='music.day';self.assertFalse(manifest(wrong))
        wrong=copy.deepcopy(data);del wrong['events']['music.day']['variants']['C'];self.assertFalse(manifest(wrong))
    def test_traits_voice_is_optional_not_identity(self):
        for name in ['gentle','lively','laborious','quiet']:
            trait=json.loads((ROOT/f'godot/content/intelligence/traits/{name}.json').read_text())
            self.assertTrue(voice(trait['voice']))
            self.assertNotIn('resident_id',trait['voice']);self.assertNotIn('appearance',trait['voice'])
if __name__=='__main__':unittest.main()

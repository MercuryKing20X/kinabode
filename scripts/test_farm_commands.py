"""Strict Python mirror of FarmCommands.valid for the one-line farm command table."""
import copy
import json
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DATA = ROOT / 'godot/content/companions/farm-commands.json'
KEYS = {'version', 'plant_words', 'harvest_words', 'guarded_words', 'ignore_words', 'crops', 'farms', 'examples'}


def words(value):
    return type(value) is list and 0 < len(value) <= 32 and all(type(w) is str and w.strip() and len(w) <= 12 for w in value)


def aliases(value):
    return type(value) is dict and 0 < len(value) <= 16 and all(type(k) is str and k and words(v) for k, v in value.items())


def valid(value):
    if type(value) is not dict or set(value) != KEYS or value['version'] != 1 or type(value['version']) is bool:
        return False
    if not all(words(value[k]) for k in ['plant_words', 'harvest_words', 'ignore_words', 'examples']):
        return False
    guarded = value['guarded_words']
    if type(guarded) is not dict or set(guarded) != {'plant', 'harvest'} or not words(guarded['plant']) or not words(guarded['harvest']):
        return False
    return aliases(value['crops']) and aliases(value['farms'])


class FarmCommandContent(unittest.TestCase):
    def setUp(self):
        self.data = json.loads(DATA.read_text())

    def test_shipped_table_valid_and_matches_game_ids(self):
        self.assertTrue(valid(self.data))
        farms = json.loads((ROOT / 'godot/content/farms.json').read_text())
        self.assertLessEqual(set(self.data['crops']), set(farms['crops']))
        self.assertLessEqual(set(self.data['farms']), {f['id'] for f in farms['farms']})

    def test_strict_rejections(self):
        for key, bad in [('version', 2), ('version', True), ('plant_words', []), ('plant_words', [1]), ('examples', ['']),
                         ('crops', {}), ('farms', {'farm.home': []}), ('guarded_words', {'plant': ['种']}), ('extra', 1)]:
            data = copy.deepcopy(self.data)
            data[key] = bad
            with self.subTest(key=key, bad=bad):
                self.assertFalse(valid(data))
        data = copy.deepcopy(self.data)
        data.pop('examples')
        self.assertFalse(valid(data))


if __name__ == '__main__':
    unittest.main()

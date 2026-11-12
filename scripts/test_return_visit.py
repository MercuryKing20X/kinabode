"""Strict new optional visit content contract; never reads user data."""
import copy
import importlib.util
import json
from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('catalog', ROOT/'godot/tools/intelligence_catalog.py')
catalog = importlib.util.module_from_spec(spec)
spec.loader.exec_module(catalog)
LIMITS = {'interval_seconds': (300,900), 'far_distance': (16,80), 'far_seconds': (90,600), 'stay_seconds': (5,40), 'stagger_seconds': (15,90), 'route_timeout_seconds': (24,300)}
def validate(value):
    catalog.keys(value, set(), set(LIMITS), 'return_visit')
    for key, v in value.items(): catalog.number(v, key, *LIMITS[key])
class ReturnVisit(unittest.TestCase):
    def test_defaults_and_traits(self):
        defaults=json.loads((ROOT/'godot/content/companions/return-visit.json').read_text())
        self.assertEqual(set(defaults), set(LIMITS));validate(defaults)
        for p in (ROOT/'godot/content/intelligence/traits').glob('*.json'):
            data=json.loads(p.read_text());validate(data.get('return_visit', {}))
    def test_invalid(self):
        for item in [{'interval_seconds':True},{'far_distance':'24'},{'far_seconds':float('nan')},{'stay_seconds':-1},{'unknown':1}]:
            with self.assertRaises(catalog.CatalogError):validate(item)
if __name__=='__main__':unittest.main()

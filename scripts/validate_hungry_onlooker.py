"""Strict optional presentation/backup content validators; no game content tuning."""
import json
import math
from pathlib import Path
import sys

EYES = dict(version=1, radius=8.0, seat_margin=.6, swallow_every=6.0,
            swallow_seconds=.6, swallow_pixels=1.5, drool_every=12.0, drool_seconds=3.0)
BACKUP = dict(version=1, recent_count=10, daily_days=7, max_total_bytes=536870912)

def numeric(value):
    return type(value) in (int, float) and math.isfinite(value)

def valid_eyes(value):
    return (type(value) is dict and value.keys() == EYES.keys()
            and all(numeric(v) for v in value.values()) and value['version'] == 1
            and 4 <= value['radius'] <= 12 and .3 <= value['seat_margin'] <= 2
            and 3 <= value['swallow_every'] <= 60
            and .2 <= value['swallow_seconds'] <= 1.5
            and value['swallow_seconds'] < value['swallow_every']
            and .5 <= value['swallow_pixels'] <= 3
            and 6 <= value['drool_every'] <= 120
            and .5 <= value['drool_seconds'] <= 4
            and value['drool_seconds'] < value['drool_every'])

def main(root=None):
    root = Path(root or Path(__file__).resolve().parents[1] / 'godot/content')
    for name, validator in [('hungry-onlooker.json', valid_eyes)]:
        if not validator(json.loads((root / name).read_text())):
            raise ValueError(f'invalid {name}')
    # Mutation probes exercise rejected types, unknown keys, NaN, and bounds.
    checks = 0
    for defaults, validator in [(EYES, valid_eyes)]:
        assert validator(defaults)
        checks += 1
        for key in defaults:
            for invalid in [None, True, '1', float('nan'), float('inf'), -1]:
                assert not validator(dict(defaults, **{key: invalid})), (key, invalid)
                checks += 1
            altered = defaults.copy()
            del altered[key]
            assert not validator(altered)
            checks += 1
        assert not validator(dict(defaults, unknown=1))
        checks += 1
    print(f'Overnight presentation content: {checks} checks passed')

if __name__ == '__main__':
    main(sys.argv[1] if len(sys.argv) > 1 else None)

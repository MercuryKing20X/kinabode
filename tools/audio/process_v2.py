"""Derive balanced, softened WAVs from the project's original synthesized clips."""
import hashlib
import json
from pathlib import Path

import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / 'godot/content/audio/sounds.json'
OUT = ROOT / 'godot/content/audio/sound-v2'
SCRIPT = 'tools/audio/process_v2.py'


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def target(event, bus):
    if event.startswith('voice.') or event in ('meal.satisfied', 'fire.ignite', 'fishing.bite', 'fish.release'):
        return -16.0
    if bus == 'Ambience':
        return -24.0
    return -20.0


def shape(samples, rate, wanted, peak_db, loop):
    # A gentle periodic frequency filter also preserves continuity of loop beds.
    frequency = np.fft.rfftfreq(len(samples), 1 / rate)
    spectrum = np.fft.rfft(samples, axis=0)
    filtered = np.fft.irfft(spectrum / (1 + (frequency[:, None] / 4500.0) ** 4), n=len(samples), axis=0)
    peak_limit = 10 ** (peak_db / 20)
    desired = 10 ** (wanted / 20)
    exponent = 1.0
    while exponent > .20:
        shaped = np.sign(filtered) * np.abs(filtered) ** exponent
        if loop:
            count = min(len(shaped), round(rate * .008))
            correction = np.linspace(0, 1, count)[:, None] * (shaped[-1] - shaped[0])
            shaped[-count:] -= correction
        rms = float(np.sqrt(np.mean(shaped * shaped)))
        if rms and float(np.max(np.abs(shaped))) * desired / rms <= peak_limit:
            break
        exponent = round(exponent - .025, 3)
    if not rms:
        raise ValueError('silent source')
    shaped *= desired / rms
    if np.max(np.abs(shaped)) > peak_limit:
        raise ValueError('cannot meet peak and average target')
    return shaped, exponent


def main():
    data = json.loads(MANIFEST.read_text())
    OUT.mkdir(parents=True, exist_ok=True)
    for event in list(data['events']):
        if event.startswith('music.'):
            del data['events'][event]
            continue
        entry = data['events'][event]
        for version, clip in entry['variants'].items():
            source = data['sources'][clip['source_id']]
            if source['kind'] == 'recording':
                continue
            if source['script'] == SCRIPT:
                old_path = ROOT / source['parameters']['input_file']
                old_source = source['parameters']['input_source_id']
            else:
                old_path = ROOT / 'godot' / clip['file'].removeprefix('res://')
                old_source = clip['source_id']
            samples, rate = sf.read(old_path, always_2d=True)
            wanted = target(event, entry['bus'])
            peak_limit = -4.6 if event.startswith('step.') else -3.1
            processed, exponent = shape(samples, rate, wanted, peak_limit, entry['loop'])
            dest = OUT / f'{event}-{version}.wav'
            sf.write(dest, processed, rate, subtype='PCM_16')
            actual, _ = sf.read(dest, always_2d=True)
            rms = 20 * np.log10(max(float(np.sqrt(np.mean(actual * actual))), 1e-12))
            peak = 20 * np.log10(max(float(np.max(np.abs(actual))), 1e-12))
            source_id = f'v2.{event}.{version}'
            data['sources'][source_id] = {
                'kind': 'synthesis', 'script': SCRIPT,
                'parameters': {'input_file': str(old_path.relative_to(ROOT)), 'input_sha256': digest(old_path),
                               'input_source_id': old_source, 'lowpass_hz': 4500, 'compression_exponent': exponent,
                               'target_rms_dbfs': wanted, 'rms_dbfs': round(rms, 6), 'peak_dbfs': round(peak, 6)},
                'license': 'project-original', 'url': '', 'sha256': digest(dest),
            }
            clip.update(file='res://content/audio/sound-v2/' + dest.name, sha256=digest(dest), source_id=source_id)
        entry['volume_db'] = 0.0
    MANIFEST.write_text(json.dumps(data, ensure_ascii=False, indent=2) + '\n')
    print('Balanced variants:', sum(len(e['variants']) for e in data['events'].values()))


if __name__ == '__main__':
    main()

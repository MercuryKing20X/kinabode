"""Reproducible one-bubble 1101 voice: one short, soft, closed-mouth pulse.

Each family keeps its relative order (bright > crisp > soft > low); per-trait
`voice.pitch` multipliers are untouched. A = softest rounded hum (default), B = closed-mouth pop, C = soft pluck.
"""
import hashlib
import json
from pathlib import Path

import numpy as np
import soundfile as sf

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'godot/content/audio/voice-single-1101'
RATE = 24000
# Old 1031 bases were bright 690 / crisp 510 / soft 425 / low 235 Hz.
FAMILIES = {
    'bright': {'frequency': 330.0, 'seconds': .085},
    'crisp': {'frequency': 262.0, 'seconds': .095},
    'soft': {'frequency': 208.0, 'seconds': .105},
    'low': {'frequency': 147.0, 'seconds': .115},
}
VARIANTS = {
    'A': {'shape': 'hum', 'pitch': 1.0, 'lowpass_hz': 750},
    'B': {'shape': 'pop', 'pitch': 1.0, 'lowpass_hz': 1000},
    'C': {'shape': 'pluck', 'pitch': 1.0, 'lowpass_hz': 1200},
}
TARGET_RMS_DBFS = -12.0
PEAK_LIMIT_DBFS = -3.2


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def lowpass(y, cutoff):
    freq = np.fft.rfftfreq(len(y), 1 / RATE)
    gain = 1 / np.sqrt(1 + (freq / cutoff) ** 4)
    return np.fft.irfft(np.fft.rfft(y) * gain, n=len(y))


def synth(shape, frequency, seconds):
    n = round(seconds * RATE)
    t = np.arange(n) / RATE
    # Gentle downward glide like a murmured syllable, tiny vibrato.
    glide = frequency * (1.0 - .07 * t / seconds)
    phase = 2 * np.pi * np.cumsum(glide) / RATE + .012 * np.sin(2 * np.pi * 5.5 * t)
    if shape == 'hum':
        y = np.sin(phase) + .12 * np.sin(2 * phase) + .025 * np.sin(3 * phase)
        envelope = np.sin(np.pi * np.arange(n) / (n - 1)) ** 1.3
    elif shape == 'pop':
        y = np.sin(phase) + .12 * np.sin(2 * phase)
        envelope = np.sin(np.pi * np.arange(n) / (n - 1)) ** 2.4
    else:
        y = np.sin(phase) + .18 * np.sin(2 * phase + .4) + .05 * np.sin(4 * phase)
        envelope = np.minimum(1, t / .006) * np.exp(-t / (seconds * .45))
    return y * envelope


def level(y):
    for _ in range(6):
        rms = float(np.sqrt(np.mean(y * y)))
        y = y * (10 ** (TARGET_RMS_DBFS / 20) / max(rms, 1e-12))
        limit = 10 ** (PEAK_LIMIT_DBFS / 20)
        if np.max(np.abs(y)) > limit:
            y = limit * np.tanh(y / limit)
    fade = min(len(y) // 4, int(RATE * .004))
    ramp = np.sin(np.linspace(0, np.pi / 2, fade)) ** 2
    y[:fade] *= ramp
    y[-fade:] *= ramp[::-1]
    return y


def main():
    manifest_path = ROOT / 'godot/content/audio/sounds.json'
    manifest = json.loads(manifest_path.read_text())
    OUT.mkdir(exist_ok=True)
    script = 'tools/audio/one_bubble_voice.py'
    for family, base in FAMILIES.items():
        event = manifest['events']['voice.' + family]
        event['variants'] = {}
        for version, variant in VARIANTS.items():
            frequency = base['frequency'] * variant['pitch']
            y = level(lowpass(synth(variant['shape'], frequency, base['seconds']), variant['lowpass_hz']))
            dest = OUT / f'voice.{family}-{version}.wav'
            sf.write(dest, y, RATE, subtype='PCM_16')
            imported=dest.with_suffix(dest.suffix+'.import')
            if imported.exists():imported.write_text(imported.read_text().replace('compress/mode=2','compress/mode=0'))
            actual, _ = sf.read(dest, always_2d=True)
            rms = 20 * np.log10(np.sqrt(np.mean(actual * actual)))
            peak = 20 * np.log10(np.max(np.abs(actual)))
            digest = sha(dest)
            source = f'single1101.voice.{family}.{version}'
            manifest['sources'][source] = {
                'kind': 'synthesis', 'script': script,
                'parameters': {'algorithm': 'single-pulse-murmur-1101', 'shape': variant['shape'], 'sample_rate': RATE,
                               'frequency_hz': round(frequency, 3), 'seconds': base['seconds'],
                               'lowpass_hz': variant['lowpass_hz'], 'target_rms_dbfs': TARGET_RMS_DBFS,
                               'rms_dbfs': round(float(rms), 6), 'peak_dbfs': round(float(peak), 6)},
                'license': 'project-original', 'url': '', 'sha256': digest}
            event['variants'][version] = {'file': 'res://content/audio/voice-single-1101/' + dest.name,
                                          'sha256': digest, 'source_id': source}
            effective = rms + float(event['volume_db'])
            assert -18 <= effective <= -14, (family, version, effective)
            assert peak + float(event['volume_db']) <= -3, (family, version, peak)
            print(f'voice.{family}-{version}: {frequency:.0f} Hz rms {effective:.2f} peak {peak:.2f}')
        event['selected'] = 'A'
    manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + '\n')


if __name__ == '__main__':
    main()

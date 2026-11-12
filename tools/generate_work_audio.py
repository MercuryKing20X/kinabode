"""Original quiet work foley; no samples, network, or inference at runtime."""
from pathlib import Path
import math, random, struct, wave
out = Path(__file__).resolve().parents[1] / 'godot/assets/audio'
out.mkdir(parents=True, exist_ok=True)
for kind, duration, frequency in [('hit', .13, 160), ('fall', .42, 80), ('pickup', .07, 260), ('deposit', .16, 190)]:
    rng = random.Random(kind)
    samples = bytearray()
    filtered = 0.0
    for i in range(int(duration * 22050)):
        t = i / 22050
        filtered = filtered * .65 + rng.uniform(-1, 1) * .35
        envelope = min(1, t / .003) * math.exp(-t / (duration * .24))
        sample = (math.sin(t * frequency * 2 * math.pi) * .4 + filtered * .6) * envelope
        samples.extend(struct.pack('<h', int(sample * 22000)))
    with wave.open(str(out / (kind + '.wav')), 'wb') as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(22050); f.writeframes(samples)

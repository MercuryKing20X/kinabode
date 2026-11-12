"""Small original atmosphere effects, not replacement character/environment art."""
from pathlib import Path
from PIL import Image
import math, random, struct, wave
ROOT = Path(__file__).resolve().parents[1]
im = Image.new('RGBA', (32, 32))
for y in range(32):
    for x in range(32):
        a = max(0, 1 - math.sqrt(((x - 15.5) / 15.5) ** 2 + ((y - 15.5) / 15.5) ** 2))
        # Quantized soft cluster at native pixel scale.
        im.putpixel((x, y), (219, 217, 196, int(a * 5) * 45))
im.save(ROOT / 'godot/assets/island/smoke.png')
for name, seconds in [('breeze', 8), ('fire', 4)]:
    rng = random.Random(name); filtered = 0.0; pop = 0.0; data = bytearray()
    for i in range(seconds * 22050):
        t = i / 22050
        noise = rng.uniform(-1, 1)
        filtered = filtered * .98 + noise * .02
        if name == 'breeze': value = filtered * (1.3 + math.sin(t * math.tau / seconds) * .5)
        else:
            if rng.random() < .0006: pop = rng.uniform(.15, .6)
            pop *= .97
            value = filtered * .7 + noise * pop
        edge = min(1, t / .04, (seconds - t) / .04)
        data.extend(struct.pack('<h', int(value * 24000 * edge)))
    with wave.open(str(ROOT / 'godot/assets/audio' / (name + '.wav')), 'wb') as f:
        f.setnchannels(1); f.setsampwidth(2); f.setframerate(22050); f.writeframes(data)

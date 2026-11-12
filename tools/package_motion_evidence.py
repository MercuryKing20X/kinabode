from pathlib import Path
from PIL import Image
import shutil
ROOT = Path(__file__).resolve().parents[1]
source = ROOT / 'tmp/motion-capture'
out = ROOT / 'production/evidence'
for kind in ['idle', 'chop', 'deposit']:
    crop = {'idle': (420, 250, 840, 530), 'chop': (410, 60, 930, 580), 'deposit': (410, 220, 930, 620)}[kind]
    rgb = [Image.open(p).convert('RGB').crop(crop) for p in sorted(source.glob(kind + '-*.png'))]
    palette = rgb[0].quantize(colors=192)
    frames = [frame.quantize(palette=palette, dither=Image.Dither.NONE) for frame in rgb]
    frames[0].save(out / ('motion-' + kind + '.gif'), save_all=True, append_images=frames[1:], duration=167 if kind == 'idle' else 83, loop=0, disposal=1, optimize=True)
shutil.copyfile(source / 'chop-006.png', out / 'motion-chop.png')
shutil.copyfile(source / 'idle-020.png', out / 'motion-idle.png')
# Detail contact sheet for reviewing real viewport poses; not synthetic animation.
indices = [1, 5, 8, 58, 73, 92]
contact = Image.new('RGB', (900, 640))
for i, frame in enumerate(indices):
    crop = Image.open(source / f'chop-{frame:03d}.png').crop((490, 200, 790, 520))
    contact.paste(crop, ((i % 3) * 300, (i // 3) * 320))
contact.save(out / 'motion-contact.png')
print('Packaged actual viewport frames:', ', '.join(p.name for p in out.glob('motion-*.gif')))

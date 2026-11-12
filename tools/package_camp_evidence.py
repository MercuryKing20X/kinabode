from pathlib import Path
from PIL import Image
import shutil
ROOT=Path(__file__).resolve().parents[1];source=ROOT/'tmp/camp-capture';out=ROOT/'production/evidence'
for kind in ['fire','meal']:
    frames=[Image.open(p).convert('RGB').crop((365,85,925,645)) for p in sorted(source.glob(kind+'-*.png'))]
    palette=frames[len(frames)//2].quantize(colors=192)
    frames=[frame.quantize(palette=palette,dither=Image.Dither.NONE) for frame in frames]
    frames[0].save(out/f'camp-{kind}.gif',save_all=True,append_images=frames[1:],duration=100,loop=0,disposal=1,optimize=True)
shutil.copyfile(source/'meal-035.png',out/'camp-meal.png')
shutil.copyfile(source/'fire-020.png',out/'camp-fire.png')
print('Actual viewport GIFs packaged.')

from pathlib import Path
from PIL import Image
import shutil
ROOT=Path(__file__).resolve().parents[1];source=ROOT/'tmp/local-capture';out=ROOT/'production/evidence'
for kind,crop in [('nearby',(400,165,960,595)),('rest',(360,145,920,575))]:
    frames=[Image.open(p).convert('RGB').crop(crop) for p in sorted(source.glob(kind+'-*.png'))]
    palette=frames[0].quantize(colors=192)
    frames=[frame.quantize(palette=palette,dither=Image.Dither.NONE) for frame in frames]
    frames[0].save(out/f'local-life-{kind}.gif',save_all=True,append_images=frames[1:],duration=100,loop=0,disposal=1,optimize=True)
shutil.copyfile(source/'controls.png',out/'local-life-controls.png')
print('Local life viewport evidence packaged.')

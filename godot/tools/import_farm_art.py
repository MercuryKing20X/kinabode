"""Import the generated sheets as editable pixel works. No API calls."""
from pathlib import Path
from PIL import Image
import json

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / 'output/imagegen/farms-20261024'
OUT = ROOT / 'godot/assets/crops'
OUT.mkdir(exist_ok=True)
for sheet, names, cols, rows in [('vegetables', ['turnip', 'tomato', 'pumpkin', 'daisy'], 4, 3), ('orchard', ['blueberry', 'apple'], 3, 2)]:
    image = Image.open(SRC / f'{sheet}.png').convert('RGBA')
    for index, name in enumerate(names):
        frames = []
        for stage in range(3):
            col, row = (index, stage) if sheet == 'vegetables' else (stage, index)
            cell = image.crop((col*image.width//cols, row*image.height//rows, (col+1)*image.width//cols, (row+1)*image.height//rows))
            pixels = []
            for r, g, b, a in cell.getdata():
                if r > 100 and b > 90 and min(r, b) > g*1.45:
                    pixels.append((0, 0, 0, 0))
                elif sheet == 'orchard' and stage < 2 and ((b > r*1.2 and b > g*.94) or (r > g*1.4 and r > b*1.4)):
                    pixels.append((67, 100, 41, a))
                else:
                    pixels.append((r, g, b, a))
            cell.putdata(pixels)
            frames.append(cell.crop(cell.getbbox()))
        width, height = (160, 192) if name == 'apple' else (112, 128) if name == 'blueberry' else (80, 96)
        scale = min((width-8)/max(f.width for f in frames), (height-8)/max(f.height for f in frames))
        canvases = []
        for frame in frames:
            frame = frame.resize((round(frame.width*scale), round(frame.height*scale)), Image.Resampling.NEAREST)
            canvas = Image.new('RGBA', (width, height))
            canvas.alpha_composite(frame, ((width-frame.width)//2, height-frame.height-3))
            canvases.append(canvas)
        strip = Image.new('RGBA', (width*3, height))
        for n, canvas in enumerate(canvases):
            strip.alpha_composite(canvas, (n*width, 0))
        quant = strip.convert('RGB').quantize(colors=95, method=Image.Quantize.MEDIANCUT)
        rgb = quant.getpalette()
        palette = ['#00000000'] + ['#%02x%02x%02xff' % tuple(rgb[n:n+3]) for n in range(0, 285, 3)]
        art = {'schema_version': 1, 'id': f'crop-{name}', 'name': {'turnip':'小萝卜','tomato':'番茄','pumpkin':'南瓜','daisy':'雏菊','blueberry':'蓝莓','apple':'苹果'}[name], 'kind':'plant', 'width':width, 'height':height, 'anchor':[width//2,height-3], 'revision':1, 'palette':palette, 'frames':{}}
        for n, key in enumerate(['seedling','growing','mature']):
            canvas = canvases[n]
            pixels = [0 if canvas.getpixel((x,y))[3] < 128 else quant.getpixel((x+n*width,y))+1 for y in range(height) for x in range(width)]
            art['frames'][key] = [{'name':'植物','visible':True,'pixels':pixels}]
            result = Image.new('RGBA', (width,height))
            result.putdata([tuple(bytes.fromhex(palette[p][1:])) for p in pixels])
            result.save(OUT / f'{name}-{key}.png')
        (ROOT/f'godot/content/works/crop-{name}.json').write_text(json.dumps(art,ensure_ascii=False,separators=(',',':')))
print('Imported 18 growth frames / 6 editable plant works')

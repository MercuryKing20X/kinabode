"""Add reviewed directional action frames without rebuilding existing artwork."""
from pathlib import Path
from PIL import Image, ImageOps
import json
ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'output/imagegen/animation-20261023'

def key(image):
    image = image.convert('RGBA')
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = pixels[x, y]
            if r > 125 and b > 125 and min(r, b) > g * 1.45 and g < 145:
                pixels[x, y] = (0, 0, 0, 0)
    return image.quantize(colors=128, method=Image.Quantize.FASTOCTREE).convert('RGBA')

for source, identity in [('girl', 'white-haired-girl'), ('farmer', 'human-starter')]:
    sheet = key(Image.open(SOURCE / (source + '.png')))
    path = ROOT / 'godot/content/characters' / (identity + '.json')
    art = json.loads(path.read_text())
    lookup = {color: i for i, color in enumerate(art['palette'])}
    preview = Image.new('RGBA', (96 * 6, 128 * 4))
    for row, direction in enumerate(['down', 'left', 'right', 'up']):
        # Generated right-facing rows contain backwards tools/poses: mirror the
        # consistent left row, including its tool, rather than ship mixed facings.
        source_row = 1 if direction == 'right' else row
        for col, action in enumerate(['blink', 'chop_0', 'chop_1', 'chop_2', 'carry', 'pickup']):
            tile = sheet.crop((col * 256, source_row * 256, (col + 1) * 256, (source_row + 1) * 256))
            if direction == 'right': tile = ImageOps.mirror(tile)
            box = tile.getbbox()
            tile = tile.crop(box)
            tile = tile.resize((round(tile.width * .44), round(tile.height * .44)), Image.Resampling.NEAREST)
            canvas = Image.new('RGBA', (96, 128))
            canvas.alpha_composite(tile, ((96 - tile.width) // 2, 120 - tile.height))
            name = f'chop_{direction}_{action[-1]}' if action.startswith('chop') else f'{action}_{direction}'
            pixels = []
            for rgba in canvas.getdata():
                color = '#%02x%02x%02x%02x' % rgba if rgba[3] else '#00000000'
                if color not in lookup:
                    lookup[color] = len(art['palette']); art['palette'].append(color)
                pixels.append(lookup[color])
            art['frames'][name] = [{'id': 'paint', 'name': '动作原画', 'visible': True, 'pixels': pixels}]
            preview.alpha_composite(canvas, (col * 96, row * 128))
    # Alternate the two lower legs under the authored carrying upper body.
    for direction in ['down', 'left', 'right', 'up']:
        original = art['frames'][f'carry_{direction}'][0]['pixels']
        for step in range(2):
            pixels = original.copy()
            for y in range(106, 128):
                for x in range(96): pixels[y * 96 + x] = 0
            for y in range(106, 120):
                for x in range(96):
                    lift = 1 if (x < 48) == (step == 0) else 0
                    pixels[(y - lift) * 96 + x] = original[y * 96 + x]
            art['frames'][f'carry_{direction}_{step}'] = [{'id': 'paint', 'name': '抱木材迈步', 'visible': True, 'pixels': pixels}]
    assert len(art['palette']) <= 4096 and len(art['frames']) <= 80
    path.write_text(json.dumps(art, ensure_ascii=False, separators=(',', ':')) + '\n')
    preview.save(SOURCE / (source + '-imported.png'))
    print(identity, len(art['frames']), 'frames;', len(art['palette']), 'colors')

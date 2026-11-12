"""Crop the original viewport sequence into five native-resolution walking GIFs."""
from pathlib import Path
import json
import sys
from PIL import Image

directory = Path(sys.argv[1])
manifest = json.loads((directory / "gait-viewports.json").read_text())
results = []
for actor in dict.fromkeys(row["actor_id"] for row in manifest["frames"] if "scenario" not in row):
    images = [Image.open(directory / f"gait-{actor}-{frame:02d}-1280x800.png").convert("RGB") for frame in range(6)]
    # Camera and route are identical for all five actual captures. Keep the whole
    # stride trajectory, ground contact and dust, not an individually recentered body.
    crop = (380, 200, 810, 510)
    crops = [image.crop(crop) for image in images]
    target = directory / f"gait-{actor}.gif"
    crops[0].save(target, save_all=True, append_images=crops[1:], duration=75, loop=0, optimize=False)
    sheet = Image.new("RGB", (6 * 180, 200))
    for index, image in enumerate(images):
        # Each strip cell is also a native pixel crop from the viewport.
        cell = image.crop((430 + index * 11, 260, 610 + index * 11, 460))
        sheet.paste(cell, (index * 180, 0))
    strip = directory / f"gait-{actor}-six-frames.png"
    sheet.save(strip)
    results.append({"actor_id": actor, "gif": target.name, "frame_strip": strip.name, "original_frame_count": 6, "native_resolution": True, "gif_crop": crop})
(directory / "gait-gifs.json").write_text(json.dumps(results, ensure_ascii=False, indent=2) + "\n")
print(f"Created {len(results)} six-frame native-pixel GIFs")

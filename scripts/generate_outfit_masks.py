#!/usr/bin/env python3
"""Build non-destructive human outfit mask candidates from existing pixels.

The result is a draft for visual review, not an assertion of semantic accuracy.
No original artwork is written. Pillow is needed only for the review images.
"""
import colorsys
import json
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "godot/content/characters/human-starter.json"
OUTPUT = ROOT / "godot/content/outfits/human-starter.json"
PREVIEWS = ROOT / "production/evidence/run-outfit-2/mask-previews"
COLORS = {"top": (255, 100, 100), "bottom": (100, 255, 100), "shoes": (110, 180, 255), "head": (255, 100, 255)}

def classify(x, y, rgba):
    r, g, b, a = (v / 255 for v in rgba)
    if a < .15:
        return None
    h, s, v = colorsys.rgb_to_hsv(r, g, b)
    # Boxes are deliberately conservative; candidates are reviewable separately.
    if y < 57 and .075 <= h <= .18 and s >= .30 and v >= .55 and g >= b * 1.25:
        return "head"
    if 70 <= y < 113 and .48 <= h <= .68 and s >= .20 and b > r * 1.12:
        return "bottom"
    if 98 <= y < 126 and .025 <= h <= .12 and s >= .25 and v <= .72 and r > b * 1.15:
        return "shoes"
    if 78 <= y < 89 and 12 <= x < 84 and .06 <= h <= .18 and .07 <= s <= .30 and v >= .72:
        return "top"
    return None

def main():
    from collections import Counter
    art = json.loads(SOURCE.read_text())
    palette = [tuple(bytes.fromhex(c.lstrip("#"))) for c in art["palette"]]
    parts = {name: {"enabled": False, "colors": {}, "masks": {}, "inherit": {}} for name in COLORS}
    PREVIEWS.mkdir(parents=True, exist_ok=True)
    counts = Counter()
    for frame, layers in art["frames"].items():
        pixels = layers[0]["pixels"]
        original = Image.new("RGBA", (art["width"], art["height"]))
        original.putdata([palette[int(i)] for i in pixels])
        overlay = original.copy()
        for index, color_index in enumerate(pixels):
            x, y = index % art["width"], index // art["width"]
            part = classify(x, y, palette[int(color_index)])
            if part:
                parts[part]["masks"].setdefault(frame, []).append(index)
                overlay.putpixel((x, y), (*COLORS[part], 255))
                counts[part] += 1
        review = Image.new("RGBA", (art["width"] * 2, art["height"]), (43, 56, 49, 255))
        review.alpha_composite(original, (0, 0))
        review.alpha_composite(overlay, (art["width"], 0))
        review.resize((art["width"] * 4, art["height"] * 2), Image.Resampling.NEAREST).save(PREVIEWS / (frame + ".png"))
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT.write_text(json.dumps({"version": 1, "artwork_id": art["id"], "parts": parts, "manual_overrides": {}, "status": "candidate_needs_review"}, ensure_ascii=False))
    # A temporary review palette exercises the masks using only existing colors.
    hues = {"top": .58, "bottom": .04, "shoes": .57, "head": .55}
    hsv = [colorsys.rgb_to_hsv(*(c / 255 for c in rgba[:3])) for rgba in palette]
    candidates = [i for i, rgba in enumerate(palette) if rgba[3] >= 240]
    for name, part in parts.items():
        indices = {int(art["frames"][frame][0]["pixels"][pixel]) for frame, mask in part["masks"].items() for pixel in mask}
        for index in indices:
            _, saturation, brightness = hsv[index]
            rgb = colorsys.hsv_to_rgb(hues[name], max(.30, saturation), brightness)
            part["colors"][str(index)] = min(candidates, key=lambda i: sum((palette[i][c] / 255 - rgb[c]) ** 2 for c in range(3)))
        part["enabled"] = True
    (PREVIEWS.parent / "human-starter-review-outfit.json").write_text(json.dumps(parts, ensure_ascii=False))
    print("frames", len(art["frames"]), "pixel counts", dict(counts), "manual overrides", 0)

if __name__ == "__main__":
    main()

"""Pack each PixelLab character into one lossless runtime PNG, preserving native canvases.

Original frames remain in playground (ignored by Godot). A runtime manifest maps
logical frame names to atlas rectangles, original alpha bounds and grounded feet.
Identical frames within a character share a rectangle. Run after any art import.
"""
import hashlib
import json
import math
from pathlib import Path
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets/characters/playground"
DEST = ROOT / "assets/characters/sheets"
PADDING = 2


def arrange(images):
    """Deterministic shelf packing retains original dimensions/orientation and transparent gutters."""
    ordered = sorted(images, key=lambda key: (-images[key].height, -images[key].width, key))
    area = sum((im.width + PADDING * 2) * (im.height + PADDING * 2) for im in images.values())
    width = max(256, max(im.width + PADDING * 2 for im in images.values()), math.ceil(math.sqrt(area) / 64) * 64)
    x = y = row_height = used_width = 0
    positions = {}
    for key in ordered:
        image = images[key]
        cell_width, cell_height = image.width + PADDING * 2, image.height + PADDING * 2
        if x + cell_width > width:
            y += row_height
            x = row_height = 0
        positions[key] = [x + PADDING, y + PADDING, image.width, image.height]
        x += cell_width
        used_width = max(used_width, x)
        row_height = max(row_height, cell_height)
    height = y + row_height
    return positions, (math.ceil(used_width / 4) * 4, math.ceil(height / 4) * 4)


def build_sheets():
    """Build all character sheets, portrait resources and baked metadata without changing a source pixel."""
    definitions = json.loads((SOURCE / "manifest.json").read_text(encoding="utf-8"))
    DEST.mkdir(parents=True, exist_ok=True)
    characters = {}
    total_frames = unique_frames = source_bytes = packed_bytes = 0
    for key, definition in sorted(definitions.items()):
        folder = SOURCE / key
        images, frame_ids, digest = {}, {}, hashlib.sha256()
        for path in sorted(folder.rglob("*.png")):
            if path.name == "sheet.png":
                continue
            relative = path.relative_to(folder).as_posix()
            image = Image.open(path).convert("RGBA")
            identity = hashlib.sha256(str(image.size).encode() + image.tobytes()).hexdigest()
            images.setdefault(identity, image)
            frame_ids[relative] = identity
            digest.update(relative.encode() + image.tobytes())
            source_bytes += path.stat().st_size
        positions, size = arrange(images)
        sheet = Image.new("RGBA", size, (0, 0, 0, 0))
        for identity, image in images.items():
            x, y, _, _ = positions[identity]
            sheet.paste(image, (x, y))
        records = {}
        for relative, identity in frame_ids.items():
            image = images[identity]
            bounds = image.getchannel("A").getbbox() or (0, 0, 0, 0)
            records[relative] = {"region": positions[identity],
                                 "bounds": [bounds[0], bounds[1], bounds[2]-bounds[0], bounds[3]-bounds[1]],
                                 "foot": bounds[3] - image.height / 2}
        if "idle.png" not in records or "rotations/south.png" not in records:
            raise ValueError(f"Missing idle/front pose for {key}")
        output = DEST / (key + ".png")
        sheet.save(output, optimize=True)
        x, y, width, height = records["rotations/south.png"]["region"]
        portrait = ('[gd_resource type="AtlasTexture" load_steps=2 format=3]\n\n'
                    f'[ext_resource type="Texture2D" path="res://assets/characters/sheets/{key}.png" id="1"]\n\n'
                    '[resource]\natlas = ExtResource("1")\n'
                    f'region = Rect2({x}, {y}, {width}, {height})\nfilter_clip = true\n')
        (DEST / (key + ".portrait.tres")).write_text(portrait, encoding="utf-8")
        characters[key] = {"definition": definition, "sheet_size": list(size),
                           "source_hash": digest.hexdigest(), "frames": records}
        total_frames += len(records)
        unique_frames += len(images)
        packed_bytes += output.stat().st_size
    (DEST / "manifest.json").write_text(json.dumps({"format_version": 1, "characters": characters}, indent=2) + "\n", encoding="utf-8")
    print(f"Built {len(characters)} sheets: {total_frames} logical frames, {unique_frames} unique regions; "
          f"{source_bytes:,} source PNG bytes -> {packed_bytes:,} sheet PNG bytes")


if __name__ == "__main__":
    build_sheets()

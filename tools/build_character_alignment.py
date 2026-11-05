"""Bake native PNG foot positions so gameplay never reads textures back from the GPU.

Run after importing/changing playground characters. Also rebuilds runtime
spritesheets and their bounds manifest; Pillow remains a build-time dependency.
"""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ART = ROOT / "assets/characters/playground"


def build_alignment():
    """Bake source alpha bounds, then rebuild the one-sheet-per-character runtime assets."""
    from PIL import Image

    manifest = json.loads((ART / "manifest.json").read_text(encoding="utf-8"))
    characters = {}
    for key in sorted(manifest):
        folder = ART / key
        feet = {}
        digest = hashlib.sha256()
        for path in sorted(folder.rglob("*.png")):
            relative = path.relative_to(folder).as_posix()
            digest.update(relative.encode("utf-8"))
            digest.update(path.read_bytes())
            with Image.open(path) as image:
                bounds = image.convert("RGBA").getchannel("A").getbbox()
                bottom = bounds[3] if bounds else 0
                feet[relative] = bottom - image.height / 2.0
        if "idle.png" not in feet:
            raise ValueError(f"Missing idle sprite for {key}")
        characters[key] = {"source_hash": digest.hexdigest(), "feet": feet}
    result = {"format_version": 1, "characters": characters}
    output = ART / "alignment.json"
    output.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    count = sum(len(value["feet"]) for value in characters.values())
    print(f"Baked alignment for {len(characters)} characters / {count} frames")
    from build_character_sheets import build_sheets
    build_sheets()


if __name__ == "__main__":
    build_alignment()

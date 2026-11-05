"""Install the twenty reviewed adventurer sprites and rebuild runtime foot alignment.

Copies existing accepted PNGs only; no PixelLab jobs or image transformations.
Run from any directory after exports/repaired-character-animations is present.
"""
import json
import shutil
from pathlib import Path

from build_character_alignment import build_alignment

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "exports/repaired-character-animations"
ART = ROOT / "assets/characters/playground"
KEYS = (
    "porcupine-barbarian marmot-berserker dormouse-rogue flying-squirrel-ranger "
    "tamia-hunter jerboa-scout dormouse-witch rat-warlock red-squirrel-druid "
    "porcupine-shaman mouse-summoner chinchilla-alchemist guinea-pig-cleric "
    "marmot-monk lemming-healer tamia-bard jerboa-jester rat-pirate "
    "beaver-blacksmith guinea-pig-merchant"
).split()


def main():
    """Install accepted frames, preserve older art, then rebuild source alignment and the runtime character sheets."""
    metadata = json.loads((SOURCE / "manifest.json").read_text(encoding="utf-8"))["characters_metadata"]
    manifest = json.loads((ART / "manifest.json").read_text(encoding="utf-8"))
    for key in KEYS:
        source = SOURCE / key
        data = metadata[key]
        for path in source.rglob("*.png"):
            if path.name in ("sheet.png",):
                continue
            relative = path.relative_to(source)
            destination = ART / key / relative
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(path, destination)
        manifest[key] = {
            "name": data["name"],
            "sit_id": data["character_id"],
            "stand_id": data["character_id"],
            "stand_count": data["clips"]["stand"]["count"],
            "action_count": data["clips"]["action"]["count"],
            "walk_counts": {direction: clip["count"] for direction, clip in data["clips"]["walk"].items()},
        }
    (ART / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    build_alignment()
    print(f"Installed {len(KEYS)} adventurer characters")


if __name__ == "__main__":
    main()

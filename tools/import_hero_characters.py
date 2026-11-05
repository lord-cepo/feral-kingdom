"""Import the reviewed crowned PixelLab packs and rebuild shared runtime character sheets."""
import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'exports/hero-sprites/pixellab'
DEST = ROOT / 'assets/characters/playground'
DIRECTIONS = ['south', 'south-west', 'west', 'north-west', 'north', 'north-east', 'east', 'south-east']


def copy_frame(source, destination):
    """Copy one reviewed PNG byte-for-byte; importing never changes pixels, scale or animation order."""
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)


def main():
    """Append the three hero appearances without touching older definitions, then bake runtime atlases and anchors."""
    reviewed = json.loads((SOURCE / 'manifest.json').read_text())['characters']
    path = DEST / 'manifest.json'
    manifest = json.loads(path.read_text())
    for key, hero in reviewed.items():
        source, target = SOURCE / key, DEST / key
        counts = {}
        for direction in DIRECTIONS:
            copy_frame(source / 'rotations' / f'{direction}.png', target / 'rotations' / f'{direction}.png')
            copy_frame(source / 'idle.png', target / 'seated' / f'{direction}.png')
            count = hero['clips']['walk/' + direction]['count']
            counts[direction] = count
            for index in range(count):
                relative = f'walk/{direction}/frame_{index:03}.png'
                copy_frame(source / relative, target / relative)
        copy_frame(source / 'idle.png', target / 'idle.png')
        for clip in ['stand', 'action']:
            for index in range(hero['clips'][clip]['count']):
                relative = f'{clip}/frame_{index:03}.png'
                copy_frame(source / relative, target / relative)
        manifest[key] = dict(name=hero['name'], stand_id=hero['id'], sit_id=hero['id'],
                             stand_count=hero['clips']['stand']['count'], action_count=hero['clips']['action']['count'],
                             walk_counts=counts, mirrored_walks={},
                             missing_clips=['seated:' + d for d in DIRECTIONS if d != 'south'],
                             rise_source='reversed reviewed south sit-down; exact standing endpoints')
    path.write_text(json.dumps(manifest, indent=2) + '\n')
    from build_character_alignment import build_alignment
    build_alignment()


if __name__ == '__main__':
    main()

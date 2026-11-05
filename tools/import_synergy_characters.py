"""Import the 28 existing PixelLab bundles without generating or redrawing art.

The export contains five walk directions, one sitting-down clip and one action.
The rise reuses sitting frames in reverse. Missing westward walks mirror the
matching eastward cycle; missing seated directions use the south sitting pose.
"""
import concurrent.futures
import json
import urllib.request
from pathlib import Path
from zipfile import ZipFile

from PIL import Image, ImageOps
from io import BytesIO

ROOT = Path(__file__).resolve().parents[1]
CACHE = ROOT / '.tools/synergy-20261028'
DEST = ROOT / 'assets/characters/playground'
DIRECTIONS = ['south', 'south-west', 'west', 'north-west', 'north', 'north-east', 'east', 'south-east']
MIRROR_SOURCES = {'west': 'east', 'north-west': 'north-east', 'south-west': 'south-east'}
REPAIRED_ART = ROOT / 'exports/repaired-character-animations'


def apply_reviewed_repairs(character, definition, repairs):
    """Let main overlay an accepted local pack after native import, retaining original source ZIPs."""
    key = character['key']
    if key not in repairs:
        return definition
    repair = repairs[key]
    source_root = REPAIRED_ART / key
    destination = DEST / key
    for direction in DIRECTIONS:
        count = repair['clips']['walk'][direction]['count']
        for index in range(count):
            relative = f'walk/{direction}/frame_{index:03}.png'
            (destination / relative).write_bytes((source_root / relative).read_bytes())
        definition['walk_counts'][direction] = count
    if repair['action_repaired']:
        count = repair['clips']['action']['count']
        for index in range(count):
            relative = f'action/frame_{index:03}.png'
            (destination / relative).write_bytes((source_root / relative).read_bytes())
        definition['action_count'] = count
    definition['animation_repairs'] = {
        'walk_group': repair['walk_repair_group'],
        'action_repaired': repair['action_repaired'],
        'source': 'exports/repaired-character-animations',
    }
    definition['missing_clips'] = [item for item in definition['missing_clips']
                                   if not item.startswith('walk:')]
    return definition


def download(character):
    """Fetch an owned, already-generated character ZIP once; preserve cache on retry."""
    path = CACHE / (character['key'] + '.zip')
    if not path.exists():
        urllib.request.urlretrieve(
            'https://api.pixellab.ai/mcp/characters/' + character['id'] + '/download', path)
    with ZipFile(path) as bundle:
        if bundle.testzip():
            raise ValueError('Corrupt PixelLab bundle: ' + character['key'])
    return character


def import_character(character):
    """Import native clips and exact westward mirrors for BoardCharacter's frame arrays."""
    key = character['key']
    with ZipFile(CACHE / (key + '.zip')) as bundle:
        names = bundle.namelist()
        rotations = {d: next(n for n in names if n.endswith('/rotations/' + d + '.png') or n == 'rotations/' + d + '.png') for d in DIRECTIONS}
        animation_names = [n for n in names if '/animations/' in '/' + n and n.endswith('.png')]

        def frames(group, direction='south'):
            """Choose one exact native group, never merge repair pilots into an original clip."""
            group_name = 'sitting_down' if group == 'sitting' else group
            candidates = [n for n in animation_names
                          if n.split('/animations/', 1)[1].split('/')[0] == group_name
                          and '/' + direction + '/' in n]
            return sorted(candidates, key=lambda n: int(Path(n).stem.split('_')[-1]))

        def copy(source, relative, mirror=False):
            """Preserve source PNG bytes, or reflect one frame without resampling its pixels."""
            target = DEST / key / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            original = bundle.read(source)
            if mirror:
                with Image.open(BytesIO(original)) as image:
                    ImageOps.mirror(image).save(target)
            else:
                target.write_bytes(original)

        sitting = frames('sitting')
        if not sitting:
            raise ValueError('Missing sitting clip: ' + key)
        action = [n for n in animation_names if 'walk' not in n.lower() and 'sitting' not in n.lower()]
        action = sorted(action, key=lambda n: int(Path(n).stem.split('_')[-1]))
        if not action:
            raise ValueError('Missing action clip: ' + key)
        copy(sitting[-1], 'idle.png')
        for index, source in enumerate(reversed(sitting)):
            copy(source, f'stand/frame_{index:03}.png')
        for index, source in enumerate(action):
            copy(source, f'action/frame_{index:03}.png')
        counts = {}
        mirrored_walks = {}
        missing = ['seated:' + d for d in DIRECTIONS if d != 'south']
        for direction in DIRECTIONS:
            copy(rotations[direction], 'rotations/' + direction + '.png')
            copy(sitting[-1], 'seated/' + direction + '.png')
            walk = frames('walk', direction)
            mirror = False
            if not walk and direction in MIRROR_SOURCES:
                source_direction = MIRROR_SOURCES[direction]
                walk = frames('walk', source_direction)
                mirror = bool(walk)
                if mirror:
                    mirrored_walks[direction] = source_direction
            if not walk:
                missing.append('walk:' + direction)
                walk = [rotations[direction]]
            for index, source in enumerate(walk):
                copy(source, f'walk/{direction}/frame_{index:03}.png', mirror)
            counts[direction] = len(walk)
        return {'name': character['name'], 'stand_id': character['id'], 'sit_id': character['id'],
                'stand_count': len(sitting), 'action_count': len(action),
                'walk_counts': counts, 'missing_clips': missing,
                'mirrored_walks': mirrored_walks,
                'rise_source': 'reversed native sitting-down clip'}


def main():
    """Import/repair the roster, preserve older mappings, and rebuild alignment plus runtime character sheets."""
    CACHE.mkdir(parents=True, exist_ok=True)
    characters = json.loads((ROOT / 'tools/synergy_characters.json').read_text(encoding='utf-8'))
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(download, characters))
    manifest_path = DEST / 'manifest.json'
    manifest = json.loads(manifest_path.read_text(encoding='utf-8'))
    repair_manifest = REPAIRED_ART / 'manifest.json'
    repairs = json.loads(repair_manifest.read_text(encoding='utf-8'))['characters_metadata'] if repair_manifest.exists() else {}
    for character in characters:
        manifest[character['key']] = apply_reviewed_repairs(character, import_character(character), repairs)
        print(character['key'], flush=True)
    manifest_path.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    from build_character_alignment import build_alignment
    build_alignment()


if __name__ == '__main__':
    main()

"""Read-only asset dependency audit, including dynamically constructed animation paths."""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
ASSETS = ROOT / 'assets'
RESOURCE_PATH = re.compile(r'res://assets/[A-Za-z0-9_./%\-]+')
EFFECT_COUNTS = {'bomb-explosion': 9, 'bomb-ignite': 9, 'bow': 7, 'cannon': 9,
                 'fire': 11, 'mshield': 9, 'pull-icons': 9, 'push-icons': 9,
                 'push-pull': 9, 'shield': 9, 'skull': 9, 'slash': 8,
                 'sleeping': 9, 'stun': 9, 'trigger': 8}


def required_assets():
    """Return static resources plus explicit runtime animation families; never infer unused from literal references alone."""
    required = set()
    sources = [ROOT / 'project.godot']
    for folder in ['scripts', 'scenes', 'assets']:
        sources.extend(p for p in (ROOT / folder).rglob('*')
                       if p.suffix in {'.gd', '.tscn', '.tres', '.gdshader'})
    for source in sources:
        text = '\n'.join(line for line in source.read_text(encoding='utf-8').splitlines()
                         if not line.lstrip().startswith('#'))
        for resource in RESOURCE_PATH.findall(text):
            path = ROOT / resource.removeprefix('res://')
            if '%' not in resource and not resource.endswith('/'):
                required.add(path)
    manifest = ASSETS / 'characters/sheets/manifest.json'
    required.add(manifest)
    for key in json.loads(manifest.read_text(encoding='utf-8'))['characters']:
        required.update([manifest.parent / (key + '.png'), manifest.parent / (key + '.portrait.tres')])
    # ActionReplay also looks up named fallback icons, not just GameIcons.action_path literals.
    required.update((ASSETS / 'icons/ui').glob('*.png'))
    for name, count in EFFECT_COUNTS.items():
        required.update(ASSETS / 'effects' / name / f'frame_{index}.png' for index in range(count))
    for name in ['grass-tall', 'grass-bush', 'tornado', 'wind']:
        required.update(ASSETS / 'environment' / name / f'frame_{index:03}.png' for index in range(9))
    for color in ['red', 'blue']:
        required.update(ASSETS / 'environment/banner' / color / f'frame_{index}.png' for index in range(9))
    for name in ['ELR_SpringlLeaf.png', 'ELR_FallLeaf.png', 'ELR_WinterlLeaf.png']:
        required.add(ASSETS / 'environment/windy-leaves' / name)
    required.update(ASSETS / 'ui/inn-sign' / f'frame_{index}.png' for index in range(9))
    required.update(ASSETS / 'ui/parchment' / f'frame_{index}.png' for index in range(7))
    # Keep font comparison resources and all attribution/license documents.
    required.update((ASSETS / 'fonts').glob('*.ttf'))
    required.update(p for p in ASSETS.rglob('*') if p.suffix.lower() in {'.md', '.txt'})
    for path in list(required):
        for suffix in ['.import', '.uid']:
            companion = Path(str(path) + suffix)
            if companion.is_file(): required.add(companion)
    return required


def audit():
    """Report missing dependencies and unused files without deleting or rewriting anything; callable by maintenance scripts."""
    required = required_assets()
    actual = {p for p in ASSETS.rglob('*') if p.is_file()}
    return {'missing': sorted(str(p.relative_to(ROOT)).replace('\\', '/') for p in required if not p.is_file()),
            'unused': sorted(str(p.relative_to(ROOT)).replace('\\', '/') for p in actual - required),
            'required_files': len(required),
            'asset_bytes': sum(p.stat().st_size for p in actual)}


if __name__ == '__main__':
    result = audit()
    print(json.dumps(result, indent=2))
    raise SystemExit(1 if result['missing'] else 0)

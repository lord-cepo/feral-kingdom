"""Package Godot's catalogue export as a standalone, offline editable HTML table."""
import base64
from io import BytesIO
import html
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def reference_units():
    """Read literal catalogue records from the JS reference; never execute or rewrite that project."""
    source = (ROOT.parent / 'guerra.game/game/cards.ts').read_text(encoding='utf-8')
    source = source.split('const cardSources:', 1)[1].split('export const troopSeeds:', 1)[0]
    source = re.sub(r'//[^\n]*', '', source)
    records = []
    for match in re.finditer(r'\{\s*id:\s*\x27([^\x27]+)\x27(.*?)\}', source, re.S):
        key, body = match.groups()
        def string(field, fallback=''):
            found = re.search(r'\b' + field + r':\s*\x27([^\x27]*)\x27', body)
            return found[1] if found else fallback
        rules = re.search(r'\brules:\s*\[(.*?)\]', body, re.S)
        printed = re.findall(r"'((?:\\.|[^'\\])*)'", rules[1]) if rules else []
        passive = string('passives')
        if passive:
            printed.append('Passive: ' + passive)
        name = string('name', key.replace('-', ' ').title())
        records.append({'id': key, 'name': name, 'kind': string('role', 'troop').capitalize(),
                        'life': int(re.search(r'baseHealth:\s*(\d+)', body)[1]),
                        'deployment': string('deploymentRegions').title(), 'rules': printed})
    return records


def reference_hover(record, data):
    """Explain reference-only terminology without claiming the card has been ported into Godot."""
    notes = ['JS reference definition. This unit has not been implemented in the Godot catalogue.',
             'Printed reference wording:\n' + '\n'.join(record['rules']),
             'Reference shorthand: self = this unit; _ = any matching participant; o:you/o:opp = friendly/enemy; subj/obj = event actor/target; adj = adjacent; r: = region; p: = property.']
    for key, explanation in data['glossary'].items():
        if any(re.search(r'\b' + re.escape(key) + r'\b', line, re.I) for line in record['rules']):
            notes.append(explanation)
    if record['kind'] == 'Temple':
        notes.append('The intended Godot rules make temples immovable. JS reference wording is preserved here for comparison.')
    if record['kind'] == 'Hero':
        notes.append('Hero: first deployment; its defeat causes its owner to lose.')
    if 'Enemy' in record['deployment']:
        notes.append('Enemy deployment is a special reference deployment condition; the full printed deployment wording is preserved.')
    return '\n\n'.join(notes)


def image_data(resource):
    """Embed project-owned images, cropping generated AtlasTexture portraits from their shared sheet for offline HTML."""
    path = (ROOT / resource.removeprefix('res://')).resolve()
    if not path.is_relative_to(ROOT) or not path.is_file():
        return ''
    if path.name.endswith('.portrait.tres'):
        from PIL import Image
        key = path.name.removesuffix('.portrait.tres')
        metadata = json.loads((path.parent / 'manifest.json').read_text(encoding='utf-8'))
        x, y, width, height = metadata['characters'][key]['frames']['rotations/south.png']['region']
        image = Image.open(path.parent / (key + '.png')).crop((x, y, x + width, y + height))
        output = BytesIO()
        image.save(output, format='PNG')
        return 'data:image/png;base64,' + base64.b64encode(output.getvalue()).decode()
    return 'data:image/png;base64,' + base64.b64encode(path.read_bytes()).decode()


def description(key, data):
    """Use the game's glossary and occurrence-specific F/T/P/A explanations."""
    parts = key.split(':')
    text = data['glossary'].get(parts[0], '')
    if len(parts) > 1:
        for marker in 'FTPA':
            if marker in parts[1]:
                text += '\n' + data['stickers'][marker]
    return text


def render_rule(text, data):
    """Convert the game's supported BBCode subset into escaped, inert HTML."""
    text = re.sub(r' \([+-]0\)$', '', text)  # live Pikeman value is not printed card data
    tips = []
    text = text.replace('[lb]', '\ue000').replace('[rb]', '\ue001')
    tokens = re.split(r'(\[img[^\]]*\][^\[]+\[/img\]|\[[^\]]*\])', text)
    result = []
    for token in tokens:
        if token.startswith('[img'):
            resource = re.search(r'\](.+)\[/img\]', token)[1]
            label = next((k for k, v in data['icons'].items() if v == resource), resource.split('/')[-1].split('.')[0])
            result.append('<img class="rule-icon" alt="' + html.escape(label, quote=True) + '" src="' + image_data(resource) + '">')
        elif token.startswith('[url=guide:'):
            tip = description(token[len('[url=guide:'):-1], data)
            if tip and tip not in tips:
                tips.append(tip)
            result.append('<span tabindex="0" class="term" data-tip="' + html.escape(tip, quote=True) + '">')
        elif token.startswith('[color='):
            color = token[7:-1]
            result.append('<span style="color:' + (color if re.fullmatch(r'#[0-9a-fA-F]{6,8}', color) else 'inherit') + '">')
        elif token in ['[/url]', '[/color]', '[/font_size]']:
            result.append('</span>')
        elif token.startswith('[font_size='):
            result.append('<span>')
        elif token in ['[b]', '[u]']:
            result.append('<strong>' if token == '[b]' else '<u>')
        elif token in ['[/b]', '[/u]']:
            result.append('</strong>' if token == '[/b]' else '</u>')
        else:
            result.append(html.escape(token).replace('\ue000', '[').replace('\ue001', ']'))
    return ''.join(result), tips


def plain_rule(text, data):
    """Keep editable rule text readable by naming icons instead of exposing asset paths."""
    def icon(match):
        path = match[1]
        key = next((k for k, v in data['icons'].items() if v == path), path.split('/')[-1].split('.')[0])
        return '(' + ('walk' if key == 'move' else key) + ')'
    text = re.sub(r'\[img[^\]]*\]([^\[]+)\[/img\]', icon, text)
    text = re.sub(r'\[(?:/?(?:url|color|font_size|b|u))[^\]]*\]', '', text)
    return re.sub(r' \([+-]0\)$', '', text).replace('[lb]', '[').replace('[rb]', ']')


def main():
    """Read freshly exported definitions and embed data/art in the HTML template."""
    data = json.loads((ROOT / '.godot/unit-catalogue-data.json').read_text(encoding='utf-8'))
    references = reference_units()
    by_id = {unit['id']: unit for unit in data['units']}
    for unit in data['units']:
        unit['implemented'] = True
        unit['aliases'] = ''
    for unit in data['units']:
        tips = []
        rich = []
        for effect in unit['effects']:
            markup, explanations = render_rule(effect, data)
            rich.append(markup)
            for tip in explanations:
                if tip not in tips:
                    tips.append(tip)
        unit['richEffects'] = rich
        unit['effects'] = '\n'.join(plain_rule(s, data) for s in unit['effects'])
        unit['hover'] = '\n\n'.join(tips) or 'This unit uses the standard activity, targeting and deployment rules.'
        if unit['kind'].lower() == 'temple':
            unit['hover'] = 'Temple: immovable after deployment, including forced movement.\n\n' + unit['hover']
        if unit['kind'].lower() == 'hero':
            unit['hover'] = 'Hero: must be deployed first. Defeating your hero loses the match.\n\n' + unit['hover']
        unit['portrait'] = image_data(unit['portrait']) if unit['portrait'] else ''
    for reference in references:
        existing = by_id.get(reference['id'])
        if existing:
            if reference['name'] != existing['name']:
                existing['aliases'] = reference['name']
            existing['hover'] += '\n\nJS reference (' + reference['name'] + '):\nLife: ' + str(reference['life']) + '\nDeployment: ' + reference['deployment'] + '\n' + '\n'.join(reference['rules']) + '\n\nThe table effects above use the current Godot definition, which may intentionally differ from the reference.'
            continue
        lines = reference['rules']
        unit = {**reference, 'implemented': False, 'aliases': '', 'effects': '\n'.join(lines),
                'richEffects': [html.escape(line) for line in lines], 'hover': reference_hover(reference, data),
                'portrait': '', 'in_roster': False, 'factory': ''}
        data['units'].append(unit)
    data['reference_count'] = len(references)
    data['iconData'] = {key: image_data(path) for key, path in data['icons'].items()}
    payload = json.dumps(data, ensure_ascii=False).replace('<', '\\u003c')
    template = (ROOT / 'tools/unit_catalogue_template.html').read_text(encoding='utf-8')
    output = ROOT / 'unit-catalogue.html'
    script = (ROOT / 'tools/unit_catalogue.js').read_text(encoding='utf-8')
    output.write_text(template.replace('__CATALOGUE_DATA__', payload).replace('__CATALOGUE_SCRIPT__', script), encoding='utf-8')
    print(f'Built {output.name}: {len(data["units"])} units, {output.stat().st_size:,} bytes')


if __name__ == '__main__':
    main()

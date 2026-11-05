"""Package the three approved PixelLab heroes with native pixels and continuity evidence.

Run after downloading completed bundles into exports/hero-sprites/pixellab/source.
This prepares an art pack only; it does not change gameplay or the live roster.
"""
import io
import json
import argparse
from pathlib import Path
from zipfile import ZipFile, ZIP_DEFLATED

from PIL import Image, ImageDraw, ImageChops

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'exports/hero-sprites/pixellab'
DIRECTIONS = ['south', 'south-west', 'west', 'north-west', 'north', 'north-east', 'east', 'south-east']


def read_image(bundle, path):
    """Decode an original RGBA frame without resampling or altering its source archive."""
    return Image.open(io.BytesIO(bundle.read(path))).convert('RGBA')


def read_clip(bundle, group, direction):
    """Read exactly one named animation and direction, rejecting missing generated clips."""
    paths = [p for p in bundle.namelist() if f'/animations/{group}/{direction}/' in '/' + p and p.endswith('.png')]
    paths.sort(key=lambda p: int(Path(p).stem.split('_')[-1]))
    if not paths:
        raise ValueError(f'Missing {group}/{direction}')
    return [read_image(bundle, p) for p in paths]


def padded(image, canvas):
    """Center-pad onto one shared canvas, preserving every native pixel and its scale."""
    result = Image.new('RGBA', canvas)
    result.paste(image, ((canvas[0] - image.width) // 2, (canvas[1] - image.height) // 2))
    return result


def changed_pixels(a, b):
    """Measure visible frame differences for seam review, ignoring invisible RGB values."""
    bg_a = Image.new('RGBA', a.size, '#252b33')
    bg_b = bg_a.copy()
    bg_a.alpha_composite(a)
    bg_b.alpha_composite(b)
    return sum(pixel != (0, 0, 0) for pixel in ImageChops.difference(bg_a.convert('RGB'), bg_b.convert('RGB')).getdata())


def write_clip(folder, frames, loop):
    """Export PNGs, a grid and a correctly timed preview; only walk cycles loop."""
    folder.mkdir(parents=True, exist_ok=True)
    for i, frame in enumerate(frames):
        frame.save(folder / f'frame_{i:03}.png')
    w, h = frames[0].size
    columns = min(6, len(frames))
    sheet = Image.new('RGBA', (columns * w, ((len(frames) + columns - 1) // columns) * h))
    for i, frame in enumerate(frames):
        sheet.paste(frame, ((i % columns) * w, (i // columns) * h))
    sheet.save(folder / 'sheet.png')
    # GIF previews use a solid review background; deliverable PNGs retain alpha.
    preview = []
    for frame in frames:
        bg = Image.new('RGBA', frame.size, '#252b33')
        bg.alpha_composite(frame)
        preview.append(bg.convert('RGB').resize((w * 4, h * 4), Image.Resampling.NEAREST))
    args = dict(save_all=True, append_images=preview[1:], duration=100, disposal=2)
    if loop:
        args['loop'] = 0
    preview[0].save(folder / 'preview.gif', **args)
    transitions = [changed_pixels(a, b) for a, b in zip(frames, frames[1:])]
    seam = changed_pixels(frames[-1], frames[0]) if loop else None
    return dict(count=len(frames), canvas=list(frames[0].size), loop=loop,
                frame_duration_ms=100, adjacent_changes=transitions, seam_change=seam,
                seam_ratio=round(seam / max(1, sum(transitions) / len(transitions)), 3) if loop else None)


def main():
    """Prepare complete native art packs and contact sheets for visual review after generation."""
    jobs = json.loads((OUT.parent / 'pixellab-jobs.json').read_text())
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--only', help='Prepare one completed hero for review while others render.')
    args = parser.parse_args()
    report = {'art_resampled': False, 'characters': {}}
    portraits = []
    for hero in jobs['heroes']:
        key = hero['key']
        if args.only and key != args.only:
            continue
        with ZipFile(OUT / 'source' / f'{key}.zip') as bundle:
            if any(p.endswith('MISSING_FRAMES.txt') for p in bundle.namelist()):
                raise ValueError('Incomplete source archive: ' + key)
            rotations = {d: read_image(bundle, next(p for p in bundle.namelist() if p.endswith('/rotations/' + d + '.png'))) for d in DIRECTIONS}
            clips = {f'walk/{d}': read_clip(bundle, 'walk', d) for d in DIRECTIONS}
            clips['sitting'] = read_clip(bundle, 'sit_down', 'south')
            clips['action'] = read_clip(bundle, 'action', 'south')
        images = list(rotations.values()) + [f for clip in clips.values() for f in clip]
        canvas = (max(i.width for i in images), max(i.height for i in images))
        # Extra room is transparent; uniform canvas prevents crop-based position jumps.
        rotations = {d: padded(f, canvas) for d, f in rotations.items()}
        clips = {name: [padded(f, canvas) for f in frames] for name, frames in clips.items()}
        clips['stand'] = list(reversed(clips['sitting']))
        folder = OUT / key
        (folder / 'rotations').mkdir(parents=True, exist_ok=True)
        for direction, frame in rotations.items():
            frame.save(folder / 'rotations' / f'{direction}.png')
        clips['sitting'][-1].save(folder / 'idle.png')
        metadata = {name: write_clip(folder / name, frames, name.startswith('walk/')) for name, frames in clips.items()}
        metadata['continuity'] = {
            'standing_to_sit': changed_pixels(rotations['south'], clips['sitting'][0]),
            'standing_to_action': changed_pixels(rotations['south'], clips['action'][0]),
            'action_to_standing': changed_pixels(clips['action'][-1], rotations['south']),
            'sit_to_idle': 0, 'rise_is_exact_reverse': True,
        }
        feet = {name: [f.getchannel('A').getbbox()[3] - canvas[1] / 2 for f in frames] for name, frames in clips.items()}
        report['characters'][key] = dict(hero, clips=metadata, foot_offsets=feet)
        rows = [('rotations', list(rotations.values()))] + list(clips.items())
        cell = max(canvas) + 10
        contact = Image.new('RGB', (170 + max(len(fs) for _, fs in rows) * cell, len(rows) * (cell + 18)), '#252b33')
        draw = ImageDraw.Draw(contact)
        for row, (name, frames) in enumerate(rows):
            y = row * (cell + 18)
            draw.text((4, y + 8), name, fill='white')
            for i, f in enumerate(frames):
                contact.paste(f, (170 + i * cell, y + 16), f)
                draw.text((170 + i * cell, y), str(i), fill='white')
        contact.save(folder / 'review.png')
        portraits.append((hero['name'], rotations['south']))
    overview = Image.new('RGB', (600, 280), '#252b33')
    draw = ImageDraw.Draw(overview)
    for i, (name, frame) in enumerate(portraits):
        draw.text((i * 200 + 8, 10), name, fill='white')
        enlarged = frame.resize((frame.width * 2, frame.height * 2), Image.Resampling.NEAREST)
        overview.paste(enlarged, (i * 200 + (200 - enlarged.width) // 2, 45), enlarged)
    overview.save(OUT / 'heroes-preview.png')
    (OUT / 'manifest.json').write_text(json.dumps(report, indent=2) + '\n')
    with ZipFile(OUT.parent / 'pixellab-heroes.zip', 'w', ZIP_DEFLATED) as archive:
        for path in sorted(OUT.rglob('*')):
            if path.is_file() and 'source' not in path.relative_to(OUT).parts:
                archive.write(path, path.relative_to(OUT))
    print(json.dumps({k: v['clips']['continuity'] for k, v in report['characters'].items()}, indent=2))


if __name__ == '__main__':
    main()

"""Import the user's owned PixelLab Mshield object; preserve animation pixels and fit its text glyph to existing UI art."""
from io import BytesIO
from pathlib import Path
from zipfile import ZipFile
from PIL import Image

ROOT = Path(__file__).resolve().parents[1]


def main():
    """Copy all nine native frames and crop/nearest-resize only the UI icon to the established 48px source height."""
    folder = ROOT / 'assets/effects/mshield'
    folder.mkdir(parents=True, exist_ok=True)
    with ZipFile(ROOT / '.tools/mshield/source.zip') as bundle:
        image = Image.open(BytesIO(bundle.read('rotations/unknown.png'))).convert('RGBA')
        image.crop(image.getchannel('A').getbbox()).resize((48, 48), Image.Resampling.NEAREST).save(ROOT / 'assets/icons/ui/mshield.png')
        frames = sorted(p for p in bundle.namelist() if '/unknown/frame_' in p)
        if len(frames) != 9:
            raise ValueError('Expected the owned nine-frame Mshield animation')
        for index, path in enumerate(frames):
            (folder / f'frame_{index}.png').write_bytes(bundle.read(path))


if __name__ == '__main__':
    main()

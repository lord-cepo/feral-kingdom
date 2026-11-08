"""Validate the Godot macOS export and package an Apple Silicon playtest."""
import hashlib
import json
import plistlib
import re
import shutil
import struct
import tempfile
import zipfile
from pathlib import Path

from package_windows_release import ROOT, VERSION, source_commit, validate_pack

RAW_EXPORT = ROOT / 'exports/macos/FeralKingdom.zip'


def verify_app(archive):
    """Identify the app and verify its version, executable architecture and embedded signature."""
    contents, = [name.removesuffix('Info.plist') for name in archive.namelist()
                 if name.endswith('.app/Contents/Info.plist')]
    info = plistlib.loads(archive.read(contents + 'Info.plist'))
    if info['CFBundleShortVersionString'] != VERSION or info['CFBundleVersion'] != VERSION:
        raise RuntimeError('The macOS preset version does not match the release version.')
    executable = contents + 'MacOS/' + info['CFBundleExecutable']
    data = archive.read(executable)
    magic, cpu, _, file_type, count = struct.unpack_from('<5I', data)
    if (magic, cpu, file_type) != (0xfeedfacf, 0x0100000c, 2):
        raise RuntimeError('Expected a native Apple Silicon Mach-O executable.')
    position = 32
    for _ in range(count):
        command, size = struct.unpack_from('<2I', data, position)
        if command == 0x1d:
            offset, length = struct.unpack_from('<2I', data, position + 8)
            if length and offset + length <= len(data):
                break
        position += size
    else:
        raise RuntimeError('The Apple Silicon executable has no embedded signature.')
    pack, = [name for name in archive.namelist()
             if name.startswith(contents + 'Resources/') and name.endswith('.pck')]
    return executable, pack


def main():
    """Verify the game pack, retain ZIP modes and add playtest instructions and build identity beside the app."""
    commit = source_commit()
    archive_path = ROOT / f'exports/FeralKingdom-v{VERSION}-macos-arm64.zip'
    build = (ROOT / 'scripts/network/network_build.gd').read_text(encoding='utf-8')
    with zipfile.ZipFile(RAW_EXPORT) as raw:
        executable, pack = verify_app(raw)
        with tempfile.TemporaryDirectory(dir=RAW_EXPORT.parent) as temp:
            count = validate_pack(Path(raw.extract(pack, temp)))
    shutil.copyfile(RAW_EXPORT, archive_path)
    with zipfile.ZipFile(archive_path, 'a', compression=zipfile.ZIP_DEFLATED) as archive:
        if not archive.getinfo(executable).external_attr >> 16 & 0o111:
            raise RuntimeError('The export lost the macOS executable permission.')
        identity = dict(version=VERSION, platform='macos-arm64', godot='4.7.2',
                        source_commit=commit, rules_hash=re.search(r'RULES_HASH := "([a-f0-9]+)"', build)[1],
                        pack_files=count)
        archive.writestr('BUILD.json', json.dumps(identity, indent=2) + '\n')
        archive.writestr('README.txt',
                         f'FERAL KINGDOM - Apple Silicon playtest v{VERSION}\n\n'
                         'Extract the ZIP on a Mac and open the Feral Kingdom app.\n'
                         'The app is ad-hoc signed and has not been notarized.\n'
                         'For online play, use the same build version on both devices.\n')
        for path in sorted((ROOT / 'licenses/godot').rglob('*')):
            if path.is_file():
                archive.write(path, 'LICENSES/Godot/' + path.relative_to(ROOT / 'licenses/godot').as_posix())
        for name in ['Jersey10-OFL.txt', 'PixelifySans-OFL.txt']:
            archive.write(ROOT / 'assets/fonts' / name, 'LICENSES/' + name)
        archive.write(ROOT / 'assets/environment/windy-leaves/CREDITS.md', 'LICENSES/WindyLeaves.md')
        archive.write(ROOT / 'assets/icons/SOURCES.md', 'LICENSES/PixelLab-provenance.md')
    with zipfile.ZipFile(archive_path) as archive:
        if archive.testzip() is not None:
            raise RuntimeError('The completed macOS archive failed its CRC check.')
    with archive_path.open('rb') as stream:
        checksum = hashlib.file_digest(stream, 'sha256').hexdigest()
    archive_path.with_suffix('.zip.sha256').write_text(checksum + '  ' + archive_path.name + '\n', encoding='utf-8')
    print(f'Validated {count} payloads and the signed arm64 Mach-O executable.')
    print(archive_path.name, archive_path.stat().st_size, checksum)


if __name__ == '__main__':
    main()

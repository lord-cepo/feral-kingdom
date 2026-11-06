"""Validate exported release files and assemble the portable Windows ZIP without running gameplay tests."""
import hashlib
import json
import re
import shutil
import struct
import subprocess
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'exports/windows'
VERSION = '0.1.0'


def validate_pack(path):
    """Check the unencrypted Godot 4.7 PCK directory, every payload checksum and required non-resource JSON inputs."""
    entries = {}
    with path.open('rb') as pack:
        magic, version, major, minor, patch, flags, base, directory = struct.unpack('<6I2Q', pack.read(40))
        if magic != 0x43504447 or version != 4 or flags != 2 or (major, minor, patch) != (4, 7, 2):
            raise RuntimeError('Unexpected Godot release pack format/version/flags')
        pack.seek(directory)
        count, = struct.unpack('<I', pack.read(4))
        for _ in range(count):
            length, = struct.unpack('<I', pack.read(4))
            name = pack.read(length).rstrip(b'\0').decode('utf-8').removeprefix('res://')
            offset, size = struct.unpack('<2Q', pack.read(16))
            digest = pack.read(16)
            file_flags, = struct.unpack('<I', pack.read(4))
            if file_flags or name in entries: raise RuntimeError('Unexpected pack entry flags/duplicate')
            entries[name] = (base + offset, size, digest)
        for name, (offset, size, digest) in entries.items():
            pack.seek(offset)
            data = pack.read(size)
            if len(data) != size or hashlib.md5(data).digest() != digest:
                raise RuntimeError('Exported payload checksum failed: ' + name)
        for name in ['project.binary', 'assets/characters/sheets/manifest.json', 'assets/environment/grass-placements.json']:
            if name not in entries or not entries[name][1]: raise RuntimeError('Missing release input: ' + name)
        for name in ['assets/characters/sheets/manifest.json', 'assets/environment/grass-placements.json']:
            offset, size, _ = entries[name]
            pack.seek(offset)
            if pack.read(size) != (ROOT / name).read_bytes(): raise RuntimeError('Outdated packed JSON: ' + name)
        if any(name.startswith(('tools/', 'tests/', 'docs/', 'relay/', 'art-source/')) for name in entries):
            raise RuntimeError('Development-only files leaked into release pack')
    return count


def main():
    """Run after export; preserve the full runtime pair, ICU data, instructions, notices and reproducible build identity."""
    executable = OUTPUT / 'FeralKingdom.exe'
    image = executable.read_bytes()
    pe_offset, = struct.unpack_from('<I', image, 0x3c)
    if image[:2] != b'MZ' or image[pe_offset:pe_offset + 4] != b'PE\0\0' or struct.unpack_from('<H', image, pe_offset + 4)[0] != 0x8664:
        raise RuntimeError('Expected a Windows x86_64 executable')
    count = validate_pack(OUTPUT / 'FeralKingdom.pck')
    templates = ROOT / '.tools/godot/appdata/Godot/export_templates/4.7.2.stable'
    shutil.copy2(templates / 'icudt_godot.dat', OUTPUT / 'icudt_godot.dat')
    (OUTPUT / 'README.txt').write_text(
        'FERAL KINGDOM - Windows playtest v0.1.0\n\n'
        'Extract this entire ZIP, then double-click FeralKingdom.exe.\n'
        'Keep FeralKingdom.pck and icudt_godot.dat beside the executable.\n'
        'Godot does not need to be installed.\n\n'
        'Build and save an army with exactly one hero. One player chooses Host;\n'
        'the other chooses Find. Choose your deck and create or join a room;\n'
        'the match starts automatically. Both players need the same release.\n'
        'Internet is required for multiplayer; the relay is already configured.\n\n'
        'Development playtest: automated network, local match, presentation,\n'
        'selection, combat and relay checks passed. A full two-device\n'
        'multiplayer/reconnect session remains to be verified.\n\n'
        'Updates and issue reports: https://github.com/lord-cepo/feral-kingdom\n', encoding='utf-8')
    notices = OUTPUT / 'LICENSES'
    notices.mkdir(exist_ok=True)
    shutil.copytree(ROOT / 'licenses/godot', notices / 'Godot', dirs_exist_ok=True)
    for name in ['Jersey10-OFL.txt', 'PixelifySans-OFL.txt']:
        shutil.copy2(ROOT / 'assets/fonts' / name, notices / name)
    shutil.copy2(ROOT / 'assets/environment/windy-leaves/CREDITS.md', notices / 'WindyLeaves.md')
    shutil.copy2(ROOT / 'assets/icons/SOURCES.md', notices / 'PixelLab-provenance.md')
    build = (ROOT / 'scripts/network/network_build.gd').read_text(encoding='utf-8')
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    identity = {'version': VERSION, 'platform': 'windows-x86_64', 'godot': '4.7.2', 'source_commit': commit,
                'rules_hash': re.search(r'RULES_HASH := "([a-f0-9]+)"', build)[1], 'pack_files': count}
    (OUTPUT / 'BUILD.json').write_text(json.dumps(identity, indent=2) + '\n', encoding='utf-8')
    archive = ROOT / f'exports/FeralKingdom-v{VERSION}-windows-x86_64.zip'
    with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as zipped:
        for path in sorted(OUTPUT.rglob('*')):
            if path.is_file(): zipped.write(path, f'FeralKingdom-v{VERSION}/' + path.relative_to(OUTPUT).as_posix())
    checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
    checksum_path = Path(str(archive) + '.sha256')
    checksum_path.write_text(checksum + '  ' + archive.name + '\n', encoding='utf-8')
    print(f'Validated {count} exported payloads; Windows x86_64 runtime and JSON inputs present.')
    print(f'ZIP: {archive.name} ({archive.stat().st_size / 2**20:.1f} MiB)')
    print('SHA-256:', checksum)


if __name__ == '__main__': main()

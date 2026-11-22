"""Validate and package the portable Linux x86_64 release without running gameplay tests."""
import hashlib
import json
import re
import shutil
import struct
import tarfile
from pathlib import Path
from package_windows_release import VERSION, source_commit, validate_pack
ROOT = Path(__file__).resolve().parents[1]
OUTPUT = ROOT / 'exports/linux'

def main():
    """Check ELF architecture and PCK integrity, include notices, and preserve executable permissions in tar.gz."""
    executable = OUTPUT / 'FeralKingdom.x86_64'
    header = executable.read_bytes()[:64]
    if header[:6] != b'\x7fELF\x02\x01' or struct.unpack_from('<H', header, 18)[0] != 62:
        raise RuntimeError('Expected a little-endian Linux x86_64 ELF executable')
    count = validate_pack(OUTPUT / 'FeralKingdom.pck')
    shutil.copy2(ROOT / '.tools/godot/appdata/Godot/export_templates/4.7.2.stable/icudt_godot.dat', OUTPUT / 'icudt_godot.dat')
    (OUTPUT / 'README.txt').write_text(
        f'FERAL-KINGDOM - Linux x86_64 playtest v{VERSION}\n\n'
        'Extract the entire archive. Run ./FeralKingdom.x86_64 from its folder.\n'
        'If needed: chmod +x FeralKingdom.x86_64\n'
        'Keep FeralKingdom.pck and icudt_godot.dat beside the executable.\n'
        'A Linux desktop with Vulkan graphics support is required. Godot need not be installed.\n\n'
        'Choose your player name, then build and save an army with exactly one hero.\n'
        'Host: select settings and deck, then Create room. Find: choose deck and room.\n'
        'Both players choose Ready, then the host starts the match. Use matching builds.\n'
        'Internet is required for multiplayer. Windows and Linux builds share the same rules fingerprint.\n\n'
        'ELF architecture and package integrity checked. Linux runtime and live cross-platform\n'
        'multiplayer have not been verified on this Windows build machine.\n\n'
        'https://github.com/lord-cepo/feral-kingdom\n', encoding='utf-8')
    notices = OUTPUT / 'LICENSES'
    shutil.copytree(ROOT / 'licenses/godot', notices / 'Godot', dirs_exist_ok=True)
    for name in ['Jersey10-OFL.txt', 'PixelifySans-OFL.txt']:
        shutil.copy2(ROOT / 'assets/fonts' / name, notices / name)
    shutil.copy2(ROOT / 'assets/environment/windy-leaves/CREDITS.md', notices / 'WindyLeaves.md')
    shutil.copy2(ROOT / 'assets/icons/SOURCES.md', notices / 'PixelLab-provenance.md')
    build = (ROOT / 'scripts/network/network_build.gd').read_text(encoding='utf-8')
    commit = source_commit()
    identity = dict(version=VERSION, platform='linux-x86_64', godot='4.7.2', source_commit=commit,
                    rules_hash=re.search(r'RULES_HASH := "([a-f0-9]+)"', build)[1], pack_files=count)
    (OUTPUT / 'BUILD.json').write_text(json.dumps(identity, indent=2)+'\n', encoding='utf-8')
    archive = ROOT / f'exports/FeralKingdom-v{VERSION}-linux-x86_64.tar.gz'
    with tarfile.open(archive, 'w:gz') as tar:
        for path in sorted(OUTPUT.rglob('*')):
            if not path.is_file(): continue
            info = tar.gettarinfo(str(path), f'FeralKingdom-v{VERSION}/'+path.relative_to(OUTPUT).as_posix())
            info.mode = 0o755 if path == executable else 0o644
            with path.open('rb') as source: tar.addfile(info, source)
    with tarfile.open(archive) as tar:
        if tar.getmember(f'FeralKingdom-v{VERSION}/FeralKingdom.x86_64').mode != 0o755:
            raise RuntimeError('Archive lost executable permissions')
    checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
    Path(str(archive)+'.sha256').write_text(checksum+'  '+archive.name+'\n', encoding='utf-8')
    print(f'Validated {count} payloads; Linux ELF and executable permissions verified.')
    print(archive.name, archive.stat().st_size, checksum)

if __name__ == '__main__': main()

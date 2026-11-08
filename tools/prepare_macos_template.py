"""Add native arm64 slices to Godot's installed Universal macOS template ZIP."""
import copy
import shutil
import struct
import zipfile

from package_windows_release import ROOT

TEMPLATE = ROOT / '.tools/godot/appdata/Godot/export_templates/4.7.2.stable/macos.zip'
BINARIES = 'macos_template.app/Contents/MacOS/'


def arm_slice(data):
    """Read the arm64 Mach-O slice from the official Universal binary."""
    magic, count = struct.unpack_from('>2I', data)
    if magic != 0xcafebabe:
        raise RuntimeError('Expected a Universal Mach-O template.')
    for index in range(count):
        cpu, _, offset, size, _ = struct.unpack_from('>5I', data, 8 + index * 20)
        if cpu != 0x0100000c:
            continue
        result = data[offset:offset + size]
        if len(result) == size and struct.unpack_from('<2I', result) == (0xfeedfacf, cpu):
            return result
    raise RuntimeError('The Universal template has no valid Apple Silicon slice.')


def main():
    """Extend the installed ZIP atomically, preserving the official Universal entries."""
    with zipfile.ZipFile(TEMPLATE) as archive:
        missing = [f'{BINARIES}godot_macos_{mode}.arm64' for mode in ('release', 'debug')
                   if f'{BINARIES}godot_macos_{mode}.arm64' not in archive.namelist()]
    if not missing:
        print('Apple Silicon templates are already available.')
        return
    pending = TEMPLATE.with_name('macos-prepare.zip')
    shutil.copyfile(TEMPLATE, pending)
    try:
        with zipfile.ZipFile(pending, 'a', compression=zipfile.ZIP_DEFLATED) as archive:
            for name in missing:
                source = archive.getinfo(name.removesuffix('.arm64') + '.universal')
                info = copy.copy(source)
                info.filename = name
                archive.writestr(info, arm_slice(archive.read(source)))
                print('Prepared:', name)
        pending.replace(TEMPLATE)
    finally:
        pending.unlink(missing_ok=True)


if __name__ == '__main__':
    main()

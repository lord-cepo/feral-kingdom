"""Refresh the Windows game pack and assemble the existing launcher-compatible ZIP."""
import argparse
import filecmp
import os
import shutil
import subprocess
import tempfile
from pathlib import Path

import generate_network_fingerprint
import package_windows_release


def main():
    """Run from a Windows checkout with the project's Godot editor and export template installed."""
    root = package_windows_release.ROOT
    output = package_windows_release.OUTPUT
    godot_data = root / '.tools/godot/appdata'
    templates = godot_data / 'Godot/export_templates/4.7.2.stable'
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--godot', type=Path, default=root /
                        '.tools/godot/editor-4.7.2/Godot_v4.7.2-stable_win64_console.exe')
    args = parser.parse_args()
    editor = args.godot.resolve()
    runtime = templates / 'windows_release_x86_64.exe'
    for path in (editor, runtime, templates / 'icudt_godot.dat'):
        if not path.is_file():
            parser.error(f'Missing release input: {path}')

    # The Windows preset uses a separate pack and leaves executable resources
    # untouched. Reuse the installed release template as the runtime.
    env = {**os.environ, 'APPDATA': str(godot_data)}
    output.mkdir(parents=True, exist_ok=True)
    generate_network_fingerprint.main()
    with tempfile.TemporaryDirectory(dir=output.parent) as staging:
        pack = Path(staging) / 'FeralKingdom.pck'
        subprocess.run([str(editor), '--headless', '--path', str(root),
                        '--export-pack', 'Windows Desktop', str(pack)],
                       env=env, check=True)
        pack.replace(output / pack.name)

    executable = output / 'FeralKingdom.exe'
    if not executable.is_file() or not filecmp.cmp(runtime, executable, shallow=False):
        shutil.copy2(runtime, executable)
    package_windows_release.main([])


if __name__ == '__main__':
    main()

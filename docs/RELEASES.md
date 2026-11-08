# Feral Kingdom releases

Windows players can download **FeralKingdomLauncher.exe** once from
[GitHub Releases](https://github.com/lord-cepo/feral-kingdom/releases).
Open it to check for the newest numbered Windows playtest and start the game.
The first run requires internet access. If an update cannot be downloaded or
verified later, the launcher can open the newest complete installed version.
The Windows ZIP, Linux tarball and Apple Silicon macOS ZIP are available for
manual installation. On a Mac, extract the ZIP and open the Feral Kingdom app.
The macOS playtest uses an ad-hoc signature and has no Apple notarization.

The launcher installs under `%LOCALAPPDATA%/FeralKingdomLauncher/versions`.
Each successful install has its own version folder. The launcher checks the
ZIP's SHA-256 before extracting, checks the Windows runtime files and build
identity, then moves the complete install into place. Godot keeps saves and
armies in its separate user-data directory.

## Build and publish

1. Set the release number in `tools/generate_network_fingerprint.py` and run
   that script. Both platform builds use that version and rules fingerprint.
2. Set the macOS preset's two version fields to the same release number. Export
   **Windows Desktop**, **Linux** and **macOS Apple Silicon** with matching Godot
   release templates. For Apple Silicon, install Godot's official macOS
   template, then run `tools/prepare_macos_template.py` to expose its arm64 slices.
   Run `tools/package_windows_release.py`,
   `tools/package_linux_release.py` and `tools/package_macos_release.py` with
   Python to validate and package the exports.
3. Run `./tools/launcher/build.ps1` from the project root on Windows. It uses the
   Windows .NET Framework compiler and writes `exports/FeralKingdomLauncher.exe`.
4. Create a GitHub release tagged `vMAJOR.MINOR.PATCH` on the exact source
   commit. Attach the platform packages, their SHA-256 sidecars and the launcher,
   then publish. Preserve the generated archive names. The launcher includes
   numbered public playtests in its update check.

Windows updates currently download the complete Windows ZIP when the version
changes. Existing installs launch without downloading an unchanged build.

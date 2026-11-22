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

For a repeat Windows build, run `python tools/build_windows_release.py`.
It refreshes the rules fingerprint and game pack, reuses the Godot Windows
runtime, and produces the usual ZIP and SHA-256 sidecar. The ZIP uses faster
compression and may be larger. Set a new release number before packaging a
new public version. The shortcut uses the project's Godot 4.7.2 templates
and the current Windows preset with separate game data and untouched executable
resources.

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

## Windows download blocks

If the standalone launcher is blocked, the portable Windows ZIP is a separate
manual installation option. Use the numbered ZIP and its SHA-256 sidecar from
the same official release. Extract the entire archive and open
`FeralKingdom.exe` alongside its data files. Both multiplayer seats need the
same version. If Windows flags the portable build too, keep that detection
in place and report the exact alert. [GitHub Releases](https://github.com/lord-cepo/feral-kingdom/releases)

For a quarantine or malware alert, capture the security product, detection name,
and release version. On Microsoft Defender, find the entry in Windows Security
under Protection history. Match the SHA-256 of the affected download to the
published asset before submitting that exact executable as a software developer
for vendor review. [Windows Protection history](https://support.microsoft.com/en-us/windows/security/windows-security/protection-history-in-the-windows-security-app)
[Microsoft file submission](https://www.microsoft.com/en-us/wdsi/filesubmission)

For an unrecognized-app warning, use a consistent trusted publisher identity to
sign and timestamp the launcher and game executable before packaging and
generating checksums. Verify the signatures on the final files before publishing.
New signed binaries can still show a SmartScreen reputation warning.
[Microsoft SmartScreen guidance](https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation)

# Windows releases

Players download a release ZIP, extract the whole folder and run
`FeralKingdom.exe`. They do not need Godot, Python or access to the source project.
Runtime resources are shipped with the executable, including the `.pck` pack.

`export_presets.cfg` defines **Windows Desktop**, a release build for x86_64.
It exports runtime resources and explicitly includes the two JSON files read by
FileAccess: character sheet metadata and grass placement data. It excludes tools,
tests, docs, relay code, exports and editable art projects. Raw source PNG frames
and old card illustrations have already been removed from the client.

Install matching official export templates for the editor version; the first
release uses **Godot 4.7.2**. The Windows release template and optional ICU data
are sufficient for this target. Then run from the repository root:

```powershell
python tools/generate_network_fingerprint.py
godot --headless --editor --path . --import
godot --headless --path . --export-release "Windows Desktop" exports/windows/FeralKingdom.exe
python tools/package_windows_release.py
```

Package every generated runtime dependency with the executable and pack; do not
ship an `.exe` by itself when its `.pck` is external. Include launch instructions,
font/art credits, Godot's MIT license and a SHA-256 checksum for the ZIP.
`tools/package_windows_release.py` validates the Windows PE architecture, PCK
payload checksums, required JSON and excluded development paths, then packages
the runtime, ICU data, instructions, build identity and notices. It currently
uses the installed 4.7.2 template under `.tools/godot/appdata/Godot/export_templates`.
It does not launch the game or execute gameplay tests.
On restricted Windows environments, set TEMP/TMP to a writable build folder if
Godot reports a safe-save error for its temporary `project.binary`; an exporter
exit code alone does not prove the pack is complete.

Exported builds are ignored under `exports/`; upload them as GitHub release
assets rather than committing binaries to the source repository.

The first release is tagged `v0.1.0` and marked as a prerelease/playtest. Both
players must use the same source/rules fingerprint. A build/export check is
separate from gameplay regression tests; run those only when requested under
`AGENTS.md`'s TEST policy. A completed two-device match and reconnect check remain
release acceptance work.

## Linux x86_64

The Linux export preset uses the same runtime inputs and compatibility fingerprint as Windows. Install `linux_release.x86_64` from the official 4.7.2 templates alongside the shared ICU data, export with `--export-release Linux exports/linux/FeralKingdom.x86_64`, then run `python tools/package_linux_release.py`. The packager checks ELF x86_64 architecture and all PCK payloads and builds a tar.gz with executable permissions, notices, build identity and SHA-256. Extract the entire archive and run `./FeralKingdom.x86_64`. Linux runtime and cross-platform multiplayer verification require a Linux desktop; packaging on Windows does not establish those results.

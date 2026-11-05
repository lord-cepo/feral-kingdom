# Runtime assets

This folder contains the art/resources shipped with the playable Godot client.
Legacy card illustrations, individual character source frames, comparison art,
unused shaders and their orphan import/UID files were removed on 2026-11-05.

| Folder | Runtime use |
| --- | --- |
| `board/hexes/` | Red/blue/neutral hex frames, shared by HexCell and action replays. |
| `characters/sheets/` | One atlas per character, atlas-backed portraits and the baked frame/bounds manifest. |
| `effects/` | PixelLab attack, protection, damage, death, displacement, sleep, trigger and bomb ignition/explosion clips. |
| `environment/` | Grass, banner, paw prints, leaf sheets and optional wind/tornado animations. All numbered clips are directly in their named folder. |
| `fonts/` | Theme/font resources and their licenses. |
| `icons/board/` | Native PixelLab board bomb icon. |
| `icons/ui/` | Prepared text/action icons, hero crown and layout spacer. |
| `maps/` | PixelLab battlefield background. |
| `shaders/` | Shaders referenced by current presentation code. |
| `ui/` | Background, cursors, frames, signs and parchment button animation. |

The board uses `icons/board/bomb-unlit.png`, `effects/bomb-ignite/` and
`effects/bomb-explosion/`. The unused older `assets/bomb.png` is gone. Bow uses
its PixelLab clip; the old single-arrow comparison toggle was removed.

Keep `.import` files belonging to active images/fonts: they retain Godot import
settings and resource identities. Generated textures in `.godot/` remain local
and unversioned. Import files whose source no longer exists are unnecessary.

`python tools/audit_runtime_assets.py` reports missing dependencies and unused
files without changing anything. It includes explicitly numbered animation
families, the character atlas manifest, dynamic icon lookups and literal resource
references; searching only for image filenames would miss these dependencies.
Update its dynamic families whenever adding or changing a runtime clip.

Editable `.pxo` projects are preserved locally in the ignored `art-source/`
folder outside the game assets. The removed original character PNGs must be
reimported from PixelLab (or recovered from repository history) before running
the character alignment/sheet-building tools. Normal play requires neither.

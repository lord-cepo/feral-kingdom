# PixelLab runtime spritesheets

Implemented 2026-10-30 to reduce startup resource loading and editor imports.

`assets/characters/sheets/` contains **one transparent PNG per character**:
83 sheets, 7,101 logical source frames and 6,547 distinct packed rectangles.
Identical frames within one character share space. Total PNG size is 13,488,607
bytes, versus 19,031,307 bytes for the separate source PNGs. Largest sheet side
is 960 pixels. Packing preserves original pixels, canvas dimensions, directions,
clip order and foot positions; it does not repair or regenerate animation art.

Each `<character>.portrait.tres` is a front-facing AtlasTexture view of that same
PNG. `manifest.json` records the original frame names, sheet rectangles, original
alpha bounds/feet, clip counts, sheet sizes and source hashes. Rectangles are
compactly packed rather than arranged as animation rows; use the named manifest
entries to extract a particular clip or frame.

## Source editing and rebuilding

Original PNGs remain editable under `assets/characters/playground/<character>`.
They are preserved, not deleted. After replacing frames, run:

```powershell
python tools/build_character_sheets.py
```

Or run `python tools/build_character_alignment.py`, which rebuilds both the
source alignment file and sheets. The synergy/adventurer importers also invoke
this pipeline, so future imports cannot silently leave runtime sheets stale.
Pillow is a build-time dependency; no runtime Python dependency is introduced.

`tools/build_unit_catalogue.py` crops atlas portraits into PNG data URLs when
building the offline HTML catalogue, so it does not embed `.tres` text as an image.

## Runtime caller map

`LocalMatchController.start_match -> BoardCharacter.preload_art -> _art_for`
loads one PNG per supported character. `_cached_frame` creates lightweight
AtlasTexture views and indexes baked bounds/feet by texture identity.
`_cached_cycle` restores authored frame order independent of physical packing.
Both owners, stationary figures and travelling overlays reuse those same packs.
This replaces 6,412 individual board-animation texture loads with 83 shared PNGs.

`SideUnitPortrait._load_art` reuses the pack's seated/standing/rise views and
baked bounds. It no longer loads individual frame files or reads images back
from the GPU to calculate portrait bounds. Missing seated-direction images use
the existing front idle pose; no new animation is invented.

`BoardCharacter._show_frame/_show_facing` and `SideUnitPortrait._draw` send native
frame sizes and normalized current/previous atlas rectangles to the existing
pose-blending shaders. Previous-pose samplers use the underlying sheet plus its
rectangle. Foot grounding, smooth fades, activity greyscale and finite-animation
barriers retain their existing behavior.

`CardCatalogue.starter_army/all_units` return only PixelLab-supported cards.
`BoardCharacter.card_art_path/portrait_path` return sheet-backed portraits only;
legacy `assets/cards` fallback loading is removed. Current playable roster order
remains 83 unit types per player, preserving existing stable IDs.

## Ignored resources

`.gdignore` excludes these source/legacy directories from Godot imports:

- `exports/` — downloaded archives and review/export frames.
- `assets/characters/playground/` — editable original character frames.
- The superseded `assets/characters/mole-artificer`, `mouse-engineer` and
  `reed-archer` source packs.
- `assets/cards/`, `assets/sprites/` and `assets/A_mouse_archer_in_simple-Idle/`
  — previous-game portraits and unused character art.

Current board terrain, UI, fonts, shaders, icons, ambience and combat effects
remain available. Existing import-cache files may remain on disk; the game no
longer requests the ignored originals and no source files were deleted.

## Verification

Godot editor import and script/resource loading passed after the conversion;
the Blacksmith sheet was visually inspected. Regression routines were updated
but not run because this request did not end with `TEST`.

`tests/character_cache_test.tscn` now checks common-sheet identity, native canvas
sizes, exact PNG region/source pixels, baked bounds/feet and rejection of legacy
portrait fallbacks. `full_roster_test` verifies the catalogue API itself excludes
unsupported units. Run them together with presentation/local-match regressions
on the next authorized `TEST` request. See [TESTING.md](TESTING.md).

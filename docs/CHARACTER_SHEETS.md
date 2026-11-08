# PixelLab runtime spritesheets

Implemented 2026-10-30 to reduce startup resource loading and editor imports.

`assets/characters/sheets/` contains **one transparent PNG per character**.
The original conversion covered 83 sheets, 7,101 logical source frames and
6,547 distinct packed rectangles.
Identical frames within one character share space. Total PNG size is 13,488,607
bytes, versus 19,031,307 bytes for the separate source PNGs. Largest sheet side
is 960 pixels. Packing preserves original pixels, canvas dimensions, directions,
clip order and foot positions; it does not repair or regenerate animation art.

Each `<character>.portrait.tres` is a front-facing AtlasTexture view of that same
PNG. `manifest.json` records the original frame names, sheet rectangles, original
alpha bounds/feet, clip counts, sheet sizes and source hashes. Rectangles are
compactly packed rather than arranged as animation rows; use the named manifest
entries to extract a particular clip or frame.

## Creating a character in PixelLab

1. **Choose the character.** Pick a name from [CHARACTER_TYPES.md](CHARACTER_TYPES.md).
2. **Use an existing roster sprite as the style reference.** Pick a character
   with a similar build and give PixelLab its south-facing standing sprite as
   an image reference. Use the low top-down view and match the reference's
   palette, shading, outline, level of realism, body proportions and apparent
   scale. Change the species, clothing and equipment as the new design needs.
3. **Generate and review one south-facing standing preview.** Both the face
   and torso must point straight south, toward the viewer. Check the muzzle,
   eyes, shoulders and chest for any three-quarter turn. Compare the preview
   with the reference side by side at native size. Regenerate if the facing or
   style drifts. Get approval on the preview before making the other views.
4. **Generate the remaining standing views.** Use the approved south sprite
   as the source for PixelLab's eight-direction generation. Keep the approved
   south frame and check that the other directions preserve the design.
5. **Generate the south-facing action.** Have the character use its tools or
   equipment, or perform a motion that expresses what makes it distinctive.
   Keep the face and torso oriented south throughout the clip.
6. **Make the eight-direction walk cycle.** Generate N, NE, E, SE and S. Create
   NW, W and SW by horizontally flipping the NE, E and SE frames by hand,
   respectively. Keep the frame order and timing of each source cycle.
7. **Generate the sit-down animation.** Check that it starts from the standing
   pose and ends in a stable seated pose.
8. **Review each clip before exporting.** Play it at speed and step through it
   frame by frame. Check that tools, equipment and other visible objects stay
   attached or move continuously, without disappearing or jumping between
   frames. Check the last-to-first transition on walk loops too. Regenerate
   the affected clip and review it again until the transitions are clean.
9. **Build the spritesheet.** Export the approved frames as transparent PNGs
   under `assets/characters/playground/<character>`, following an existing
   character's folder layout and frame naming. Run
   `python tools/build_character_alignment.py` to rebuild the alignment data
   and pack the runtime sheet using the same pipeline as the other characters.

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
The original conversion replaced 6,412 individual board-animation texture loads
with 83 shared PNGs. The current roster adds 14 more packed character PNGs.

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
contains 97 unit types per player, with the eleven frontier entries appended
after all existing stable IDs. Their reviewed source frames are in the
PixelLab character export. See [FRONTIER_UNITS.md](FRONTIER_UNITS.md).

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

# PixelLab icon sources

Runtime cleanup (2026-11-05): the IDs and preparation notes below record
provenance. Unused original crop inputs were removed; prepared `ui/` icons
remain. The native board bomb is now `board/bomb-unlit.png`, and its ignition
animation is `../effects/bomb-ignite/`. Reimport the original PixelLab objects
when rebuilding a prepared icon. Mshield uses its separate purple icon/clip.

32×32 source objects, downloaded unchanged on 2026-10-20:

- Red heart: c2945308-1349-4e8e-99a9-4e4f0d2ff7f7
- Blue heart: a7952c72-5612-489e-873f-d9a406edc035
- Bow and arrow: 610190f3-c394-4ef0-8f20-1bf2919e71e3
- Fire: e22a97be-fb44-4269-ab0d-305de870031c
- Unlit bomb: 8dbe9cc8-2def-4907-abcd-7b9e63082d42
- Lit bomb: 075d5525-dcbd-4289-ad5e-3ab5ef7ed869
- Ignition: unlit bomb animation group 6de964b9-bb0e-4f9d-af83-d946864dec8b, nine frames
- Stun: Creator gallery 1792509022298 (transparent golden stars); saved through MCP as Object 3e1db0e2-57ed-4b39-8f3a-6efea7f00dab

All are the user's existing PixelLab artwork; no new generation was requested.

## Prepared UI icons

`ui/` contains cropped, proportion-preserving PNGs. Crop originals to their alpha
bounds, fit within 44×44 using one scale factor and nearest-neighbor sampling,
and add a two-pixel transparent gutter on each side. Hearts instead fit within
32×32. Result canvases remain rectangular to avoid wasting horizontal space.
GameIcons.bb() scales both prepared dimensions by requested_size / 48, preserving
aspect ratio and smaller heart sizing. The fixed row spacer supplies uniform line
metrics independently. Original art and board bomb animation remain unchanged.
Rebuild from originals after replacing an icon, never from a prepared copy.

## Creator outline refresh (2026-10-20)

The existing Objects were refreshed through MCP save_to_asset using the current
32×32 Creator image pixels, preserving Object identities:

| Icon | Creator gallery | Object |
| --- | --- | --- |
| Red heart | 9fa6a49e-55ac-5413-89d1-3296443353f1 | c2945308-1349-4e8e-99a9-4e4f0d2ff7f7 |
| Shield | 13a92fe8-4061-576c-a839-179d36b43bcf | ff7b5cc9-5a15-46ff-be02-c04f9fc96485 |
| Stun | 1792509022298 | 3e1db0e2-57ed-4b39-8f3a-6efea7f00dab |
| Bow | 05206fc6-2b64-5e1d-95f4-d40f116c22db | 610190f3-c394-4ef0-8f20-1bf2919e71e3 |
| Fire | 6965e102-8bd1-5334-8f2f-bf0b1476dd47 | e22a97be-fb44-4269-ab0d-305de870031c |

Local source PNGs use the same Creator pixels; prepared ui/ images are rebuilt
with the proportion-preserving crop process above. GameIcons maps both Shield
and Mshield to shield.png; existing magic-protection text coloring is retained.

## Cannon and boot (2026-10-20)

- Cannon Object: 3c354899-cbe8-4292-96ab-f658b795cf4e
- Boot Object: 0c0330a1-1c7e-4a29-b7ad-1032d01a9054

Original 32×32 rotations are retained in cannon.png and boot.png. Their ui/ copies use the same alpha crop, proportional 44×44 fit, nearest sampling and two-pixel gutters as the other non-heart icons. GameIcons maps Cannon and Move respectively; Fly retains its own symbol.

Boot sizing adjustment: the prepared boot fits within 40×40 rather than 44×44, with the same two-pixel gutters and preserved aspect ratio; its source PNG is unchanged.

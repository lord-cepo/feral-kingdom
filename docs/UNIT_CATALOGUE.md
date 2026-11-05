# Offline unit catalogue

Open `unit-catalogue.html` in a normal web browser. It contains all 93 known units:
the 77 JS-reference units plus additional Godot cards, deduplicated by identity.
41 have Godot CardCatalogue definitions, 52 are reference-only, and 24 belong to
the current roster. Implemented values come from Godot, including intended changes
from JS; their hover notes also preserve the original JS wording for comparison.
Reference-only cards retain their literal source effects and deployment conditions;
listing them is not a claim that their rules have been ported. Renamed Godot cards
show their original JS names as searchable aliases. Ownership remains contextual.

Search any unit/alias/effect text, filter implementation/type/region/roster, or sort by name/life. Hover
or focus a keyword/icon for its guide, including the stickers on that occurrence.
The Hover infos column expands the glossary entries used by the card. Hero and
temple restrictions are included. All portraits/icons are embedded, so the single
HTML file works offline and can be moved independently of the repository.

Edit table exposes name, life, deployment, effects and hover-note fields. Changes
are a design working copy in the browser's local storage, not executable game
rules. Export JSON to back up/import edits; Export CSV opens in spreadsheet tools.
Reset edits restores the generated card data after confirmation. Browser storage
may be unavailable for local files; export still preserves the current tab's work.

Use **+ Add unit** to create a custom draft with name, type, life, deployment rule,
effects and hover notes. New entries appear immediately, have stable custom IDs,
and survive local storage and JSON export/import. The Custom drafts filter isolates
them. Reset edits discards custom drafts as well as edits after confirmation.

In effects and hover text, `(walk)`, `(heart)`, `(bow)`, `(fire)`, `(bash)`, `(die)`,
`(stun)`, `(shield)`, `(bomb)`, `(cannon)`, `(push)` and `(pull)` render as embedded
pixel icons in read mode. The add dialog's icon palette inserts these tokens into
the last focused effects/hover textarea. Other text is escaped; unknown tokens
remain readable text. Tokens are presentation syntax for the design table only,
not a gameplay rule parser. Editing a field shows tokens; Done editing shows icons.

## Refresh from the game

1. Run `godot.exe --headless --path . res://tools/export_unit_catalogue.tscn`.
2. Run Python on `tools/build_unit_catalogue.py`.

`export_unit_catalogue.gd._ready` discovers public player-bound factories in
CardCatalogue, adds implicit movement and reads EffectText/RuleGuide. It writes
`.godot/unit-catalogue-data.json` and exits without loading the user's saved match.
`build_unit_catalogue.py` also reads literal cardSources records from the adjacent
`guerra.game/game/cards.ts` reference without executing or editing that project.
It merges by stable card identity, preserving Godot values for implemented cards.
It converts supported BBCode into escaped HTML, embeds
project image assets and data in `tools/unit_catalogue_template.html`, and writes
the standalone `unit-catalogue.html`. No external dependencies or network are
needed by the page. Editing the table does not rewrite GDScript definitions.
The browser logic lives in `tools/unit_catalogue.js` and is embedded at build
time. `mergeRecords` accepts only whitelisted editable fields and custom drafts;
saved data cannot inject HTML or mark a draft as implemented. `renderTokens`
escapes text and resolves icons from embedded game assets. Custom entries use the
same local persistence and export/import path as existing edits.

Verification: export completed for all factories and the embedded JavaScript
passed Node syntax checking. Browser preview was blocked because the browser tool
does not permit local `file:` URLs; interactive/visual verification was not run.

# Project size and functionality snapshot

Snapshot: **2026-10-19**. Project: `C:/Users/ciava/Documents/feral-kingdom`.

## Counting method

Counts are physical text lines, including comments and blank lines. A final newline
does not add an empty line. Function counts include named GDScript methods,
constructors, static factories, and methods inside nested classes; anonymous
callbacks are not counted as named functions.

The inventory includes every maintained GDScript, scene, Markdown document,
shader, font resource, SVG, artwork helper, editable diagram, and root text
configuration present before this report was created. **This report excludes
itself**, so its own size does not make the snapshot self-referential.

Generated `.godot/`, local `.tools/`, `.uid`/`.import` metadata, editor temporary
saves, and the bundled engine executable are excluded from authored line counts.
Raster artwork has file/byte counts, not line counts. Disk totals separately
include those generated and bundled files. No source files were changed for this
inventory, and no tests were created or run.

## Overall size

| Category | Files | Lines |
| --- | ---: | ---: |
| Application GDScript under `scripts/` | 50 | 7,350 |
| Test GDScript | 5 | 1,557 |
| Main/scaffold scenes | 5 | 99 |
| Test entry scenes | 5 | 30 |
| Existing Markdown documents under `docs/` | 11 | 3,374 |
| Contributor instructions, `AGENTS.md` | 1 | 361 |
| Runtime art shader | 1 | 43 |
| Other maintained text/resources | 22 | 366 |
| **Total maintained text before this report** | **100** | **13,180** |

The 50 application scripts contain **572 named function declarations** and occupy
**368,955 bytes**, about **360 KiB**. Their 7,350 lines break down as follows:

| Line classification | Lines |
| --- | ---: |
| Nonblank lines not starting with a comment | 5,714 |
| Full-line comments, including `##` contracts | 1,019 |
| Blank lines | 617 |

The first classification is a text-counting metric, not a count of executable
instructions: it includes declarations, data, inline comments, and string content.

## Application code by responsibility

| Area | Files | Lines | Named functions | Responsibility |
| --- | ---: | ---: | ---: | --- |
| Effects | 22 | 2,481 | 255 | Definitions, selectors, validation, choices, costs, execution, conditions, contributions, and action factories. |
| UI | 5 | 1,325 | 73 | Match controls, card trays, generated hover descriptions, and composition/scaffolding. |
| Runtime | 6 | 1,060 | 76 | Authoritative match state, phases, trigger queue, control, map creation, and idle snapshots. |
| Combat | 7 | 978 | 58 | Attack/encounter records and common combat/movement resolution. |
| Board | 2 | 922 | 65 | Hex rendering, Bash halves, hover animation, highlights, clicks, and selection UI. |
| Model | 7 | 314 | 20 | Unit/player/hex/property data, stable identity compatibility, and timed grants. |
| Catalogue | 1 | 270 | 25 | Starter roster, 23 named card factories, and a shared card constructor. |
| **Total** | **50** | **7,350** | **572** | |

Grouped more broadly, rule/model/runtime/combat code is **4,833 lines (65.8%)**;
board and UI presentation is **2,247 lines (30.6%)**; card authoring is **270 lines
(3.7%)**. Percentages are rounded.

## Functionality represented in the source

| Area | Implemented slice | Remaining scope / limitations |
| --- | --- | --- |
| Local match | Two players, six-card starter roster, hero-first deployment, action/deployment allowances, defeat and hero victory. | Full army/deck building and finalized format rules. |
| Board and control | Hex regions, occupancy, control based on current life/control bonus, home tie-break, control-gated deployment, derived physical control bonus. | Complete catalogue-specific deployment restrictions and richer inspection of contribution sources. |
| Effects | Reusable object-authored definitions; separate activation/phrase execution; guards; optional choices; one/all targets; ordered consequences. | Additional card-driven predicates and general scheduled effects. |
| Selection | Stable unit/hex/player/property references, spatial queries, filters, composition, projections, shared HEX-to-UNIT adaptation, legality rechecks. | Additional geometry and selectors required by remaining cards. |
| Costs | Self-Stun 1; atomic built-in bundles; cumulative resource preflight; no refunds after paid consequence failure; P/F/T/A stickers. | Other atomic cost families and broader temporary sticker grants. |
| Trigger runner | Captured occurrences, event stages/families, retained choices, nested followups, pausable Start/End/combat continuation. | General future-phase scheduling and remaining card interactions. |
| Turns and activity | Own Start removes one positive Stun from each friendly deployed unit without activating; after own End effects, inactive zero-Stun friendly units activate; activation followups finish before cleanup/switch. | Later format/token decisions and any further explicitly requested timing rulings. |
| Combat | Fire, Bow, Cannon, Bomb placement/merge/defuse/ignition/blasts/chains, Gore, Move/Fly, Push/Pull of units and bombs, Bash; contact/immunity/shield behavior and Fast/Steady/Titanium/First Strike. | Additional card interactions and broader movement/action upgrades. |
| Modifiers and grants | Separate persistent/temporary counters, derived continuous modifiers/passives/action values, Bow counters, timed action-value grants, defeat-trigger suppression. | Broader lifetime/grant types and UI provenance. |
| Presentation | Illustrations, inactive tint, compact hex summaries, target highlights, action switching, split Bash hover, automatically generated compact hover rules. | Full JS presentation/animation/preview parity and reduced-motion support. |
| Saving | Versioned local snapshot at an idle Action boundary, restore on startup, reset control. | Mid-choice saves, serialized pending runner continuations, decks/scenarios, and online persistence. |
| Catalogue | **23 named Godot card factories**; the starter uses six instances. | The reference snapshot lists **77 JS cards**. Factory count measures authored entries, not overall game completion or exact card parity. |
| Online services | Network/persistence scene nodes exist as scaffolds. | Transport, authentication, matchmaking, reconnect/resume, shared authoritative hosting, and account/deck services. |

This functionality map is a static source/documentation review, not fresh runtime
verification. Five integration scenes exist, but they were not executed for this
report. Some activation expectations in the existing tests predate the
2026-10-19 activity-rule revision.

## Maintenance observations

- The largest files are `combat_resolver.gd` (903 lines),
  `local_match_controller.gd` (853), and `hex_cell.gd` (572). Together they contain
  **2,328 lines, or 31.7% of application GDScript**.
- Effect and selection machinery is the largest functional area at 2,481 lines.
  Card-specific factories themselves remain small at 270 lines; shared authored
  effect recipes also live in `collection.gd`.
- Documentation/contracts are a substantial part of the physical size. The
  application alone has 1,019 full-line comments, before counting the separate
  rulebook and usage documents.
- Small compatibility/scaffold files are included in the totals:
  `control.gd`, `troople.gd`, `phrase_selection.gd`, `unit.gd`, and
  `system_placeholder.gd`. Their existence does not imply implemented online
  or alternate unit/control systems.

## Complete per-file inventory

The following tables list all 100 maintained text/resource files in this
snapshot, with their role. Binary artwork and generated metadata are summarized
separately after the tables.

### scripts/model

| File | Lines | Named functions | Role |
| --- | ---: | ---: | --- |
| [scripts/model/enums.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/model/enums.gd) | 24 | 0 | Shared enumerations for sides, regions, ownership, state, card type, and property kinds. |
| [scripts/model/hex_info.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/model/hex_info.gd) | 22 | 1 | Data record for a board hex, including axial coordinate and region metadata. |
| [scripts/model/player.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/model/player.gd) | 12 | 0 | Player identity and tracked action/deployment allowances. |
| [scripts/model/prop.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/model/prop.gd) | 7 | 0 | Typed property record used for counters and flags. |
| [scripts/model/timed_grant.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/model/timed_grant.gd) | 28 | 2 | Concrete recipient-bound numeric action contribution with captured player-turn cleanup identity. |
| [scripts/model/troople.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/model/troople.gd) | 3 | 0 | Legacy `Troople` class-name compatibility wrapper over `TargetRef`; new code should use `TargetRef` factories. |
| [scripts/model/unit_info.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/model/unit_info.gd) | 218 | 17 | Authoritative card instance data: owner, life, activity, properties, effects, and derived modifiers. |

Subtotal: **7 files; 314 lines**.

### scripts/runtime

| File | Lines | Named functions | Role |
| --- | ---: | ---: | --- |
| [scripts/runtime/control_resolver.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/runtime/control_resolver.gd) | 53 | 6 | Derives regional control and the live regional physical bonus from current board state. |
| [scripts/runtime/control.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/runtime/control.gd) | 1 | 0 | Comment-only legacy placeholder. `ControlResolver` is the active control implementation. |
| [scripts/runtime/match_snapshot.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/runtime/match_snapshot.gd) | 364 | 21 | Saves and restores stable local match state, including unit/player counters and pending combat records, in `user://local_match_snapshot.json`. |
| [scripts/runtime/match.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/runtime/match.gd) | 385 | 28 | Authoritative live match: army/map records, lookup, deployment, defeat, phases, events, and the `RulesRunner` connection; owner Start removes one friendly Stun without activation, and owner End activates eligible inactive units after End effects. It is the `Match` autoload. |
| [scripts/runtime/regions.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/runtime/regions.gd) | 59 | 6 | Generates the axial board and assigns side/region metadata. |
| [scripts/runtime/rules_runner.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/runtime/rules_runner.gd) | 198 | 15 | Owns managed commands, captured triggers, queued continuations, and action-token completion. |

Subtotal: **6 files; 1,060 lines**.

### scripts/effects

| File | Lines | Named functions | Role |
| --- | ---: | ---: | --- |
| [scripts/effects/action_sticker.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/effects/action_sticker.gd) | 22 | 2 | Typed P/F/T/A sticker definition attached to one action phrase; reusable action definitions stay unchanged. |
| [scripts/effects/action_stickers.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/effects/action_stickers.gd) | 9 | 0 | Named options such as Instant, Pierce, Tireless, and Action-free. |
| [scripts/effects/actions.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/effects/actions.gd) | 325 | 46 | Named action entry points and legality wrappers; delegates combat rules to `CombatResolver` where appropriate. |
| [scripts/effects/collection.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/effects/collection.gd) | 218 | 21 | Readable object-authored factories that compose costs, selectors, verbs, and consequences. |
| [scripts/effects/condition.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/effects/condition.gd) | 222 | 22 | Read-only predicates and Boolean combinations used by selectors and contributions. |
| [scripts/effects/continuous_effect.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/effects/continuous_effect.gd) | 67 | 5 | Reusable read-only “while” and “have” definition with recipient filters and typed contributions. |
| [scripts/effects/contribution.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/effects/contribution.gd) | 46 | 5 | Typed outputs for live modifiers, passive flags, Bow values, and event policy. |
| [scripts/effects/cost_payment.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/effects/cost_payment.gd) | 52 | 1 | Preflight and commit for atomic built-in resource cost bundles. |
| [scripts/effects/distance_selector.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/effects/distance_selector.gd) | 65 | 6 | Spatial selector that returns hex references at or within a declared range. |
| [scripts/effects/effect_event.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/effects/effect_event.gd) | 102 | 6 | Immutable occurrence record with stable participants and copied historical details. |
| [scripts/effects/effect_execution.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/effects/effect_execution.gd) | 251 | 15 | Per-activation state for source, event, payment, phrase progress, outcomes, and completion. |
| [scripts/effects/effect.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/effects/effect.gd) | 328 | 24 | Reusable effect definitions: cost, event pattern, consequence phrase, and ordered consequence sequence. |
| [scripts/effects/phrase_execution.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/effects/phrase_execution.gd) | 158 | 10 | Per-phrase subject/target choice, candidate refresh, validation, and exactly-once commit state. |
| [scripts/effects/phrase_selection.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/effects/phrase_selection.gd) | 9 | 1 | Compatibility subclass of `PhraseExecution` for older callers. |
| [scripts/effects/query_selector.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/effects/query_selector.gd) | 54 | 5 | Unit/hex/player query filters for owner, relative owner, type, region, side, control, and state. |
| [scripts/effects/rule_context.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/effects/rule_context.gd) | 19 | 1 | Read-only view of source, subject, event, recipient, and completed phrase results for rules. |
| [scripts/effects/selector.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/effects/selector.gd) | 25 | 6 | Base selector contract and validation surface. |
| [scripts/effects/selectors.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/effects/selectors.gd) | 213 | 33 | Reference selectors, composition, explicit projections, and property selection. |
| [scripts/effects/state_modifier.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/effects/state_modifier.gd) | 45 | 5 | Read-only conditional physical/magical contribution attached to a unit. |
| [scripts/effects/target_ref.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/effects/target_ref.gd) | 60 | 12 | Stable typed references to units, hexes, players, match, or properties. It lives with the effect API because selectors and verbs exchange it. |
| [scripts/effects/target_resolver.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/effects/target_resolver.gd) | 45 | 4 | Shared selector boundary: resolves references, adapts supported domains, validates and deduplicates candidates. |
| [scripts/effects/verbs.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/effects/verbs.gd) | 146 | 25 | Named verb factories with fixed subject/target kinds and bound action/legality functions. |

Subtotal: **22 files; 2,481 lines**.

### scripts/combat

| File | Lines | Named functions | Role |
| --- | ---: | ---: | --- |
| [scripts/combat/bash_info.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/combat/bash_info.gd) | 8 | 0 | Pending Bash encounter identities, response owner, target hex, and resolution state. |
| [scripts/combat/bomb_info.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/combat/bomb_info.gd) | 8 | 0 | Inert or queued bomb identity, owner, location, damage, and Pierce setting. |
| [scripts/combat/bow_attack.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/combat/bow_attack.gd) | 13 | 0 | Captured Bow source, victim, location, amount, and resolution outcome. |
| [scripts/combat/cannon_attack.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/combat/cannon_attack.gd) | 13 | 0 | Captured Cannon or bomb-blast payload and resolution state. |
| [scripts/combat/combat_resolver.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/combat/combat_resolver.gd) | 903 | 57 | Validates and resolves attacks, contact, movement interactions, bombs, damage, and ordered combat windows. |
| [scripts/combat/fire_attack.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/combat/fire_attack.gd) | 21 | 1 | Captured Fire declaration, including original victim identity and historical origin/target. |
| [scripts/combat/gore_attack.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/combat/gore_attack.gd) | 12 | 0 | Captured Gore leap path, source, target, amount, and outcome. |

Subtotal: **7 files; 978 lines**.

### scripts/catalogue

| File | Lines | Named functions | Role |
| --- | ---: | ---: | --- |
| [scripts/catalogue/card_catalogue.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/catalogue/card_catalogue.gd) | 270 | 25 | Builds the local test roster and representative Guerra card definitions, including continuous Temple, White Wolf, Canyon Ibex, and Marsh Badger rules. |

Subtotal: **1 files; 270 lines**.

### scripts/board

| File | Lines | Named functions | Role |
| --- | ---: | ---: | --- |
| [scripts/board/board.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/board/board.gd) | 350 | 29 | Draws/updates the playable board, tracks selected units, forwards candidate selections to executions, and relays hex hover enter/exit and Bash participant IDs to the HUD without redrawing on hover. |
| [scripts/board/hex_cell.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/board/hex_cell.gd) | 572 | 36 | Displays one region hex and its deployed card figures, including life/effect summaries, inactive tint, targetable pose, and hover signals; unresolved Bash records retain Player 2-left/Player 1-right half portraits across refreshes, show life and centered physical/magic stats, and reveal the hovered participant with Guerra's delayed side transition. |

Subtotal: **2 files; 922 lines**.

### scripts/ui

| File | Lines | Named functions | Role |
| --- | ---: | ---: | --- |
| [scripts/ui/effect_text.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/ui/effect_text.gd) | 446 | 26 | Read-only BBCode generator: normal actions use hex-style amount/icon/range notation; complex rules retain concise trigger/selector/condition/contribution text, explicit optionality, and custom payments. Walks definitions and supported live values without executing rules or relying on card-specific labels. |
| [scripts/ui/game.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/ui/game.gd) | 12 | 1 | Scene composition root; starts the local match after child nodes are ready. |
| [scripts/ui/local_match_controller.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/ui/local_match_controller.gd) | 853 | 44 | Connects the local two-player setup, unit-first action menus, compact card trays, status display, save snapshot/reset controls, generated hover card details, and board to `Match`; the smaller corner hover fits wrapped rules with no outer frame or details heading. |
| [scripts/ui/system_placeholder.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/ui/system_placeholder.gd) | 4 | 0 | Structural placeholder used for planned network/persistence scene nodes. |
| [scripts/ui/unit.gd](C:/Users/ciava/Documents/feral-kingdom/scripts/ui/unit.gd) | 10 | 2 | Node-level unit presentation scaffold. Match data lives in `UnitInfo`. |

Subtotal: **5 files; 1,325 lines**.

### Tests and their entry scenes

| File | Lines | Named functions | Role |
| --- | ---: | ---: | --- |
| [tests/fire_test.gd](C:/Users/ciava/Documents/feral-kingdom/tests/fire_test.gd) | 532 | 18 | Combat integration assertions: Fire, Bow, Cannon/Bomb, Gore, displacement, Bash, and defenses. |
| [tests/fire_test.tscn](C:/Users/ciava/Documents/feral-kingdom/tests/fire_test.tscn) | 6 | 0 | Scene entry point for fire_test. |
| [tests/local_match_test.gd](C:/Users/ciava/Documents/feral-kingdom/tests/local_match_test.gd) | 99 | 3 | Local match assertions: deployment, control, action spending, recovery, and turn changes; some activation expectations predate the latest ruling. |
| [tests/local_match_test.tscn](C:/Users/ciava/Documents/feral-kingdom/tests/local_match_test.tscn) | 6 | 0 | Scene entry point for local_match_test. |
| [tests/m2_test.gd](C:/Users/ciava/Documents/feral-kingdom/tests/m2_test.gd) | 301 | 24 | Runner assertions: costs, retained choices, nested triggers, phase/combat continuations. |
| [tests/m2_test.tscn](C:/Users/ciava/Documents/feral-kingdom/tests/m2_test.tscn) | 6 | 0 | Scene entry point for m2_test. |
| [tests/selection_test.gd](C:/Users/ciava/Documents/feral-kingdom/tests/selection_test.gd) | 387 | 17 | Selector/reference/domain and execution assertions, including real board selection handlers. |
| [tests/selection_test.tscn](C:/Users/ciava/Documents/feral-kingdom/tests/selection_test.tscn) | 6 | 0 | Scene entry point for selection_test. |
| [tests/trigger_state_test.gd](C:/Users/ciava/Documents/feral-kingdom/tests/trigger_state_test.gd) | 238 | 10 | Continuous state, trigger capture, passive/action grants, and suppression assertions. |
| [tests/trigger_state_test.tscn](C:/Users/ciava/Documents/feral-kingdom/tests/trigger_state_test.tscn) | 6 | 0 | Scene entry point for trigger_state_test. |

Subtotal: **10 files; 1,587 lines**.

### Main and scaffold scenes

| File | Lines | Role |
| --- | ---: | --- |
| [scenes/board/board.tscn](C:/Users/ciava/Documents/feral-kingdom/scenes/board/board.tscn) | 29 | Board node and board script instance. |
| [scenes/board/hex_cell.tscn](C:/Users/ciava/Documents/feral-kingdom/scenes/board/hex_cell.tscn) | 28 | Reusable clickable hex scene. |
| [scenes/game.tscn](C:/Users/ciava/Documents/feral-kingdom/scenes/game.tscn) | 15 | Main playable local-match scene and its composition root. |
| [scenes/server/server.tscn](C:/Users/ciava/Documents/feral-kingdom/scenes/server/server.tscn) | 19 | Server/network/persistence scaffold; not the project's current startup scene. |
| [scenes/unit.tscn](C:/Users/ciava/Documents/feral-kingdom/scenes/unit.tscn) | 8 | Reusable unit presentation scene. |

Subtotal: **5 files; 99 lines**.

### Documentation and contributor instructions

| File | Lines | Role |
| --- | ---: | --- |
| [AGENTS.md](C:/Users/ciava/Documents/feral-kingdom/AGENTS.md) | 361 | Project-specific implementation rules, architecture boundaries, and gameplay rulings for contributors. |
| [docs/CONTINUOUS_ROADMAP.md](C:/Users/ciava/Documents/feral-kingdom/docs/CONTINUOUS_ROADMAP.md) | 280 | Continuous-rule design, current implementation, and remaining grant/lifetime work. |
| [docs/FILE_GUIDE.md](C:/Users/ciava/Documents/feral-kingdom/docs/FILE_GUIDE.md) | 187 | This map of source files, scenes, tests, docs, and asset groups. |
| [docs/forge.md](C:/Users/ciava/Documents/feral-kingdom/docs/forge.md) | 157 | Secondary Forge architecture reference; not executable game rules. |
| [docs/GENERAL_RULES.md](C:/Users/ciava/Documents/feral-kingdom/docs/GENERAL_RULES.md) | 352 | Intended gameplay rules and currently open decisions. |
| [docs/GUERRA_RULES.md](C:/Users/ciava/Documents/feral-kingdom/docs/GUERRA_RULES.md) | 312 | Source-linked snapshot of legacy JS behavior and the card catalogue. |
| [docs/M2_EXECUTION.md](C:/Users/ciava/Documents/feral-kingdom/docs/M2_EXECUTION.md) | 266 | Managed commands, trigger capture, payment, and resumable phase/combat execution. |
| [docs/ROADMAP.md](C:/Users/ciava/Documents/feral-kingdom/docs/ROADMAP.md) | 388 | Milestones, current implementation status, and remaining work. |
| [docs/RULINGS.md](C:/Users/ciava/Documents/feral-kingdom/docs/RULINGS.md) | 169 | Numbered interaction rulings with timing, scope, and implementation notes. |
| [docs/SELECTION.md](C:/Users/ciava/Documents/feral-kingdom/docs/SELECTION.md) | 606 | Current selector/effect APIs, caller map, examples, and integration-scene instructions. |
| [docs/TRIGGER_AND_STATE_PLAN.md](C:/Users/ciava/Documents/feral-kingdom/docs/TRIGGER_AND_STATE_PLAN.md) | 381 | Broader trigger/state design reference and its implementation boundaries. |
| [docs/TRIGGER_ROADMAP.md](C:/Users/ciava/Documents/feral-kingdom/docs/TRIGGER_ROADMAP.md) | 276 | Trigger stages, event families, implementation steps, and parity boundary. |

Subtotal: **12 files; 3,735 lines**.

### Shader, font, SVG, diagram, artwork helpers, and project settings

| File | Lines | Role |
| --- | ---: | --- |
| [.editorconfig](C:/Users/ciava/Documents/feral-kingdom/.editorconfig) | 4 | Editor indentation/encoding conventions. |
| [.gitattributes](C:/Users/ciava/Documents/feral-kingdom/.gitattributes) | 2 | Text line-ending conventions. |
| [.gitignore](C:/Users/ciava/Documents/feral-kingdom/.gitignore) | 6 | Generated/editor/local-tool exclusions. |
| [assets/cards/move_and_resize.sh](C:/Users/ciava/Documents/feral-kingdom/assets/cards/move_and_resize.sh) | 2 | Local artwork preparation helper; not executed by the game. |
| [assets/fonts/hex_info_font.tres](C:/Users/ciava/Documents/feral-kingdom/assets/fonts/hex_info_font.tres) | 4 | System-font configuration for compact board information. |
| [assets/move_and_resize.sh](C:/Users/ciava/Documents/feral-kingdom/assets/move_and_resize.sh) | 2 | Local artwork preparation helper; not executed by the game. |
| [assets/shaders/inactive_board_art.gdshader](C:/Users/ciava/Documents/feral-kingdom/assets/shaders/inactive_board_art.gdshader) | 43 | Card art crop/hex mask, inactive tint, hover tilt, Bash clipping and fade. |
| [assets/sprites/crown-blue-board.svg](C:/Users/ciava/Documents/feral-kingdom/assets/sprites/crown-blue-board.svg) | 12 | SVG crown/helm/temple artwork variant. |
| [assets/sprites/crown-blue.svg](C:/Users/ciava/Documents/feral-kingdom/assets/sprites/crown-blue.svg) | 12 | SVG crown/helm/temple artwork variant. |
| [assets/sprites/crown-red-board.svg](C:/Users/ciava/Documents/feral-kingdom/assets/sprites/crown-red-board.svg) | 12 | SVG crown/helm/temple artwork variant. |
| [assets/sprites/crown-red.svg](C:/Users/ciava/Documents/feral-kingdom/assets/sprites/crown-red.svg) | 12 | SVG crown/helm/temple artwork variant. |
| [assets/sprites/crown-tray.svg](C:/Users/ciava/Documents/feral-kingdom/assets/sprites/crown-tray.svg) | 12 | SVG crown/helm/temple artwork variant. |
| [assets/sprites/helm-blue-board.svg](C:/Users/ciava/Documents/feral-kingdom/assets/sprites/helm-blue-board.svg) | 19 | SVG crown/helm/temple artwork variant. |
| [assets/sprites/helm-blue.svg](C:/Users/ciava/Documents/feral-kingdom/assets/sprites/helm-blue.svg) | 19 | SVG crown/helm/temple artwork variant. |
| [assets/sprites/helm-red-board.svg](C:/Users/ciava/Documents/feral-kingdom/assets/sprites/helm-red-board.svg) | 19 | SVG crown/helm/temple artwork variant. |
| [assets/sprites/helm-red.svg](C:/Users/ciava/Documents/feral-kingdom/assets/sprites/helm-red.svg) | 19 | SVG crown/helm/temple artwork variant. |
| [assets/sprites/helm-tray.svg](C:/Users/ciava/Documents/feral-kingdom/assets/sprites/helm-tray.svg) | 19 | SVG crown/helm/temple artwork variant. |
| [assets/sprites/temple-blue-board.svg](C:/Users/ciava/Documents/feral-kingdom/assets/sprites/temple-blue-board.svg) | 8 | SVG crown/helm/temple artwork variant. |
| [assets/sprites/temple-red-board.svg](C:/Users/ciava/Documents/feral-kingdom/assets/sprites/temple-red-board.svg) | 8 | SVG crown/helm/temple artwork variant. |
| [assets/sprites/temple.svg](C:/Users/ciava/Documents/feral-kingdom/assets/sprites/temple.svg) | 29 | SVG crown/helm/temple artwork variant. |
| [docs/effect-creation-and-resolution.drawio](C:/Users/ciava/Documents/feral-kingdom/docs/effect-creation-and-resolution.drawio) | 103 | Editable effect architecture/lifecycle diagram. |
| [icon.svg](C:/Users/ciava/Documents/feral-kingdom/icon.svg) | 1 | Project icon. |
| [project.godot](C:/Users/ciava/Documents/feral-kingdom/project.godot) | 42 | Godot project settings, startup scene, input, renderer, and the `Match` singleton. |

Subtotal: **23 files; 409 lines**.


## Artwork and disk footprint

There are **150 raster images under assets/**, totaling **114.1 MiB**,
including **81 PNG card illustrations directly under assets/cards/**.
There are also **13 SVG sprite files** under assets/sprites/ (200 text lines),
plus the root SVG project icon. Illustration count is independent of implemented card factories.

The workspace occupied approximately **601.3 MiB** at measurement time, including
the bundled engine, downloaded tools, editor caches, metadata, and temporary files.
MiB means 1,048,576 bytes. The table below describes physical disk contents, not authored code.

| Disk component | Files | MiB | Interpretation |
| --- | ---: | ---: | --- |
| `.tools/` | 21 | 229.18 | Ignored local runtimes, downloaded archives, helper scripts, and logs. |
| `assets/` | 331 | 114.26 | Art, import metadata, shader, font, and image-preparation helpers. |
| `.godot/` | 487 | 82.96 | Generated editor/import cache and local logs. |
| `docs/` | 18 | 1.93 | Existing documents and diagrams/rendered images, before adding this report. |
| `scripts/` | 100 | 0.35 | Application GDScript and its generated UID sidecars. |
| `tests/` | 15 | 0.08 | Assertions, test scenes, and UID sidecars. |
| `scenes/` | 7 | 0.01 | Main/scaffold scenes and editor temporary saves. |
| `godot.exe` | 1 | 172.48 | Bundled Godot engine executable, not project source. |

Root text settings and icon add a small remainder. Empty editor-support folders
contain no runtime implementation. Disk sizes vary as the editor regenerates
imports/logs; this report is a dated snapshot, not a live counter.

## Reading the project

Start with [FILE_GUIDE.md](FILE_GUIDE.md) for boundaries,
[GENERAL_RULES.md](GENERAL_RULES.md) for intended rules,
[SELECTION.md](SELECTION.md) for implemented usage/caller maps, and
[M2_EXECUTION.md](M2_EXECUTION.md) for command/trigger/phase ownership.
ROADMAP.md describes staged scope; later milestones are not automatically implemented.


## Conservative cleanup inventory — 2026-10-26

The earlier tables remain the historical 19 October snapshot. After the
26 October audit and conservative cleanup, application code under `scripts/`
contains **71 GDScript files and 12,895 physical lines** (including comments and
blank lines), compared with 74 files and 12,943 lines immediately before cleanup.
Three unused scripts, their UID sidecars and the empty unit scene were removed;
portrait lookup, displayed selector range and common fallback glyphs now have
shared implementations. Tests remain at 8 scripts / 2,261 lines and were not run.
See CODEBASE_AUDIT_2026-10-26.md for scope and intentionally deferred work.

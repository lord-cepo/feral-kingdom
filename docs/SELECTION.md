# Selection and effect execution

Current art loading (2026-10-30): [CHARACTER_SHEETS.md](CHARACTER_SHEETS.md)
documents one shared PNG per supported PixelLab character and source/legacy
import exclusions. AtlasTexture views preserve native canvas/foot anchors;
board/tray shaders now remap current/previous frame UVs into their sheet regions.
This changes presentation loading only, not effect definitions or execution.

Availability update (2026-10-29): `RulesRunner.command_available` retains private
payment bindings through `_cost_choices_available` until `_consequence_available`
checks the first mandatory consequence. Only the preview RuleContext receives
synthetic `cost_choice_N`/`cost_N` identities/amounts; no resource is paid and no
real EffectExecution receives a paid result. Rogue can bind its donor counter
kind, reject an incompatible recipient FLAG and explore another kind. Warlock's
chosen Disable may create its own future Revive recipient. See
[TESTING.md](TESTING.md) for non-mutation and cross-owner regressions.

The twenty adventurer definitions and their caller map are documented in
[ADVENTURER_UNITS.md](ADVENTURER_UNITS.md). `RuleBinding.UNIT_ID` reads a completed
UNIT choice; `RuleBinding.HEX_ID` reads its execution-owned pre-commit
`target_hexes` snapshot. Summoner retains a Return cost's former hex through
`cost_1`, while ordinary UNIT references continue to resolve their live position.
Cleric's `AdventurerRules.ExistingCounters` projection includes existing zero
counters; payment-oriented `Selectors.CountersOf` continues to require positive
counters. Shaman collects two different participant choices before either Return.

For managed player commands and M2 trigger/phase execution, see
[M2_EXECUTION.md](M2_EXECUTION.md).

Effects and selectors are reusable definitions. Each activation owns an
`EffectExecution`; each cost or consequence owns a separate `PhraseExecution`.
`SELF` comes from the shared effect execution. Pending subjects and targets never
live on selectors.

## Authoring effects

```gdscript
var phrase := Effect.ConsequencePhrase.new(
    Selectors.Self.new(),
    Verbs.deactivate(),
    DistanceSelector.within(2)
)
$Board.select_phrase(phrase, TargetRef.unit(0))
```

Distance always returns hexes. `Verbs.deactivate()` declares UNIT targets, so the
shared resolver expands those hexes into individual occupants before the user
chooses. `Verbs.fire(2)` declares HEX targets and receives the original hexes.

A named verb owns its action, subject/target kinds, parameters, and legality
check. Definitions do not repeat its types. Use `Verbs.fire(amount)` for a real
magical attack. The older `Verbs.damage` is a notification-only compatibility
placeholder used by generic selection tests, not the Fire implementation.

```gdscript
var enemies := Selectors.UnitsOn.new(DistanceSelector.within(2)).where(
    Selectors.EnemyOfSelf.new()
)
var all_enemies := Effect.ConsequencePhrase.new(
    Selectors.Self.new(), Verbs.deactivate(), enemies,
    Effect.Phrase.TargetMode.ALL
)
```

`CHOOSE_ONE` is the default. Targets always require a user choice, even when
only one exists. A unique subject is resolved automatically. `ALL` skips the
target picker; it snapshots the legal targets at commit in stable ID order.
Set `phrase.optional = true` to request a separate confirmation before selection
or execution.

## References and selector domains

Use `TargetRef.unit(id)`, `hex(id)`, `player(id)`, or
`property(host_ref, key)`. Units and tiles use stable indices into the flat
`Match.army` and `Match.map` arrays. Never erase/reorder those arrays: use a null
slot for removed entries and append new entities. A unit's current position and
owner come from Match, not from copied reference fields.

The unused `Troople` compatibility class has been removed. Its old
positional constructor and snapshot methods are no longer the selection API.

- `Selectors.Self` and `Selectors.Subject` preserve the referenced kind.
- `Selectors.Recipient` reads the current recipient binding in continuous effects; ordinary contexts default it to SELF.
- `DistanceSelector.new(n)` selects an exact ring;
  `DistanceSelector.within(n)` includes the center and all tiles up to n.
- Distance defaults to SELF. Pass `Selectors.Anchor.SUBJECT` to center on the
  chosen actor. TOWARDS/AWAY use `reference` as the second anchor and require a
  strictly decreasing/increasing distance to it.
- `QuerySelector.new(kind)` enumerates UNIT (default), HEX, or PLAYER.
  Its owner/type/state/side/control/region criteria filter that domain.
- `Selectors.UnitsOn` explicitly expands hexes to units.
- `Selectors.HexOf` explicitly projects units to their current tiles.
- `Selectors.PropertyOf(host_selector, key)` addresses a counter or flag.
- `and_with` / `where` intersect same-domain selectors; `or_with` unions them.
  Both deduplicate identities.

Only HEX -> UNIT is automatic. UNIT -> HEX, ownership, and property selection
require explicit selectors. Unsupported domains produce a nonempty
`execution.error`, even if the selector is empty. Valid queries finding nothing
fail with no type error.

Unit filters check unit ownership, including on tiles shared by both players.
Hex ownership filters check the tile instead. Off-board units retain valid
identity, but cannot supply a spatial anchor. Spatial candidates are recomputed
before commit: a moved unit remains the same reference, but must still be legal.

## Counters and flags

```gdscript
var spend_poison := Effect.ConsequencePhrase.new(
    Selectors.Self.new(),
    Verbs.decrement(1),
    Selectors.PropertyOf.new(Selectors.Self.new(), &"poison")
)
```

Properties use the existing `Prop.name` as a unique key per host; duplicate names
make that address invalid. Their array order is irrelevant. `decrement` accepts
COUNTER properties with enough value; `set_flag(true)` accepts FLAG properties.
Hosts can be units, tiles, players, or `TargetRef.match_host()` for global
`Match.props`. Missing properties yield no targets; these verbs do not create
properties. Properties cannot host other properties.

## Running a complete effect

```gdscript
Match.rules_runner.submit(Collection.fire_DR(2, 3), TargetRef.unit(0))
```

The runner owns the command, pays its cost, runs consequences and captured
followups, and accounts for its standalone token once. The Board observes the
active execution automatically. Alternatively,
retain the execution returned by `effect.eval(source, trigger)` and drive
`execution.current.choose(ref)` / `confirm(bool)` from another UI. That caller
must also spend the player's action token when the action succeeds or its cost
has already been paid.

### Action stickers, counters, and timed grants

Timed records now distinguish action values from physical/magical modifier pairs.
`Verbs.grant_modifiers(2, 0)` attaches a recipient-bound +2/+0 through the captured
current End cleanup; UnitInfo derives it without counter mutation, and snapshots
retain its kind. Jerboa King's Move support refreshes identical same-source grants.
See [HERO_UNITS.md](HERO_UNITS.md) and [HOVER_TEXT.md](HOVER_TEXT.md) for current
callers, examples, general description rules and the distinct purple Mshield asset.

P/F/T/A are typed phrase stickers. `Collection.ranged()` accepts an
`ActionStickers` option object; older action factories accept equivalent booleans
and record the same typed sticker definitions. Bow value counters are persistent
unit properties. Timed action-value grants attach to the concrete chosen units
and last through End followups; continuous `have` contributions are always
derived from the current source/selector/conditions.

```gdscript
var target := Effect.ConsequencePhrase.new(
    Selectors.Self.new(), Verbs.upgrade_bow(1, 1), Selectors.Self.new())
var permanent_bow_counter := Effect.new(null, null, target)

var allies := QuerySelector.new(TargetRef.Kind.UNIT)
allies.relative_owner = Enum.YOU
var nearby_allies := Selectors.UnitsOn.new(
    DistanceSelector.within(2)).where(allies)
var bow_until_end := Collection.grant_action_values(&"bow", [1, 1], nearby_allies)

var friendly := QuerySelector.new(TargetRef.Kind.UNIT)
friendly.relative_owner = Enum.YOU
var bow_aura := ContinuousEffect.have(friendly,
    [Contribution.bow_values(1, 1)], null, null, "Friendly Bow +1/+1")
```

`Verbs.upgrade_bow()` creates/changes stored `bow_damage` and `bow_range`
counters. `Collection.grant_action_values()` captures selected recipients and
the current player/turn expiry when the action resolves. `ContinuousEffect.have()`
does not store recipient values. These three sources add to printed action values
independently; only the timed grant expires automatically.

### Entry points and callers

| Entry point | Caller and next step |
| --- | --- |
| `Match.start_turn(player)` → `_start_boundary()` → `_enter_action()` | Setup/turn progression resets the allowance and removes one positive Stun from each friendly deployed unit, without changing activity or emitting Activate. Start trigger choices finish before Action. |
| `Match.complete_action()` → `_end_phase(player)` → `_activate_unstunned_units(player)` → `_next_turn(player)` | After combat, resolve End triggers/choices, then activate only the ending player's inactive deployed units with no Stun. Activate followups finish before timed-grant cleanup and the opponent's Start; no repeated Activate for already-active units. |
| `LocalMatchController._unit_effect_details()` → `EffectText.unit_lines(unit)` | Board, Bash-side, and tray hover cards render generated BBCode for actions, triggers, state/continuous rules, and stored passive flags. No card ID or handwritten rule label is used as a rule-description source; the unused legacy text fields have been removed. |
| `EffectText.describe_effect(effect, unit)` → `compact_action()` / `_steps()` | Presentation-only rule summary: simple normal actions use hex-style symbols; triggers keep participants, conditions, optional policy, custom payments, and sequence order. Mandatory policy and normal self-Stun costs are implicit. SELF values use supported UnitInfo derivations; no candidates are resolved or executions created. |
| `EffectText._phrase()` / `_continuous()` → `_action_grant()` / `_modifiers()` | Shared signed upgrade notation: `+N🏹+M`, current/max-life `+N/+M❤️`, physical/magic `+N/+M`. Zero and negative slots remain explicit; timed/temporary qualifiers and target selection remain attached. `_steps()` groups only adjacent compatible mandatory SELF physical/magic counter changes in the display, without changing execution. |
| `hover_content.minimum_size_changed` → `LocalMatchController._layout_hover_panel()` | Deferred layout fits the compact, 360-unit-wide bottom-left hover host without an outer frame or details heading. The ScrollContainer expands/fills its height, keeping clipped content visible; resizing descriptions does not refresh board cells or restart Bash animation. |
| `HexCell.refresh()` → `_render_bash()` / `_update_bash_info()` | Board state/selection refreshes create a split only for a new live Bash. Rendering constructs a typed participant array directly and marks the display retained only after both portraits and labels exist; hover tweens require that completed display. The same encounter updates life, both modifiers, activity tint, and action rows in place, preserving its current hover animation and pending side-change delay. |
| `HexCell.bash_unit_hovered` → `GuerraBoard.hex_unit_hovered` → `LocalMatchController._on_hex_unit_hovered()` | Pointer entry/side changes identify the exact participant for the hover card immediately, including during the neutral split transition; this path never refreshes the board. Tile exit clears both tile and participant focus. |
| `Collection.fire_DR` / `bow_DR` / `cannon_DR` / `bomb_DR` / `defuse_bomb` / `gore_DR` / `movement` / `shield_DR` | Object-authored actions; compose activity costs and pass target, timing, and token rules through named verbs. Bow uses `Selectors.BowTargets` to include permanent unit range upgrades; Movement resolves immediately and can create a delayed Bash. |
| `ActionSticker` / `Collection.with_action_policy` | Records typed P/F/T/A definitions on an action phrase; the existing payment/resolution path applies each sticker's specific rule. |
| `Collection.reed_archer_sharpen_trigger` → `Verbs.upgrade_bow` → `Action.upgrade_bow` → `UnitInfo.add_bow_counters` | Wound captures a cost-free ALL-on-SELF upgrade, applied automatically before combat continues. Adds persistent Bow damage/range counters; effective Bow values, selector range, combat, and snapshots read the same properties. |
| `Collection.grant_action_values` → `Verbs.grant_action_values` → `Action.grant_action_values` | Captures chosen unit recipients and the current player-turn expiry; `UnitInfo.effective_action_values` reads it until `Match._next_turn` expires it after End followups. |
| `ContinuousEffect.have` → `UnitInfo.effective_action_values` | Derives action values from current sources and recipients without storing per-unit values or mutating shared definitions. |
| `Collection.squirrel_king_kindle_trigger` → `Verbs.mend` → `Action.mend` | Squirrel King's captured target-stage Fire declaration automatically restores one current life with ALL on SELF as a command followup, capped at max life; it does not wait for attack resolution. |
| `Collection.thunder_toad_charge_trigger` → `Verbs.up_life` → `Action.up_life` | Thunder Toad's hostile-Stun trigger automatically changes current/max life by −1/+1 with ALL on SELF; `MatchSnapshot` preserves the updated max life. |
| `RulesRunner.submit(effect, source)` | Managed player command; owns payment, captured followups and token completion. |
| `Board.observe_execution(execution)` | Runner notification; connects phrase and effect confirmation controls without owning payment. |
| `Board._unhandled_input()` → `_clear_focus_after_unmatched_click()` | Cancels a preview/deployment after an unrelated unhandled click. HUD buttons consume input first; legal HexCell picks claim the click before the deferred cancellation. |
| `Board.select_effect(effect, source, trigger)` | Low-level integration entry; caller owns accounting. Normal play uses submit. |
| `UnitInfo.eval(ieff)` / `Effect.eval(source, trigger)` | Direct activation entry; caller owns action-token accounting. The local controller uses the Board callback path. |
| `EffectExecution.start()` | Validates event and phrases, then emits `phrase_started` before `PhraseExecution.begin()`. |
| `Effect.ConsequenceSequence` | Card definitions provide ordered phrases; `EffectExecution` resumes each step and records `step_N` results. |
| `PhraseExecution.begin()` / `choose()` / `confirm()` | Board attaches on `phrase_started`; cell/menu/button handlers resume the pending choice. |
| `Verbs.fire(amount)` → `Action.fire()` | Phrase commit calls the verb's bound action; Action delegates to `CombatResolver.declare_fire()`. |
| `Verbs.bow(amount, range)` → `Action.bow()` | Phrase candidates come from `Selectors.BowTargets`; both candidate legality and CombatResolver declaration include permanent Bow bonuses on the source unit. |
| `Verbs.movement(range, flying)` → `Action.move()` / `Action.fly()` | Phrase commit resolves the destination through CombatResolver; it captures origin control, changes position, cancels any Bash dodged by the mover, and creates a new Bash on an enemy landing. |
| `Verbs.mend(amount, range)` → `Action.mend()` | Phrase commit restores actual life up to starting life, emits a resolved Mend event, and refreshes derived regional control. `CardCatalogue.spring_temple()` authors the reference card. |
| `Verbs.stun(amount, range)` → `Action.stun()` → `CombatResolver.stun()` | Phrase commit deactivates an enemy and adds the requested Stun counters. The recipient may already be inactive; all other counters, including temporary protection, remain intact (2026-10-26 ruling). `Collection.stun_DR()` adds the shared activity/token policy. |
| `Verbs.revive()` → `Action.revive()` | A captured death trigger chooses a defeated allied non-hero, restores it to full life in undeployed reserve, and leaves deployment to a later command. The source cannot revive itself. |
| `Verbs.return_to_hand()` → `Action.can_return_to_hand()` / `Action.return_to_hand()` | PhraseExecution offers deployed UNIT identities, revalidates the exact choice, then moves it inactive to its owner's hand without Reset. Emits one `return_to_hand`, cancels departed Bash records and refreshes control inside one runner boundary. The selector supplies ownership/range restrictions. |
| `WildRules.harvest_counters()` → `Selectors.CountersOf` → `PhraseExecution.AMOUNT` / `choose_amount(X)` | Collect one friendly deployed UNIT, one positive counter PROPERTY and one bounded positive X without payment. CostPayment revalidates all choices, commits atomically and records `cost_N.amount`; `RuleNumber.paid_amount(N)` supplies consequences. |
| `Verbs.return_and_deploy()` → `WildActions.return_and_deploy()` → `Match.deploy_from_effect()` | Chinchilla Returns one friend, recovers at full current maximum health on that captured hex and emits a new Deploy without ordinary placement/resource requirements. Followups wait for both zone changes. |
| `Match.action_event(return_to_hand)` → `GuerraBoard._on_action_presentation()` → `board_return.gd` | Snapshots the departing figure before repaint, fades upward and waits as finite causal feedback before trigger acknowledgements/phase continuation. |
| `Verbs.bomb_throw` / `defuse_bomb` → `Action` → `CombatResolver` | Phrase commit places/merges or removes an inert bomb; Fire lights it and Cannon's area resolver handles the blast and chains. |
| `HexCell.refresh()` → `_refresh_bomb_indicator()` | Displays the inert bomb or queued blast's captured `bomb_hex` on the right side, including during Bash. `MatchSnapshot` preserves the center so lit markers survive reload. |
| `HexCell._add_unit_figure()` / `_update_bash_info()` → `BoardCharacter.setup()` / `set_follow_pointer()` / `set_hover()` | Six manifest-mapped PixelLab appearances replace their board portraits. Selecting switches seated to standing and enables eight-direction cursor facing outside the home hex. Hover controls opacity and fades info to 35%. Other cards keep their portraits; mapped tray/hover portraits use the matching standing image. |
| `CombatResolver.walk_path()` → movement event `path` → `Board._on_action_presentation()` / `_advance_walk()` | Legality and committed movement share one deterministic BFS through empty intermediate tiles. The board follows captured hex IDs with nonblocking character walking and departure/arrival info fades. |
| `Board._advance_walk()` → `BoardCharacter.set_walk_direction()` | Each segment selects one of eight directional walking cycles: eight frames for Mouse Archer, six for the other five appearances. |
| `Board._layout_board()` → `BoardBackground/Terrain` | The PixelLab map PNG shares the board camera/origin. Exported `terrain_anchor` (PNG pixel at axial origin) and `terrain_scale` align its clearing/terrain with the hex grid across viewport changes; the sprite has no input handling. |
| `Board._ready()` → `BoardAmbience.setup()` / `Board._layout_board()` → `realign()` | Places 23 grass tufts and 22 bushes in six compact clusters outside the playable hexes, sharing terrain calibration. Each plant rests 2–10 seconds, then plays once; a 10% roll starts its whole cluster together. Layout refreshes positions without rebuilding animations. |
| `Board/ScreenLeaves._ready()` → `_reset_leaf()` / `_process(delta)` | Seeds and recycles 12 five-frame leaves across the viewport beneath Interface, with private cosmetic randomness and no input or rules ownership. |
| `BoardAmbience` Timer.timeout → `_spawn_weather()` → `_weather_effect()` → animation_finished → `_fade_weather()` | Disabled by default (`weather_enabled = false`). When enabled before setup, every three seconds wind and tornado spawn at random vacant hexes, fade in, play once and fade out/free. Cosmetic sprites remain beneath units/info and never consume input, rules time or game RNG. |
| `HexCell` selection refresh → `BoardCharacter.set_follow_pointer()` → stand-up frames / `_show_frame()` | A new selection starts the card's nine-frame idle-to-standing animation once. Each frame's cached opaque foot edge is translated to the seated idle baseline; completion preserves the same baseline for standing/pointer-facing poses. Deselecting or committing an action cancels the cosmetic rise without delaying rules. |
| `Board._on_action_presentation()` → `HexCell.play_character_action()` → `BoardCharacter.play_action()` | Committed Bow/Fire target-stage declarations or Bomb-throw resolved events play the supplied character action once. Archer uses seven frames and briefly holds its final action pose; Mole King uses its alternate-state Fireball; the other four use their nine-frame custom clips. Preview and delayed impact do not replay them. |
| `Verbs.gore` / `push` / `pull` / `push_bomb` / `pull_bomb` → `Action` → `CombatResolver` | Phrase commit captures Gore's path hits, displaces a unit/Bomb along an axial line, and creates Bash on enemy landings. |
| `CombatResolver.resolve_window(defender)` | `Match.complete_action()` calls it at Combat-resolve; queued Bow/Gore, Cannon/Bomb, Fire, then eligible Bash resolve in order. |
| `Match.defeat(unit)` | Lethal Fire calls it; stable army entry remains while the unit loses its live hex. |
| `Match.action_event` → `RulesRunner.capture_event()` | Match connects this once; the runner de-duplicates occurrences, orders matching `trigger_effects`, and drains supported cost-free ALL consequences after each event. |
| `UnitInfo.state_modifiers()` → `StateModifier.evaluate()` → `Condition.test()` | Modifier getters call this read-only path; attached contributions change effective stats without counter writes. |
| `UnitInfo.state_modifiers()` → deployed source `ContinuousEffect.evaluate()` → `TargetResolver` / `Condition` | Effective modifier reads scan deployed aura sources and test each current recipient; the War Temple factory uses this path during Bash. |

The local prototype's `RulesRunner` spends tracked actions by calling
`Match.finish_action()` after an effect/deployment and its followups finish unless
the consequence phrase is Action-free. Action buttons remain available at zero
tokens only for effects with that sticker. Direct phrase calls do not advance a turn.
`Action.damage` is only a compatibility notification helper, not physical damage.

## Local two-player match

Running `scenes/game.tscn` starts the object-authored sample roster. Its caller
chain is `Game._ready()` → `LocalMatchController.start_match()` →
`CardCatalogue.starter_army()` → `Match.start_local_match()` → `Match.start_turn()`.
The HUD's Deploy button asks `Match.can_deploy()` for valid tiles, then calls
`Match.deploy()` after a tile click. Deployment spends one player action and one
deployment counter, enters inactive, and adds one Stun counter. At each owner
Start, the hero removes one counter from each friendly deployed unit with positive
Stun, leaving its activity unchanged. After that owner's End effects and choices,
inactive friendly deployed units with no Stun automatically activate; opposing
units are not touched. Activate followups finish before turn-grant cleanup and
the player switch. Already-active units emit no redundant Activate event.
After the player selects a deployed unit
and clicks one of its action buttons, the controller calls `RulesRunner.submit()`;
the shared phrase runner pays `self_stun`, resolves the choices and followups,
then the runner calls `Match.finish_action()` once.
Clicking a friendly figure or its Choose unit card selects its source;
the card then opens that unit's actions. After roster validation,
`Match.start_local_match()` adds an implicit Walk 1 to every non-temple without
an ordinary Walk/Move/Fly action. Explicit Move 0 suppresses it, and triggered
movement does not count. The action appears first and is marked default; its
implicit definition is omitted from compact hex infos. Clicking an action starts
the usual runner. While a target preview is awaiting payment, another action
button switches the preview without spending Stun or an action token. Board
outside-click cancellation runs in `_unhandled_input()`, after HUD controls:
running it in `_input()` would cancel on button press, removing the selected
card's action buttons before their release can switch to Bow. For example,
select Reed Archer, then click `2  1🏹4` to replace the default Walk preview
with Bow targets. An unrelated board/background click still cancels the preview;
legal tile picks claim the click before the deferred cancellation check.
Board figures use their card illustrations, inactive figures use a parchment-gray
tint, and legal target hexes move down slightly and shrink without changing their
region frame color. `HexCell.refresh()` uses the pixel-art color variants based
on current control: red for Player 1, blue for Player 2, and grey for neutral.
Starting and front regions use dark red/blue; intermediate regions use light
red/blue. All variants derive from the selected second frame of
`assets/dark-blue-hex.pxo` (its first frame is blank). The 128×128 transparent
canvas contains only the pixel-art lower rim; the original source is unchanged.
The scene maps pixel `(64.5,80)` to the tile center with scale
`(2.857143,2.888889)`, fitting its 91-pixel width to 260 world units and its
30-pixel lower half to the hex's 86.67-unit bottom. Nearest filtering keeps crisp
pixels, and terrain stays visible through the transparent top/interior. Control
changes update rim color on the next refresh; regional control, bonuses,
deployment and selection legality are unchanged.
The updated source removes the sloping sides and keeps only the bottom ornament.
Re-exporting preserves the same canvas anchor/scale so the shorter artwork stays
at the hex bottom rather than stretching it to the full tile width.
The ornament is rendered at 40% opacity and raised 18 world pixels from that
original alignment, leaving more space around character feet without shifting
the tile's collision, characters, info, or selection targets.
Matching palette variants are available as both editable `.pxo` and exported
`.png` files: `assets/dark-red-hex`, `light-red-hex`, `light-blue-hex`, and
`grey-hex`. These preserve the source's frames, pixel positions and alpha while
shifting the existing shading toward the corresponding legacy region color.
`assets/hex-color-preview.png` compares them alongside the original blue. All five
PNGs are used by the board with the same opacity, size and raised position.
An unresolved `BashInfo` at a tile switches `HexCell.refresh()`
to Guerra-style Player 2-left/Player 1-right split portraits, exposing each
unit's current life and centered signed physical/magic modifier pair (magic in
purple, omitted at zero). Pointer motion inside the hex selects
one side; the shared portrait expands with a slide, the opposing side fades, and
that card's three status/action rows fade in beneath the separate stats. Switching
sides first restores the split for Guerra's 340 ms transition interval, then
reveals the new side. The bottom-left hover card immediately follows the same
participant, even during that interval. Leaving restores the split and closes
inspection. Match and selection refreshes update the retained Bash nodes, so they
do not reset its active fade or pending side-change timer.

For example, hover the left half of a pending Bash to inspect red Player 1 alone;
cross to the right half to inspect Player 1 while the split resets, then watch
that portrait expand. A rule changing either participant's modifiers updates
the displayed values without restarting that reveal.

### PixelLab terrain background

`scenes/board/board.tscn` places `assets/maps/pixellab-battlefield.png` behind
the hex frames, characters and markers. This is the existing PixelLab map
`d3283b82-4c5a-48b5-b7b8-bf72a39082f5`, exported at 1600×960 from terrain cells
x −2..47, y −2..27. Refreshed on 2026-10-20 with the connected terrain and central
clearing, with no placed objects. The PNG is assembled from
four adjoining full-resolution map renders; no terrain was repainted/generated.
PixelLab's existing missing-transition black tiles remain in the source export.

`Board._layout_board()` places PNG pixel `(784, 464)` at axial `(0, 0)` with
world/pixel scale `(1.73, 2.24)`, calibrated to the smaller dark-green area exported
on 2026-10-20. The clearing matches the missing middle hex, the dark-green boundary
follows the outer hexes, and the extra surrounding terrain keeps the PNG's outer
edges farther from the board view. The map and hexes share
one world-space camera, including compact layouts and viewport resizing. The
parchment still fills space outside the map/HUD; the PNG never consumes clicks.
To adjust a revised map, edit the Board's `terrain_anchor` and `terrain_scale`
exports; for example increasing anchor X shifts the PNG left without moving hexes.

### Animated terrain ambience

The `Board/Ambience` node renders above terrain (z −5 versus background z −10)
and beneath hexes, characters, info and HUD. It contains AnimatedSprite2D nodes,
not mouse-handling Controls or collision objects. Board initializes it once after
layout; it has no saved rules state and runs during pending choices without
blocking play.

Available PixelLab object types, tall grass
`4a6bff2f-921e-4b45-b75d-a19c7b6949a1` and bush grass
`a97240b3-72c6-4635-94d8-289241567b32`, use their nine-frame animations at six fps.
`assets/environment/grass-placements.json` places 23 enlarged grass tufts and 22 bushes in six compact groups around the board perimeter,
including their terrain-cell positions and footprint sizes. Clusters mix grass and bushes; three plants nearest the upper-left board edge were removed to leave more clearance. Placements are sorted by foot position so nearer sprites draw over those behind them. Each placement carries an explicit `group` ID. A one-shot Timer per plant waits a fresh random 2–10 seconds, then `_grass_pause_finished()` plays one nine-frame pass. Its 10% group roll cancels pending sibling timers and restarts the whole cluster in sync. `animation_finished` calls `_grass_finished()` to restore frame zero and schedule fresh independent delays. All randomness is private presentation state.
`realign()` maps the 32px terrain cells (minimum −2,−2) through Board's PNG anchor
and scale; the original grass feet sit at their placement position.

`wind.pxo` is exported unchanged into nine PNG frames under
`assets/environment/wind/`, preserving its six-fps rate. The existing PixelLab
wind/tornado object `275aa516-4ae0-45c9-a337-4337529c080d` supplies another nine
frames, played at eight fps. Local wind and tornado are currently disabled through
`weather_enabled = false`; their assets remain available. If enabled before setup,
a Timer spawns one of each every three seconds at
random vacant board hexes with a small central offset, using separate hexes when
possible. Each fades in for 0.2 seconds while playing its single pass, then holds
the final frame during a 0.45-second fade and is freed. Nothing is spawned when
no hex is vacant. For example, with weather enabled, leave a match idle for three seconds to see two
short weather effects while grass and bushes sway intermittently; selecting/playing
units continues normally. Reusing existing animations spends no generation credits.

### Screen-wide drifting leaves

`Board/ScreenLeaves` calls `screen_leaves.gd._ready()` on scene entry. It caches
three unchanged five-frame, 16×16 PNG sheets from EdgeLoopRepeat’s Windy Leaves
pack, creates a fixed pool of 12 AnimatedSprite2D nodes, and seeds routes across
the screen immediately. `_reset_leaf()` chooses size, speed, height, flutter phase
and color variation. `_process(delta)` advances normalized routes left to right
with shallow downward drift, flutter, rotation and 65% maximum opacity; leaves
fade at both edges and recycle off-screen. Viewport size is read each frame so
resizing follows the screen independently of board camera zoom. No gameplay state,
input, timers or global RNG are involved. `leaf_count` is editable on the scene
node before entry. Canvas layer 1 draws over the board; Interface uses layer 2.
For example, open a match and leaves are already scattered across the screen,
then continue drifting while selecting units or resolving choices. Original asset
source and usage terms are recorded in `assets/environment/windy-leaves/CREDITS.md`.
The previous local wind/tornado clips remain disabled.

### Playground character appearances

BoardCharacter uses six explicit appearance mappings from
`assets/characters/playground/manifest.json`:

| Rule card | PixelLab appearance |
| --- | --- |
| Squirrel King | red squirrel king |
| Pine Processionary | mouse necromancer |
| Thunder Toad | red squirrel climber |
| Walnut Crab | mole artificier |
| Reed Archer | mouse archer |
| Mole Artificer | mole king |

The manifest records seated/standing source IDs, stand-up and action frame counts,
and the eight directional walk counts. Each card folder contains `idle.png`,
`rotations/`, `stand/`, `walk/<direction>/` and `action/`. Downloaded images retain
their native canvases and pixels. This replaces the older project-root mole and
Reed-specific paths for these six appearances. Other cards retain their portraits.
Rule definitions, stable card IDs, snapshots, ownership and stats are unchanged. Display names now match the mapped PixelLab character names.

`BoardCharacter._appearance_key()` matches a full card prefix followed by its
player suffix, rather than splitting at the first '-p': Pine Processionary's
internal '-p' must remain part of the card ID. `supports()` gates board characters
and walking overlays. `portrait_path()` supplies the same standing image to
HexCell Bash art, the card tray and hover cards through their `_card_art_path()`
helpers. `setup()` loads manifest-selected clips before the figure is parented.

At rest each character sits south at 50% opacity with fully visible hex info.
Selection plays the nine-frame stand-up once at 10fps, then uses eight standing
facings only while the pointer is outside the real home hex collision polygon.
Inside it holds standing south; deselection turns south by the shortest facing arc and reverses the stand-up clip to seated south. Hover fades
opacity to 100% and the corresponding info to 35%. Ordinary/Bash refreshes retain
character nodes and do not restart the rise. Per-figure greyscale follows live activity after committed presentation finishes. Existing scale 2 and shader enlargement 1.5 remain bottom anchored.

`_frame_foot_level()` caches each texture's used-alpha lower edge relative to its
canvas center. `_show_frame()` grounds each stand/static frame to seated idle.
For walking/actions, the cycle's first frame supplies its anchor instead of the
smaller standing rotation canvas, preserving authored movement on expanded
PixelLab canvases without a baseline jump. No frame is stretched or cropped.

Committed Move events keep the historical legal BFS `path` before Match moves
the unit. Board creates a cosmetic overlay, using the same six appearances,
and `_advance_walk()` selects facing per segment and moves at 0.8 seconds per
step. Mouse Archer has eight-frame directional cycles; the others have six.
Departure info fades over the first half-step; destination info starts appearing
in the final half-step. The stationary destination sprite is hidden until arrival.
On arrival `_finish_walk(id, true)` calls `HexCell.finish_character_walk()` with
the overlay's final directional sector, before releasing the overlay and revealing
the stationary character. That character turns to south through the shortest arc
of its eight standing facings (0.12s per pose with a 0.1s crossfade; north ties turn through west),
then plays all nine stand-up frames backward at 10fps to sit. Feet stay grounded
through the reverse transition; info fades keep their existing travel timing.
Overlays follow hex IDs across resize and are removed on another move, defeat,
or reset. Fly/displacement presentation remains separate from this walk prototype.

Bow/Fire target declarations, resolved Bomb throws and resolved Stun/Shield
operations play the mapped south action once after repaint. Most action clips
have nine frames; Archer has seven and holds its final drawn-bow frame for 0.25s.
Mole King uses its alternate `stand1` state's six-frame Fireball. `play_action()`
first calls `_turn_to_south(true)` from the current facing, then plays the clip
and calls `_start_sitting()` to reverse the stand-up sequence. `_process()` owns
these cosmetic phases; selection and hover refreshes preserve them. A new command
can replace an old sequence. An action issued during cosmetic travel cancels the
overlay and carries its last facing to the stationary actor's turn. Invalidation
or movement replacement calls `_finish_walk()` without the arrival flag and never
sits at an obsolete tile. These existing
clips are presentation only and delayed attack impact does not replay declaration
animations. They never delay rules, costs, triggers, player choices or combat.

For example, select Thunder Toad: the red squirrel climber rises with grounded
feet and follows the pointer outside its hex; committing Stun turns the character south, plays its supplied
rope-action clip, then reverses the stand-up frames to sit. Its actual Stun rule and card name remain Thunder Toad. Select
Reed Archer, choose Walk and a destination, and its new mouse-archer sprite uses
the directional path animation with departure/arrival info fades.

### Generated hover descriptions

The hover generator follows Guerra JS's `cardRuleDetails()` /
`detailedRuleDescriptions()` approach: describe structured rules rather than
maintain a second card text. Godot walks the existing object-authored definitions
directly; this adds no DSL parser or execution state to any definition.

`EffectText.unit_lines(unit)` returns compact BBCode rows. It includes implicit Walk
with a `default` marker, each normal/triggered Effect, StateModifier conditions
and signed values, ContinuousEffect recipients/conditions/typed contributions,
stored passive flags, and printed control bonus. Magic text is purple; relative
ownership uses the source player's red/blue color. The UI keeps live life and
modifier totals above these rule rows and fits the smaller window to its wrapped
content. Individual cards keep their background; the outer host has no frame,
and there is no redundant `Hex details` or `Card details` heading. A small
54×72 portrait and single-spaced rule rows keep inspection compact.
The ScrollContainer must use vertical `SIZE_EXPAND_FILL`: `SIZE_SHRINK_BEGIN`
can collapse its viewport because scrolling excludes child height from its
minimum size, hiding the generated content inside an otherwise visible panel.

Ordinary actions use the hex-info amount/sticker/icon/range notation, such as
`1🔥3`, `1P🔥2`, `🥾2`, or `2🛡️`. Action icons are not repeated as names.
`EffectText.compact_action()` accepts simple SELF/CHOOSE_ONE actions and the
standard Mend/Stun ownership filters; custom filters, exact distances,
directional rules, other actors, and ALL targets retain their explicit criteria.
Normal self-Stun payment is implicit. Custom costs and trigger payments come
from the actual CostPhrase/CostBundle, including self-Stun and decrement amounts.
Optional trigger policy follows EffectExecution: DEFAULT
triggers with costs are optional, DEFAULT triggers without costs are mandatory,
and explicit OPTIONAL/MANDATORY overrides this. Only optional policy adds
`you may`; mandatory policy never adds `you must`. Optional phrases also use
`you may`. Sequences retain ordered steps, and ALL keeps an explicit `all`.
Trigger anchors use concise participant/icon/target clauses; target-stage events
retain a `(declared)` qualifier, while ordinary resolved events use the implicit
colon notation. The common deployed scope of state rules and auras is implicit;
their nontrivial source/recipient conditions remain visible.

Descriptions preserve native selector domains and explicit projections, including
the convenience HEX-to-UNIT conversion required by a unit-targeting verb.
Exact-distance and within-radius selectors, directions, source/subject/event/
recipient anchors, Boolean conditions, quantifiers, comparisons, event facts,
and query owner/type/state/region/side/control restrictions are represented.
Targets describe the definition's criteria, not a cached list of currently legal
candidates; verb legality still owns operational restrictions.

Live Move/Fly/Fire/Cannon/Bow values follow the currently implemented engine
derivations only when the described actor is SELF. Each spatial selector keeps
its own distance and applies its supported range grant independently. Grants
are described as signed adjustments rather than executed or added to themselves;
timed action-value grants state that they last through the current player's End.
Upgrade descriptions use signed numeric tuples rather than repeating parameter
names:

| Object operation | Display example | Slot order |
| --- | --- | --- |
| Permanent Bow upgrade or two-value action contribution | `+1🏹+2` / `+1🔥+0` | First action value, icon, second action value. |
| One-value movement or defuse contribution | `🥾+1` | Range stays on the right, matching the action notation. |
| `up_life(actual, maximum)` | `-1/+1❤️` | Current life / maximum life. |
| StateModifier, modifier contribution, or persistent modifier counter change | `+2/-1` | Physical / magical; the second value retains its purple color. |
| A physical-only counter change | `+1/+0` | The unchanged component remains visible as zero. |

The same action-upgrade notation covers permanent Bow counter operations,
timed grants, and continuous action contributions. Their recipient/condition and
explicit timed or temporary lifetime remain in the surrounding clause.
Ordinary Mend still uses its one-amount action form, such as `1❤️ to itself`;
the slash-heart form describes the two-value life adjustment.

For Ironhide/Prism-style sequences, adjacent mandatory `change_counter` phrases
for SELF's persistent physical and magical counters are presented as one
`+1/+1 to itself` pair. The formatter requires matching target modes, no optional
phrases or qualifiers, and the same SELF actor/host. It does not group costs,
unrelated recipients/properties, or intervening steps. Only text is grouped;
sequential mutations and their separate events retain their original order.

Handwritten `label` fields remain available to other callers but have no effect
on generated hover rules. Unknown selector/condition/contribution/consequence
types display an explicit `Unrecognized ...` marker; extend this formatter when
adding a new object type rather than inventing a card-specific description.

For example, these are inspection calls, not effect activations:

```gdscript
var archer := CardCatalogue.reed_archer(1)
var rules := EffectText.unit_lines(archer)
# Includes 1🏹4; normal self-Stun payment is implicit.
# The Wound trigger's permanent Bow upgrade is +1🏹+1 to itself.

var king := CardCatalogue.squirrel_king(1)
var king_action := EffectText.describe_effect(king.effects[0], king)
# 1🔥3
var king_trigger := EffectText.describe_effect(king.trigger_effects[0], king)
# this unit 🔥 to any hex: 1❤️ to itself

var moth := CardCatalogue.prism_moth(2)
var trigger_text := EffectText.describe_effect(moth.trigger_effects[0], moth)
# Describes a declared Bash against this unit, followed by +1/+1 to itself.

var temple := CardCatalogue.war_temple(1)
var aura_rules := EffectText.unit_lines(temple)
# Describes +1/+0 to friendly recipients that are bashing enemies,
# even if the aura has an empty handwritten label or currently has no recipients.
```

`ControlResolver` owns region grouping and strength. It adds current life and
printed `UnitInfo.control_bonus`, then the home player's 0.5 in starting and
intermediate regions; ties are neutral. Deployment requires the destination's
region to be controlled and vacant. `UnitInfo.physical_modifier` adds a live +1
when its owner controls its current region. This bonus never contributes to
control strength. `Match.refresh_control()` updates the tile display/query cache
after setup, deployment, and defeat; calculations used for legality remain live.

`LocalMatchController` currently exposes one action and three deployments per
player as editable Inspector values. These are test format values, not finalized
rules. A successful deployment or action spends the one action and automatically
advances the turn after its followups finish; the End turn button can pass early.
Each player starts with a distinct hero and two troops. The Squirrel King and Mole
Artificer demonstrate Fire and Bomb/Pierce Fire; the troops include Bow/Gore/
Push/Pull and Cannon/Bomb actions. Their trays show card art on the parchment
background and resize around the board. The full catalogue, additional card
actions, and general scheduled consequences remain future work.

`select_phrase` runs only a standalone phrase and does not pay an enclosing cost.
`PhraseSelection.begin_standalone` provides the same behavior without a board.

Single costs require CHOOSE_ONE and a verb marked as an atomic cost
(`self_stun` or `decrement`). Unsupported multi-target costs fail before any
mutation. Cancelling before payment leaves the board unchanged. Once paid, the
cost is not refunded if the consequence is cancelled, declined, or fails.
A missing consequence completes successfully after payment.

For ordered consequences, pass an `Effect.ConsequenceSequence` as the third
argument to `Effect.new()`. Each step uses the same SELF, gets independent
subject/target choices, and starts only after the preceding step succeeds:

```gdscript
var sequence := Effect.ConsequenceSequence.new([
    Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.change_counter(1),
        Selectors.PropertyOf.new(Selectors.Self.new(), UnitInfo.PHYSICAL_COUNTER)),
    Effect.ConsequencePhrase.new(Selectors.Self.new(), Verbs.change_counter(2),
        Selectors.PropertyOf.new(Selectors.Self.new(), UnitInfo.MAGICAL_COUNTER)),
])
var effect := Effect.new(null, null, sequence)
$Board.select_effect(effect, TargetRef.unit(0))
```

The runner preserves progress while each step waits for the Board. Failure or
cancellation stops later steps; earlier successful steps and paid costs remain.
Completed steps are available as `execution.results["step_0"]`, `step_1`, etc.
Use `Selectors.Completed.new(&"step_0", &"targets", kind)` to refer to an
earlier step's selected targets. `results["consequence"]` summarizes all step
outcomes after the whole sequence succeeds. Use `Effect.CostBundle` for atomic built-in activity/deactivate/decrement
payments; all selections precede cumulative preflight and commitment. See
[M2 cost bundles](M2_EXECUTION.md#atomic-cost-bundles).

`Collection.fire_DR(damage, radius, instant, pierce, tireless, action_free)` is a
complete sticker example. Instant and Pierce configure Fire resolution; Tireless
removes the generated self-Stun cost; Action-free skips the local action token but
still pays self-Stun unless Tireless is also set. An Action-free Fire remains legal
at zero tokens. Combat factories now share the default-cost/sticker policy; named
ActionStickers are also available through Collection.ranged. Numeric Bow counters
and temporary action-value grants use separate stored paths; continuous sticker
grants and scheduled future actions remain future work.

Completed phase results are available under `execution.results["cost"]` and
`["consequence"]`. Use `Selectors.Completed.new(&"cost", &"targets", kind)`
(or role `&"subject"`) for explicit cross-phrase references.

## Events

Actions emit `Match.action_event` with an `EffectEvent`, in addition to the
existing deactivate/fire signals. Supply this event when starting a triggered
effect. `EventPhrase` matches action name and selected participants; it does not
execute its verb or rerun the action's legality check after it has happened.
An event selector can use `Selectors.Reference.new(Selectors.Anchor.EVENT_TARGET)`
or EVENT_SUBJECT.

Each `EffectEvent` captures a unique `occurrence_id`, `turn_number`, `phase`, and
`controller`; supplied details are copied into `event.data`. Historical
information such as movement origin belongs in named event data fields. Event
queries otherwise inspect current Match state.

`Match.action_event` feeds `Match.rules_runner`. It captures all matching deployed
sources in active-player/army/printed-rule order before executing any consequence.
Die is captured before deployed presence is removed, preserving spatial matching.
The runner de-duplicates occurrence IDs, retains executions across subject/target
choices, and defers followups until the relevant mutation or effect bundle ends.
Cost followups finish before parent consequences; End choices block player switch.

Costed triggers are optional by default, with confirmation before payment.
`Effect.policy` can explicitly select OPTIONAL or MANDATORY. Free triggers are
mandatory by default. Unsupported atomic bundle cost types fail before mutation;
ordinary triggered choices and payment are no longer skipped. A diagnostic work
limit retains pending work on a runaway chain. See M2_EXECUTION.md for details.

```gdscript
var hit := Effect.EventPhrase.observe(&"hit", Selectors.Self.new(),
    QuerySelector.new(TargetRef.Kind.UNIT))
var gain := Effect.ConsequencePhrase.new(Selectors.Self.new(),
    Verbs.change_counter(1),
    Selectors.PropertyOf.new(Selectors.Self.new(), UnitInfo.PHYSICAL_COUNTER),
    Effect.Phrase.TargetMode.ALL)
var trigger := Effect.new(null, hit, gain)
unit.trigger_effects.append(trigger)
```

## Commit behavior and UI

Each commit checks current source, subject, targets, and action legality.
Repeated clicks or reentrant callbacks cannot commit the same phrase twice.
ALL freezes its membership, then rechecks each target before applying the action:
targets removed or invalidated by earlier actions are skipped; new arrivals do
not join the batch. Per-target outcomes record success or failure. A batch succeeds
if at least one target succeeds. It is sequential, not atomic or simultaneous.

The board highlights target locations. Multiple unit/property choices on one tile
open a menu; players and off-board properties/units use a separate button.
Escape cancels. Optional effects expose a confirmation button.

The effect owns its current phrase; the phrase holds a weak parent reference to
avoid a RefCounted cycle. Retain the effect execution for the life of its UI.

## Fire and modifiers

The complete source-linked JS rules and 77-card reference are in
[GUERRA_RULES.md](GUERRA_RULES.md).

```gdscript
# Usually queue Fire and let the opponent respond before combat.
var phrase := Effect.ConsequencePhrase.new(
    Selectors.Self.new(), Verbs.fire(3), DistanceSelector.within(2)
)
$Board.select_phrase(phrase, TargetRef.unit(0))

# After the entire action and its choices finish, the local controller calls:
Match.finish_action(1)      # Spends one token; Fire remains pending for a response.
Match.finish_action(2)      # On the last token, Player 2's combat window resolves Fire.
```

The local controller tracks an editable test allowance of one action and three
deployments per player; these are not finalized format rules. A completed action
or deployment automatically ends that player's turn after all followups;
`Match.complete_action(player, 0)` is also used by the pass button. Start/End and
combat continuations now wait for triggered choices; future-phase scheduled
consequences remain M3 work.

Fire defeats only when `life <= damage - magical_modifier`. A nonlethal contact
leaves life unchanged. It consumes `temp_magical`, but never `magical`, `physical`,
`temp_physical`, or continuous contributions. A captured victim that leaves its
tile dodges; a replacement on that tile is not hit. An originally empty target can
catch a later enemy. The attack remains pending even if its source is defeated.

`Verbs.fire(amount, true)` is instant; the third argument enables piercing.
Obsidian is represented by the unit FLAG property `obsidian`; it prevents ordinary
Fire contact and preserves temporary protection. Pierce bypasses Obsidian and
magical modifiers, while still consuming temp_magical on contact.

Every unit starts with four modifier COUNTER properties: `physical`, `magical`,
`temp_physical`, and `temp_magical`, plus a numeric `stun` counter.
`Verbs.shield(n)` and `Verbs.mshield(n)` add to
the relevant temporary counter on an ally. To modify persistent counters:

```gdscript
var bonus := Effect.ConsequencePhrase.new(
    Selectors.Self.new(), Verbs.change_counter(1),
    Selectors.PropertyOf.new(Selectors.Self.new(), UnitInfo.MAGICAL_COUNTER)
)
```

`change_counter` accepts signed deltas. Effective modifiers are persistent +
temporary + live state contributions, exposed as `physical_modifier` and
`magical_modifier`; the compatibility `modifier` vector has physical x and magic y.

```gdscript
# Attach this only to a unit with the printed rule.
unit.state_effects.append(StateModifier.adjacent_to_hero())
```

This adds +1 physical while any hero is adjacent and stops immediately when the
condition becomes false. Multiple adjacent heroes do not multiply one rule.
Different attached rules add their contributions. State evaluation never mutates
counters. A deployed unit gains a derived +1 physical while its owner controls
its region. Regional control and deployment validation live in ControlResolver
and Match; the physical bonus is not stored in a counter.

`Condition.Wounded` supports attached wounded-only rules; `Condition.All`,
`Condition.AnyOf`, and `Condition.Not` compose read-only predicates. The current
catalogue examples `CardCatalogue.alps_lone_wolf(player)` and
`CardCatalogue.pyromaniac_beetle(player)` demonstrate a wounded +2 physical
bonus and a deployed +2 magical bonus. `CardCatalogue.ironhide_boar_pup(player)`
demonstrates a Hit trigger that grants persistent physical and magical counters.
`CardCatalogue.prism_moth(player)` adds a target-stage Bash trigger and an Instant
Bow; `CardCatalogue.canyon_hawk(player)` carries the Steady flag read by Bash.
These factories are available for deck construction and focused tests; they are
not added to the six-card local starter roster.

`ContinuousEffect` adds a narrow aura form for physical/magical modifiers. It has
a source condition, a recipient selector, an optional per-recipient condition,
and signed modifier deltas. `Selectors.Recipient` reads the current recipient;
`Selectors.Self` remains the aura source. The current card-backed example is:

```gdscript
var temple := CardCatalogue.war_temple(1)
```

Its friendly-unit aura contributes +1 physical only while that unit is in an
unresolved Bash against an opposing unit. `UnitInfo.state_modifiers()` scans
deployed sources on each read, so the bonus stops as soon as the Bash resolves or
the temple leaves play. The aura does not write counters. Other contribution
types, expiry lifetimes, schedules, and explanations in the modifier display
remain future M3 work.

`Match.fire` announces a committed attack for presentation. `Match.fire_resolved`
returns its FireAttack/outcome, including misses. EffectEvent distinguishes Fire
`target` and `resolved` stages; ordinary EventPhrase patterns default to resolved.
Under the approved 2026-10-28 rules, Fire publishes Hit on actual contact and Wound
only on positive life loss. Nonlethal Fire is Hit without Wound; misses and
immunity emit neither. Cannon shares these events; Bomb keeps bomb_hit.

## Bow and Cannon

`Collection.movement(range, flying)` authors Move or Fly with the standard self-Stun
cost. Move searches for an adjacent path of at most `range` steps through empty
playable tiles; occupied intermediate tiles and the board gap block that path.
Fly checks hex distance and ignores intermediate occupancy. Both reject friendly
landings, reserved Bash tiles, and temple actors. Landing on an enemy moves the
actor immediately and creates the ordinary delayed Bash. The resolved `move`
event stores origin/destination hexes and control at the origin; `movement_kind`
distinguishes Fly in the event data. `Match.start_local_match()` gives non-temples
an implicit Walk 1 where no ordinary movement is authored; explicit Move 0
suppresses it, and temples remain immovable. The implicit action is executable
and selectable but omitted from compact hex summaries.

`Collection.mend_DR(amount, radius)` selects injured friendly units within the
radius, applies the standard activity cost, and restores up to the requested
amount without exceeding `max_life`. Full-health targets are omitted by verb
legality. The resolved `mend` event reports the actual amount restored.

`Collection.pine_processionary_trigger()` matches the source's captured death
event and offers defeated allied non-heroes as off-board choices. Reviving
restores full life and reserve status but does not deploy or spend another
action token. The defeated source identity cannot select itself.

`Collection.bow_DR(damage, radius)` authors a physical attack; a selected occupied
hex captures its current opposing unit. Bow resolves in the next opposing Combat
window, or immediately with its Instant argument. It subtracts current physical
modifier, consumes temporary physical protection on contact, and emits Hit even
when protection reduces damage to zero; Wound requires positive life loss.
Titanium prevents contact and preserves temporary protection. A captured target
that leaves the hex dodges; an originally empty hex can catch a later enemy.
`Selectors.BowTargets` adds the source unit's permanent Bow range bonus when it
offers cells, while CombatResolver captures its current Bow damage bonus. Reed
Archer's Wound trigger adds +1 to each bonus; `MatchSnapshot` saves both values.
Squirrel King heals one current life when Fire is declared (the `target` stage),
before its delayed attack resolves, while Thunder Toad
gains max life and loses current life after applying hostile Stun. The tray and
hex action summaries use the same action emoji map as Guerra JS.

These three mandatory self-effects explicitly use `ALL` with `Selectors.Self`:
their fixed recipient requires no player decision. For example, after Reed
Archer wounds an enemy with Bow, its +1 damage/range applies immediately and the
queued combat/phase continuation resumes; clicking the Archer is unnecessary.
Keep ordinary attacks and triggers with a genuine recipient choice as
`CHOOSE_ONE`, which still asks even when only one legal target remains.

`Collection.cannon_DR(damage, radius)` authors a magical straight-line action.
Players choose an aligned endpoint; every playable hex on that line gets a
captured record, including empty hexes. Cannon damages either player's occupants
at resolution using magical modifiers, consumes temporary magic on contact, and
respects Obsidian unless piercing. Both actions resolve after Bow and before Fire
in the current Combat window. The local sample roster contains one of each.

`Collection.bomb_DR(damage, radius)` places or strengthens an inert bomb; bombs
on a shared hex merge damage and preserve Pierce. `Collection.defuse_bomb(radius)`
removes an inert bomb without a blast. Fire targeting a bomb lights it instead
of resolving ordinary Fire. Its magical blast covers the center and adjacent
playable hexes. Delayed blasts resolve after the defender's response; chain-lit
bombs wait for the following opposing window. Bomb attacks use Cannon's magical
modifier and temporary-shield handling; Fire's Pierce setting governs the blast
and bypasses Obsidian. A Bomb's stored Pierce marker is preserved on merge/move.
Each bomb hex has a separate right-side icon with damage and optional `P` below
it, leaving all three card action rows available. Inert bombs use
`bomb-unlight.png`; queued explosions use `bomb-light.png` at their captured
`CannonAttack.bomb_hex` center, never on every neighboring blast tile. This marker
updates before the retained-Bash refresh shortcut and disappears after explosion
or defusing. For example, throw a Bomb, then target it with delayed Fire: the
same hex changes to the lit asset until the blast resolves. Snapshots preserve
the center for newly saved blasts; older snapshots without it do not guess a
lit marker's location. Bomb timing and damage rules are unchanged.
Gore moves immediately and queues physical damage against captured opposing units
still on crossed hexes. Push/Pull move one selected aligned unit; their Bomb variants
move inert bombs and merge them on contact. Enemy landings create a Bash after
the opponent's response. Fast makes a Bash resolve in its creating combat window.
Bash uses life plus physical modifiers, with Titanium, First Strike, Steady, and
temporary physical protection handled by the resolver.

## Verification commands

Run the integration scenes:

```text
godot --headless --path . res://tests/selection_test.tscn
godot --headless --path . res://tests/fire_test.tscn
godot --headless --path . res://tests/local_match_test.tscn
godot --headless --path . res://tests/trigger_state_test.tscn
godot --headless --path . res://tests/m2_test.tscn
godot --headless --path . res://tests/presentation_test.tscn
```

Tests cover native domains, conversion, shared tiles, stable references,
composition, property targeting, isolated contexts, cost and consequence
sequencing, event matching, optional/ALL execution, stale choices, reentrancy,
and the real board click/menu handlers. The trigger/state scene covers continuous
modifier reads, Ironhide's once-per-occurrence Hit trigger, and runner de-duplication.
The local-match scene covers region ownership, deployment, action tokens, the
Stun cost, and Start recovery. Activation timing changed on 2026-10-19 to owner
End after effects; earlier activation assertions predate that ruling. Tests are
only updated/run when the user's prompt ends with `TEST`, per AGENTS.md.

Neutral lower rims use pure-white `grey-hex.png` at 40% opacity, matching controlled red/blue rims. `HexCell.refresh()` applies this opacity when selecting the control texture. The editable `grey-hex.pxo` uses the same white pixels.

Hex rim art and the UnitFigures container are shifted upward by 26 additional world pixels. Board._advance_walk() uses a -18 Y anchor (the prior +8 minus 26) so travelling sprites meet the raised stationary figures without a jump. Picking polygons and terrain positions stay aligned to their original board cells.

### Pixel typography

Godot loads the bundled `assets/fonts/Jersey10-Regular.ttf` through `gui/theme/custom_font` in `project.godot`, giving existing labels, buttons, card text and hover text the same pixel typeface. `gui/theme/custom` loads `assets/fonts/game_theme.tres` with default size 20 instead of 16. LocalMatchController overrides are approximately 20% larger, and HexCell.INFO_FONT_SIZE is 31 instead of 26. HexCell keeps its explicit `INFO_FONT` overrides: `assets/fonts/hex_info_font.tres` wraps Jersey 10 Regular for hex stats, bomb markers and Bash details. The font is bundled locally with its OFL license; no system font installation or network access is needed at runtime. Restart a running game to reload the project default font.

### PixelLab rule icons and bomb ignition

`GameIcons.action_path()` maps Bow, Fire, Stun, hearts and bomb operations to
`assets/icons/`. `GameIcons.bb()` serves EffectText, HexCell life/action/Bash rows
and hover health/bomb rows; `GameIcons.texture()` serves plain action Buttons,
which cannot parse BBCode. Hearts select red for owner 1 and blue for owner 2.
Descriptions always use the unlit bomb, including Light and Defuse actions.
Other action symbols retain their existing presentation. Stun comes from Creator
asset `1792509022298`, also saved as Object `3e1db0e2-57ed-4b39-8f3a-6efea7f00dab`; other sources are listed in
`assets/icons/SOURCES.md`. Existing generated assets are downloaded without new generation.

`HexCell.setup()` calls `_setup_bomb_sprite()` once, loading unlit/lit poses and
nine looping ignition frames at nine fps. `_refresh_bomb_indicator()` reads BombInfo and
unresolved explosion CannonAttack centers: an unlit object displays the unlit
pose; the first lit transition starts continuous ignition playback. Repaints preserve the
current loop frame; removal hides both sprite and numeric damage marker. Returning to unlit
resets the transition. No costs, selections, explosion timing or rule events
wait for this animation. For example, throwing a bomb shows the unlit object,
then igniting it loops the fuse animation until resolution.

Hex info and Bash rows start 20px higher. Board inline icons are 48px, hover/description icons default to 32px, action-button icons cap at 24px, and the board bomb sprite is 56px. Label heights are expanded for the larger symbols. GameIcons owns the description size default; HexCell supplies its board size.


HexCell._fixed_info_rows() gives each explicit ordinary/Bash info row the same transparent 1×60 layout image, matching the tallest Fire icon. Shared line/paragraph separation then produces identical line metrics for text-only, heart, Stun and Fire rows. refresh(), _bash_stats_text() and _bash_card_details() all use it; departing movement ghosts keep the formatted BBCode. The ordinary label height is 260px to allow five uniform rows without clipping. Icon artwork sizes are unchanged.

Uniform hex-info rows retain the 60px invisible strut and now use -16 line separation plus -14 paragraph separation, reducing the gap by another eight world pixels between explicit rows. Ordinary and Bash labels share these values.

Inline icons and action buttons load prepared PNGs from `assets/icons/ui/`.
Originals are cropped to alpha bounds and proportionally fit within 44×44
(hearts: 32×32), using nearest-neighbor sampling and two-pixel gutters.
Prepared canvases remain rectangular. GameIcons.bb() scales both dimensions
by requested size / 48, preserving artwork proportions, smaller hearts and tight
spacing beside numbers. Fixed row spacers keep line metrics uniform regardless
of actual icon height. Original source art and board bomb animation are unchanged.

Character sequence caller map: `Board._advance_walk()` → `_finish_walk(id, true)`
→ `HexCell.finish_character_walk()` → `BoardCharacter.finish_walk()` →
`_turn_to_south(false)` → `_finish_turn()` → `_start_sitting()`.
Actions use `HexCell.play_character_action()` → `play_action()` →
`_turn_to_south(true)` → `_finish_turn()` → action frames → `_start_sitting()`.
Both use `_process()` to step poses and reverse the grounded stand-up clip, then
restore seated idle. Normal selection still plays stand-up forward and enables
outside-hex pointer facing. No new animation assets or generation are required.

### Deployment drop and sit presentation

`Match.action_event` → `Board._on_action_presentation()` handles resolved Deploy
only after refreshing the destination figure. It calls
`HexCell.play_character_deploy()` → `BoardCharacter.play_deploy()` for mapped
characters. Ordinary refreshes and snapshot restoration do not start this clip.
The south standing sprite begins transparent, 48 world pixels above its normal
anchor (16 sprite-local pixels through the existing scale/shader enlargement).
`_process()` eases that lift to zero and opacity to one over 0.45 seconds, then
calls `_start_sitting()` to play the nine stand-up frames backward at 10fps.
Every sitting frame remains foot-grounded. Completion restores seated idle and
`_fade_to_hover_opacity()` returns to the latest hover opacity (1 or 0.5).

The temporary lift is applied in `_show_frame()` rather than changing the
figure's layout position, so resize/refresh keeps deployment attached to its
hex. Hover updates are remembered during the fade without overriding it;
selection refreshes preserve the sequence. A new committed action may replace
an in-progress deployment and restores the normal anchor/opacity before turning.
Self-cost Stun events are excluded from action presentation, so payment cannot
mistakenly start an attack clip. Deployment and subsequent rules/choices never
wait for these cosmetic timings. Example: deploy Reed Archer into a legal vacant
hex; the standing mouse fades in while descending, then sits using its reversed
stand-up frames, with hex info available throughout.

### Inactive interaction and continuous color transition

Idle board clicks offer only active friendly deployed units through
`Board._on_cell_pressed()`. LocalMatchController._select_unit() and
_begin_unit_action() also reject inactive units, and _make_card() disables their
selection/action buttons. BoardCharacter.set_follow_pointer() independently
rejects new inactive selection poses. Existing PhraseExecution subject/target
choices are handled first and remain unchanged: inactivity does not prohibit
being chosen as a legal effect target, and hover inspection stays available.

Gameplay activity is still committed by rules immediately. BoardCharacter keeps
its visible color while `_command_animating()` reports deployment, travel,
return-turn, action or reverse sit-down. After the full sequence it eases
`inactive_blend` to one over 0.35 seconds; reactivation eases back to zero.
The shader's `inactive_amount` mixes RGB with luminance using smoothstep while
preserving alpha and the bottom-anchored enlargement. An already inactive idle
snapshot starts grey, not briefly colored. Travelling sprites start colored;
arrival transfers full color immediately to the stationary sprite before its
turn/sit, avoiding a one-frame grey flash. Externally inactivated idle selections
stop rising/following the pointer. No rule costs, activity timing or turn phases
wait for the cosmetic fade.

Example: commit Reed Archer's Bow. It is immediately unavailable for new action
clicks, but its sprite stays colored while turning, drawing the bow and sitting;
only then does it smoothly become grey. On activation its color returns smoothly.

### Six-hex region membership and restored control

`RegionMap._generate_hex_grid()` calls `_region_kind_for()` before Match setup
or snapshot restoration. The board has seven six-hex regions: one starting and
two intermediate regions per side, plus the neutral front. After the left
starting triangle is classified, all remaining negative-x/positive-y tiles
belong to the same left intermediate region. The previous x+y <= 0 condition
incorrectly kept only its diagonal three hexes and assigned its other three to
the neighboring intermediate region, producing a three-hex/nine-hex split.

The corrected condition is x < 0 and y > 0. ControlResolver's strength calculation
is unchanged: current life plus printed control bonus, home +0.5 outside the
front, ties neutral. All members of each geographical region therefore share
control and its derived +1 physical bonus. Map iteration and hex IDs are unchanged,
and snapshots restore units to the same tiles before refreshing control.
In the saved example, Mole Artificer at (-1,1) belongs with (-1,2), (-1,3),
(-2,2), (-2,3), and (-3,3); its four life outweigh the home player's 0.5, so all
six tiles are blue. The adjacent Walnut Crab at (-1,0) belongs to the other
left intermediate region and continues contributing there. No snapshot rewrite
or reset is required; restart to regenerate membership and restore live control.

Deselection presentation: HexCell selection refresh calls
BoardCharacter.set_follow_pointer(false) once on a real selected-to-unselected
transition. A standing unit turns south and plays the reverse rise to sit.
Deselecting during stand-up instead passes its current rise frame to
_start_sitting(start_frame), reversing only the already-played portion without
jumping to full standing. Routine refreshes are idempotent. Deployment, walking,
action and existing turn/sit sequences preserve their own finish rather than
being replaced by deselection. All reverse frames retain the grounded feet.

Creator outline refresh: outlined red heart, steel shield, golden Stun stars, Bow and Fire are copied to their existing PixelLab Objects with save_to_asset, then synchronized to local source/prepared UI PNGs. GameIcons.action_path() now maps Shield and Mshield to the outlined shield, replacing their emoji in board info, descriptions and action-button textures. Source gallery/Object identities are listed in assets/icons/SOURCES.md.

### Switching the selected unit in one click

When a normal command has an unpaid, cancellable target preview, clicking an
invalid target hex containing another active friendly unit now routes through
Board._offer_unit_selection() instead of merely cancelling. A legal effect
subject/target still takes priority; paid commands and captured trigger choices
cannot be replaced. Shared-hex unit pickers retain individual selection.

LocalMatchController._select_unit() records pending_unit_switch_id and cancels
the old preview. _on_effect_completed() waits for RulesRunner release, clears the
old selection, then selects the new unit and its usual action preview. Choose
unit buttons on other active friendly cards allow the same switch. No costs or
actions are spent by cancelling the unpaid preview. Inactive units remain ignored.
HexCell refresh forwards false to the old character and true to the new one:
the old turns south/sits (or reverses its partial rise), while the new stands up.
Rapidly switching back during a sit reverses from its current frame into standing;
a deselection-only turn may resume pointer facing without jumping to seated idle.
Existing deployment/committed action presentation remains protected.

Example: select Reed Archer, then click Walnut Crab while choosing a Walk target.
Archer sits as Walnut Crab's mapped mole artificier stands and gets its own action
preview. Selecting a valid ally for Mend still resolves that choice rather than
switching the selected actor.

Walking presentation now plays at 8fps and travels at 0.8 seconds per hex step, a modest slowdown from 10fps/0.65s. Board._advance_walk() keeps departure/arrival fades tied to step progress; turn, action, stand-up and sit-down speeds are unchanged.

Walk start delay: BoardCharacter.WALK_START_DELAY is 0.2s. Board seeds a committed Move overlay record at negative delay and clamps path progress to zero during this lead-in, preserving origin info and preventing backward travel. BoardCharacter.setup(moving=true) uses the same negative clock, holding a directional standing pose before starting walk frames. After the delay, travel remains 0.8s per step and frames run at 8fps. Rules commit immediately; this is presentation only and existing interruption/invalidation cleanup still applies.

GameIcons.action_path() now maps Move to the PixelLab boot and Cannon to the side-view cannon. Both use proportion-preserving prepared UI copies (alpha crop, 44×44 fit, two-pixel gutters), so hex rows, effect descriptions and action buttons share the same images and scale rules. Fly keeps its distinct symbol. Originals and Object source IDs are in assets/icons/SOURCES.md.

The prepared Move boot is slightly smaller: a proportional 40×40 fit plus two-pixel gutters instead of 44×44. GameIcons scales these prepared dimensions normally; fixed hex-row spacing is unchanged.

### Directional pose crossfades

`BoardCharacter._show_facing(sector)` handles selected pointer-facing and the
shortest-path return turn. Standing directions blend for 0.1s through a sine-eased
tween calling `_set_facing_blend()`. An ongoing blend finishes before the next
requested facing is accepted, avoiding a sudden retarget when the pointer moves
quickly. Return-turn poses now last 0.12s, allowing each blend to complete before
the next step. A pending south-facing blend finishes before actions or sitting.
Stand-up, sit, walk and action frames still use direct `_show_frame()` playback;
changing to a clip cancels any directional blend. The 0.2s walking lead-in and
0.8s-per-step travel timing are unchanged.

The character shader samples the previous/current textures in one pass, mapping
old UVs through their foot-offset difference. Premultiplied-color interpolation
keeps alpha/hover translucency correct without two overlapping sprite layers or
dark transparent borders. Vertex tint is preserved separately, and the shared
smooth greyscale mix applies after the pose blend. Previous-pose sampling uses
nearest filtering. No additional perspectives, image generation or gameplay
state are involved. Example: select a unit, move outside its hex around different
sides, then deselect; directional changes and its southward turn blend before
the normal reverse stand-up sit-down.

### Playground display names

CardCatalogue's six existing factories now set their UnitInfo.name to the
PixelLab appearance name: Red Squirrel King, Mouse Necromancer, Red Squirrel
Climber, Mole Artificier, Mouse Archer and Mole King. Starter_army(), catalogue
factory names, stable UUID prefixes and rule effects retain their previous
identities. LocalMatchController and TargetRef labels already read UnitInfo.name,
so card trays, hover cards, prompts and unit-choice menus pick up the names
without presentation-specific overrides. MatchSnapshot restores by stable UUID,
not display name, and does not overwrite unit names, so existing snapshots use
the new names on restart without migration or reset. Historical rule references
and factory names in this document still identify the original rule card.

Board bomb sizing: HexCell._setup_bomb_sprite() uses scale 2.625, 1.5× the previous 1.75 (84px canvas instead of 56px). The unlit/lit/ignition frames share that scale. BombIndicator is a centered 60×42 text box above the sprite in draw order, anchored to the round body center three source pixels below the canvas center; damage and Pierce text stay on the bomb rather than underneath. Inline description bomb icons are unchanged.

Pending explosion bombs now loop all nine ignition frames continuously at 9fps. HexCell._refresh_bomb_indicator() starts the loop only on the unlit-to-lit transition, preserving playback through repaints; resolution/removal hides it and a return to an unlit object switches to the static unlit pose. The old animation_finished/static-lit handoff is removed. Damage stays centered throughout.

Bomb-loop continuity: source ignition frame 1 is fully transparent. HexCell._setup_bomb_sprite() now adds PersistentBombBody, a static unlit Sprite2D beneath the AnimatedSprite2D overlay. It inherits the same position/scale/visibility, so the bomb body remains visible through blank/partial animation frames and disappears with the parent on resolution/removal. Source frames and 9fps loop timing are preserved; centered damage remains above both layers.

### Bash slider comparison with animated characters

`HexCell.bash_slider_enabled` defaults to false, restoring side-by-side characters:
Red Player 1 at x=-65 and blue Player 2 at x=65. During the final walking step,
`Board._advance_walk()` queries `HexCell.bash_arrival_offset()` and calls
`set_bash_approach()`: the attacker approaches its side while the defender eases
from center to the opposite side. The lead-in holds their starting positions.
`_on_action_presentation()` reapplies approach after repaint; `_finish_walk()`
settles the defender before revealing the stationary attacker at the same anchor.
For example, walking onto an enemy now ends beside it without a sideways jump.

Enabling the exported setting selects the experimental slider described below.
In that mode, `_render_bash()` centers both mapped characters at x=0 and sets
their shader `bash_side`: red Player 1 owns the left half, blue Player 2 the right half.
At rest each shows its own clipped half and its life/modifier column; action
details are hidden. Existing portrait participants retain their JS-style slider.

`_on_mouse_entered()` / pointer-half changes → `_set_bash_hover_side()` →
`_animate_bash_focus()` tween both characters' `bash_reveal` and `bash_opacity`
over 0.34s with sine easing. Hovering a half expands that participant to full
width, hides the other participant, slides its stats to center, and reveals
full-width action details at the character's usual 35% hover-info opacity.
Leaving restores the split. Switching halves retains the existing 0.34s return
to split before the other reveal; generation guards discard stale delayed work.
The hover inspector follows the actual participant immediately.

The character shader clips a vertical half-plane using its enlarged local x
coordinate; this combines with directional crossfades, animation frames, hover
translucency and deferred greyscale without replacing their materials. Ordinary
repaints retain the encounter nodes and focus progress. `_update_bash_info()`
leaves character activity to BoardCharacter instead of writing a legacy boolean
shader uniform. When Bash ends, `_add_unit_figure()` clears slider uniforms on
retained characters so ordinary rendering is whole again. Arrival text fades use
self_modulate independently from the focus tween's modulate, preventing either
from overwriting the other. Rules, targets, ownership and Bash resolution do not
change. Example: hover the left half of a pending Bash to inspect red Player 1,
then the right half for blue Player 2, and leave to restore the shared split.

Reference: guerra.game/hex-grid.html `.bash-left-picture`, `.bash-right-picture`,
`.bash-focus-left/right` clipping and 0.34s UI transitions. That reference project
was read only; this comparison changes the Godot presentation.

Bash life reads current life followed by the heart. _add_bash_stats uses the same 120px side columns as _add_bash_details, centering life and modifiers over action lines; _animate_bash_focus preserves those centers (or centers the column during optional slider focus).

Bash departure: CombatResolver._apply_move_unit captures origin_bash_partner before cancellation. Board._on_action_presentation retains that ID and the origin cell in the walk record. _advance_walk starts the traveller on its player side and calls HexCell.set_bash_departure to ease the remaining partner to center over the first step, after the usual lead-in. _finish_walk settles interrupted departures; stale participants or a new Bash are ignored. Example: moving red out of a Bash starts at the left and returns blue from the right to center. This is presentation only.

Selectable rim color: HexCell.refresh calls _refresh_target_color after choosing the control texture. Selectable rims crossfade over 0.25 seconds into a white-texture gold overlay at 70% opacity, with no pulse. _apply_target_color blends complementary rim opacities; the regional texture remains underneath. Clearing targetability fades back to its current regional color at 40% opacity. Repaints preserve progress and rapid selection changes reverse from the current blend. Only HexFrame changes; characters, labels and rules are unaffected. Example: choose a movement action to see its legal destinations in gold, then cancel to restore their regional colors.

Deploy landing continuity: BoardCharacter.play_deploy cancels any facing blend and displays the final stand-up frame. _process reapplies _show_frame every falling tick (even when texture is unchanged), updating the grounded deploy_offset while opacity rises. At ground level _start_sitting reverses from that identical frame, preventing a midair hold or landing teleport. Example: deploy any mapped unit to see it fall and fade simultaneously, then sit.


### Bash participant click identity

HexCell now gives each live Bash participant a disjoint GUI click box. Its
bash_unit_pressed(coordinate, unit_id) signal enters GuerraBoard._on_cell_pressed()
with an explicit participant identity. The board uses this identity for replay,
active-friendly unit selection and legal UNIT target choice; it never expands a
participant click to another occupant. HEX-target verbs still choose the shared
hex. Area2D hex clicks use bash_unit_at_position() as the same side-based fallback.
For example, after an enemy walks into a defender's hex, clicking the attacker
box replays its prior-turn walk, while clicking the defender box can select that
active friendly defender. Both box hover and exit borders use the common fade.

Effect choices for Copy: Selectors.EffectsOf.new(unit_selector) explicitly maps UNIT references to read-only EffectOption PROPERTY references. UnitInfo.effect_options generates stable category/definition keys and origin provenance; Match.get_property revalidates current membership, and Verbs.copy_effect declares UNIT -> PROPERTY. The existing CHOOSE_ONE picker offers readable effect captions, including off-board choices after lethal Wound. No definition stores selected targets or runtime state. See RAT_SYNERGIES.md.

## Disable: choose a hand unit

`Verbs.disable()` declares UNIT → UNIT. `Action.can_disable` accepts only an
existing UNDEPLOYED (in-hand) target; it does not impose ownership. Use normal
QuerySelector ownership filters, including relative or explicit player ownership.
The default CHOOSE_ONE picker offers each off-board unit separately; legality is
rechecked before mutation. No DSL or new selector domain is introduced.

```gdscript
var hand := QuerySelector.new()
hand.state = Enum.t_state.UNDEPLOYED
hand.relative_owner = Enum.OPP # Enum.YOU for friendly; omit for either owner
var consequence := Effect.ConsequencePhrase.new(
    Selectors.Self.new(), Verbs.disable(), hand)
```

EffectExecution → PhraseExecution → TargetResolver → Action.disable is the caller
path. Disable changes state to DEFEATED, clears position/activity and preserves
health, counters and abilities. One resolved `disable` UNIT/UNIT occurrence is
emitted inside the runner boundary, followed by state_changed. It does not emit
Die or Return, so death/return triggers do not fire. A disabled hero still loses
under the general hero-defeat rule. Costs and event conditions belong to the
surrounding Effect; Disable is not added to the atomic cost whitelist.
EffectText displays the underlined keyword; Ctrl-hover uses RuleGuide's entry.

## Woodland additions (2026-10-24)

WoodlandRules.soul_upgrade demonstrates dependent choice: UpgradeUnits returns friendly deployed UNIT references with numeric abilities; choose_upgrade_unit records the chosen identity; UpgradeOptions anchored to Completed step_0 returns PROPERTY references to eligible effects. upgrade_ability commits the exact recipient-bound grant. There is no implicit UNIT-to-PROPERTY conversion. FleeDestinations returns HEX references; WoodlandActions checks current Move/Fly ranges and routes and executes one free movement with normal events. RuleNumber parameters resolve from captured event fields through Verb.bound_to, shared by selection and commitment.

See [WOODLAND_UNITS.md](WOODLAND_UNITS.md) for card wording, interactions, caller maps and focused regression coverage. Tests were added; running them requires a request ending in TEST.

### Name groups and printed rule conventions (2026-10-26)

`QuerySelector.name_contains = "wild"` matches a case-insensitive substring of
`UnitInfo.name`. Use `"squirrel"`, `"mouse"`, or another name fragment for the
same kind of group. Group membership is queried live and is neither a passive
flag nor an effect that Copy/Reset can grant. `required_flag` remains available
for actual passives. `WoodlandRules.heal_on_wild_hit()` now uses `name_contains`;
its deployed-friendly scope and received/contact rules remain explicit.

Printed friendly deployed queries abbreviate to "friendly unit"; hovering
"friendly" explains deployed scope. Explicit hand/defeated scopes remain
visible, and historical event watchers retain their authored zone behavior.
Bashing conditions print "is" plus the shared Bash icon. Printed action grants
are neutral; physical modifiers use normal color and magic modifiers purple.
`EffectText.action_value(current, printed)` marks only already-applied changed
M/N values magenta. `RuleGuide` supplies the friendly/name-group hover text.

Snapshot format 3 accepts versions 1 and 2, discarding obsolete Wild flags and
copied Wild entries while preserving actual resources and passive abilities.
`tests/wild_return_test.tscn` includes name membership, eligibility, formatting
and legacy-snapshot regressions; behavioral tests still require a TEST request.

### Compact trigger wording and Beaver's previous hex (2026-10-26)

Printed triggers use `it` for their subject, `target` for their object, and
`itself` as an alias for this unit. Miner prints the friendly Bomb victim as the
subject of "friend is hit by Bomb", then heals "it". These are presentation
names only: EVENT_SUBJECT/EVENT_TARGET remain separate captured references.
Friend/enemy replace generic friendly/enemy-unit phrases, and enemy replaces
enemy-player wording; explicit hand/defeated or typed-unit restrictions remain.
Flee's movement contract stays in its hover glossary. A Bash condition need not
repeat the implicit enemy qualification. Physical-only grants print +N, while
physical/magic pairs retain normal/purple styling.

`Selectors.EventHex.new(&"origin_hex")` declares native HEX output and resolves
only the captured integer event field. `WoodlandRules.bomb_after_walk()` uses
this selector with ALL to leave Bomb 2 on Beaver's former hex automatically;
region choice is removed. The existing Bomb verb still owns creation/merging and
publishes its normal event. Missing origin history cannot redirect the effect to
the source's current location. `tests/woodland_effects_test.tscn` now covers the
changed result, source ownership/identity, historical anchor and non-trigger
cases; no behavioral tests were run for this change.

### Short printed payments and keywords (2026-10-26)

Revive omits its redundant recipient phrase; its hover description still states
friendly defeated non-hero eligibility. Unit-then-ability Upgrade sequences print
`M upgrade N to friend`, while the same two execution choices remain required.
Porcupine's unit/counter/X payment prints `[AC] -X counters on friend: +X souls`;
its atomic costs, allowed counter kinds and numeric choices are unchanged.
Name groups precede friend/enemy (`wild friend`). Own movement and Deploy
triggers print `this unit Walk` and `this unit deploys`. Return prints lowercase
`return`, and its third-person `returns` shares the same hover entry. Pronoun
hover entries explain only the word: it = trigger subject, target = trigger
object, itself = this unit. These are formatting changes only.

### Sprite-backed local roster

The local roster offers the 35 implemented units with PixelLab sprites to both
owners (70 cards total). The previous 64-card prefix is retained, then Mara,
Tamia and Grey Squirrel append for each owner. The other 17 definitions remain
catalogue-only; `CardCatalogue.all_units()` inventories all 52.

Both sprite-backed heroes are alternative first deployments; the chosen hero
remains the sole hero identity for that player, including after Return. Existing
58-card snapshots retain their stable IDs and choice migration. `starter_army()`
builds the playable roster, while the exporter lists all implemented definitions
and marks only sprite-backed units as available. `tests/full_roster_test.tscn`
covers 35/35 availability, sprite eligibility, identity, hero alternatives and
snapshot persistence. Tests remain unrun unless explicitly requested with TEST.


### Disable engines and Grey Squirrel (2026-10-27)

See [DISABLE_UNITS.md](DISABLE_UNITS.md) for the final three PixelLab units and
complete caller/eligibility map. Mara uses `WildRules.grow_on_disable` with the
disabled target's relative owner: permanent `Verbs.upgrade_cannon(1, 0)` for a
friend, or actual `Verbs.up_life(1, 1)` for an enemy. `UnitInfo.add_cannon_counters`
stores acquired `cannon_damage`/`cannon_range`; effective Cannon values, previews,
combat capture, Return, Reset and snapshot properties share the existing paths.

Tamia's `WildRules.disable_for_deployment` is a normal cost plus an ordered
Disable/grant-deployment consequence. `QuerySelector.excluded_type = HERO` keeps
non-hero hand targets inclusive of troops and temples. Grey Squirrel uses
`Collection.grant_action_values("bow", [1, 0], adjacent_friends, false, true)`: A
waives only the player action, not activity; the concrete recipient's grant
expires after the captured current player's End followups. `EffectText` keeps
printed grants neutral, applied Cannon/Bow M/N changes magenta and the A marker
visible in hover/menu/hex descriptions.
# Character preload and baked alignment (2026-10-27)

Caller map: `LocalMatchController.start_match -> BoardCharacter.preload_art ->
_art_for -> _cached_cycle/_cached_frame`. Startup prepares the 83 current
appearances as shared spritesheets before creating the HUD. `HexCell` and Board travel overlays
then call `BoardCharacter.setup`, which binds shared texture arrays and saved
foot offsets. Each figure retains independent playback and shader state.
`_show_frame -> _frame_foot_level` performs only an offset lookup; gameplay never
reads texture pixels back from the GPU. Existing static/rise grounding and
first-frame walk/action grounding remain unchanged.

After importing or replacing PixelLab PNGs, run
`python tools/build_character_alignment.py` with Pillow installed. This rebuilds
`assets/characters/playground/alignment.json` from native alpha bounds, then
regenerates `assets/characters/sheets/` and its runtime frame/bounds manifest.
The source alignment file is no longer loaded during play. Missing sheet entries fail preload
with an asset error rather than silently adding an expensive runtime fallback.
Direct setup callers can lazily load a pack; normal local play preloads all packs.

Match state, runner-idle and trigger-cue notifications now use
`_queue_hud_refresh -> _flush_hud_refresh -> _refresh_hud` to coalesce a burst into
one deferred repaint. Direct input refreshes consume a queued request. Rules,
animation barriers and acknowledgements are unchanged. `ControlResolver.refresh`
also calculates each geographical region once per pass; its memo is discarded
before subsequent mutations and live legality queries remain uncached.

Opt-in regression: `godot --headless --path . res://tests/character_cache_test.tscn`.
It checks every retained frame against native alpha bounds and confirms repeat
preload retains textures. Only run this scene when the user requests `TEST`.

## Approved synergy extensions (2026-10-28)

Animation import correction (2026-10-29): `tools/import_synergy_characters.py`
now supplies missing W/NW/SW walks by reflecting every frame of E/NE/SE,
respectively, rather than importing a single standing rotation. Its caller is
the asset-preparation command; `BoardCharacter._art_for()` reads the resulting
six-frame counts from `assets/characters/playground/manifest.json`.
For example, the Tamia Blue Mage's west cycle contains six mirrored east
frames. The importer records `mirrored_walks`, and
`tools/build_character_alignment.py` must run after import to bake the new
frames' offsets. This changes presentation assets only.

The same import command calls `apply_reviewed_repairs()` after native import
when `exports/repaired-character-animations/manifest.json` exists. That accepted
pack supplies the new six-frame S/N strides and selected action repairs;
unaffected source clips and original source ZIPs are preserved. Its manifest
records the replacement PixelLab groups, exact mirrors and per-frame offsets.
Walks loop; sitting/standing/actions are one-shot clips. The existing
`BoardCharacter._process()` already uses that distinction. Do not compare a
sitting clip's final seated frame to its initial standing frame as a loop seam.

See [SYNERGY_UNITS.md](SYNERGY_UNITS.md) for current card text, caller map and
examples. `SynergyCatalogue` appends 28 units for each owner; the 63 appearances
use the existing transitions, participant boxes and acknowledgement gates.

Courier resolves positive counter PROPERTY identities, retains a bounded amount
on PhraseExecution, and binds the donor/key/amount of that completed step through
`RuleBinding`. Both hosts are revalidated within range before one conserving
transfer mutation. No implicit domain conversions or runtime selector fields
were introduced. Sacrifice joins atomic cost preflight, including duplicate
victim and departed-resource reservations. Die/Sacrifice capture before departure;
causal trigger choices can explicitly rescue a sacrificed hero before final loss.

The A/S/AS/nS presentation distinguishes action-token payment from activity;
the internal Action-free sticker is no longer displayed as an ambiguous A.
Guardian threshold queries read only the physical modifier axis before their
magical/Bow outputs are derived. Shared attack contact records freeze `kind`,
applied `damage` and `wounded`, allowing Hit-without-Wound on any actual attack
while excluding misses/immunity. Bomb continues to use its separate bomb_hit.

Focused scene: `godot --headless --path . res://tests/synergy_units_test.tscn`.
Only execute behavioral scenes when the user's prompt ends in `TEST`.


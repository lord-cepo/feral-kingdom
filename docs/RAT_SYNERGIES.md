# Rat units, Reset and Copy

Implemented from the 2026-10-23 card specifications and clarifications. These are
object-authored definitions; no rule-text parser is involved.

| Card | Health / deployment | Actions | Other effects |
| --- | --- | --- | --- |
| Rat Dark Mage | 2 / Starting | Fire 2, range 2; default Walk 1 | Own death: choose one unit to Reset. |
| Wild Rat | 3 / Starting | Walk 2 | Friendly unit death triggers activate one additional time. This is a static aura, not a death trigger on Wild Rat. |
| Rat Musketeer | 2 / Front | Cannon 1, range 4; default Walk 1 | Any enemy death: choose another friendly defeated non-hero to return to hand. |
| Rat Thief | 1 / Intermediate | Walk 2; Instant Bow 1, range 1 | Wound: choose one effect of the wounded unit to Copy. |
| Rat Warrior | 3 / Starting | Walk 2; pay 2 Soul plus normal activity/action cost for +1 deployment | Friendly return to hand: +1 Soul on this unit. |
| Rat Pikeman | 2 / Intermediate | Walk 3 | Physical contribution equals your remaining deployments minus the opponent's, including negative differences. |
| Rat Swordsman | 3 / Starting | Walk 2 | +1 physical while bashing; when its original defender leaves a Bash it initiated, +1 action on its owner's next turn. |

## Reset

Reset accepts any existing unit, including enemies, heroes and defeated units.
It preserves owner, hex, card state and activity. A deployed unit stays on the
board; a defeated unit stays defeated. It restores printed actual/max health,
printed actions/triggers/states/auras/passive flags, deployment regions and
control bonus, discarding accumulated counters, wounds, timed upgrades and copied
effects. Reset is not Revive and does not emit Return-to-hand or Die.

The printed baseline is captured after implicit movement is supplied at match
initialization. Existing queued attacks and already captured triggers retain
their independent histories/definitions.

## Copy

Copy duplicates an effect; the original unit keeps it. Actions, triggered
effects, state modifiers, continuous contributions and stored passive flags are
individual choices. Future SELF bindings belong to the recipient. Mutable
activation state and accumulated counters are never copied. Missing printed
resource counters required by the source card are initialized at zero.

`Selectors.EffectsOf` explicitly projects UNIT references into effect PROPERTY
references. `EffectOption` carries a definition and readable choice caption.
Its property key uses category and definition identity, rather than an array
position. Match validates each reference through `get_property`. The ordinary
PhraseExecution/TargetResolver CHOOSE_ONE path offers the effect choices, on the
victim's hex or through the off-board chooser after a lethal wound.

## Death repetition and fleeing

Wild Rat's `EXTRA_DEATH_TRIGGER` contribution is read while the death occurrence
is captured, before removal. Each extra activation gets a new EffectExecution
with independent target choices; the runner does not emit another Die event.
Multiple matching amplifiers add extra activations. Existing trigger suppression
still takes precedence.

The attacker is the unit that entered the occupied hex, including forced entry.
Swordsman's reward requires that exact unit to be the Swordsman, and its original
defender to leave the encounter while still deployed. Either voluntary movement
or forced displacement can make that defender flee. Moving Swordsman itself out,
or defeating the defender, does not grant the reward. The one-shot action bonus
is consumed at the owner's next Start, separately from the recurring allowance,
even if the original Swordsman has since left play.

## Callers and persistence

- `CardCatalogue.starter_army` appends these seven units for both players after
  the original eight stable IDs; the individual factories use `RatRules`.
- `Match.start_local_match` calls `UnitInfo.capture_printed_state` after adding
  implicit movement. `Verbs.reset_unit` -> `Action.reset_unit` restores that
  baseline inside a runner boundary.
- Wound -> `RatRules.copy_on_wound` -> `Selectors.EffectsOf` ->
  `Verbs.copy_effect` -> `Action.copy_effect` -> `UnitInfo.add_effect_copy`.
- `Action.revive` emits `return_to_hand`; `RatRules.soul_on_return` increments
  the Warrior's Soul through the existing property verb. Its conversion uses an
  atomic CostBundle, with a read-only resource/active condition for availability.
- `RulesRunner.capture_event` reads live death contributions and allocates each
  activation separately; existing acknowledgement/choice handling is retained.
- `CombatResolver.cancel_dodged_bashes` records `defender_fled` using historical
  encounter identities. `RatRules.action_on_flee` schedules the player resource
  through `Verbs.next_turn_actions`; `Match.start_turn` consumes it once.
- `MatchSnapshot` saves copied-effect provenance as printed source/category/index
  triples and saves pending next-turn action grants. It rebuilds definitions
  from printed baselines on load. An unchanged older roster prefix can load with
  appended new cards initially in hand, without changing existing IDs.
- `EffectText` describes Reset, Copy, resource conditions, death amplification and
  the live deployment-difference modifier. Soul appears in the detached unit
  counter panel; pending next-turn actions appear in player info.

## Keyword guide and card wording

Hover rules underline Reset, deploy, revive, flee, return, C and AC terms using explicit BBCode underlines; icons and counter replay links are not underlined.
`RuleGuide.decorate` annotates visible text and shared icons without changing
definitions or nesting existing counter replay links. LocalMatchController's
rule/health/counter labels route metadata enter/exit to `_on_rule_guide_entered`
and `_on_rule_guide_exited`; `_update_rule_guide` fades a separate glossary box
only while Ctrl is held. Releasing Ctrl fades the guide; Ctrl-drag still moves
the main inspection panel. Example: hold Ctrl over Reset to inspect its meaning,
then hover the skull to read the death entry. Replay links remain clickable.

EffectText derives rat wording from rule objects: Swordsman's original-defender
flee trigger and Bash condition, Warrior's `[C] 2 soul: +1 deploy` and friendly
Return trigger, Pikeman's colored deployment-difference formula, Thief's Copy
target and Wild Rat's friendly death-trigger amplification. Revive uses its word
instead of an angel glyph. C explains written payment plus an action; AC explains
the normal self-Stun additional payment. This update changes presentation only.

`assets/characters/playground/manifest.json` records imported PixelLab sources and
clip counts. Existing art is used without generating new assets. Refreshed on
2026-10-23: all seven rats have eight-direction walking and front stand-up clips
(also played backwards for sitting). Six have front action clips; Musketeer
still uses a stationary authored pose for its missing action clip. Pikeman now
uses the replacement seated state `81cd8019-ce0b-4720-b949-7734ac9055f4`.

Verification now includes `tests/rat_effects_test.tscn`, with focused cases for each rat ability, Disable, no-action defeat, source attribution, Copy categories and Reset. Run history and commands are recorded in M2_EXECUTION.md.

Warrior hover order: EffectText.unit_lines places bundled deployment conversions after triggers, displaying Walk, friendly Return → Soul, then [C] 2 soul → deploy. Definition indices, action shortcuts, and execution order remain unchanged.

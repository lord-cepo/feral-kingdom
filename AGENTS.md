# Effect and selection architecture

## Scope

Follow `docs/ROADMAP.md` for the staged route to JS feature parity and readable,
owner-maintainable code. Implement stages only when requested; the roadmap is
not authorization to start the entire port. Document every new or changed
function with a meaningful GDScript `##` contract; explain concrete callers or
signal connections for entry points, state changes, and timing. Keep the relevant
usage document's caller map and examples current. Prefer fewer concepts and
shared rules over compressed code; do not remove documentation to reduce lines.
Every new or changed gameplay effect must have a focused behavioral regression
test covering its result, eligibility/ownership, and important non-trigger cases.
Keep rulebook terms and interaction rulings current alongside the effect.
Creating/updating these per-effect tests is required as part of implementation;
only run tests when the user's prompt ends with `TEST`.

## Presentation transitions

Prefer animated transitions for visual state changes: fade, ease, roll up/down,
or blend from the current visible state instead of abruptly replacing it.
Keep animation state separate from authoritative rules. The graphical client
orders attack resolution, damage (Slash), then eventual death (Skull). Phase
continuations wait for finite action animations to finish; persistent counter,
sleeping and ambience loops never block phase advancement. When a
captured ability triggers, the rules runner retains it before activation until
causal animations finish and both player identities acknowledge the blink or
Space prompt. Local hot-seat input acknowledges the two players in succession;
future online input must authenticate the player identity on the authority.
Trigger cues highlight the fired rule text in yellow; acknowledgement dismisses
only their presentation, fading the blink before releasing queued rules. Clicking
the unit itself does not acknowledge. Headless rules leave this UI gate disabled.

When two units share a Bash hex, provide distinct participant click boxes. Route
the exact clicked identity through hover, replay, unit selection and UNIT target
choice; a replay or eligible action on the other occupant must not intercept it.
Hex-targeted actions still address the shared hex under normal selector rules.

`docs/GENERAL_RULES.md` is the intended game rulebook; `docs/GUERRA_RULES.md` is
the JS reference snapshot. Preserve explicit differences in the intended rules
(notably self-stun activity costs, hero Start Stun recovery, owner End activation, and immovable temples) rather
than silently replacing them with legacy behavior. Consult the rulebook's open
decisions before implementing unspecified interactions.

User direction: author effects directly through objects for now. Do not introduce
a DSL parser. Use card texts to identify needed Condition, Contribution, Sequence,
scheduled-effect, and sticker objects; distinguish proposed interfaces from
existing APIs. Definitions remain reusable; activation state stays in execution
objects.

This file records the agreed execution direction and the recommended selector
design. Implement it incrementally when effect-system work is requested; this
document alone is not an instruction to rewrite the project.

The core architecture below is now implemented. See `docs/SELECTION.md` for actual
factory names, usage, lifecycle rules, and the integration test command. Selector
helpers live under `Selectors` (for example `Selectors.Self.new()` and
`Selectors.UnitsOn.new(...)`). `TargetResolver.resolve` performs validation,
native resolution, conversion, and deduplication; PhraseExecution adds verb
legality and target choice. Keep this separation when extending the system.
See `docs/FILE_GUIDE.md` for the current source-folder layout and file roles.

Current cost policy: individual costs use CHOOSE_ONE with an atomic cost verb.
Effect.CostBundle collects all choices, then preflights cumulative resource use
and commits built-in self-Stun/deactivate/decrement, life payments and next-turn-action grants together. Unsupported
cost types fail before mutation. Paid costs are not refunded after consequence
failure. Consequence sequences remain sequential and retain earlier mutations.

Match.rules_runner owns managed commands, captured triggers and phase/combat
continuations. It retains subject/target choices, asks optional triggers before
payment, releases cost followups before consequences, and releases consequence
followups at bundle completion. Board observes executions; it does not pay tokens.
See docs/M2_EXECUTION.md for current APIs and caller maps, and docs/RULINGS.md
for numbered interaction rulings. Typed P/F/T/A action stickers, continuous
modifier/passive/action-value/defeat-policy grants, Bow value counters, and timed
action-value grants through End cleanup are implemented. General scheduled
consequences and other action-counter families remain future work. Chosen-ability
upgrades and captured life-increase amounts are recipient/execution bound; life
payments may defeat their payer without cancelling paid consequences.
Definitions stay reusable; RuleContext is the read-only query view shared with
PhraseExecution.

## Combat and modifier rules

Read `docs/GUERRA_RULES.md` for the source-linked JS rules tables and all 77 current
catalogue definitions. It distinguishes source behavior, user decisions, and
deferred Godot work. Read `docs/SELECTION.md` for the implemented APIs. JS files are
reference material; do not change that project as part of a Godot port unless asked.
Use `docs/forge.md` and the [Card-Forge/forge](https://github.com/Card-Forge/forge)
repository as a secondary technical reference for MTG-style static/passive rules,
continuous contributions, and trigger suppression. Transfer the architecture only
where it fits Guerra's event model and the user's rulings; Forge rules do not
override `GENERAL_RULES.md` or the confirmed differences above.

- Every UnitInfo creates four modifier COUNTER properties (`physical`, `magical`,
  `temp_physical`, `temp_magical`) plus a numeric `stun` counter. Modifier counters
  remain separate identities; effects can address them through PropertyOf.
- Bow value counters (`bow_damage`, `bow_range`) are created when first awarded;
  timed numeric action grants are separate recipient-bound records and expire after
  their captured player's End followups. Continuous grants remain read-only derived values.
- Effective physical = physical + temp_physical + live physical state contributions;
  effective magical = magical + temp_magical + live magical state contributions.
  The +1 regional control contribution is included in effective physical by
  ControlResolver; it must never enter region strength.
  Values may be negative. `modifier` is a derived Vector2i (physical x, magical y);
  never assign the total directly.
- User ruling: persistent counters are NOT consumed by attacks. Shield/Mshield add
  to temp_physical/temp_magical. Consume only the relevant temporary counter on
  contact. Immunity preventing contact preserves it. Fire never consumes physical
  counters; Bow/Gore contact and Bash consume temporary physical protection unless
  Titanium prevents that unit's contact.
- StateModifier evaluates a while-condition without writing counters or emitting
  action events. `adjacent_to_hero()` gives the requested example: +1 physical once
  while any hero is adjacent, not +1 per hero. Attach it only to units with that rule.
- Regional control and its automatic +1 physical are implemented in
  ControlResolver. Control sums current life + printed `control_bonus`, with a
  home tie-break of +0.5; equal totals are neutral. Deployment requires a vacant
  tile in a region the player currently controls. Keep control and the unit's +1
  physical as derived values; never store the bonus in counters or count it twice.
- User confirmed Fire keeps JS behavior: defeat iff current life <= captured
  attack value - current magical modifier. Survivors take NO partial damage.
  Pierce ignores magical modifiers and Obsidian. Contact consumes temp_magical
  even for nonlethal or piercing Fire, but never permanent/continuous bonuses.
- Normal Fire stores a FireAttack and resolves in the opposing player's combat
  window. Instant Fire shares the resolver. Captured owner/origin/target/value and
  original victim ID do not drift. The original victim must remain at that tile;
  replacement units are not hit. Originally empty tiles may catch arriving enemies.
  Source defeat does not cancel queued Fire. Bomb throw/merge, defuse, Fire ignition,
  area blasts, and delayed chains are implemented in CombatResolver.
- Bow and Cannon now use the same object-authored selector/verb pattern. Bow is
  physical, consumes temporary physical protection on contact, and Titanium
  blocks contact. Cannon captures playable cells on an axial straight line,
  damages either owner with magic rules, and Pierce bypasses Obsidian/modifiers.
  Bomb damage shares Cannon's magical area resolver. Gore, Push/Pull, bomb
  displacement, and Bash now use object-authored actions; combat order is Bow,
  Gore, Cannon/Bomb, Fire, then eligible Bash encounters. Fast, Titanium, First
  Strike, and Steady affect Bash resolution.
- Activity ruling (2026-10-19): normal actions still pay self-Stun 1. At own Start,
  the hero removes one Stun from each friendly deployed unit with positive Stun,
  without changing activity. After own End effects/choices, automatically activate
  only that player's inactive deployed units with no Stun; emit Activate once per
  actual transition and finish its followups before cleanup/player switch. Do not
  activate the opponent's units or remove Stun at End. This replaces Start activation.
- Match.finish_action(player) spends one tracked local action after a committed
  deployment/effect, then Match.complete_action resolves the window. At zero:
  opposing Fire -> End effects -> owner activation -> cleanup -> switch player -> Start recovery -> Action. Start/End/combat continuations now wait for captured trigger choices; future-phase
  scheduling remains M3 work. Call only
  after the whole phrase/effect completes, never once per target in an ALL phrase.
- Fire emits separate target and resolved stages. EventPhrase defaults to resolved.
  Misses are reported through Match.fire_resolved without inventing contact/Wound
  events. A successfully queued phrase is not yet resolved damage.
- Run tests/fire_test.tscn and tests/selection_test.tscn for relevant changes;
  fire_test.tscn covers Bow, Cannon, Bomb, Gore, Push/Pull, and Bash as well as Fire.

## Definitions and execution

Keep `Effect`, `Phrase`, `Verb`, and `Selector` reusable definitions. Never store
an activation's source, selected subjects/targets, or candidate lists on them.

- `Effect`: cost, event pattern, consequence.
- `Phrase`: subject selector, verb, target selector, and target mode (`CHOOSE_ONE`
  by default, or `ALL`). Preserve optional consequence behavior. Add bounded
  multi-selection only when a concrete rule needs it.
- `Verb`: action, parameters, fixed subject and target kinds declared by its named
  definition/factory, and a non-mutating legality check. Effect authors must not
  have to repeat these kinds each time they use a verb.
- `EffectExecution`: definition, source reference (`SELF`), triggering event,
  current phase/status, and completed phrase results.
- `PhraseExecution`: phrase definition, parent `EffectExecution`, chosen subject,
  chosen targets, pending candidates, selection stage, and completion status.

Create one `EffectExecution` per activation. Its phrase executions share the
parent source and triggering event but own their subject/target choices. Reuse
the existing `PhraseSelection` behavior as the basis for `PhraseExecution`.
The board observes selection changes and submits choices to this execution.

Selectors receive a `RuleContext` (`PhraseExecution` extends this view) as a method
argument. The runner supplies it; effect authors never assign context to each
selector. `SELF` reads the parent source. `SUBJECT` reads the current phrase's
chosen actor. Use explicit `EVENT_SUBJECT`, `EVENT_TARGET`, or named completed
results for cross-phrase references. Do not reuse mutable subject/target fields
across cost, event, and consequence. Resolve subjects before dependent targets;
an unavailable required anchor produces no candidates.

## Recommended selector result contract

Return `Array[TargetRef]`, not bare integers and not snapshots containing a unit,
its owner, and its copied position. `TargetRef` can replace or evolve `Troople`.
Use a small tagged reference with named factories:

- UNIT: stable unit ID.
- HEX: stable hex ID.
- PLAYER: stable player ID.
- PROPERTY: host reference plus stable property key/ID. A host may be a unit,
  hex, player, or match for a global property. Do not allow property hosts to
  form recursive property chains.

Counters and flags are property subtypes, matching the existing `Prop.increment`.
Use a property constraint when a verb accepts only one subtype. Identify a
property by a unique key per host, or by a stable instance ID if duplicate keys
are allowed. Never use its mutable list position as identity.

Factories should be readable: `TargetRef.unit(id)`, `TargetRef.hex(id)`,
`TargetRef.player(id)`, `TargetRef.property(host, key)`. Compare references by
kind and identity; property equality includes host and key. Keep inactive fields
private by convention and validate references at boundaries.

`Match` remains authoritative for ownership, position, deployment, occupants,
and property values. Stable array indices are acceptable IDs only while entries
are never removed or reordered. Keep historical positions on event records or
explicit selection snapshots, not on an ordinary unit reference.

## Native selector kinds and verb contracts

Each selector returns references in its natural domain. The verb does not change
what a selector means. Use this conceptual API (examples are design sketches,
not claims about APIs already implemented):

```gdscript
# Selector: declared output kind, or a contextual kind for Self/Subject.
resolve(phrase_execution) -> Array[TargetRef]

# Named verb definitions set their own contracts once:
Verbs.deactivate() # subject_kind = UNIT, target_kind = UNIT
Verbs.damage(2)    # subject_kind = UNIT, target_kind = HEX, amount = 2
```

`DistanceSelector` returns HEX references. Its definition owns the distance/range
rule, center reference, direction, and any required directional anchor. It does
not store context or occupants. Resolve a unit anchor's current hex through
Match without changing the anchor's identity. An off-board anchor gives no
spatial candidates. Define exact distance versus within-radius explicitly.

`Self` and `Subject` preserve the referenced entity's kind. Unit/player queries
declare UNIT/PLAYER. `PropertyOf(host_selector, key)` declares PROPERTY and
selects the named property, not its host. A filter preserves its input kind.
Do not allow mixed-kind arrays from a selector. Contextual output kinds are
checked when the effect source or subject becomes known.

## One conversion boundary

`PhraseExecution` builds candidates through a shared `TargetResolver`. Put domain
conversion here, before selection and before calling the verb. Do not duplicate
it inside DistanceSelector, board click handlers, or individual actions.

```text
selector.resolve(context)
  -> native references
TargetResolver.adapt(references, native_kind, verb.required_kind, context)
  -> references of the required kind
deduplicate + check existence + apply verb legality
  -> legal candidates shown to the player / used by ALL
```

Pass the native kind separately so an empty result cannot hide a bad type
contract. Apply the same resolver to subjects using `verb.subject_kind` before
resolving targets using `verb.target_kind`.

Supported default adaptations are deliberately small:

| From | Required | Meaning |
| --- | --- | --- |
| Any kind | Same kind | Preserve references. |
| HEX | UNIT | Expand each tile into its current occupants via Match. Empty tiles contribute nothing. |
| Any other mismatch | Different kind | Definition/type error; require an explicit projection. |

HEX -> UNIT is the documented convenience for spatial selectors. It means
"units on these tiles," not "choose a tile and affect everyone there." Several
occupants become separate candidates before CHOOSE_ONE/ALL is applied.

Keep `UnitsOn(hex_selector)` available as the explicit form of this same
conversion. Use `HexOf(unit_selector)` when a unit selection should become its
tile. Do not automatically convert UNIT -> HEX: that can broaden an effect from
one selected unit to a tile containing other units. Player ownership and property
selection also require explicit selectors/projections; no automatic conversion
chains or guessed property keys.

Validate known mismatches when constructing/validating definitions; validate
contextual kinds at runtime before offering choices. Report unsupported
conversion as an error, distinct from a valid selector finding no candidates.

## Composition and readable definitions

Intersect/union only selectors with the same output kind, and deduplicate by
reference identity. Project into the desired domain before applying filters
specific to that domain. Do not intersect hex IDs with unit IDs.

```gdscript
# Spatial targets are hexes; deactivate's contract expands them to units.
Phrase.new(Self.new(), Verbs.deactivate(), DistanceSelector.within(2))

# The same spatial selector stays hexes for damage.
Phrase.new(Self.new(), Verbs.damage(2), DistanceSelector.within(2))

# An ownership condition on units requires entering the unit domain first.
Phrase.new(Self.new(), Verbs.deactivate(),
    UnitsOn.new(DistanceSelector.within(2)).where(EnemyOfSelf.new()))

# A counter is explicitly addressed on its host.
Phrase.new(Self.new(), Verbs.decrement(1), PropertyOf.new(Self.new(), "poison"))
```

In these examples, `within(2)` defaults its center to SELF. `EnemyOfSelf` checks
the candidate unit's owner against the source's current owner; a hex ownership
filter instead checks the hex's ownership. These are different rules when both
players occupy the same tile. Property verbs declare PROPERTY plus a counter or
flag constraint where appropriate. Missing properties yield no candidates;
creating a property is a separate host-targeting action.

## Target choice and execution

Store `target_mode` on Phrase, independently of the selector and verb:

- `CHOOSE_ONE` (default): show legal adapted targets and wait for the user's
  choice, including when there is only one target. A hex with multiple legal
  units opens a unit choice; clicking it must not select all occupants.
- `ALL`: no target picker; select the complete legal adapted set at execution
  time. Keep optional-effect confirmation separate from target selection.

Keep one subject per phrase initially: automatically resolve a unique subject,
otherwise ask the user to choose one before resolving dependent targets.
`ALL` affects targets, not subjects. Zero legal targets means this phrase cannot
execute by default; no action runs. Let the effect runner decide how that failure
affects the enclosing cost/consequence sequence.

Before committing, regenerate legal candidates against current Match state.
For CHOOSE_ONE, require the chosen identity to remain legal; never substitute
another target. For ALL, freeze the current deduplicated set in deterministic
ID order. This prevents targets created during execution joining the same batch.

Pass the chosen array to one `Verb.execute_many(subject, targets, params)` entry
point even for CHOOSE_ONE. A simple verb can share a default implementation that
applies its single-target action to each reference. Check existence and legality
before each application as earlier actions may change the board; skip invalidated
remaining targets and record per-target outcomes. This default batch is not
atomic or simultaneous. Costs requiring all-or-nothing payment and rules requiring
simultaneous effects need explicit preflight/commit behavior, not the default loop.
Use execution status to reject repeated commits and clicks; selection previews
must never mutate the board. Define event emission as part of each verb's action
contract rather than emitting again in the target resolver.

Actions receive validated references and resolve objects through Match. Any
low-level conversion to indices stays inside the action; domain adaptation has
already happened before the UI or verb sees candidates.

## Implementation sequence

1. Reconcile the current refactor: `Match.army` is flat, but parts of `Troople`,
   tests, and callers still use armies grouped by player. Repair constructor
   misuse, outdated class/member names, missing context APIs, the incomplete
   distance selector, and the deactivate target signature. Establish a parsing
   baseline before extending behavior.
2. Introduce reference factories and Match lookup methods. Migrate unit/hex/player
   references first; add property addressing when a concrete property verb is
   implemented. Keep unit IDs stable and derive owner/location from Match.
3. Add `EffectExecution` and `PhraseExecution`. Move selection state from
   `PhraseSelection` into the latter or adapt it temporarily. Pass the parent
   execution into each phase instead of creating independent sources.
4. Remove `Selector.context`, `ihxs`, and `iuns` as runtime storage. Implement
   native output kinds, reference selectors, distance-as-hex selection, explicit
   projections, and same-domain composition using the common result contract.
   Keep criteria on selector definitions.
5. Add named verb factories with fixed kind contracts and the shared TargetResolver
   identity/HEX-to-UNIT adaptations. Connect CHOOSE_ONE/ALL after conversion and
   legality checks. Migrate board highlighting and menus to reference lookups;
   distinguish units sharing a tile and expose off-board/property choices where
   needed. Keep unsupported adaptations visible as definition errors.
6. Add execution-boundary validation and adapt actions. Specify movement behavior
   explicitly: follow a unit's current identity and recheck legality by default;
   require a recorded position/revision only for rules that invalidate movement.
7. Implement event matching separately from action execution. Preserve event
   participants and historical data. Define cancellation, cost payment, and
   consequence failure rules before connecting the full activation sequence;
   previews and cancelled selections must not accidentally pay costs.
8. Update selection documentation and meaningful integration tests: overlapping
   executions of the same definition, shared SELF with separate phrase choices,
   distance -> deactivate versus distance -> damage, empty/shared hexes, conversion
   deduplication, domain mismatches (including empty results), explicit projections,
   CHOOSE_ONE versus ALL, moved/removed targets, property identity, cancellation,
   and exactly-once execution. Run the Godot integration scene once the parsing
   baseline is restored.

## Lifetime

Avoid a RefCounted ownership cycle: if `PhraseExecution` holds its parent strongly,
the parent must not also retain that child strongly. Store completed value results
on the parent and let the runner own active phrases, or use a weak back-reference.
Release pending execution references on completion/cancellation.

# Card-owned passives and continuous rules roadmap

Updated: 2026-10-16. This plan records implementation status and remaining work
for object-authored passives, auras, and ongoing card rules. Follow
`GENERAL_RULES.md` for intended behavior and `AGENTS.md` for the project boundary.

## Goal

Keep each card's active actions, triggers, passives, and continuous rules as
authored card data. Evaluate ongoing rules as read-only contributions to live
game state. A rule becoming true must not increment a counter, emit an event, or
modify a shared action definition. The same definition should supply mechanics,
provenance, and eventually card/hex/hover descriptions.

## What Guerra JS does

The JS catalogue stores these definitions together in each card's `rules` list.
`card-parser.ts` classifies an entry as an action, trigger, or derived rule;
`rule-parser.ts` builds the corresponding typed representation. This is useful
as a behavioral reference, not a reason to port its text parser.

- A derived `selector have contribution` rule evaluates a selector and rebinds
  `self` to each selected unit. Nested `have` scopes repeat this process.
- A `while condition : contribution` rule evaluates the condition against live
  state. Its contribution disappears as soon as the condition or deployed source
  no longer qualifies.
- `rule-state.ts` derives each unit's modifiers, passive properties, and action
  adjustments from printed data, stored grants, and live derived rules. It does
  not store a second mutable total or accumulate bonuses on repeated reads.
- `engine.ts` uses those effective values in combat, passive checks, and action
  adjustment. The recipient's effective Bow values are derived for the action;
  the shared catalogue/action definition is not rewritten.
- The JS examples include War Temple's friendly Bash bonus, ranged temples'
  Bow/Fire bonuses, Temple of Marches' Move bonus, White Wolf's inactive-source
  Bow aura, and self-conditional rules such as Canyon Ibex while bashing.
- JS currently allows a unit's own `die` trigger: `remove()` captures the dying
  card's rules and last-known unit before removal. Pine Processionary and Temple
  of the Last Bell are examples. The requested “units being defeated don't
  trigger” rule would therefore be an intentional Godot ruling, not JS parity.

Reference files: `C:/Users/ciava/Documents/guerra.game/game/cards.ts`,
`card-parser.ts`, `rule-parser.ts`, `rule-state.ts`, `rule-runtime.ts`,
`engine.ts`, and `docs/rule-language.md`.

## Current Godot foundation and gap

Godot already has read-only `Condition` and `RuleContext`, shared selectors and
`TargetResolver`, `StateModifier`, and `ContinuousEffect`. `UnitInfo` currently
stores separate `effects`, `trigger_effects`, `state_effects`, and
`continuous_effects` arrays. `UnitInfo.state_modifiers()` asks each definition
for a live physical/magical contribution and adds the regional control bonus
once. War Temple is the current live aura example. `RulesRunner.capture_event()`
scans card triggers, and `Match.defeat()` captures the dying unit's own `die`
trigger before clearing its board presence.

The core continuous slice is now implemented without a new signal system or
parser. `Contribution` has typed modifiers, passive flags, Bow values, and
defeat-trigger suppression. `ContinuousEffect.have()` exports contributions to
selector recipients; `while_self()` evaluates a condition on its source. Legacy
modifier constructor fields remain as a compatibility view. Active and triggered
definitions remain in their existing UnitInfo arrays; one unified `rules`
collection and UI provenance are still future work.

### Implemented continuous slice

- “While” uses `StateModifier` or `ContinuousEffect.while_self()` with read-only
  Wounded, Active, Deployed, Shielded, Bashing, BashingEnemy, and
  BashingEnemyHero conditions.
- “Have” uses `ContinuousEffect.have()` with the existing selector/projection
  composition and source/recipient conditions. Each recipient is evaluated once
  against the live selector result.
- `Contribution` supports modifier deltas, passive flags, named action parameter
  adjustments (Bow, Fire, Cannon, Move, and Fly value plumbing), and the
  Hushbringer defeat-trigger policy.
- War Temple, four ranged/action-value Temples, Temple of Marches, White Wolf,
  Canyon Ibex, Crown Breaker, and Marsh Badger have object-authored catalogue
  examples. Combat and target previews read the same effective values.
- `RulesRunner` preserves the Die event and filters its trigger candidates at
  capture. Sequential defeat is implemented; simultaneous last-known-state
  snapshots require a future batch-defeat API.
- P/F/T/A stickers are typed per-action phrase definitions. Bow damage/range
  counters are stored as unit properties; temporary named action-value grants
  attach to concrete recipients and expire after the active player's End choices.
  Idle snapshots preserve those timed grants and their expiration identities.

## Current object model and remaining card-data work

Extend the existing definitions rather than introducing a rule language or a
general-purpose interpreter:

1. Give each card one authored `rules` collection. Its entries are existing
   active/trigger `Effect` definitions plus continuous/passive definitions.
   Keep named factories such as `Collection.bow_DR()` for readable card data.
   During migration, `UnitInfo` may expose derived compatibility views for the
   action menu and runner; do not keep two independently editable copies.
2. Let a `ContinuousEffect` contain a recipient selector, optional source and
   recipient conditions, and one or more typed `Contribution` values. Implemented
   output kinds are physical/magical delta, passive property grant, Bow action
   adjustment, and defeat-trigger suppression policy.
3. Have one read-only effective-state query return effective values together
   with contribution provenance: source card/rule, recipient, and contribution.
   `UnitInfo` can keep its current `physical_modifier` and `magical_modifier`
   getters as thin views over that result. Do not cache until profiling shows
   that a board-sized scan is a problem.
4. Keep stored grants separate from live continuous contributions. Triggered
   upgrades/counters persist according to their verb; losing an aura removes
   only its derived grant. A getter never performs life clamping, defeat, or
   mutation.
5. Keep triggers on the existing `RulesRunner` path. Continuous trigger-policy
   contributions are queried at event capture; they do not subscribe a card to
   signals and do not create an event handler of their own.

The current API example is:

```gdscript
var friendly := QuerySelector.new(TargetRef.Kind.UNIT)
friendly.relative_owner = Enum.YOU
var effects: Array[Effect] = [Collection.movement(2)]
var auras: Array[ContinuousEffect] = [ContinuousEffect.have(
    friendly, [Contribution.modifiers(1, 0)], null,
    Condition.Bashing.new(), "Friendly units while bashing")]
```

Active/triggered effects and continuous rules still live in parallel
`UnitInfo` arrays. Unifying card-owned rules and adding contribution provenance
remain open implementation work; the code examples above use actual APIs.

## Requested rulings and example translations

### Defeated units do not trigger

JS permits the departing source's own `die` trigger. Godot captures that trigger
before removal unless an active Hushbringer contribution applies. The implemented
filter follows the Forge/Hushbringer pattern documented in [forge.md](forge.md):
keep publishing the successful `die` event and its history, then filter matching
trigger candidates before creating `EffectExecution`s.

The recommended scope is “defeat does not cause triggered abilities to fire,”
not merely “the defeated unit's own ability does not fire.” When active for a
defeat, this suppresses the defeated unit's own `die` trigger and other cards'
triggers caused by that `die` event. Other consequences of defeat still happen,
and unrelated triggers remain eligible. This is intentionally broader than
Guerra JS. Apply suppression to an event occurrence, not by mutating
`EffectEvent.succeeded()` or omitting `Match.action_event`; retained history is
still needed by non-trigger consumers and diagnostics.

Current defeat capture reads the relevant live sources before removing its one
unit. If simultaneous multi-unit defeat is introduced, snapshot all policy
sources before removing any member of that batch to avoid order-dependent results.

### “Your units have +1 while bashing”

Represent this as a continuous effect on the source card: recipients are units
owned by its controller; the recipient condition is `Bashing` (or the narrower
`BashingEnemy` where required); the contribution is physical `+1`. Resolve the
condition per recipient. The same source contributes once per recipient, no
matter how many matching Bash records or adjacent allies exist. War Temple is the
reference card and the current Godot aura is its starting implementation.

### “Your units have +1/+0 Bow”

Represent this as a continuous action adjustment contribution for Bow damage
`+1` and range `+0`, distributed to the card's friendly-unit selector. Build the
effective Bow parameters when generating legal actions and again at commitment;
capture the resulting amount/range in delayed attacks at the existing action
boundary. Never modify the shared Bow `Effect` or `Verb`, and do not apply the
bonus to Fire, Cannon, or another unit's Bow.

### “+1/+1 Bow until end of turn” and “+1/+1 Bow counter”

These have different storage and lifetime. Use
`Collection.grant_action_values(&"bow", [1, 1], recipients)` for the temporary
grant. It freezes the chosen unit identities when the action resolves and stores
the grant on each recipient. `Match._next_turn()` removes it after that player's
End triggers, before the next Start. It survives its source leaving the board and
does not alter a reusable Verb. Use `Verbs.upgrade_bow(1, 1)` for permanent Bow
damage/range counters; the `bow_damage` and `bow_range` properties persist until
another effect changes them. Both combine additively with live continuous Bow
contributions. They must never be encoded as one another or as a cached total.

## Staged implementation roadmap

### C0 — Align the card-data contract (remaining)

- Audit current `UnitInfo` arrays and all factories that fill them.
- Introduce one authored card `rules` collection, then migrate active actions,
  triggers, `StateModifier`, and `ContinuousEffect` incrementally.
- Derive action-menu and trigger-runner views from that collection; remove each
  old parallel field only after its readers have moved.
- Give every definition a stable card-local rule ID for explanations and future
  saves. Definitions stay reusable; source/recipient and activation state do not
  live on definitions.

**Complete when:** a card's authored rules are discoverable in one factory and
there is one authoritative copy of each rule.

### C1 — Generalize contributions and effective state (partially complete)

- Typed contribution records now support physical/magical deltas, passive grants,
  Bow/Fire/Cannon/Move/Fly parameter adjustments, and defeat-trigger policy.
- Typed P/F/T/A definitions attach to action phrases; numeric Bow counters and
  timed numeric action grants use separate persistent and cleanup-managed storage.
- Preserve the current source-condition, recipient-selector, per-recipient
  condition, and deduplication behavior.
- Action values and passive flags are read through effective queries. Provenance
  records remain future work. Regional control remains a separate authoritative
  contribution and is not counted twice.
- Validate contribution type/target at definition construction or evaluation;
  unsupported combinations produce diagnostics, not silently ignored bonuses.

**Complete when:** effective queries also expose provenance and definition
validation reports invalid output/target combinations.

### C2 — Passive properties and action values (implemented subset)

- Derived passive flags combine printed flags and live continuous grants through
  `UnitInfo.has_effective_flag()`.
- Named action parameter adjustments currently cover Bow, Fire, Cannon, Move,
  and Fly. Previews and combat legality/resolution read the same query.
- Delayed attack values are captured at declaration.
- Add source/provenance to the modifier explanation data so the card/board can
  later explain which temple or passive supplied a value.

**Complete when:** all required action families and stickers use this same path;
the representative Guerra cards are ported and covered by behavior tests.

### C3 — Event eligibility as card data (implemented for defeat)

- Add a typed event-cause filter read by `RulesRunner` after ordinary event
  matching and before it captures executions. Keep event matching pure and
  capture timing owned by the runner.
- Implement the Hushbringer-style defeat rule: suppress all triggered abilities
  caused by the affected unit's `die` event, including its own trigger and other
  cards' death reactions. Keep the Die event successful and inspectable.
- Simultaneous defeat batch snapshots, stable source/rule IDs, and historical
  provenance remain future work.
  A filter cannot retroactively remove a trigger already captured.
- Keep global game policy distinct from a card-granted aura: a card-level rule
  can suppress eligibility for its selected recipients, while a project-wide
  ruling belongs in the central policy and must not be faked as a card.

**Complete when:** event capture applies the policy once at the documented
boundary, duplicate publication cannot change the result, unrelated triggers
remain eligible, and death listeners are suppressed only when they are caused
by the filtered event.

### C4 — Port representative cards and generate descriptions (partially complete)

- War Temple, the ranged temples, Temple of Marches, White Wolf, Canyon Ibex,
  Crown Breaker, and Marsh Badger now have typed catalogue definitions. Remaining
  validation should cover overlapping sources and more presentation provenance.
- Passive flags and the Hushbringer rule have direct contribution/test examples.
- Render the same definition data in compact card/hex summaries and full hover
  text. Descriptions must not become a second manually maintained rules list.
- Keep authored prose optional while no general natural-language parser exists;
  object factories remain the mechanics source.

**Complete when:** the representative cards can be added by composing existing
objects, their explanation matches their effective values, and no card-specific
branch was added to combat, Match, or the UI.

## Validation scenarios to cover when implementation is requested

- Read a modifier/action/passive value repeatedly; counters and events remain
  unchanged.
- One and two War Temples; an ally entering/leaving Bash; source deployment,
  defeat, and recipient defeat.
- Two aura sources grant the same passive; removing one does not remove the
  other. Printed and continuously granted passives combine predictably.
- Bow bonus changes legal range and damage, is captured for a delayed Bow, and
  never changes Fire or the shared Bow definition.
- A die event with the agreed suppression policy: the dying card's trigger and
  other reactions caused by that death are suppressed; unrelated events still
  trigger; event history remains present; a previously captured trigger is
  unaffected by later state changes.
- Card and board explanations identify each contributing source without
  exposing internal implementation concepts.

The project's `AGENTS.md` requires tests only when the user's prompt ends with
`TEST`; this roadmap does not run tests.

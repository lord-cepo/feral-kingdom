# Forge notes: continuous rules and trigger suppression

Reviewed: 2026-10-16. Forge is a secondary architecture reference for the
object-authored rules engine in Feral Kingdom. Its MTG rules are not Feral
Kingdom rulings. For the current card-owned contribution plan, see
[CONTINUOUS_ROADMAP.md](CONTINUOUS_ROADMAP.md); for trigger ownership and timing,
see [M2_EXECUTION.md](M2_EXECUTION.md).

## Recommendation for defeat-trigger rules

Keep the `die` occurrence and filter trigger candidates against it. Do not
cancel, omit, or mark the underlying death event unsuccessful just because a
continuous rule suppresses triggers.

The event is a fact about the match: the unit was defeated, had a last hex, may
have caused victory, and may matter to future non-trigger mechanics or event
history. Suppression changes which triggered abilities are created from that
fact. Conflating those responsibilities would make death look as if it never
happened to every consumer, including rules that still need the death record.

Forge follows the candidate-filter approach for static trigger suppression. Its
`TriggerHandler.runTrigger()` receives an event mode and run parameters; then
`canRunTrigger()` checks each candidate trigger and calls
`StaticAbilityDisableTriggers.disabled(game, trigger, runParams)` before that
trigger is run. In other words, the event continues through the trigger system,
while a card rule can disqualify an individual trigger from that occurrence.
Forge also has a separate broad mode-suppression early return in `runTrigger()`;
that is too coarse for a conditional card ability such as Hushbringer. See the
[Forge TriggerHandler source](https://github.com/Card-Forge/forge/blob/master/forge-game/src/main/java/forge/game/trigger/TriggerHandler.java#L233-L250)
and the per-trigger check at
[canRunTrigger](https://github.com/Card-Forge/forge/blob/master/forge-game/src/main/java/forge/game/trigger/TriggerHandler.java#L360-L394).

Forge's static-ability inventory includes `DisableTriggers`; its enum comment
points to `StaticAbilityDisableTriggers`, and `TriggerHandler` invokes that
policy at the trigger-candidate boundary. The [Forge Statics guide](https://github.com/Card-Forge/forge/wiki/Statics)
describes continuous/static abilities as card-authored effects and lists
`DisableTriggers` among rules-layer static modes. The [trigger scripting guide](https://github.com/Card-Forge/forge/blob/master/docs/Card-scripting-API/Triggers.md)
describes triggers as event listeners with event-specific parameters and
triggered-object bindings.

Hushbringer is the closest MTG example: its static ability says that creatures
entering or dying do not cause abilities to trigger. This is broader than
“the departing creature's own death trigger does not fire”: abilities on other
cards that trigger because that creature died are also suppressed. At the same
time, the creature still dies; other non-triggered effects of the move are not
undone. Card rulings also make clear that replacement effects are not triggered
abilities and remain active. See the [Hushbringer card and rulings](https://mtg.wtf/card/eld/18/Hushbringer)
and Forge's `TriggerHandler` comment describing its static check as handling
“Torpor Orb and the like.”

### Apply that distinction to Feral Kingdom

The user's wording, “units being defeated don't trigger,” most closely maps to
Hushbringer's event-cause semantics:

- Publish and retain the `die` event normally, with its subject, last hex,
  controller, and success facts.
- Before creating any `EffectExecution` for that event, apply a trigger filter
  to each otherwise-matching candidate. When the suppression rule is active for
  a defeated unit, no ability caused by that `die` occurrence fires. This
  includes the defeated unit's own `die` trigger and another card's reaction to
  that unit dying.
- Do not suppress unrelated triggers, such as `end`, just because their source
  is also defeated, unless a separate rule says so. Do not suppress direct
  state changes or non-trigger consequences.
- A trigger already captured for an earlier occurrence remains captured. The
  filter applies at the defined event-capture boundary, not retroactively.

This intentionally differs from the narrower proposal in the previous
continuous-effects roadmap draft. It also intentionally differs from Guerra JS,
which captures the departing source's own `die` triggers. If the intended Feral
ruling is only to silence abilities owned by the defeated unit, narrow the
predicate to trigger source instead; do not silently mix those two meanings.

## Simultaneous defeat and last-known state

Forge's Hushbringer ruling covers a creature dying at the same time as
Hushbringer, including Hushbringer itself. That behavior needs last-known state:
evaluate relevant static effects from the board snapshot for the death batch,
not whichever permanents happen to remain after sequential removal.

For Feral Kingdom, a single `Match.defeat()` can capture continuous trigger
filters before changing the unit to `DEFEATED`. If a resolver can defeat several
units as one simultaneous outcome, capture the eligible suppression rules for
the entire batch before applying any removal. Use stable source/rule IDs and
event facts; do not depend on signal order. This is the only extra history
needed for this ruling. It does not require replacing `EffectEvent` with a
second event bus.

## Technical patterns worth reusing

### Card-authored definitions

Forge stores card data as declarations for activated abilities, triggers,
replacement effects, and static abilities. `CardFactory` loads those categories
onto the card from its record. Static abilities describe either continuous
characteristic changes or game-rule restrictions. The card scripting API gives
each category an explicit record (`A`, `T`, `R`, `S`) rather than putting
resolution state on a global handler. See [CardFactory](https://github.com/Card-Forge/forge/blob/master/forge-game/src/main/java/forge/game/card/CardFactory.java)
and [Card scripting API](https://github.com/Card-Forge/forge/wiki/Card-scripting-API).

For Feral, reuse the idea that card-owned definitions declare behavior and the
runner evaluates them. Keep our typed GDScript objects and the agreed object
composition; do not copy Forge's text syntax, Java class hierarchy, or separate
MTG rules layers wholesale.

### Continuous effects

Forge distinguishes stat-layer contributions such as power/toughness changes
from game-rule effects such as disabling triggers or restricting actions. Its
statics guide documents affected-object selectors and effect zones; the
engine's `StaticAbilityMode` enumerates common game-rule policies. This supports
Feral's proposed contribution kinds:

- Numeric/stat contributions: physical and magical modifiers.
- Action contributions: named action values such as Bow damage/range.
- Property contributions: a passive supplied by one or more live sources.
- Rule-policy contributions: an event filter or action legality restriction.

All should be read through one authoritative, read-only effective-state/policy
query with provenance. Keep policy contributions separate from attack math, but
let both use the card's selectors, conditions, source lifetime, and stable
definition identity. The existing `StateModifier`, `ContinuousEffect`,
`Condition`, `RuleContext`, and `RulesRunner` are the starting points.

## Suggested implementation boundary

Add a small candidate-level API conceptually like:

```text
event = published immutable EffectEvent(die, defeated_unit, last_hex)
candidates = RulesRunner.find_matching_triggers(event)
eligible = TriggerPolicy.filter(candidates, event, captured_rule_state)
capture EffectExecution for each eligible candidate
```

The filter is a read-only predicate over the event and continuous policy
contributions captured at the relevant boundary. `EventPhrase.matches()` remains
responsible for ordinary action/participant matching. The filter must not mutate
the event, pay costs, run consequences, or remove the defeated unit's history.

Keep the first implementation narrow and declarative: the `die` event-cause
policy plus the current continuous modifier and action-grant examples. Add other
Forge-like rules only when a Feral card or explicit ruling needs them. See
[CONTINUOUS_ROADMAP.md](CONTINUOUS_ROADMAP.md) for staged card-data,
contribution, passive, action-value, and presentation work.

## Forge sources reviewed

- [Forge repository](https://github.com/Card-Forge/forge)
- [Statics guide](https://github.com/Card-Forge/forge/wiki/Statics)
- [Trigger scripting guide](https://github.com/Card-Forge/forge/blob/master/docs/Card-scripting-API/Triggers.md)
- [TriggerHandler.java](https://github.com/Card-Forge/forge/blob/master/forge-game/src/main/java/forge/game/trigger/TriggerHandler.java)
- [StaticAbilityMode.java](https://github.com/Card-Forge/forge/blob/master/forge-game/src/main/java/forge/game/staticability/StaticAbilityMode.java)
- [CardFactory.java](https://github.com/Card-Forge/forge/blob/master/forge-game/src/main/java/forge/game/card/CardFactory.java)
- [Hushbringer card text and rulings](https://mtg.wtf/card/eld/18/Hushbringer)


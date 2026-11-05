# General trigger effects: technical roadmap

Updated 2026-10-16. This document turns the trigger design into an incremental
implementation and parity plan. It describes the current Godot implementation
and planned extensions; it does not authorize starting later roadmap stages.
For executable APIs and ownership details, see [M2_EXECUTION.md](M2_EXECUTION.md).
For the broader event/state model, see [TRIGGER_AND_STATE_PLAN.md](TRIGGER_AND_STATE_PLAN.md).

## Goal and parity boundary

An action or lifecycle occurrence should be published once as an immutable event.
The rules runner matches that event against reusable trigger definitions, captures
all matching activations at the correct timing boundary, and executes their
consequences through the regular effect/choice pipeline. No card should connect
itself directly to mutation signals or implement its own event listener.

Guerra JS is the behavior reference for event stages, event families, source and
participant binding, matching conditions, trigger order, and consequence timing.
Godot must preserve the explicit rulings in `GENERAL_RULES.md` where they differ
from the legacy JS snapshot, including self-Stun activity costs, hero Start Stun
recovery, owner-only End activation after effects, and immovable temples.
A parity gap is not permission to overwrite those rulings.

## Existing foundation

The initial event-handler and matcher already exist in Godot. The generic event
authoring path now supports exact actions, action sets, any action, named attack
families, participant selectors, stage, and captured detail constraints through
`Effect.on_event()`. Extend these pieces instead of introducing a parallel trigger
system.

| Responsibility | Current owner | Current behavior |
| --- | --- | --- |
| Event record | `EffectEvent` | Captures action name, stable subject/target references, copied detail values, stage, occurrence ID, turn, phase, and actor controller; `validation_error()` rejects malformed records and `succeeded()` filters cancellations. |
| Event publication | `Match`, `Action`, `CombatResolver`, `CostPayment` | Publishes action and lifecycle occurrences through `Match.action_event`; mutation boundaries defer consequences until cleanup is complete. |
| Pattern validation and matching | `Effect.EventPhrase` | Checks stage, exact action, action set, wildcard, or `atk`/`patk`/`ratk` family, exact detail constraints, then resolves and compares subject and target selectors. It does not recheck post-action legality. |
| Capture and matching | `RulesRunner.capture_event()` | Scans deployed sources and their trigger definitions, validates each pattern, tests its condition, filters defeat triggers through live Hushbringer contributions, and captures eligible `EffectExecution`s. Duplicate delivery of one occurrence is ignored. |
| Dispatch and suspension | `RulesRunner` | Queues captures in deterministic order, holds work across mutation boundaries, and pauses for managed choices. |
| Trigger consequences | `EffectExecution` and `PhraseExecution` | Uses the ordinary cost, optional confirmation, subject/target choice, sequence, and verb execution path. |

### Event names and fields available to card definitions

Patterns use the action names below, not UI labels. `details` values are copied
when the event is created. `EventPhrase.observe(..., details)` can require exact
field values, while `Effect.condition` can compose `Condition.EventFact` checks.

| Occurrence | Stages | Useful captured details |
| --- | --- | --- |
| `activate`, `start`, `end`, `deploy`, `die` | `resolved` | Death includes `last_hex` and `owner`; deploy target is the destination hex. |
| `move` | `resolved` | Shared Move/Fly event; `movement_kind`, origin/destination hex, and origin/destination control. |
| `bow`, `fire`, `cannon`, `gore`, `bash` | `target` and/or `resolved` | Action amount, pierce, target/origin facts, and resolution outcome as emitted by that action. `bash` target is the engagement occurrence. |
| `hit`, `wound` | `resolved` | Actual damage and attack kind; Wound exists only when physical life loss is positive. |
| `stun`, `mend`, `push`, `pull` | `resolved` | Requested/actual amount or captured movement origin/destination facts. Self-Stun payment carries `self_cost`; hostile Stun carries `hostile`. |
| `bomb_throw`, `bomb_light`, `bomb_defuse`, `bomb_explosion`, `push_bomb`, `pull_bomb` | `resolved` | Bomb damage, pierce, and/or captured origin. Bombs are not members of `atk`, `patk`, or `ratk`. |
| `deactivate`, `damage`, `upgrade_bow`, `up_life`, `revive`, `decrement`, `change_counter`, `set_flag`, `shield`, `mshield` | `resolved` | Action-specific amount/delta values. |

An attack family is a pattern alias, not an emitted event name: `atk` matches
Fire/Cannon/Gore/Bash/Bow, `patk` Gore/Bash/Bow, and `ratk` Fire/Cannon. For
example, use `observe_family(&"atk", enemy_selector, self_selector,
TargetRef.Kind.UNIT, TargetRef.Kind.UNIT, &"target")` for an opponent's attack
declaration against this unit. Use `observe_any([&"move"], ...)` with the exact
`movement_kind` detail to distinguish Fly from Move.

The primary call path is:

```text
Match / Action / CombatResolver mutation
  -> Match.action_event(EffectEvent)
  -> RulesRunner.capture_event(event)
  -> EventPhrase.validate() / EventPhrase.matches()
  -> captured EffectExecution(source, event)
  -> RulesRunner boundary/work queue
  -> EffectExecution and PhraseExecution
  -> verb mutation emits further events
```

Death is a deliberate special boundary: capture the dying unit's rules before
removing its deployed presence, then retain its stable identity/event facts for
the consequence. Triggered follow-up events are queued; they must not recursively
advance the turn or run halfway through a combat mutation.

The Hushbringer-style policy is applied to a successful `die` occurrence before
trigger matching creates any executions. It suppresses both the defeated unit's
own reaction and other cards' reactions to that defeat, while the event record
remains intact. See FK-1 in [RULINGS.md](RULINGS.md) and the
[continuous implementation roadmap](CONTINUOUS_ROADMAP.md). The current capture
path handles one defeat at a time; a future simultaneous-defeat batch must
snapshot policy sources before removing the first unit.

## Guerra JS behavior to preserve

Reference implementation paths:

- `game/rule-runtime.ts`: `eventFromIntent`, `matchingRules`,
  `executeNormalizedIntent`, `emitNormalizedEvent`, `emitNormalizedResolved`,
  and `executeTriggers`.
- `game/rule-evaluator.ts`: `matchRuleAnchor` and event-condition evaluation.
- `game/engine.ts`: builds runtime rules from current units and preserves source
  snapshots for removal/lifecycle cases.
- `tests/engine-catalogue-triggers.test.mjs` and `tests/rule-runtime.test.mjs`:
  examples of order, phase anchors, suspended work, and trigger results.

The JS runtime establishes these semantics:

1. An occurrence has a stable identity, action/name, stage, participants, event
   facts, controller, and turn context. Successful action intent is distinguishable
   from successful resolution. A queued/delayed attack is not resolved damage.
2. At an occurrence boundary, the matcher considers trigger rules, resolves the
   source from live state or its captured last-known snapshot, checks phase-owner
   semantics, matches the event anchor, then evaluates the rule guard.
3. Matching is captured before consequences run. A trigger changing or defeating
   another source cannot retroactively remove an already captured matching rule.
4. Consequences execute in a stable order, left-to-right within each rule. A
   pending choice suspends the queue and resumes at the same trigger/step.
5. Mutation bundles capture events as their members commit but defer their
   follow-ups until the bundle boundary. Cost follow-ups resolve before the parent
   effect's consequences. A partial consequence sequence keeps earlier committed
   work and does not execute unperformed later steps.
6. Event families are explicit: JS `atk` is Fire/Cannon/Gore/Bash/Bow;
   `patk` is Gore/Bash/Bow; `ratk` is Fire/Cannon. Bomb is not silently included.
7. `target` and `resolved` are separate stages where the rule needs them.
   Conditions may use captured historical facts as well as current Match state.
8. Failed/cancelled occurrences do not match ordinary event patterns. A successful
   attack whose resolution misses remains a successful action event and still
   publishes its resolved stage.

These are behavior contracts, not a request to port JS parsing or its rule DSL.
Godot card definitions remain authored as typed objects and named factories.

## Implementation roadmap

### T0 — Freeze the occurrence contract

Keep `EffectEvent` as the common value-like record. Audit each event producer and
write down its action, stage, subject/target kinds, controller, detail keys, and
whether it is published before mutation, after mutation, or at a lifecycle
boundary. Preserve captured origin/destination and last-known source data when a
rule requires history; do not put mutable unit objects in event details.

**Done when:** every trigger-relevant action has a documented event contract and
one authoritative publication path. Multiple notifications for one occurrence
reuse its occurrence identity rather than creating duplicate trigger activations.

### T1 — Complete the event publisher / handler boundary

Use `Match.action_event` as the single route into `RulesRunner.capture_event()`.
The handler validates the event record, guards duplicate occurrence delivery, and
captures matching executions; it does not mutate gameplay state or render UI.
`begin_boundary()` / `end_boundary()` bracket multi-step mutations and defer queue
draining until cleanup finishes. Ensure nested events are appended as follow-up
work rather than recursively drained from a signal callback.

Check all producers: deploy, activation/Start/End, movement, damage/contact,
Wound, hostile Stun, death, target-stage and resolved-stage Fire/Bash, costs,
and any new action added later. A missing publication is a missing trigger
capability even if the matcher supports its name.

**Done when:** the event inventory has no unintentional gaps, duplicate signal
delivery cannot double-dispatch, and boundary ordering is explicit at every
multi-step mutation.

### T2 — Keep event matching pure and separate from execution

`EventPhrase.validate()` validates the reusable pattern once at execution start:
required selectors, native kinds, supported stage, and action/family definition.
`EventPhrase.matches()` is a read-only predicate over `(pattern, context, event)`:

```text
match = event stage matches
     && action name/set/family (or wildcard) matches
     && every declared detail constraint equals the captured event value
     && event subject is in resolved subject candidates
     && event target is in resolved target candidates
```

Do not call the verb, pay a cost, mutate counters, or re-evaluate action legality
inside the matcher. For example, a successful `deactivate` event still matches
after its target has become inactive. A condition/guard is evaluated after the
anchor matches, using the captured event plus current read-only `RuleContext`.
Keep historical facts explicit; do not infer old positions from a unit's current
hex.

**Done when:** matching an event twice has no side effects, empty candidate sets
remain distinct from invalid pattern/type definitions, and each event family and
stage has a named contract.

### T3 — Capture a deterministic match set at the right instant

For each event, scan eligible trigger definitions exactly once and capture
`EffectExecution(definition, source_ref, event)` for every passing match before
executing any one of them. Preserve the event and SELF binding across movement,
death, owner changes, and UI suspension. For death and leave-play triggers, capture
before removal and use last-known facts where their rule requires them. For
resolved-stage events, match against state at the resolution boundary.

Define order in one place to match the JS `runtimeRules()` ordering: event
controller first, then deck position, hero priority where the JS format specifies
it, stable card identity as a tie-break, and printed rule order. Do not rely on
signal connection order or Dictionary iteration. Record a dispatch key at least as specific as
`(occurrence_id, source_id, trigger_definition_id)`; a later occurrence may
legitimately fire that definition again.

**Done when:** a trigger captured before another consequence disables or defeats
its source still resolves under ordinary action legality; a trigger that did not
match at capture cannot join later; duplicate notifications cannot repeat it.

### T4 — Drain captured triggers through managed work

`RulesRunner` owns an ordered queue of captured executions and continuations.
Mutation boundaries defer draining; `EffectExecution.finished` releases nested
follow-ups before the next sibling trigger. A choice leaves the current execution
and queue position intact. Keep a work limit with a diagnostic causal trace for
unbounded trigger chains. Do not implement this as per-card signal callbacks,
recursive phase advancement, or frame polling.

Treat cost and consequence bundles distinctly: collect/preflight atomic costs,
commit once, resolve cost-generated triggers, then resume the parent consequence.
Consequence sequences remain sequential; committed earlier steps are not rolled
back if a later step fails. UI observes the execution signals and submits choices;
the Board never matches triggers or pays trigger costs itself.

**Done when:** simultaneous matches resolve in documented order, nested work and
cost follow-ups resume exactly once, choice suspension does not lose or replay
work, and another player command cannot enter while managed work is pending.

### T5 — Expand trigger rule coverage card by card

Use object-authored `Effect.on_event()`, `EventPhrase`, `Condition`, `Selector`,
`ConsequencePhrase`, and `ConsequenceSequence` definitions. Add a matcher feature
only for a concrete rule: explicit phase anchors, named event families/stages,
event-fact conditions, optional policy, ALL/CHOOSE_ONE target behavior, or a
specific historical participant. Do not create a card-specific event handler.

For each new rule, add one catalogue definition and document its trigger event,
stage, source/recipient binding, condition, consequence, ordering, and failure
behavior. Compare it to the JS card/source test, then record any intended rulebook
divergence. Broader phase schedules, delayed effects and expiration lifetimes are
separate M3 work; an ordinary event trigger must not become a hidden scheduler.

**Done when:** each supported card trigger is composed through the shared system,
and the catalogue parity table marks implemented, partial, intentionally
different, or deferred behavior.

## Acceptance checklist for future trigger changes

When the user authorizes running tests by ending the prompt with `TEST`, relevant
coverage should establish:

- exact action, family, and stage match/mismatch, including explicit attack-family
  membership and event detail binding;
- one occurrence cannot dispatch twice, while the same rule can fire on a later
  occurrence;
- all matching rules are captured before the first consequence, with deterministic
  controller/source/printed-rule ordering;
- deploy/death and target/resolved boundaries preserve their intended source and
  historical facts;
- a trigger that suspends for confirmation or target choice resumes at the same
  position and retains its source/event;
- cost triggers precede parent consequences; consequence sequence failures retain
  already committed effects and release only captured follow-ups;
- a follow-up event is queued until the active mutation/bundle boundary completes;
- matcher previews do not mutate Match or pay a cost.

Use existing Godot integration scenes as relevant references: `tests/m2_test.tscn`,
`tests/trigger_state_test.tscn`, and focused selection/combat scenes. This document
does not authorize running them.

## Caller map

| Change | Primary owner / caller | Keep in sync |
| --- | --- | --- |
| Add an event type or stage | `Match`, `Action`, or `CombatResolver` publishes `EffectEvent` | Event inventory in T0; `EffectPhrase.observe` authors pattern |
| Change pattern matching | `Effect.EventPhrase.validate()` / `matches()` | Event family/stage/detail semantics and trigger definitions |
| Change capture/order/dedup | `RulesRunner.capture_event()` and queue | `M2_EXECUTION.md`, this roadmap, trigger integration coverage |
| Change cost/choice/sequence resume | `EffectExecution`, `PhraseExecution`, `RulesRunner` | `M2_EXECUTION.md` APIs and caller map |
| Add a card trigger | `Collection` factory + `CardCatalogue` composition | `GUERRA_RULES.md` parity/deviation notes and usage docs |

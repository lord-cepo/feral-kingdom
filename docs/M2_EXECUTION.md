# M2: commands, triggers and phase continuations

Online boundary update (2026-11-05): `NetworkSession` routes public deployment,
runner submission, effect/phrase choice, confirmation/cancel and board
acknowledgement input through host validation before mutation. Accepted calls
enter the same engine; definitions, costs and continuations are unchanged.
Consumed choices that end in engine failure are still replicated, preserving
paid costs and failure state. Reconnect reconstructs a settled snapshot plus its
accepted command tail. See [MULTIPLAYER.md](MULTIPLAYER.md) for the caller map,
wire examples, identity gates and opt-in tests.

2026-10-29 availability regression update: `command_available` now carries each
payable branch's preview `cost_choice_N`/`cost_N` bindings into
`_consequence_available`, then discards that private context. Rogue can query
the exact donor counter kind without paying or awarding it. Disable/Return costs
may create Warlock/Summoner's future recipients. CostBundle validation accepts
these supported atomic departures and deployment payments. Revive is shared by
paid Warlock commands and captured death triggers, retaining friendly, defeated,
non-hero and not-SELF checks. See [TESTING.md](TESTING.md) for coverage and callers.

Implemented 2026-09-26. This describes executable APIs, complementing
[SELECTION.md](SELECTION.md) and the broader [trigger/state plan](TRIGGER_AND_STATE_PLAN.md).

## Ownership and timing

`Match.rules_runner` owns player commands, captured triggered executions, and
pending combat/phase continuations. The local controller submits an effect with
`submit(effect, source)`. False means the command was rejected without replacing
the current execution. The Board observes `execution_started`, attaches to its
phrase/confirmation signals, and submits choices to that execution.

The runner rejects a second command or deployment while busy. Match also rejects
Pass and public token completion while a managed choice is pending. Completion
spends one standalone action token for the original player after the effect and
its followups; a paid cost remains paid after subsequent failure/cancellation.
Triggered consequences do not spend an implicit standalone token. Explicit
resource costs still apply. Action-free and Tireless remain independent.

The 2026-10-28 printed cost notation is [A] for action, [S] for activity/self-Stun,
[AS] for both (the unmarked default), and [2S] for double self-Stun without an
action. [A2S] retains Flying Squirrel's original action-plus-double-Stun cost.
[SYNERGY_UNITS.md](SYNERGY_UNITS.md) documents the 28-card extension: atomic
Sacrifice, bounded counter transfer, shared Cannon/Fire Hit/Wound, Deploy
suppression and live player-action allowances with separately retained spending.

`Effect.eval`, `Board.select_effect`, `Board.select_phrase`, and direct action
helpers remain low-level integration/test entry points. They do not submit a
player command or own its token accounting. Use `rules_runner.submit` for normal
play, including Tireless actions on inactive units.

## Events and bundles

For each occurrence, the runner scans eligible deployed sources for the event
controller first, then the other player, retaining stable army/deck and each
source's printed rule order. It tests
all matching patterns and conditions before executing any consequence. The
captured executions retain SELF and the occurrence; they do not rematch after a
previous trigger moves, disables or defeats their source.

Mutation boundaries prevent signal delivery from executing effects halfway
through damage, defeat, or a Bash exchange. Own/nearby death patterns are captured
before Match removes the dying unit's hex. Gore declarations capture origin,
destination and origin control before movement. Resolved occurrences inspect
the state at their resolution boundary. Querying ordinary references always
reads current Match state; historical rules explicitly use event facts.
`EffectEvent` validates its action, stage, participants, and controller before the
scan. Its controller normally comes from the event actor; damage-caused death
passes the causing controller explicitly so response-turn actions keep the right
trigger order. Cancelled events do not match, while a resolved Fire miss remains
a successful Fire event.

An effect holds events produced by its consequence sequence until the sequence
finishes (or stops after a committed partial result). Nested followups run before
the next sibling trigger. Cost followups run after payment and before the parent
consequence, even when those followups need their own UI choices. Earlier
consequence mutations survive later failure; this is not a simultaneous batch.

Bow, Gore and Bash share physical contact publication: Hit for contact, Wound
only for positive actual life loss. Immunity produces neither. Fire retains its
separate lethal test and does not acquire physical Hit/Wound events.

`Effect.on_event(pattern, consequence, guard, cost, policy)` composes a triggered
effect from reusable objects. `EventPhrase.observe` matches one exact action;
`observe_any` matches an explicit action set or all names when passed an empty
list; `observe_family` accepts only `atk`, `patk`, or `ratk`. Patterns can match
subject/target references, target/resolved stage, and exact captured detail fields.
`Effect.condition` supplies additional read-only guards such as `Condition.EventFact`.
`atk` includes Fire/Cannon/Gore/Bash/Bow, `patk` Gore/Bash/Bow, and `ratk`
Fire/Cannon. Bomb is excluded. Stage defaults to `resolved`; Prism Moth uses
Bash's `target` stage.

The event names currently published by Godot are the names card authors should
use. Move and Fly publish `move` with `movement_kind` set to `move` or `fly`;
`fire`, `bow`, `cannon`, `gore`, and `bash` have target/resolved stages where
applicable; `hit` and `wound` are resolved physical-contact events. Lifecycle
events are `activate`, `start`, `deploy`, `end`, and `die`. Other action names
include `stun`, `mend`, `push`, `pull`, `bomb_throw`, `bomb_light`,
`bomb_defuse`, `bomb_explosion`, `revive`, and the supported counter/upgrade
verbs. See `EffectEvent.new()` calls in Match, Action, and CombatResolver for the
captured detail fields. Resolved cancelled events do not match; a successful
attack that misses still publishes its resolved event.

```gdscript
var pattern := Effect.EventPhrase.observe_any(
    [&"move"], Selectors.Self.new(), QuerySelector.new(TargetRef.Kind.HEX),
    TargetRef.Kind.UNIT, TargetRef.Kind.HEX, &"resolved",
    {&"movement_kind": &"fly"})
var consequence := Effect.ConsequencePhrase.new(
    Selectors.Self.new(), Verbs.change_counter(1),
    Selectors.PropertyOf.new(Selectors.Self.new(), UnitInfo.PHYSICAL_COUNTER),
    Effect.Phrase.TargetMode.ALL)
var trigger := Effect.on_event(pattern, consequence)
```

The pattern is reusable card data. `RulesRunner.capture_event()` validates the
event, matches and captures the execution; it does not retain selection state on
the pattern. Event publication remains centralized through `Match.action_event`.

## Optional effects and choices

`Effect.policy` is DEFAULT, OPTIONAL or MANDATORY. DEFAULT costed triggers ask
before paying; free triggers are mandatory. An optional effect emits
`confirmation_requested`; call `execution.confirm(true/false)` to answer. This
acceptance is separate from phrase-level optional confirmation.

CHOOSE_ONE always asks, including a single legal target. ALL selects targets,
not subjects: multiple actors still suspend for a subject choice. Mandatory
triggered choices cannot be skipped through Escape. A phrase explicitly marked
optional keeps its own skip behavior. Every choice is revalidated before use.

The runner's work limit halts with a diagnostic and retains pending work instead
of silently dropping an infinite trigger chain. `reset()` discards old match
work. The work list currently contains runtime continuations, not save data;
serialization belongs to M7.

## Atomic cost bundles

```gdscript
var physical_payment := Effect.CostPhrase.new(
    Selectors.Self.new(), Verbs.decrement(1),
    Selectors.PropertyOf.new(Selectors.Self.new(), UnitInfo.PHYSICAL_COUNTER))
var costs := Effect.CostBundle.new([Collection.action_cost(), physical_payment])
var benefit := Effect.ConsequencePhrase.new(
    Selectors.Self.new(), Verbs.change_counter(2),
    Selectors.PropertyOf.new(Selectors.Self.new(), UnitInfo.MAGICAL_COUNTER),
    Effect.Phrase.TargetMode.ALL)
Match.rules_runner.submit(Effect.new(costs, null, benefit), TargetRef.unit(0))
```

Each payment uses CHOOSE_ONE. All choices are collected without mutation, then
`CostPayment` validates their current identities and cumulative spending in a
shadow resource ledger. Two decrements of 2 cannot spend the same counter of 3;
two activity payments cannot spend the same activity. Only after full preflight
does the bundle commit, with followups deferred until the whole payment finishes.

Supported bundle verbs include self-Stun, deactivate, decrement, life payment,
next-turn-action grants, Sacrifice, Disable, Return, deployment spending and
the selection-only `choose_counter_unit` anchor. The explicit enemy-hero
Shield variant can be a payment and publishes Shield before consequences.
Variable decrements bind their positive X before cumulative preflight.
Custom mutation costs, optional payment members, ALL costs, and costs that need
newly created targets are rejected or outside this interface. New atomic cost
types require explicit preflight and commit support, not an arbitrary Callable
assumed to be reversible. Individual target choices must be legal in the current
board before payment; the ledger validates cumulative resource use.

Paid results are available as `cost_0`, `cost_1`, etc., with an aggregate `cost`.
Unsupported or unaffordable bundles do not partially mutate resources.

For dependent resource choices, `cost_choice_N` contains provisional unpaid
identities while collecting the bundle. `Selectors.CountersOf` projects the
selected UNIT into its positive stored counter PROPERTY identities;
`Verbs.decrement_choice()` then asks for X through `PhraseExecution.AMOUNT` and
`choose_amount(X)`. `RuleNumber.paid_amount(N)` reads `cost_N.amount` only after
successful payment, preserving X across cost-trigger followups. Availability
uses read-only dependent-choice exploration and positive numeric minima; a real
commit never invents a paid amount. See [WILD_RETURN_UNITS.md](WILD_RETURN_UNITS.md)
for the Porcupine example, lifetime rules and complete caller map.

## Read-only conditions and named stickers

`RuleContext` supplies SELF, SUBJECT, the triggering event and completed results.
`PhraseExecution` extends that view; UnitInfo state reads construct it directly,
without a fake effect execution. Definitions never retain contexts.

Condition objects include Wounded, All (AND), AnyOf (OR), Not, Matches
(ANY/NONE/nonempty-ALL), Compare (property number comparisons), and EventFact
(explicit historical equality). Empty ANY/ALL are false; empty NONE is true.
Type errors remain errors under NOT. StateModifier stores a typed Condition;
passing a Selector wraps it in Matches. Other object types fail closed.

```gdscript
var stickers := ActionStickers.new()
stickers.instant = true
stickers.pierce = true
stickers.tireless = true
var fire := Collection.ranged(&"fire", 2, 3, stickers)
# An optional fifth argument supplies an explicit cost instead of the default.
```

Existing `fire_DR`/`bow_DR`/`cannon_DR` and other combat factories remain valid.
They share `Collection.with_action_policy` for default costs and token stickers;
each phrase also records typed `ActionSticker` definitions for P/F/T/A. Persistent
Bow counters use `Verbs.upgrade_bow()`. `Collection.grant_action_values()` creates
a chosen-recipient timed numeric grant that expires after the active player's End
followups. Continuous modifiers, passive flags, named action values, timed grants,
and their distinct lifetimes are documented in [RULINGS.md](RULINGS.md) and
[CONTINUOUS_ROADMAP.md](CONTINUOUS_ROADMAP.md). General scheduled consequences and
timed grants of nonnumeric properties remain future work.

## Continuous “while” and “have” rules

`ContinuousEffect.while_self(condition, outputs)` evaluates a condition against
the source card and applies the outputs to that card. `ContinuousEffect.have`
resolves a recipient selector and evaluates the optional recipient condition
for each recipient. Definitions contain no live recipient or Match state.

```gdscript
var friendly := QuerySelector.new(TargetRef.Kind.UNIT)
friendly.relative_owner = Enum.YOU
var bow_aura := ContinuousEffect.have(friendly,
    [Contribution.bow_values(1, 0)])
var wounded_self := ContinuousEffect.while_self(Condition.Wounded.new(),
    [Contribution.modifiers(2, 0)])
var passive_aura := ContinuousEffect.have(friendly,
    [Contribution.passive_flag(&"steady")])
```

Caller map: `UnitInfo.state_modifiers()` derives modifier outputs;
`UnitInfo.effective_action_values()` supplies live named action parameters to
`DistanceSelector`, `CombatResolver`, and Bow UI previews;
`UnitInfo.has_effective_flag()` supplies combat passive checks; and
`RulesRunner.capture_event()` checks defeat-trigger policy before candidate
execution capture. Each is read-only. Delayed Bow, Fire, and Cannon values are
captured when declared. See FK-1 and FK-2 in
[RULINGS.md](RULINGS.md) for scope and timing.

`Collection.tortoise_end_shield()` is a real-card example of an optional costed
phase trigger applying Shield to ALL adjacent friendly units. Ironhide and Prism
Moth remain examples of free automatic triggered sequences.

## Phase behavior retained and extended

Start resets the configured sample allowance and applies the hero's one-Stun
recovery to every friendly deployed unit with positive Stun, including itself.
This changes only Stun counters; zero-Stun inactive units remain inactive.
The Start occurrence and its captured choices finish before entering Action.
The recovery remains one built-in Match operation, not a second card effect.

At zero remaining actions, the runner freezes all eligible combat groups before
resolving the first attack. It resumes Bow, Gore, Cannon/Bomb, Fire and Bash in
order, waiting for their triggered choices. Newly declared delayed attacks do not
join a later group in the same window. End effects and choices finish before
`Match._activate_unstunned_units(ending_player)` scans current state. It activates
only that player's inactive deployed units with no Stun; already-active, stunned,
off-board, and opposing units are untouched. Each transition emits one Activate
occurrence. A mutation boundary defers its captured followups until the activation
pass completes; pending Activate choices suspend cleanup/player switch. Timed
grants remain live through those followups, then expire in `_next_turn()` before
the opponent's Start. This follows the 2026-10-19 owner-only activation ruling.

Victory still prevents new commands and later turn phases. Already captured
followups retain their identities and undergo normal verb legality; specialized
post-victory card rules remain unspecified. Format allowances, hostile Stun shield
side effects, spells and exile have not been assigned new rules.

## Caller and verification map

| Caller | API / signal | Responsibility |
| --- | --- | --- |
| LocalMatchController | `RulesRunner.submit` | Submit one player command. |
| Match/CombatResolver | `begin_boundary` / `end_boundary` | Finish a mutation before releasing followups. |
| Match.action_event | `capture_event` | Snapshot all matching definitions once per occurrence. Reserve any turn-limited trigger before enqueueing it. |
| RulesRunner | `execution_started` -> Board.observe_execution | Attach or restore choice UI. |
| EffectExecution | `after_cost` | Release cost followups before resuming consequences. |
| Board controls | `confirm`, phrase `choose`, execution `cancel` | Resume retained work with current legality. |
| RulesRunner | `command_finished` -> controller | Display result; no second token payment. |
| Match | `schedule` | Continue Start/combat/End after child work. |
| Match.complete_action | `_end_phase` → `_activate_unstunned_units` → `_next_turn` | Finish End choices, activate eligible units of the ending player, finish Activate followups, then clean up and switch. |
| UnitInfo/conditions | `RuleContext` + TargetResolver | Read live effective state without mutation. |

Run `tests/m2_test.tscn` with the existing selection, fire, local-match and
trigger-state integration scenes. M2 regressions exercise real Board confirmation,
command exclusion, deploy/death triggers, subject choices, cost-trigger suspension,
atomic cumulative spending, End pauses, combat-window capture, Bash contact,
conditions and nested bundle ordering. The original suites retain the broader
targeting and combat formula coverage.

## Source footprint and validation snapshot

Physical GDScript lines, including meaningful comments and blank lines, counted
on 2026-09-26. Includes root/scripts/tests sources only; excludes generated UIDs,
Godot imports, scenes/assets and the local `.tools` runtime. This is a maintenance
baseline, not a claim of size parity with the complete JS product.

| Category | Files | Lines |
| --- | ---: | ---: |
| Engine and queries | 35 | 3177 |
| Authored factories | 2 | 230 |
| Presentation and local UI | 7 | 573 |
| Tests | 5 | 1391 |

The local validation runtime is official Godot 4.5.1; the project's existing
4.7 feature declaration was preserved. Headless scene verification supplements,
but does not replace, a visual playthrough.


### Graphical trigger acknowledgement boundary

The graphical Board enables RulesRunner.trigger_acknowledgements_enabled;
headless rule consumers leave it false. drain() retains a captured trigger at
work[0] and emits trigger_presentation_requested(execution) before activation.
GuerraBoard._on_trigger_presentation_requested() creates presentation state;
_sync_trigger_presentation() waits for incoming attacks, movement and complete
damage/death feedback before exposing the blink and setting presentation_ready.

RulesRunner.acknowledge_trigger(execution, player) accepts only players 1/2,
once each, for the exact waiting execution after presentation is ready. The
local Board maps successive blink clicks/nonrepeating Space presses to the
first missing player; acknowledge_trigger_for_player(player) is the explicit
future network-adapter entry point. A network authority must authenticate that
identity: this change does not implement a transport or online session.

After both acknowledgements, Board fades the blink and clears yellow text;
its tree exit calls release_trigger_presentation(execution), which marks that
execution acknowledged and resumes drain(). Triggers resume their ordinary
optional/cost/choice lifecycle; resumes never gate the same execution again.
busy() includes this wait, preserving commands, phase/combat continuations and
queued followups. reset() clears stale gates/acknowledgements while preserving
the graphical gate policy. Rule definitions do not retain presentation state.

Example: lethal Bow resolves logically, attack travel finishes, the victim's
new Slash plays, its retained figure fades under a Skull burst, then a captured
trigger's blink appears. Player 1 acknowledges; the runner stays paused. Player
2 acknowledges; blink fades and the captured trigger can begin. A nonlethal
result omits Skull, and a trigger without damage skips both damage clips.


### Finite-animation continuation barrier

The graphical Board registers RulesRunner.presentation_busy_query. Before a
queued Callable (command completion, resume or phase continuation), drain()
queries it; if busy, the callable remains at work[0] and continuation_waiting
is set. Board._resume_phase_presentation() defers drain once the query becomes
false. The current authoritative phase therefore remains in place until the
finite action animation is complete; this is not only delayed sign text.
reset() clears the wait flag and preserves the client query configuration.
Headless consumers have no query and keep their existing synchronous flow.

GuerraBoard._phase_presentation_busy() covers walking, Push/Pull wind/slide,
character action/deployment/return-to-sit, Bomb Throw, Bash exit, incoming
projectiles, finite bursts, damage/death and resolved-marker fades. Pending
counter loops, sleeping/ambient loops and historical replays are excluded.
The inn sign's finite entrance also settles before the next continuation.
Trigger presentation uses this same query before its blink accepts input.

The phase_sign.gd trigger blink is beside the measured phase word and fades
with the existing two-player gate. Board input checks its viewport hit bounds
and routes it to the same acknowledgement entry point as the unit blink;
it never starts a second trigger or a separate acknowledgement count.

Mouse Necromancer: Collection.pine_processionary_trigger observes SELF Die and authors an ALL consequence targeting the friendly PLAYER query. Verbs.grant_deployments(2) fixes UNIT -> PLAYER contracts; Action.can_grant_deployments validates existence and positive amount, including defeated source records. Action.grant_deployments adds deployments_remaining, emits one resolved grant_deployments event and state_changed inside a runner boundary. There is no target picker, Revive, action-token grant or implicit deployment.

Phase sign omits routine boundary animations: empty Resolve and Start/End without captured triggers do not add presentation waits. PhaseSign reads combat-window eligibility on COMBAT_RESOLVE and listens to RulesRunner.trigger_presentation_requested for special boundaries; it never evaluates trigger definitions itself. Logical phases, Start recovery/action refresh, End activation/events and captured-trigger gating remain unchanged.

Bomb resolution presentation now orders radial arrival -> one-shot lit-bomb explosion -> Slash -> eventual Skull. Board creates cosmetic bomb_explosion.gd from each resolved bomb_explosion occurrence; damage feedback rechecks its remaining duration and phase/trigger barriers include the finite clip. Combat mutations and chain scheduling remain runner-owned.

Slash-timed life presentation: damage_feedback stores previous actual/max life and exposes life_revealed 250ms into Slash. Board.life_number holds old UI values until that beat and formats the changed number's pulse; authoritative mutations, defeat and event capture remain immediate. Ordinary/Bash/hover/ghost health consumers share this formatter. Bomb-explosion gold-rim feedback is suppressed when its captured outcome contains no positive damage.

Rat extensions: captured Die abilities read live EXTRA_DEATH_TRIGGER contributions and create independent EffectExecutions, not synthetic deaths. Reset restores a captured printed baseline within a boundary; Copy appends an immutable chosen effect with new future SELF bindings. Return-to-hand occurrences feed Warrior Soul property changes and atomic Soul/activity costs. Swordsman's defender_fled event flag schedules a one-shot player action bonus consumed at next own Start. See RAT_SYNERGIES.md for definitions, persistence and callers.

## No legal action defeat
Match._ready connects runner.idle and state_changed to deferred _check_no_legal_actions. The check runs only in a settled Action window, after choices/continuations finish, and assigns the opposing winner if has_legal_action finds neither a legal can_deploy destination nor a deployed unit command. RulesRunner.command_available is shared with LocalMatchController._action_available: it queries source/condition eligibility, cost identities with cumulative shadow ledgers, and legal first consequence actor/target pairs through TargetResolver. No effect is started and no resource is paid during the query. Ordered sequences may legally begin with their first required step; later dependent steps retain normal sequential failure behavior. Example: no deployments and all non-Tireless units inactive means defeat; a payable Soul conversion or legal Tireless action prevents defeat.

## Rat/keyword regression coverage (2026-10-23)

Run `godot.exe --headless --path . res://tests/rat_effects_test.tscn`.
The scene creates isolated maps/resources, disables graphical gates and uses
actual runner choices, verb actions, event capture and live contributions.
Cases cover Reset and Dark Mage death, stacked/friendly Wild Rat amplification,
Musketeer Revive and Return, Thief Copy across all five categories, Warrior Soul
watching/atomic conversion, signed Pikeman X, Swordsman attacker/defender identity,
forced Flee and non-Flee/death exclusions, Disable ownership/hero/nondeath rules,
no-legal-action defeat, and maximum-life source snapshot/Reset behavior.
Snapshot checks use in-memory capture/apply and never write the user's save.

Regression discovery: cancelled Bash encounters were rejected by the ordinary
successful-event matcher, preventing Flee rewards. EventPhrase.observes_cancelled
now explicitly opts the Swordsman pattern into those encounters; its dodged and
defender_fled constraints still apply. Ordinary attack patterns remain unchanged.

Related suites: selection_test, fire_test, m2_test, trigger_state_test,
local_match_test, presentation_test. The M2 Board-routing test deliberately turns
off graphical acknowledgement/animation gates; presentation_test keeps the real
gates and waits for finite continuations before checking previous-turn replays.

## Woodland additions (2026-10-24)

LifeChanges.publish captures positive applied components; RuleNumber reads the captured occurrence. Verb.bound_to supplies ephemeral parameters to PhraseExecution legality/commit and RulesRunner availability. RuleContext.query_verb lets spatial selectors derive the exact ability bonus. CostPayment and RulesRunner preflight cumulative life alongside activity/counters. Final-life payment may defeat the payer without cancelling consequences. Upgrade records a unit choice, then chooses an ability PROPERTY anchored to completed step_0. UnitInfo retains recipient-bound grants; MatchSnapshot restores definition indices after copied definitions. Reset clears grants. Flee invokes one legal current movement without a new cost.

See [WOODLAND_UNITS.md](WOODLAND_UNITS.md) for card wording, interactions, caller maps and focused regression coverage. Tests were added; running them requires a request ending in TEST.

### Board Return authoring (2026-10-26)

`Verbs.return_to_hand()` is a reusable UNIT-to-UNIT definition. The normal
PhraseExecution → TargetResolver → legality → execute path owns choice and
revalidation; Action owns the zone mutation and publishes `return_to_hand` for
existing synergies. Use the enclosing effect's cost/sticker policy as usual.
For example, this ordinary action chooses one friendly deployed card:

```gdscript
var friendly := QuerySelector.new()
friendly.relative_owner = Enum.YOU
friendly.state = Enum.t_state.DEPLOYED
var consequence := Effect.ConsequencePhrase.new(Selectors.Self.new(),
    Verbs.return_to_hand(), friendly)
var effect := Collection.with_action_policy(consequence, false, false)
```

Removing the ownership filter permits either owner; use spatial selectors for
range. Return keeps health, counters, upgrades and abilities, clears position,
enters hand inactive and cancels departed Bashes without Flee. Revive still
emits the same Return occurrence for its separate defeated-to-hand recovery.
Stun only deactivates and adds Stun; it never clears other counters. Reset
remains an in-place restoration of printed state.

Focused coverage: `tests/rat_effects_test.tscn` now covers board Return state,
ownership, real Soul synergy, repeat/off-board rejection, hero eligibility and
Stun preservation/non-trigger cases. Run it only when explicitly requested.

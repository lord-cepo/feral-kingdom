# Wild Return units

Implemented from the 2026-10-26 table and follow-up rulings. These are live
object-authored catalogue definitions, not proposed interfaces or a DSL.

## Printed cards

All eight are Wild troops by their names; Wild and species groups are not flags or effects. S/I/F mean Starting/Intermediate/Front; oI means an
opposing-side Intermediate region under normal control/vacancy rules. Every
troop without printed Walk/Fly receives the existing implicit Walk 1.

| Unit | Life | Regions | Actions | Triggers/state |
| --- | --- | --- | --- | --- |
| Wild Marmot | 2 | S | Walk 2; Return another adjacent friendly unit | Adjacency is exactly distance 1, not the same hex. |
| Wild Jerboa | 1 | I | Pull 1, range 2 | When an enemy declares Bash against this unit, Return that exact attacker. |
| Wild Dormouse | 2 | F | Bow 2, range 2 | On own Deploy, Return one unit at exactly distance 1, of either owner. |
| Wild Chinchilla | 1 | SI | Fire 2, range 2 | On own Deploy, +1 remaining deployment. On own Die, Return a deployed friendly unit, then deploy this unit at full current maximum health on that card's former hex. |
| Wild Lemming | 2 | oI | Instant Fire 1 against a deployed enemy, unlimited range | On own Deploy, +3 Stun counters, in addition to the normal deployment Stun: four total from a clean hand. |
| Wild Porcupine | 3 | SI | Bow 3, range 1; [AS] remove X of one counter kind from a deployed friendly unit, gain X Soul; [AS] pay X Soul, Stun one deployed enemy for X, unlimited range | Printed Soul starts at zero. X is a chosen positive integer. |
| Wild Hedgehog | 2 | I | Walk 2 | When this unit receives Hit, gain +1 persistent physical and +1 persistent magical counter. |
| Wild Flying Squirrel | 1 | S | [A2S]: Fly 3 | While bashing, +3 physical/+0 magical, derived rather than stored. |

Ordinary activated actions cost one player action and self-Stun 1. Porcupine's
[AS] adds its written payment to ordinary action/activity payments. Flying Squirrel's
[A2S] replaces the one-Stun payment with two, deactivates the active payer and spends
one player action. Free triggers do not add ordinary activity or token costs.

## Interaction rulings

- An omitted range is unlimited. Lemming queries deployed enemy UNIT identities
  and explicitly projects their hexes for the existing Fire verb. It cannot
  choose empty or friendly-only tiles. Fire keeps its existing lethal threshold,
  immunity, temporary-magical-protection and no-partial-damage rules.
- Porcupine first chooses a deployed friendly UNIT, then one positive stored
  counter kind on that exact host, then X from 1 through its current balance.
  Stun, Soul, physical/magical, shields and acquired action counters qualify.
  Flags, negative/zero counters and read-only contributions do not. Range is
  unlimited; undeployed and defeated cards do not qualify. SELF is a friendly
  candidate when it has a payable positive counter.
- Harvest collects unit, property, amount and activity choices before any cost
  mutation. Cancelling any of those stages pays nothing. Full current legality
  and cumulative spending are rechecked before atomic commit. Removal precedes
  the activity payment, so newly added activity Stun cannot be harvested as part
  of that same payment. The consequence grants the amount actually paid, never
  the resource's later balance. Soul-to-Stun also retains its paid X across cost
  followups. Consequence failure does not refund paid resources.
- Both adjacent Return abilities use exact distance 1. They cannot Return SELF
  or a unit sharing SELF's own hex. Ordinary Return preserves owner, wounds,
  counters, upgrades, copied abilities and timed-grant records, while clearing
  position and activity. It does not heal, Reset, Die or Flee.
- Jerboa observes the incoming declaration, including forced entry, and Returns
  its captured enemy attacker rather than another occupant. Outgoing Bash and
  cancelled/resolved attack records do not retrigger it. Return cancels the
  abandoned Bash without a Flee reward.
- Chinchilla's special deployment spends neither an action nor a deployment and
  bypasses region, side, control and normal first-deployment requirements. It
  preserves acquired state, restores current health to its existing maximum,
  enters inactive with one additional deployment Stun and emits Deploy again,
  granting its owner +1 remaining deployment. A remaining enemy occupant creates
  the normal Bash; no second friendly occupant can be stacked there. There is no
  Reset and no Revive occurrence. Return watchers still see the friendly card
  returned as part of replacement.
- A doubled Chinchilla death trigger creates two independent activations, but
  only a still-defeated source can replace a friend. After the first succeeds,
  the second has no legal replacement and cannot Return another friendly card.
  No friendly recipient, a zero maximum, or Disable instead of Die means no
  automatic recovery. The Return and placement finish inside one mutation
  boundary before followups; a later consequence failure never refunds a Return.
- Hedgehog watches Hit's recipient, not its actor. Zero-damage physical or
  magical attack contact qualifies under the 2026-10-28 ruling. Immunity, bomb_hit,
  outgoing hits, misses and cancelled events do not. A captured lethal Hit can award counters
  to the defeated identity without reviving it.
- Flying Squirrel's Bash bonus disappears when its encounter ends or a
  participant leaves. It never writes physical counters or contributes to
  regional strength.

## Authoring examples and caller map

```gdscript
# Exact adjacency selects native hexes; Return's UNIT contract adapts occupants.
var consequence := Effect.ConsequencePhrase.new(Selectors.Self.new(),
    Verbs.return_to_hand(), DistanceSelector.new(1))

# A chosen counter amount belongs to an execution. Its later consequence reads
# the amount actually paid at this cost index, never the live resource balance.
var removal := Effect.CostPhrase.new(Selectors.Self.new(),
    Verbs.decrement_choice(), Selectors.PropertyOf.new(Selectors.Self.new(), &"Soul"))
var captured_x := RuleNumber.paid_amount(0)

# Replacement activity cost, rather than ordinary self-Stun plus an extra two.
var fly_cost := Effect.CostPhrase.new(Selectors.Self.new(),
    Verbs.pay_activity(false, 2), Selectors.Self.new())
```

| Caller → implementation | Responsibility |
| --- | --- |
| `CardCatalogue.starter_army()` → eight `wild_*` factories | Append both owners after the previous roster prefix; retain old stable IDs and snapshot compatibility. |
| Catalogue → `WildRules` | Compose typed selectors, events, costs, numeric queries and consequences. |
| `WildRules.harvest_counters()` → `Verbs.choose_counter_unit()` → `WildActions` | Retain a legal UNIT resource host without a fictional gameplay event. |
| `Selectors.CountersOf(Selectors.Completed("cost_choice_0", ...))` | Project that selected host into its positive stored counter PROPERTY identities. |
| `PhraseExecution.choose()` → `AMOUNT` → `choose_amount(X)` | Retain exact PROPERTY identity, expose live bounds and revalidate before completing the choice. |
| `EffectExecution` → `CostPayment.commit()` | Collect unmutated choices, preflight the full bundle and record paid `cost_N.amount` values. |
| `RuleNumber.choice()` / `paid_amount(N)` → `Verb.bound_to(ctx)` | Bind a chosen or paid scalar into an ephemeral verb; reusable definitions remain symbolic. |
| `RulesRunner.command_available()` → dependent cost exploration | Query legal UNIT/property/payment paths without mutation or a picker. |
| `Verbs.return_and_deploy()` → `WildActions.return_and_deploy()` → `Match.deploy_from_effect()` | Complete Chinchilla's Return and special placement before releasing followups. |
| `GuerraBoard._show_counter_choices()` / `_on_amount_chosen()` | Present counter kind and bounded X using the ordinary retained phrase. |
| `Match.action_event` → Board → `board_return.gd` | Snapshot the actual departing figure and animate an upward fade; finite feedback gates later trigger acknowledgement and phase continuations. |
| `BoardCharacter` → playground manifest | Share the imported PixelLab character across board, tray and hover art for both owners. |

`cost_choice_N` records are provisional, unpaid identities used only to anchor
later choices in that same bundle. `cost_N` records become authoritative after
successful atomic payment. Neither is stored on Effect, Phrase, Verb or Selector.
Pending numeric choices remain unsaveable under the existing idle-only snapshot
policy; no new runtime-only definitions are serialized into saved cards.

## Art and focused coverage

Existing PixelLab characters were imported with all eight standing and seated
directions, six-frame walks in eight directions, nine-frame rises and nine-frame
actions. The manifest records standing/seated source character IDs. No new art
was generated and no stationary fallback was needed. Existing grounded fades,
turning, walking, deployment and activity blends apply to these characters.

`tests/wild_return_test.tscn` covers each new effect's result, ownership and
important non-trigger cases, plus bounded X, cancellation, resource changes,
shared definitions, captured paid amounts, actual enemy-side deployment and
roster/art registration and name-based group membership. Existing `fire_test.tscn`, `selection_test.tscn`,
`rat_effects_test.tscn`, `m2_test.tscn` and presentation coverage remain relevant
to shared changes. Run behavioral scenes only when the user request ends in
`TEST`; adding these tests does not authorize running them.

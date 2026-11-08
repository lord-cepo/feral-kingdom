# Twenty adventurer units

Current concise hover wording, independent cost notation and Blue Mage/Jester
explanations are maintained in [HOVER_TEXT.md](HOVER_TEXT.md). Tireless/T is no
longer a visible sticker; [A] denotes an action without normal self-Stun. This
presentation revision preserves the additional abilities and existing payments.

Implemented 2026-10-29 from the supplied table. Both owners receive all twenty
cards, appended after existing roster identities. The local roster now has 83
appearances per owner. JS reference definitions are unchanged.

S/I/F mean Starting/Intermediate/Front. Opponent I means the opponent's
geographical Intermediate side, with ordinary control/vacancy requirements.
Unmarked commands pay [AS]; [A] pays an action without activity; [3S] pays three
self-Stun without a player action. Separate abilities are separate commands.
Implicit Walk one remains unless a printed ordinary Walk/Fly replaces it.

| Unit | Life | Deploy | Rules |
| --- | ---: | --- | --- |
| Porcupine Barbarian | 3 | IF | Walk 2; live +X/+X, X distinct adjacent friends. |
| Marmot Berserker | 4 | S | [S] Walk onto an enemy within 2 with normal path legality; [AS] Shield 2/0. |
| Dormouse Rogue | 2 | Opponent I | [AS] remove one adjacent enemy counter: gain one of that exact kind; [AS] remove one own counter: defeat a deployed enemy. |
| Flying Squirrel Ranger | 2 | I | Pierce Bow 1/3; Mshield 1/1. |
| Tamia Hunter | 2 | S | Printed control +2; [AS] remove one adjacent friend's counter: Reset any unit within 2. |
| Jerboa Scout | 1 | S | [A] Walk 2; +1 player action while on enemy Starting, regardless of control. |
| Dormouse Witch | 2 | I | Fly 2; Fire 1/2; [AS] remove one Ember from any deployed friend: permanent Fire damage +1/range +0. |
| Rat Warlock | 1 | IF | Stun 1/2; [3S] Disable a friendly hand card: Revive a friend, including the disabled card. |
| Red Squirrel Druid | 2 | I | [AS] spend one Soul: +0 current/+1 maximum life; live +X/+X, X maximum life minus 2. |
| Porcupine Shaman | 2 | F | [3S] Stun 2/2; [A] spend one deployment: Return any two distinct bashing units. |
| Mouse Summoner | 1 | S | Mshield 2/1; [AS] Return a friend: deploy a friendly hand card on its former hex, including the same friend. |
| Chinchilla Alchemist | 1 | S | A positive Ember addition to a deployed friend: +1 Soul; [AS] spend three Soul: Instant Fire 1/3. |
| Guinea Pig Cleric | 3 | I | [AS] +1 to an already-present counter type on an adjacent friend, including value zero; any unit Returns: Reset any unit. |
| Marmot Monk | 3 | F | Shield 1 to any deployed friend; Mshield 1 to any deployed friend. |
| Lemming Healer | 2 | SI | Walk 2; Mend 1/2. |
| Tamia Bard | 1 | Opponent I | Push 1/2; adjacent units of either owner have Bow damage +1/range +0. |
| Jerboa Jester | 2 | I | Pull 1/3; enemy newly gains control of this unit's region: Instant Bow 2/2. |
| Rat Pirate | 2 | Opponent I | [A] Walk 2; Fast. |
| Beaver Blacksmith | 3 | I | Fast; Steady. |
| Guinea Pig Merchant | 2 | IF | Friend dies: +1 Soul; separate [AS] spend-one-Soul commands grant adjacent friend Pierce or Instant for its next Fire. |

## Interaction rulings

Shaman selects any two distinct live participants, including different Bash
encounters and either owner. The first choice performs no Return. Both must
still qualify before either leaves. Returning the first may cancel its Bash;
the already-validated second Return still completes. Fewer than two participants
or no remaining deployment prevents payment. Paid costs are not refunded after
consequence failure.

Summoner retains the paid Return's former hex. The same returned identity is
eligible. Effect-deployment pays no additional action/deployment and ignores
ordinary control and printed-region restrictions. It preserves health/counters,
enters inactive with one Stun, respects the sole-hero choice, rejects a friendly
occupant and starts Bash against an enemy occupant. Return-cost followups finish
before the chosen hand card and destination are revalidated.

Cleric chooses an existing numeric PROPERTY, including zero. It cannot create
a missing counter type, select a FLAG, target SELF as an adjacent friend, or
target an enemy. Its displayed effect explains this. Its Return watcher matches
either owner, including Revive's existing Return occurrence.

Merchant's pending P/F belongs to the recipient, combines with printed stickers,
and is consumed only on its next successful Fire declaration, before declaration
followups. Preview/rejection preserves it; queued Fire cannot gain it later.
It survives Return and End, disappears on use/Reset, and persists in snapshots.
Duplicate grants of the same sticker combine on one next Fire.

Alchemist earns one Soul per positive friendly deployed Ember addition,
irrespective of amount. UNIT awards, transfers and PROPERTY changes share one
canonical occurrence. Zero/removal/consumption, enemies and off-board recipients
do not qualify. Soul awards cannot recursively trigger Ember watchers.

Jester captures one occurrence per geographical region becoming enemy-owned,
including neutral-to-enemy. Repeated refresh, friendly ownership and changes in
other regions do not qualify. Caches update before occurrence publication.
Setup and snapshot restoration rebuild the cache without publishing control-gain
occurrences; loading a match cannot grant a fictional Jester attack.

## APIs, caller map and examples

- `CardCatalogue.starter_army/all_units` append `AdventurerCatalogue.all_units`.
  Factories compose existing `Collection`, `SynergyRules`, `Verbs`, selectors and
  continuous contributions. No parser or activation state on definitions.
- `RulesRunner.command_available/submit` and `EffectExecution` own eligibility
  and choices. `CostPayment.commit` includes Return/Disable departure reservations
  and cumulative deployment balances with existing counter/activity/life costs.
- `PhraseExecution._commit` retains `target_hexes` before mutation, including
  selection-only cost choices. `EffectExecution._record_paid_bundle` publishes
  them in `cost_N`. `RuleBinding.HEX_ID` supplies Summoner's destination;
  `RuleBinding.UNIT_ID` supplies Shaman's first choice. Normal references stay live.
- `AdventurerRules.BashingUnits` enumerates distinct participants; `return_two`
  checks both before two standard Return actions within one mutation boundary.
- `Match.refresh_control` emits `gain_region` after updating caches.
  `AdventurerRules.OwnRegion` restricts Jester's watcher.
- `UnitInfo._change_action_counter` and `Action.change_counter` call
  `UnitInfo.publish_ember_gain`; event matching captures Alchemist.
- `AdventurerRules.grant_next_fire` writes recipient records;
  `CombatResolver._apply_declare_fire` captures/consumes them after legality.
  Reset clears them; snapshots serialize/validate/restore them, defaulting older
  saves to an empty sticker list.
- `EffectText` renders the new costs, selectors, formulas and triggers.
  `BoardCharacter` maps all twenty accepted existing sprite/animation folders.
- `tools/import_adventurer_characters.py` copies accepted PNGs from
  `exports/repaired-character-animations`, updates counts and rebuilds alignment.
  Generated sheets/previews are excluded from runtime frames.

Example: `AdventurerCatalogue.porcupine_shaman(owner).effects[1]` uses
`AdventurerRules.shaman_return()`. Existing-counter-only grants use
`AdventurerRules.ExistingCounters.new(hosts)` with `Verbs.change_counter(1)`.
Unlike `Selectors.CountersOf`, that projection includes zero-valued counters.

## Regression coverage

`tests/adventurer_units_test.tscn` exercises production definitions/executions:
result, ownership/range exclusions, exact paid counter kind, non-accumulating
modifiers, Scout allowance, separate-encounter/stale Shaman choices, Summoner's
same-card deployment and historical destination, Cleric's zero/missing counters,
Ember exclusions, control-transition deduplication, next-Fire consumption/Reset/
snapshot capture, native passives and catalogue registration. It reuses fixture
helpers from the synergy test, overriding its entry point.

The user authorized `TEST` on 2026-10-29. These and the earlier suites were
executed through `tools/run_tests.py`; `adventurer_synergies_test.tscn` adds nine
managed cross-roster chains. [TESTING.md](TESTING.md) documents coverage, isolated
save data and fixes found during execution. Future runs still require `TEST`.

Marmot Berserker cost revision: `AdventurerCatalogue.marmot_berserker` authors
Walk with `Verbs.movement(2, false, true)` and `SynergyRules.command(..., 1, false)`.
The shared activity payment deactivates it and adds one self-Stun; the runner
spends no player action. Enemy-only destinations and ordinary path legality remain.
Example: using Walk onto an enemy keeps your remaining player actions unchanged.
`adventurer_units_test.gd::test_berserker_stun_only_walk` covers the committed cost,
activity, owner eligibility and invalid destinations; run only on a TEST request.
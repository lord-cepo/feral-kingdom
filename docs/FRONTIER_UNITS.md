# Frontier units

The eleven approved PixelLab characters appear for both players. Their IDs
follow the existing roster, so older unit IDs and local save prefixes stay valid.
The other nine artwork candidates remain in the export archive.

| Card | Deployment / life | Rules |
| --- | --- | --- |
| Mole Shaman | Starting, 2H | Walk 2. [AS] Revive another friend while on the enemy geographical side. [AS] Sacrifice another deployed friend for one action at your next Start. |
| Lemming Wizard | Intermediate, 3H | Fire 1/3. When another deployed friend gains any positive number of Embers, gain one Ember. Capture at most once each turn. |
| Mole Alchemist | Intermediate, 2H | Fire 1/2. [AS] Sacrifice another deployed friend for Embers equal to its current life immediately before payment. |
| Flying Squirrel Thief | Intermediate or Front, 1H | Fly 2. An adjacent deployed enemy hero gaining exactly +1 current and +1 maximum life grants one remaining deployment, then a friendly Revive choice. |
| Rat Hunter | Front, 3H | Adjacent deployed units of either owner with positive stored Projectiles gain +1 Bow damage and range. Another loaded unit's attack declaration offers a free Walk 1 that strictly increases distance from that attacker. |
| Guinea Pig Berserker | Starting or Front, 4H | Gain one Soul when declaring Bash. Choose and spend positive X Souls to Walk up to X without AS, then gain +X/+X through enemy End. |
| Mara Merchant | Any region type, 1H | Shield 2 and +3 Control. May also deploy in enemy-controlled regions. |
| Beaver Engineer | Starting or Front, 3H | Cannon 1/3. Spend two Souls from an adjacent deployed friend, then Disable one friendly hand card and one enemy hand card. Pays neither A nor S. |
| Marmot Crossbowman | Starting or Intermediate, 1H | Bow 1/3. Own Deploy grants two Projectiles. Each own Hit adds one permanent Bow damage. Its printed Bow has ordinary AS and no explicit Projectile payment. |
| Red Squirrel Paladin | Opponent-side Intermediate, 3H | [S] Bow 2/2. [S] Shield a selected friend in Bash and the deployed enemy hero for two each. |
| Jerboa Pirate | Front, 2H | Free Walk 2 must select an enemy landing when a legal Bash is reachable. Other deployed friends gain +1 Walk range. |

Unlisted ordinary movement is the game's implicit Walk 1. The Paladin still
needs ordinary regional control on the opposing side. Merchant's exception
does not allow neutral or occupied hexes. A Hunter retreat has no AS cost and
uses normal Walk legality. Loaded means positive stored Projectiles at capture,
so an attacker whose last Projectile was paid before declaration does not
qualify. The Pirate's passive governs its Walk destination when using the
command. It does not force a Walk instead of another command or move the unit
automatically.

Both recipients of the Paladin's command and both hand choices for Engineer
must exist when the command starts. Consequences are ordered. If a later
choice is invalidated, previous mutations and costs remain committed. The
Thief's deployment grant likewise remains when there is no legal Revive.
Each paid Berserker modifier grant stacks and expires independently at enemy End.

## Caller map

| Caller | Contract |
| --- | --- |
| `CardCatalogue.starter_army/all_units` | Appends `FrontierCatalogue.all_units` for both owners. `BoardCharacter.supports` reads the new sheet and portrait mappings. |
| `RulesRunner.capture_event` | Captures the Wizard's first qualifying Ember occurrence before enqueueing it, so queued or recursive occurrences cannot reserve another. The per-unit ledger persists through Reset and snapshots. |
| `CostPayment.commit` and `RulesRunner.command_available` | Record the selected Sacrifice donor's current life, using the shadow life balance for read-only availability. `RuleNumber.paid_amount` reads the frozen result after cost followups. |
| `PhraseExecution`, `CombatResolver.can_move`, `DistanceSelector.resolve` | Resolve the Berserker's chosen X and check Walk range, routes, and the Pirate's compulsory Bash with the same landing rules in preview and execution. |
| `Match.can_deploy` and `Match.expire_timed_grants` | Apply the Merchant's control exception and remove the Berserker's typed modifier grant after enemy End followups. |
| `Verbs.shield` and `Action.can_shield/shield` | The Paladin's explicit enemy-hero Shield uses the same temporary counter and occurrence as ordinary Shield. |
| `EffectText` | Uses the same definitions for card descriptions, including symbolic payments, once-per-turn text and passive restrictions. |

For example, the Berserker pays with `Verbs.decrement_choice()` against its
Soul property. Both the Walk and timed modifier verbs take the same
`RuleNumber.paid_amount(0)`. They do not read the Soul counter again after
payment. The Alchemist uses `paid_amount(1)`, the second cost in its AS plus
Sacrifice bundle.

Focused regressions live in `tests/frontier_units_test.tscn`. The roster sweep
in `tests/full_roster_test.tscn` checks all 97 cards per owner and their stable
IDs and definition contracts. See [TESTING.md](TESTING.md) for the opt-in runner.

# Frontier units

Both approved PixelLab batches appear for both players. Each batch appends
after the earlier roster, preserving old unit IDs and local save prefixes.

## First batch

| Card | Deployment / life | Rules |
| --- | --- | --- |
| Mole Shaman | Starting, 2H | Walk 2. [AS] Revive another friend while on the enemy geographical side. [AS] Sacrifice another deployed friend for one action at your next Start. |
| Lemming Wizard | Intermediate, 3H | Fire 1/3. When another deployed friend gains any positive number of Embers, gain one Ember. Capture at most once each turn. |
| Mole Alchemist | Intermediate, 2H | Fire 1/2. [AS] Sacrifice another deployed friend for Embers equal to its current life immediately before payment. |
| Flying Squirrel Thief | Intermediate or Front, 1H | Fly 2. An adjacent deployed enemy hero gaining exactly +1 current and +1 maximum life grants one remaining deployment, then a friendly Revive choice. |
| Rat Hunter | Front, 3H | Friend with Projectiles attacks: Walk 1 away from it. Adjacent units of either owner with Projectiles gain +1 Bow damage and range. |
| Guinea Pig Berserker | Starting or Front, 4H | Gain one Soul when declaring Bash. Choose and spend positive X Souls to Walk up to X without AS, then gain +X/+X through enemy End. |
| Mara Merchant | Any region type, 1H | Shield 2 and +3 Control. May also deploy in enemy-controlled regions. |
| Beaver Engineer | Starting or Front, 3H | Cannon 1/3. Spend two Souls from an adjacent deployed friend, then Disable one friendly hand card and one enemy hand card. Pays neither A nor S. |
| Marmot Crossbowman | Starting or Intermediate, 1H | Spend one of its own Projectiles with the ordinary AS cost to use Bow 1/3. Own Deploy grants two Projectiles. Each own Hit adds one permanent Bow damage. |
| Red Squirrel Paladin | Opponent-side Intermediate, 3H | [S] Bow 2/2. [S] Shield 2 to enemy hero: Shield 2 to a friend in Bash. |
| Jerboa Pirate | Front, 2H | Free Walk 2 must select an enemy landing when a legal Bash is reachable. Other deployed friends gain +1 Walk range. |

Unlisted ordinary movement is the game's implicit Walk 1. The Paladin still
needs ordinary regional control on the opposing side. Merchant's exception
does not allow neutral or occupied hexes. A Hunter retreat has no AS cost and
uses normal Walk legality. It increases distance from the event subject.
An attack here starts Bash or declares Bow, Fire or Cannon. Loaded means positive stored Projectiles at capture,
so an attacker whose last Projectile was paid before declaration does not
qualify. The Pirate's passive governs its Walk destination when using the
command. It does not force a Walk instead of another command or move the unit
automatically.

Both recipients of the Paladin's command and both hand choices for Engineer
must exist when the command starts. The Paladin's self-Stun and enemy-hero
Shield are one payment. If a later
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
| `Verbs.shield` and `Action.can_shield/shield` | CostPayment commits the explicit enemy-hero Shield with self-Stun before the friendly consequence. It uses the same temporary counter and occurrence as ordinary Shield. |
| `EffectText` | Uses the same definitions for card descriptions, including symbolic payments, once-per-turn text and passive restrictions. |

For example, the Berserker pays with `Verbs.decrement_choice()` against its
Soul property. Both the Walk and timed modifier verbs take the same
`RuleNumber.paid_amount(0)`. They do not read the Soul counter again after
payment. The Alchemist uses `paid_amount(1)`, the second cost in its AS plus
Sacrifice bundle.

## Second batch

Ordinary actions pay **[AS]**. **[S]** pays self-Stun without a player action.
**[]** pays only the written resource. Values are given before range.

| Card | Deployment / life | Rules |
| --- | --- | --- |
| Beaver Bard | Intermediate or Front, 2H | Walk 2 and enemy-only Push 1/2. Friend Bashes from an adjacent hex → it gets +1 Shield and +1 Mshield. |
| Chinchilla Druid | Intermediate or Front, 2H | Walk 2 and Mend 1/2. Every other wounded deployed friend has +1 live regional strength wherever it stands. |
| Dormouse Bard | Intermediate, 1H | Walk 2. [S] Return an adjacent friend. Whenever another unit of either owner Returns within 2, optionally move one unit within 2 onto its vacant former hex. Both trigger distances are measured from the Bard. |
| Guinea Pig Jester | Intermediate, 2H | Walk 2, Bow 1/2 and +1 Soul on own Deploy. This unit is attacked → Flee. |
| Hedgehog Cleric | Starting, 3H | Implicit Walk 1. Give 1 Mshield to a friend at any distance. Friend with 1+ Mshield survives a physical attack → +3 current life and +1 Shield on it. |
| Hedgehog Musketeer | Front, 2H | Walk 1 and +2 Projectiles on own Deploy. [AS] and one Projectile pays for Cannon 2/3. This unit wounds a friend → target gets +2 Shield and Flees. |
| Lemming Monk | Intermediate, 1H | Walk 2. [] −1 Stun from an adjacent friend → +1 Stun on an enemy. While the deployed enemy hero has at least five Stun, the Monk supplies +1 action. |
| Mara Witch | Intermediate, 1H | Walk 1 and Fire 1/3. [S] Disable a friendly hand card to give 2 Ember to a deployed friend within 2, including SELF. |
| Otter Blacksmith | Intermediate, 3H | Walk 1 and self Shield 2. −1 Shield → +2 Projectiles on an adjacent friend. |

### Timing and choices

- Shield and Mshield are stored counters with existing keys `temp_physical`
  and `temp_magical`. Matching contact clears the corresponding balance.
  An unsigned amount and range describe the action that adds them. A signed
  amount describes the counter change. Otter's forge pays ordinary [AS] plus
  its own −1 Shield. Any adjacent friend can receive the Projectiles.
- Beaver Bard reads the Bash attacker's recorded departure hex, including a
  Bash started by forced movement. A unit deployed into Bash has no departure
  hex. Each qualifying declaration can grant both counters.
- Dormouse Bard can relocate allies, enemies or itself. A temple cannot move. The
  Return hex must be vacant at capture and commit, including after Summoner
  replacements. The trigger has no turn cap. The move uses the Bard's radius
  and a fixed destination rather than the chosen unit's printed movement.
- Jester checks the original Bow/Fire victim, any affected Cannon line hex,
  or the exact Bash defender. Flee 2 follows a free Walk path into a vacant
  destination. The trigger pays neither Soul nor activity and can repeat.
  An Instant attack waits for the captured Flee to finish. Cannon still hits current line
  occupants and can hit the Jester again if it ends on the line.
- Cleric checks the surviving friend's stored Mshield after Bow, Gore or Bash
  contact. The friend gains up to three current life, capped by its maximum,
  and still gets +1 Shield at full life. A Musketeer grants Shield before
  asking for Flee. If no escape is legal, the Shield still lands.
- Monk transfers a raw counter. It changes neither unit's activity directly.
  Its action allowance is live and uses the existing spending ledger. Mara's
  Disable and self-Stun are atomic. Disable followups resolve before choosing
  the Ember recipient. A later failed choice leaves the paid costs committed.

### Second-batch callers

| Caller | Contract |
| --- | --- |
| `CardCatalogue.starter_army/all_units` → `FrontierRecruits.all_units` | Adds nine authored definitions and matches their sprite/portrait keys through `BoardCharacter`. |
| `CombatResolver._finish_unit_move` → `RulesRunner.capture_event` | Walk/Fly publish `move` with origin and Bash facts. A different unit's relocation or Flee instruction publishes `shifted` with the moved unit and instigator. Push/Pull share the same `shifted` contract. |
| `CombatResolver` declarations → `RulesRunner.defer_reacted_attack` | Keep only a reacted Instant attack's impact behind its captured declaration followups. Delayed attacks retain their usual queue. |
| `CombatResolver._create_bash` → Beaver Bard's Bash declaration | Capture the departure hex and grant both counters to the exact friendly attacker. |
| `CombatResolver._physical_contact` → Cleric's Hit pattern → `Verbs.up_life` | Check surviving life and stored Mshield at contact. Add up to three current life and then apply Shield to the exact friend. |
| `ControlResolver.strength` → `Contribution.regional_strength` | Sum derived strength for a wounded ally in its own region. The predicate reads life and ownership, so it never recurses through region control. |
| `Player.actions_remaining` → `SynergyRules.player_action_bonus` | Derive Monk's action from its enemy hero's stored Stun without minting tokens on repeated reads. |
| `Verbs.relocate/flee` → `RuleBinding.Field.SOURCE` | Preserve the effect's source separately from its chosen moving subject. |

For example, if a friendly troop Returns from two hexes west of Dormouse Bard,
an enemy two hexes east is an eligible replacement. The enemy is moved across
the four-hex gap. Jerboa King can observe this as **is moved** if that enemy is
its friend. A Jester's own Flee 2 counts as **moves**.

Focused regressions live in `tests/frontier_units_test.tscn`. The roster sweep
in `tests/full_roster_test.tscn` checks 106 cards per owner, their stable IDs and
definition contracts. See [TESTING.md](TESTING.md) for the opt-in runner.

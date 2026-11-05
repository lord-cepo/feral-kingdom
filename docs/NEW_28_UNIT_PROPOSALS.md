# Proposals for the 28 new PixelLab units

Superseded by the user's [MY_28_UNIT_PROPOSALS.md](MY_28_UNIT_PROPOSALS.md).
The implementation and current rulings are in [SYNERGY_UNITS.md](SYNERGY_UNITS.md).

Design proposal, 2026-10-28. These are proposed effects and starting balance
values, not implemented cards or changes to the rulebook.

Based on [synergies.md](synergies.md), the actual definitions in
[`CardCatalogue`](../scripts/catalogue/card_catalogue.gd), and the implemented
[Rat](RAT_SYNERGIES.md), [Woodland](WOODLAND_UNITS.md),
[Wild Return](WILD_RETURN_UNITS.md), and [Disable](DISABLE_UNITS.md) cards.
The roster is the 28 newest PixelLab characters: eight Grey Squirrels, three
Beavers, seven Jerboas, two Marmots, two Chinchillas, and six Tamias. PixelLab
names and action-animation themes were checked through its character tools.

## Reading the proposals

- All 28 are troops. S/I/F mean Starting/Intermediate/Front deployment regions.
  Ordinary control, vacancy, deployment allowance, and action costs apply.
- An action costs ordinary activity/self-Stun 1 and one player action unless
  stated otherwise. A triggered consequence is free of those costs. An explicit
  additional cost is paid along with ordinary activity and the player action.
- Units without printed Walk have implicit Walk 1. Adjacency means exactly one
  hex away; a range includes the source hex. Friends include SELF unless the text
  says another friend. Recipients are deployed unless a zone is explicitly named.
- Soul is the existing unit-bound counter, not a new player currency. These
  proposals permit an effect awarding Soul to create that counter at zero on a
  recipient that lacks it. Transfers move existing Souls and never create them.
- A once-per-turn limit is per source per player turn, including the opponent's
  turn. Return, redeployment, and Reset do not refresh that limit. A spent printed
  action is different: Reset intentionally restores it.
- Surviving damage means positive actual life loss with the victim still deployed
  after that damage. Cannon uses explicit damage wording rather than changing
  the current physical-only Wound event. Bomb contact may include zero damage.
- Bonuses stated until End last through the current player's End followups and
  expire at cleanup. Persistent bonuses remain until Reset or another removal.

## Grey Squirrels: archery, preparation, and Reset

| Unit | Life | Deploy | Proposed actions | Proposed triggers or continuous effects |
| --- | ---: | --- | --- | --- |
| Grey Squirrel Archer | 2 | I | Bow 1, range 4 | Once per turn, after its Bow wounds an enemy, give another friend within 2 that has Bow +1 Bow damage until End. |
| Grey Squirrel Naturalist | 2 | S/I | Mend 1, range 2; Reset an adjacent friend | No additional effect. A simple support unit that can restore spent actions or remove drawbacks, at the cost of also removing upgrades. |
| Grey Squirrel Crossbowman | 2 | I/F | Bow 4, range 3, usable once before Reset | Committing this Bow spends that exact action even if the attack later misses. Reset restores it. |
| Grey Squirrel Pikeman | 3 | I | Pull 1, range 2 | While bashing a wounded enemy, +2 physical. |
| Grey Squirrel Warrior | 3 | S/I | Walk 2 | Once per turn, after a friendly Bow wounds an enemy, optionally Walk 1 to a hex closer to that exact enemy. |
| Grey Squirrel Guardian | 3 | S/I | Shield 2, range 1 | Other adjacent friends with physical modifier at least 3 have +1 Bow range. |
| Grey Squirrel Musketeer | 2 | F | Cannon 2, range 4 | After a friend survives damage from this unit's Cannon, that exact friend gains 1 Soul. Once per victim per Cannon attack. |
| Grey Squirrel Wizard | 2 | S | Additional cost: spend X Soul, where X is 1-3; Pull X, range 3 | Once per turn, after another friend within 2 is Reset, gain 1 Soul. |

The Archer feeds other archers rather than duplicating Mouse Archer's personal
permanent growth. The Warrior and Pikeman turn Bow wounds into engagements.
Guardian connects the existing Shield users to the archery package. Naturalist
and Crossbowman establish the Reset payoff, while Wizard turns restoration into
positioning. Musketeer links friendly Cannon damage to the existing Soul users.

## Beavers: bomb handling and defensive infrastructure

| Unit | Life | Deploy | Proposed actions | Proposed triggers or continuous effects |
| --- | ---: | --- | --- | --- |
| Beaver Warrior | 4 | I | Walk 2 | +1 magical. Once per turn, after surviving contact from any bomb, gain Shield 2 on SELF. |
| Beaver Guardian | 3 | S/I | Shield 3, range 1 | Other adjacent friends with physical modifier at least 3 have +1 magical. |
| Beaver Architect | 2 | I | Place Bomb 2, range 2; Defuse an inert bomb within 2 | After successfully defusing a bomb, gain 1 Soul. |

Warrior can accompany bombs without being completely immune to large blasts.
Guardian makes a protected formation resilient to both damage types. Architect
supplies bombs and recovers value from unused or dangerous ones. Wild Beaver
already supplies movement-based bomb placement; these cards add different roles.

## Jerboas: movement, friendly fire, and Fire preparation

| Unit | Life | Deploy | Proposed actions | Proposed triggers or continuous effects |
| --- | ---: | --- | --- | --- |
| Jerboa Banner Bearer | 2 | I | Walk 2 | Other adjacent friends have +1 physical while bashing an enemy that was Pushed or Pulled this turn. |
| Jerboa Warrior | 3 | I | Walk 3 | While bashing an enemy with at least 1 Stun, +2 physical. |
| Jerboa Cannoneer | 2 | I | Cannon 1, range 3 | After a friend survives damage from this unit's Cannon, that exact friend's Fire has +1 damage until End. Once per victim per Cannon attack. |
| Jerboa Assassin | 1 | I/F | Walk 3 | First Strike. Once per turn, after defeating an enemy through its own attack, gain 1 Soul. |
| Jerboa Pyromancer | 2 | I | Fire 1, range 3 | Once per turn, when its Fire contacts an enemy but fails the lethal test, gain 1 Soul. Misses, immunity, and bomb ignition do not qualify. |
| Jerboa Soldier | 3 | S/I | Push 1, range 2, targeting a unit or inert bomb | Once per turn, after surviving damage from a friendly Cannon, gain +1 current and +1 maximum life. |
| Jerboa Courier | 2 | S/I | Walk 3; Action-free: transfer up to 2 Soul from one friend within 2 to a different friend within 2 | Transfer still pays ordinary activity/self-Stun. It cannot transfer more Souls than the donor has. |

Soldier puts a willing recipient in a Cannon line and can move bombs or rescue a
Bash participant. Its life growth also feeds Red Squirrel Explorer and Wild Red
Squirrel. Cannoneer can prepare a friendly mage as well as wound an enemy.
Pyromancer and Assassin earn Souls through different combat outcomes; Courier
routes those Souls to Rat Warrior, Wild Mouse, Wizard, or Tamia Red Mage.
Banner Bearer rewards setting up Bashes with displacement, while Warrior rewards
Stun support rather than requiring a separate combat keyword.

## Marmots: sacrifice and succession

| Unit | Life | Deploy | Proposed actions | Proposed triggers or continuous effects |
| --- | ---: | --- | --- | --- |
| Marmot Halberdier | 3 | I | Walk 2; sacrifice another adjacent friendly non-hero as an additional cost: gain +1 persistent physical, then optionally Walk 1 for free | No additional effect. The free movement uses ordinary routes and can enter an enemy's hex to begin Bash. |
| Marmot Paladin | 4 | S | Shield 2, range 1 | Once per turn, after another friend within 2 is sacrificed, optionally Revive a different friendly non-hero that was already defeated before that sacrifice. |

Halberdier converts a friend into lasting combat strength and a small positional
followup. Paladin brings back an older casualty rather than immediately recycling
the sacrificed identity. Mouse Necromancer supplies deployment allowance when
sacrificed; Rat Dark Mage supplies Reset; Wild Rat can amplify their death
abilities. Paladin's own trigger observes Sacrifice, not Die, so Wild Rat does
not double it.

## Chinchillas: ETB suppression and a worthwhile drawback

| Unit | Life | Deploy | Proposed actions | Proposed triggers or continuous effects |
| --- | ---: | --- | --- | --- |
| Chinchilla Soldier | 5 | I | Walk 2 | On Deploy, Return another adjacent friend if one exists. This is mandatory when a legal recipient exists. |
| Chinchilla Sentinel | 2 | S/I | Push 1, range 1 | While deployed, other friends deploying adjacent to this unit do not trigger their own Deploy abilities. |

Soldier offers a large mobile body with a deployment drawback, but Return can
also recover an ETB unit or give Rat Warrior a Soul. Sentinel suppresses that
drawback and Wild Lemming's extra deployment Stun. It also suppresses beneficial
own-Deploy abilities such as Wild Chinchilla's +deploy, so positioning matters.
It does not suppress the ordinary deployment Stun, costs, or Deploy watchers on
other units. Returning Soldier without Reset preserves wounds as usual.

## Tamias: Bow control, sacrifice fuel, and combined Fire

| Unit | Life | Deploy | Proposed actions | Proposed triggers or continuous effects |
| --- | ---: | --- | --- | --- |
| Tamia Knight | 4 | I | Walk 2 | On Deploy, add 2 Stun to SELF beyond normal deployment Stun. While bashing, +2 physical. |
| Tamia Warrior | 3 | S/I | Walk 2; sacrifice another adjacent friendly non-hero as an additional cost: gain 3 Soul | No additional effect. A dedicated sacrifice-to-Soul converter. |
| Tamia Archer | 2 | I | Bow 1, range 3 | Once per turn, after its Bow wounds an enemy that survives, optionally Push that exact enemy 1 away from this unit. |
| Tamia Crossbowman | 2 | I/F | Bow 2, range 3 | This Bow has +1 damage when its chosen enemy victim has at least 1 Stun at declaration. |
| Tamia Red Mage | 2 | I | Fire 2, range 2. As an optional additional cost, spend up to 3 Soul in total from SELF and up to two other friends within 2; add the total paid to this Fire's damage | One combined Fire attack is captured, not one attack per contributor. |
| Tamia Blue Mage | 2 | S/I | Stun 1, range 2; additional cost: spend 1 Soul from SELF to remove 1 Stun from a friend within 2 | Removing Stun does not activate its recipient immediately. |

Knight provides another bad ETB for Sentinel to suppress, or Stun counters for
Wild Porcupine to harvest. Warrior feeds the shared Soul network through
sacrifice. Archer trades raw growth for displacement; Crossbowman and Jerboa
Warrior reward Blue Mage's Stun. Blue Mage can also improve friendly recovery.
Red Mage pools resources built by the team into one large Fire threshold,
including Souls earned by failed Fire or friendly Cannon damage.

## Connections to try first

| Package | New cards | Implemented partners |
| --- | --- | --- |
| Bow support and pursuit | Grey Squirrel Archer, Warrior, Pikeman, Guardian; Tamia Archer and Crossbowman | Mouse Archer, Mouse Sorcerer, Wild Grey Squirrel, Mouse Warrior |
| Failed Fire into combined Fire | Jerboa Pyromancer, Courier, Cannoneer; Tamia Red Mage | Red Squirrel King, Wild Mouse, Wild Porcupine |
| Friendly Cannon damage | Grey Squirrel Musketeer; Jerboa Cannoneer and Soldier | Mole Artificier, Wild Mara, Red Squirrel Explorer, Wild Red Squirrel |
| Restore a spent action | Grey Squirrel Naturalist, Crossbowman, Wizard | Wild Mouse, Rat Dark Mage |
| Suppress deployment drawbacks | Chinchilla Sentinel and Soldier; Tamia Knight | Wild Lemming; Wild Chinchilla as the beneficial-ETB tradeoff |
| Sacrifice, Revive, deploy | Marmot Halberdier and Paladin; Tamia Warrior | Mouse Necromancer, Rat Dark Mage, Wild Rat, Rat Warrior |
| Soul distribution | Jerboa Courier and Assassin; Tamia Warrior and Red Mage; Grey Squirrel Wizard | Rat Warrior, Wild Mouse, Wild Porcupine |
| Bomb production and handling | Beaver Architect and Warrior; Jerboa Soldier | Mole King, Wild Beaver, Wild Mole Rat, Mole Miner, Mouse Engineer |
| Shield thresholds | Beaver Guardian; Grey Squirrel Guardian | Mole Artificier, Wild Hedgehog, Red Squirrel Explorer |
| Stun and displacement | Tamia Blue Mage, Knight, Crossbowman; Jerboa Warrior and Banner Bearer | Red Squirrel Climber, Wild Porcupine, Mouse Warrior, Mouse Engineer |

## Rules to settle before implementation

These proposals reuse existing rules where possible, but several need explicit
new support. No implementation is authorized by this document.

- **Sacrifice:** proposed as an additional cost that defeats another deployed
  friendly non-hero. Validate all costs before mutation. Publish ordinary Die
  and a distinct Sacrifice occurrence with the victim's captured hex and owner;
  release captured followups through the normal paid-cost boundary. A replacement
  that prevents defeat would make that sacrifice payment fail. Exact prevention
  policy still needs confirmation. Disable is not Sacrifice.
- **ETB suppression:** proposed to prevent capturing a deploying recipient's own
  Deploy abilities when another friendly Sentinel is already deployed adjacent
  to its destination. It prevents both beneficial and harmful own-Deploy triggers;
  it does not cancel deployment or suppress external watchers.
- **Single-use action:** commitment marks the Crossbowman's selected Bow action
  spent before its followups. Captured attacks still resolve. Reset restores the
  printed action; Return and Revive do not. Copying a spent action must not
  accidentally restore its donor; the recipient's use allowance needs a ruling.
- **Friendly damage:** Cannon must expose attacker, exact victim, damage amount,
  survival, and attack identity. Zero damage, immunity, enemy attackers, and
  defeated victims do not qualify for these proposed surviving-damage triggers.
- **Fire failure:** Pyromancer observes resolved contact and a failed lethal test,
  not declaration or any generic miss. Check this before unrelated followups can
  move, heal, or defeat that victim.
- **Combined Fire:** choose Soul donors and amounts before payment; preflight the
  entire distributed cost atomically. Capture the total actually paid on Red
  Mage's single attack. Donors do not perform Fire, spend activity, or emit Fire
  events. Later movement, defeat, or Reset cannot change that captured value.
- **Timing and history:** add turn limits, actual sacrificing/defeating source,
  historical forced movement, and Reset observations where needed. A cancelled
  action or failed payment cannot produce these payoffs. Already captured attack
  values do not grow when a later grant is awarded.
- **Counter removal:** friendly Stun removal is distinct from hostile Stun and
  ordinary Start recovery. It preserves activity and other counters. Soul grants
  and transfer must preserve resource totals and exact unit ownership.

All numbers should be reviewed together with action economy and region control.
The intended first pass is one clear role per card, with combinations across
species rather than compulsory species-only armies.

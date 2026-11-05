# My proposals and some comment
+N control puts N control counters on the unit. they contribute in the control calculation
I chose that [S] other_cost, is stun + other cost, while [A] is consume action. If cost is not specified in actions, it should be [AS].
[AS] other_cost substitutes the [AC], while [C] becomes [A]. double stun becomes [2S]
+N ember counters give +N fire damage on next attack, then it's removed
## Grey Squirrels: archery, preparation, and Reset

| Unit | Life | Deploy | Proposed actions | Proposed triggers or continuous effects |
| --- | ---: | --- | --- | --- |
| Grey Squirrel Archer | 2 | I | Bow 1, range 4; this unit wounds: +2 control |  |
| Grey Squirrel Naturalist | 2 | S/I | [2S]: 2 stun 1; Reset an adjacent friend |  |
| Grey Squirrel Crossbowman | 2 | I/F | this unit deploys: +2 projectiles; [AS] -1 projectile: Bow 4, range 2 |  |
| Grey Squirrel Pikeman | 3 | I | Pull 2, range 2 | While this unit (bash): +1 actions |
| Grey Squirrel Warrior | 3 | S/I | Walk 2 | friendly (bow) wounds: +1 soul; [AS] -2 souls: 1/0 upgrade 2 |
| Grey Squirrel Guardian | 3 | S/I | Shield 2, range 1 | adjacent friends with at least +3 have +1 (bow) +0 . |
| Grey Squirrel Musketeer | 2 | F | this unit deploys: +2 projectiles; [AS] -1 projectile: Cannon 3, range 3 | this unit wounds a friend: +1 projectile |
| Grey Squirrel Wizard | 2 | S | friend is reset: +1 soul; [AS] -1 soul: return adjacent unit |  |

## Beavers: bomb handling and defensive infrastructure

| Unit | Life | Deploy | Proposed actions | Proposed triggers or continuous effects |
| --- | ---: | --- | --- | --- |
| Beaver Warrior | 3 | I | Walk 2 | +1 magical; friends on unlit bombs have +1 magical |
| Beaver Guardian | 3 | S/I | Shield 3, range 1 | adjacent friends with at least +3 have +1 magical. |
| Beaver Architect | 2 | I | [AS] -1 soul: bomb 3, range 3; defuse 2 | defuse: +1 soul |

## Jerboas: movement, friendly fire, and Fire preparation

| Unit | Life | Deploy | Proposed actions | Proposed triggers or continuous effects |
| --- | ---: | --- | --- | --- |
| Jerboa Banner Bearer | 2 | I | Walk 2 | Other adjacent friends have +1 physical while bashing an enemy that was Pushed or Pulled this turn. |
| Jerboa Warrior | 3 | I | Walk 2 | While (bash) an enemy with at least 1 Stun, +3 physical. |
| Jerboa Cannoneer | 2 | I | Cannon 1, range 3 | this unit wounds a friend: target +1 ember |
| Jerboa Assassin | 2 | I/F | Walk 3 | steady; first strike |
| Jerboa Pyromancer | 2 | I | Fire 1, range 3 | this unit hits and not wounds: +1 ember to adjacent friend |
| Jerboa Soldier | 3 | S/I | Push 1, range 3 | friend hits with fire: this unit +1 magic shield |
| Jerboa Courier | 2 | S/I | Walk 2; [S]: transfer up to 2 counters from a unit within 2 to a unit within 2 | |

## Marmots: sacrifice and succession

| Unit | Life | Deploy | Proposed actions | Proposed triggers or continuous effects |
| --- | ---: | --- | --- | --- |
| Marmot Halberdier | 3 | I | Walk 2; [AS] sacrifice a unit within 2: +1/+1 | |
| Marmot Paladin | 4 | S | Shield 2, range 1 | friend is sacrified: revive a friend |

## Chinchillas: ETB suppression and a worthwhile drawback

| Unit | Life | Deploy | Proposed actions | Proposed triggers or continuous effects |
| --- | ---: | --- | --- | --- |
| Chinchilla Soldier | 5 | I | Walk 2 | this unit deploys: you must return another friend |
| Chinchilla Sentinel | 2 | S/I | Push 1, range 3 | deployment of adjacent units does not trigger any ability |

## Tamias: Bow control, sacrifice fuel, and combined Fire

| Unit | Life | Deploy | Proposed actions | Proposed triggers or continuous effects |
| --- | ---: | --- | --- | --- |
| Tamia Knight | 2 | F | Walk 2 | this unit deploys: +3 stun. While bashing, +4 physical. |
| Tamia Warrior | 3 | S/I | Walk 2; [AS] sacrifice an adjacent unit: 3F bow 2 |  |
| Tamia Archer | 1 | I | [S] Bow 1, range 3 |  |
| Tamia Crossbowman | 2 | I/F | Bow 3, range 1 | this unit hits: +0 bow +1 |
| Tamia Red Mage | 2 | I | Fire 1, range 3; | this unit hits and not wound: +2 ember |
| Tamia Blue Mage | 2 | S/I | Stun 1, range 2; friend stuns a stunned unit: +1 stun to target |  |



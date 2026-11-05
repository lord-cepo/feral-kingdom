# Woodland catalogue additions

Implemented from the 2026-10-24 specifications and replies. Wild Beaver receives
the new Fire/Bomb specification; the existing Mole Artificier is unchanged.

## Fixed card wording

Actions use `value icon range`; triggers use `event: consequence`; sequences use
`; then`. Life deltas use signed `current heart maximum` components, including
zero. A one-value movement keeps its distance after the boot/wing. Static modifiers
are signed physical/magical pairs. Ownership words refer to the source's owner.

| Unit | Life | Deployment | Actions | Other effects |
| --- | ---: | --- | --- | --- |
| Red Squirrel Explorer | 2 | Starting, Front | Walk 2 | Any friendly deployed unit increases life by +X heart +Y: +X/+Y to this unit. Only positive components count. |
| Red Squirrel Doctor | 4 | Intermediate, Front | Walk 2; [AS] -1 heart +0: +1 heart +1 to a friendly deployed unit | — |
| Wild Red Squirrel | 1 | Intermediate | Walk 3 | Any friendly deployed unit's maximum life increases by X: X Instant Bow 2. |
| Wild Beaver | 2 | Intermediate | 1 Piercing Fire 2; implicit Walk 1 | +0/+2; after Walk: Bomb 2 on its previous hex. |
| Mole Miner | 3 | Opponent-side Intermediate | Walk 2 | First Strike; a friendly deployed unit is hit by a Bomb: +1 heart +1 to that exact unit. |
| Wild Mole Rat | 1 | Starting, Intermediate | Implicit Walk 1 | +0/+2; an enemy Bashes this unit: Bomb 2 on this unit's hex; then Flee. |
| Mouse Sorcerer | 2 | Starting | 2 Fire 2; [AS] -1 heart -1: permanent +1 Bow +1 to a friendly deployed unit; implicit Walk 1 | — |
| Mouse Warrior | 3 | Starting | 2 Pull 2; implicit Walk 1 | An enemy Bashes this unit: Stun 1 to that exact enemy; then +1/+0 to this unit. |
| Wild Mouse | 2 | Intermediate | [A] +1 action on the enemy player's next turn: +2 Soul; [AS] 1 Soul: 1 Upgrade 0 to a friendly unit's chosen ability; [AS] 1 Soul: Reset any unit; implicit Walk 1 | Soul starts at zero. |
| Wild Guinea Pig | 2 | Intermediate | [AS] -1 heart +0: +0 heart +1 to itself; implicit Walk 1 | A friendly Wild unit hits: +1 heart +0 to this unit. |

`SF/IF/SI` mean Starting+Front / Intermediate+Front / Starting+Intermediate.
Mole Miner's `oI` is treated as opponent-side Intermediate. Control, vacancy and
first-hero rules still apply there. Wild is a case-insensitive substring of the
unit name, just like squirrel or mouse. It is not a flag, effect or copyable
ability; changing a name changes group eligibility immediately.

## Interactions

- Life increases emit one captured `life_increase` with independently clamped
  positive current/max components. Damage, negative components and clamped healing
  do not award positive amounts. Explorer gets its own counters; Wild Red Squirrel
  captures only positive maximum growth as Bow damage. Both use the original event
  amounts even if choices or other effects change health later.
- `[AC]` bundles the written life/Soul payment with normal self-Stun and one
  player action. Full affordability is checked before any payment. Paying the
  final life is allowed; the payer is defeated, death followups resolve, and the
  already-paid consequence continues using its stable source identity. Health
  changes to a defeated unit never implicitly Revive it. A zero-maximum casualty
  must have a positive maximum restored before it can be Revived.
- Wild Mouse's `[C]` gives the selected opposing player a one-shot action bonus at
  that player's next Start. It consumes one current action but no self-Stun, then
  grants two Soul. Resetting/defeating Mouse does not cancel the paid player bonus.
- Upgrade chooses a unit, then one numeric activated ability. The grant belongs
  to that exact recipient/definition, not every ability sharing its action family.
  +M/+N changes its first/second numeric action values; single-value actions use
  the applicable first value. Fire's second value is its selector range. A range
  after `M Upgrade N` restricts the first unit query; without it the explicit
  selector (here any friendly deployed unit) supplies eligibility. Reset clears
  grants; Copy does not copy accumulated grants; snapshots restore selected
  ability identities after copied definitions are rebuilt.
- Flee grants one free complete use of one of the unit's current Walk/Fly
  abilities. It uses that ability's range/upgrades and normal route/occupancy rules,
  without paying activity or a token. Moving the original defender out cancels
  its Bash and can trigger an attacking Swordsman's Flee reward. The ordinary
  Move/Fly event still occurs, allowing Walk triggers and existing presentation.
- Bomb contact has its own `bomb_hit` occurrence, emitted per actual contact,
  including zero damage but excluding Obsidian immunity. This does not change
  attack Hit/Wound semantics; Cannon and Fire now share those events, while Bomb
  retains its separate contact event. Miner targets the exact victim; a subsequently
  defeated victim remains defeated after the health grant.
- Beaver's movement trigger automatically leaves inert Bomb 2 on the captured
  `origin_hex`, regardless of region. It does not ask for a tile or follow the
  source's later location; absent/malformed origin history yields no placement.
  Rat leaves its inert Bomb on its own hex before choosing Flee.
  Neither placement itself means an immediate explosion.

## Callers and state ownership

`CardCatalogue` attaches `WoodlandRules` object factories. Existing starter IDs
remain stable: Mouse Warrior follows the rats, then the remaining nine cards
append for both players. `BoardCharacter` loads all ten PixelLab appearances;
the manifest has complete eight-direction walks, stand/sit and action clips.

`LifeChanges.publish` is called from authoritative life changes and healing.
`RuleNumber` reads frozen event fields. `Effect.Verb.bound_to` creates ephemeral
parameters for those event values and recipient-bound upgrades; PhraseExecution
uses them for legality and commitment. Distance/Bow selectors read the same
ability bonus. Shared definitions never retain activation state.

`Verbs.pay_life` and `pay_next_turn_action` are atomic cost verbs. `CostPayment`
preflights cumulative health/counter/activity resources, then commits within the
runner boundary. RulesRunner's availability query uses equivalent shadow ledgers.

`Selectors.UpgradeUnits` filters the initial unit choice; `choose_upgrade_unit`
records that choice without mutation. `UpgradeOptions(Completed(step_0, targets))`
offers that recipient's numeric effect properties; `upgrade_ability` stores the
grant on UnitInfo. `MatchSnapshot` saves those grants by recipient effect index
and restores them after effect copies. No unit-array identity is reordered.

## Verification

`tests/woodland_effects_test.tscn` has focused cases for each new effect, positive
and opposing-event exclusions, lethal payment continuation, Upgrade's two stages,
First Strike/deployment constraints, Flee range and exact recipients, and snapshot
provenance. Tests were created but not run: this request did not end with TEST.
Godot editor import/compilation and the read-only catalogue export are checked
separately. The standalone HTML is rebuilt from the same factories.

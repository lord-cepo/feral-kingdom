# Guerra rules — JS reference and Godot migration

Snapshot: 2026-09-24. This is a compact inventory of gameplay, rule-language, and
catalogue behavior in the local `guerra.game` TypeScript sources. It excludes
networking, accounts, persistence formats, and visual presentation. Source code
takes precedence over older comments/documentation. The JS project was read, not
modified. A rule listed here is not automatically implemented in Godot.

Godot update, 2026-10-28: the approved roster uses A/S cost markers and shared
Cannon/Fire Hit/Wound, with nonlethal Fire counting as Hit without Wound.
The JS tables below remain the reference snapshot, not an override of those
new intended rules. See [SYNERGY_UNITS.md](SYNERGY_UNITS.md) and FK-9.

## What the game is about

Guerra is a two-player tactical game on a hex board. Each player builds a small
force around one hero and wins by defeating the opposing hero. Position determines
which regions can be controlled, where reinforcements can deploy, and which units
benefit from support. Most attacks leave a response window: declaring an attack
does not immediately settle the fight.

The strategic implications below are an interpretation of the implemented rules,
not additional mechanics.

| Central decision | Why it matters |
| --- | --- |
| Protect or expose the hero | The hero is both the defeat condition and the normal source of turn action tokens. |
| Attack now or improve position | Delayed attacks allow movement, shields, reinforcement, and reactive effects before impact. |
| Which unit should act | Activity costs restrict repeated use; action-token bonuses and Tireless/action-free rules change the available sequence. |
| Hold a region or concentrate forces | Control affects deployment and physical protection. It uses current life, so wounds can change control without removing units. |
| Wound or finish | Bow/Cannon/Bomb can leave permanent damage. Fire is an execution threshold: it either defeats or leaves life unchanged. |
| Spend a shield or rely on support | Temporary counters absorb one relevant contact; persistent counters and active while-bonuses can protect against repeated attacks. |
| Enter a shared hex | Bash commits two units to a contested position; either may respond, modifiers can change, and movement can dodge the exchange. |
| Build combinations | Movement, phase, attack, and death events can trigger further actions or permanent improvements. Temples and conditional rules support other units. |

## Worked situations

| Situation | Result under the recorded rules |
| --- | --- |
| Fire 4 targets life 3 with magical 1 + temp_magical 1 | Threshold is 2: unit survives at life 3; temp_magical becomes 0. A later Fire 4 now has threshold 3 and can defeat it. |
| Bow 2 wounds a life-4 unit with no physical modifier; Fire 2 follows | Bow leaves life 2. Fire is then lethal if magical modifier is 0. Combat order matters. |
| Fire is aimed at a unit that moves away before impact | It misses. Even if a replacement enters, the original occupied-target victim ID is not replaced. |
| Two adjacent heroes satisfy one “while adjacent to a hero, +1 physical” rule | One +1 contribution. When neither remains adjacent, the contribution disappears; no counter was added. |
| Bash: life 3, physical +1 versus life 2, physical 0 | Powers are 4 versus 2. The weaker unit dies; winner receives 1 permanent injury and has life 2 before any subsequent effects. |
| Reinforcement changes regional control before Bash | Recompute control and modifiers at combat, rather than using the values shown when Bash began. |

## Source map

| Key | Source | Main responsibility |
| --- | --- | --- |
| E | [engine.ts](C:/Users/ciava/Documents/guerra.game/game/engine.ts) | Authoritative actions, phases, damage, control, defeat |
| B | [board.ts](C:/Users/ciava/Documents/guerra.game/game/board.ts) | Board, regions, distance, lines |
| C | [cards.ts](C:/Users/ciava/Documents/guerra.game/game/cards.ts) and [card-parser.ts](C:/Users/ciava/Documents/guerra.game/game/card-parser.ts) | Catalogue and implicit actions |
| AC | [action-costs.ts](C:/Users/ciava/Documents/guerra.game/game/action-costs.ts) and [consequence-policy.ts](C:/Users/ciava/Documents/guerra.game/game/consequence-policy.ts) | Tokens, activity, optional consequences |
| S | [rule-state.ts](C:/Users/ciava/Documents/guerra.game/game/rule-state.ts) | Stored and continuous state, modifier/life computation |
| R | [rule-runtime.ts](C:/Users/ciava/Documents/guerra.game/game/rule-runtime.ts) | Event capture, bundles, continuations |
| Q | [rule-parser.ts](C:/Users/ciava/Documents/guerra.game/game/rule-parser.ts), [rule-evaluator.ts](C:/Users/ciava/Documents/guerra.game/game/rule-evaluator.ts), [action-selector.ts](C:/Users/ciava/Documents/guerra.game/game/action-selector.ts) | Grammar, conditions, selection |
| V | [rule-vocabulary.ts](C:/Users/ciava/Documents/guerra.game/game/rule-vocabulary.ts) | Actions, passives, attack families |
| N | [named-values.ts](C:/Users/ciava/Documents/guerra.game/game/named-values.ts) | Typed counters and flags |
| T | [rule-scheduler.ts](C:/Users/ciava/Documents/guerra.game/game/rule-scheduler.ts) | Future phase work |
| D | [deck-state.ts](C:/Users/ciava/Documents/guerra.game/client/deck-state.ts) | Deck legality |

## Confirmed Godot decisions and implementation boundary

| Topic | Godot rule / status |
| --- | --- |
| Fire | Implemented: magical **lethal check**, matching JS. Defeat if `life <= damage - magical_modifier`; otherwise life is unchanged. |
| Persistent counters | Implemented: `physical`, `magical`; signed values, changed only by effects. Attacks do not consume these counters. This supersedes consuming legacy JS native modifier fields. |
| Shields | Implemented: `shield` adds `temp_physical`; `mshield` adds `temp_magical`. Fire consumes `temp_magical` on contact, even if nonlethal or piercing. Bow/Gore contact and Bash consume `temp_physical`, unless Titanium blocks contact. |
| Effective modifier | Implemented: persistent counter + temporary counter + current state contributions, independently for physical and magical. |
| Continuous state | Implemented: attached `StateModifier` and deployed-source modifier auras contribute from read-only RuleContext queries. Includes adjacent-to-any-hero, wounded/deployed bonuses, and War Temple's friendly Bash aura; never writes counters. Other passive/action grants and lifetimes remain M3 work. |
| Region control | Implemented from intended rules: current life + printed `control_bonus`, home +0.5 in starting/intermediate regions, neutral ties; deployment validates control; +1 physical is derived. Bash participants count at their shared destination. Card-specific `enemy` deployment filters remain unimplemented. |
| Fire timing | Implemented: queue at declaration; resolve in the opponent's combat window. Instant and piercing options use the same resolver. |
| Turn integration | Partial: `Match.finish_action()` tracks sample-format tokens and `Match.complete_action()` advances Bow/Gore, Cannon/Bomb, Fire, Bash, End, and Start windows. Godot's 2026-10-19 user ruling keeps self-Stun 1 costs, removes one friendly Stun at owner Start without activation, and activates only the ending player's inactive zero-Stun deployed units after End effects. Activate followups finish before cleanup/switch. This supersedes Godot's earlier Start activation; the source-linked JS phase tables below remain the legacy reference. Start/End/combat pause for triggered choices. Future-phase scheduling remains M3; final format allowances are still unspecified. |
| Other combat | Move/Fly resolve immediately with intended path, landing, and temple restrictions; moving or defeating a Bash participant cancels that encounter as a dodge. Mend heals injured allies up to starting life. Hostile Stun deactivates an enemy and adds its requested counters; the intended 2026-10-26 ruling preserves every other counter, including temporary protection. Revive returns a selected defeated allied non-hero to full life in reserve, excluding the death source. Bow, Cannon, Bomb, Gore, Push/Pull, and Bash use object-authored actions and the local HUD. Gore hits queue before Cannon/Bomb and Fire; Bash resolves after them. Fast, Titanium, First Strike, and Steady affect Bash. Titanium blocks Bow/Gore contact; Obsidian blocks Fire/Cannon/Bomb unless piercing. |
| Events | Move/Fly emit one resolved movement occurrence with origin, destination, and captured control facts. Fire declaration and resolution stages are distinct. M2 captures matching definitions before followups, preserves death anchors, resumes choices and defers cost/consequence bundles. Timed contribution cleanup/scheduling remains M3. |

## 1. Match, board, deployment, and control

| ID | Rule in JS | Source |
| --- | --- | --- |
| G01 | Two players; Player 1 starts. Defeating an enemy hero wins. A winner prevents subsequent commands. | E:98,480,855 |
| G02 | Decks contain 8 or 10 distinct known cards and exactly one hero. | D:isCompleteDeck |
| G03 | Roles: hero, troop, temple. Temples occupy tiles and contribute control; no implicit movement. | C |
| G04 | JS coordinates: `-3 <= x <= 3`, `-4 <= y <= 4`, `-3 <= x-y <= 3`; `(0,0)` is a gap. | B:isBoardCoordinate |
| G05 | JS distance is `max(abs(dx), abs(dy), abs(dx-dy))`; adjacent steps are `(±1,0)`, `(0,±1)`, `(1,1)`, `(-1,-1)`. Godot uses the reflected `dx+dy` basis; do not copy coordinate lists unchanged. | B:hexDistance; Godot DistanceSelector |
| G06 | Six home regions: each player has one starting and two intermediate regions. Remaining playable tiles form the neutral front. Region membership is explicit in B. | B:regionAt |
| G07 | Regional control strength = sum of units' current life + printed control bonuses in that region, plus 0.5 for that region's home player. Highest total controls; equal totals mean neutral. | E:388 |
| G08 | A pending Bash attacker contributes at the contested destination, including control previews for the whole region. | E:412 |
| G09 | A unit in a region controlled by its owner gains +1 physical modifier. This is recomputed from current board state. | E:428 |
| G10 | Deploy only to a vacant tile of a printed allowed region type that you control. `enemy` deployment additionally requires the opponent's home region. | E:962 |
| G11 | Deploy your hero before non-hero cards. Already deployed or defeated cards cannot deploy. Deployment carries the inactivity paid while off-board, so ordinary deployment enters inactive. | E:962; AC |
| G12 | Non-temples gain Move 1 unless Move/Fly is explicit. Explicit Move 0 suppresses that default and is removed as an available move. | C:parseActions |
| G13 | Every unit can self-shield for 1 unless it has a printed self-shield value. Self-magic-shield requires a printed capability. Range-zero shield actions become those self capabilities. | E:835,1021; C:parseCard |

## 2. Turn phases and costs

| Order / ID | Rule in JS | Source |
| --- | --- | --- |
| P01 Start | Publish active player's Start and opponent-relative Start events; hero rules grant action tokens even before deployment. Enter Action after pending Start work completes. | E:98,1174,1449 |
| P02 Action | Active player chooses a legal action. Pending rule choices take priority; only their owner/source may answer. | E:752,843 |
| P03 Payment | Validate the action on disposable state; simulate the whole cost bundle before paying any part. Explicit costs replace defaults. Paid costs are not refunded if a cost trigger later invalidates the action. | E:1312,1409; AC |
| P04 Action-resolve | Apply the immediate action or queue its delayed consequence; run event followups and suspended choices before continuing. | E:960,1135; R |
| P05 More actions | If the player still has tokens, return to Action. Do not enter the delayed combat window yet. | E:1424 |
| P06 Combat-resolve | Once tokens reach zero, resolve eligible opposing delayed effects, then ready Bashes. The acting player is the defender for this window. | E:1434,1510 |
| P07 End | Publish End; wait for its choices; make newly pending Bashes eligible after this End; publish opponent-relative End. | E:1437 |
| P08 Cleanup | Finish pending stack presentation, reactivate eligible old inactive troops of the ending player, decrement that player's stun durations. | E:1444 |
| P09 Next player | Switch active player, increment global turn and that player's turn count, then Start → Action. | E:1448 |
| C01 | Ordinary standalone actions generally pay deactivation + one player action token. Pass pays one token and does not deactivate a unit. | AC; E:1315 |
| C02 | `T` / Tireless omits deactivation. `A` / action-free omits the standalone token independently. | AC:implicitActionCosts |
| C03 | A troop with an inactivity marker cannot pay deactivation again. At owner End, markers older than `globalTurn - 1` are cleared; do not model this as a blanket Start reset. | E:120; AC |
| C04 | Triggered Bow/Gore/Bomb-throw/Fire/Cannon/Fly/Move/Shield/Mshield/Pull/Push/Stun pay activity unless Tireless; they do not automatically spend standalone tokens. | AC; consequence-policy |
| C05 | Costly triggered consequences are optional unless `must`; Tireless/free consequences are mandatory by default. Explicit costs make them optional unless `must`. | consequence-policy |
| C06 | Optional explicit-target consequences ask even for one candidate. `all` offers one accept-all/skip choice. Costs are paid only after acceptance. | E:1262; R |
| C07 | `up-actions(N)` changes one player's tokens without permitting a negative balance; `activate`/`deactivate` also address off-board identities. | AC:applyResourceEvent |

## 3. Attack resolution

Let `H` be current life, `P` effective physical modifier, and `M` effective magical
modifier. Printed/updated attack value is captured when an attack is created;
defender modifiers are read when it resolves.

| Attack | Targets and timing | Result | Source |
| --- | --- | --- | --- |
| Bow | Enemy or empty tile in range; normally opposing combat window. | Permanent damage `max(0, D-P)`; piercing ignores P. Consume native physical shields on contact, including zero damage. Titanium blocks contact. | E:1084,1516 |
| Fire | Enemy or empty tile in range; normally opposing combat window. Shared tile selects the opposing participant. | Defeat iff `H <= D-M`; **no partial wound otherwise**. Physical modifier irrelevant. Consume temporary magic bonus on contact. | E:1111,1574 |
| Fire, piercing | Same timing; ignores magical modifier and Obsidian. | Defeat iff `H <= D`; still consume temporary magical protection on contact. | E:1117,1580 |
| Cannon | Straight line after source through chosen destination. May cross central gap. Every affected tile can hit either player's occupants. | Permanent magical damage `max(0,D-M)`; piercing ignores M and Obsidian. Consume temporary magical protection on contact. | E:1064,1554 |
| Gore | Move immediately in a straight-line leap; intermediate units do not block. Queue physical hits for enemies captured along the path. Enemy landing creates Bash. | Delayed physical damage; captured enemies must remain at their captured tiles. Missing Gore source cancels its damage. | E:994,1516 |
| Bomb explosion | Center and adjacent playable tiles; neutral damage to either player; normally delayed. | Permanent magical damage using M; Obsidian blocks unless piercing. | E:316,1554 |
| Bash | Opposing units share a contested tile. Normally waits for an End, then a later combat window. | Compare `H+P`; resolve rules below. | E:169,1587 |

| ID | Resolution detail in JS | Source |
| --- | --- | --- |
| A01 | Opposing Bow/Gore resolve first, then Cannon/Bomb, then Fire, then ready Bash. Effects within a group retain queue order. | E:1510 |
| A02 | Ordinary Bow/Fire capture the current victim ID **and** target tile when occupied. If that victim moves, is removed, or is replaced, the attack misses; it does not follow the victim or hit the replacement. Initially empty targets use the occupant at resolution. | E:1093,1123,1519,1576; engine-combat tests |
| A03 | This victim-ID behavior is stricter than the older rule-language document's “hit whoever occupies the tile.” Preserve the implementation deliberately; do not infer solely from old prose. | Same as A02 |
| A04 | Queued Fire does not require the source to remain deployed. Its captured controller, origin, target, and value remain available. | E:1574 |
| A05 | `F` makes supported attacks immediate; it does not by itself remove activity/token costs. Immediate Fire still uses a lethal threshold. | E:1086,1114; AC |
| A06 | Non-piercing Obsidian prevents magical contact and preserves temporary magic protection. Titanium prevents physical contact and preserves physical shields; piercing physical attacks still encounter Titanium in the current engine. | E:1525,1566,1580 |
| A07 | Hit means physical damage resolution contacted the target, even for zero damage. Wound requires positive physical life loss. Current engine dispatches these result events for Bow/Gore; do not invent Fire wound events. | E:1496,1536 |
| A08 | Death removes deployed presence, retains a defeated identity, and can trigger last-known-source rules. Hero death declares the opponent winner. | E:480 |
| A09 | Resolving delayed attacks clears their source's consumed action upgrades after the batch; ordinary delayed effects belonging to the current defender remain queued. | E:1665 |

## 4. Bash and movement

| ID | Rule in JS | Source |
| --- | --- | --- |
| M01 | Move uses a free adjacent path within range. Units block intermediate tiles; an enemy may occupy the endpoint. Cannot land in the center gap, on a friendly unit, or in an existing Bash. | E:382,978 |
| M02 | Fly ignores intermediate occupancy; range and landing restrictions remain. | E:978 |
| M03 | Entering an enemy tile puts both units there and creates Bash immediately. A second attacker cannot enter an existing Bash. | E:978 |
| M04 | If either participant leaves before resolution, remove the pending Bash as a dodge; no Bash damage. | E:1592 |
| M05 | Ordinary Bash: compare both `H+P`. A tie defeats both. Otherwise loser dies; winner receives permanent damage `max(0, loser_power - winner_P)`. | E:1648 |
| M06 | First Strike: one bearer attacks first for `max(0, its_H + its_P - target_P)`; a surviving target retaliates using its reduced current life and freshly computed modifiers. Current code picks the attacker first if both have First Strike. | E:1608,1622 |
| M07 | Titanium branch precedes First Strike: bearer receives zero physical damage but still deals its normal exchange. If both survive, Bash waits for another End/combat window. | E:1610,1662 |
| M08 | Steady suppresses only its opposing Bash participant's entire physical modifier (shield, control, rule bonuses); it does not change either base life or its bearer's own modifier. | E:428 |
| M09 | Fast on either Bash participant allows the new Bash into the creating action's combat window. It does not turn Bash into an upgradable turn action. | E:169 |
| M10 | Physical shields are consumed by resolved Bash unless the bearer has Titanium. A dodge does not consume them. | E:1595,1658 |
| M11 | Push/Pull require aligned source/target and the specified displacement length. Intermediate units and the center gap do not block displacement; final tile must be playable. | E:361,1026 |
| M12 | Displaced unit cannot land on its own ally or an existing Bash; enemy landing creates a new Bash. UI can select either participant on a shared tile. | E:1026 |
| M13 | Push/Pull can move a bomb. Landing on another bomb merges damage and preserves piercing if either has it. | E:1034 |

## 5. Other actions, counters, and live state

| ID | Rule in JS / confirmed Godot mapping | Source |
| --- | --- | --- |
| S01 | Shield adds physical protection to a friendly unit; Mshield adds magical protection. Repeated grants stack and follow the unit, not its tile. | E:338,1079 |
| S02 | JS transient fields are consumed by relevant hits; normalized permanent contributions survive. Godot maps this explicitly to persistent versus `temp_` counters. | E:343,1567; S |
| S03 | Effective physical = native shields + native bonus + stored/live physical contributions (+ control in combat summary). Effective magical = native magic bonus + stored/live magic contributions. Signed contributions can weaken defenses. | S:174; E:428 |
| S04 | Continuous `while` rules are reevaluated from current board state and apply only while their source is deployed; they do not accumulate or emit a mutation event. | S:derivedForUnit; E:normalizedDerivedRules |
| S05 | `up-mod(P,M)` changes modifier contributions; `up-life(actual,max)` changes life contributions; starting life is bounded below by zero and actual life is clamped to `[0, starting]`. | S:174 |
| S06 | Mend heals an allied target by reducing permanent damage, never below zero damage. | E:1095 |
| S07 | Upgrade selects a useful ability of an allied non-temple and adds numeric bonuses. Instant abilities consume upgrades when used; delayed attacks retain them until resolution. | E:259,358,1100,1669 |
| S08 | Stun targets an enemy, keeps the maximum current/requested duration, clears native temporary combat/magic protection, prevents action, and decrements at that owner's End. Stored rule contributions have their own lifetimes. | E:352,889,1124 |
| S09 | Revive returns a selected defeated allied non-hero card to undeployed availability and clears its inactivity markers; it does not deploy it. Death-source cannot revive itself. | E:924 |
| S10 | Typed named counters/flags attach to hex, unit, or player identity. Missing JS counters read 0; flags read false. Counter updates add signed integers; flag updates set on/off. | N |
| S11 | In Godot, property selectors require an existing property; modifier counters are created with every unit. `change_counter(delta)` is signed mutation; `decrement(n)` remains a spend requiring sufficient value. | UnitInfo; Action |

## 6. Bomb lifecycle

| ID | Rule in JS | Source |
| --- | --- | --- |
| B01 | Bomb-throw places an inert bomb in range, or merges its damage into an existing bomb. It is an ordinary costed action; an inert bomb does not explode on its own. | E:1072; AC |
| B02 | Fire targeting an inert bomb lights it and replaces the ordinary Fire effect with the bomb's explosion; do not also Fire the troop on that tile. | E:1113 |
| B03 | Lighting removes the inert bomb and queues its damage at center + adjacent playable tiles. Piercing propagates from the lighting attack. | E:316 |
| B04 | A delayed blast can light another inert bomb. Fresh chain effects belong to the responding player, so they wait for the next opposing response rather than recursively resolving in that pass. | E:1557 |
| B05 | Instant Fire detonates its directly targeted bomb immediately; bombs reached by that blast are ignited as queued effects. | E:324 |
| B06 | Bomb-light / Bomb-defuse triggered consequences are forced and do not deactivate their source; chosen normal Bomb-defuse follows its standalone action cost. Defuse removes the inert bomb. | V; E:applyNormalizedTriggeredIntent |
| B07 | Bomb-on is the lit/pending explosion state; Bomb-off is an inert object. Throw, light, and explosion are distinct events. | V; Q |

## 7. Rule language and execution

| ID | Construct | Meaning / implementation constraint | Source |
| --- | --- | --- | --- |
| R01 | `event : consequence` | Capture matching rules when the event occurs; apply event first, then captured consequences. | R |
| R02 | `costs :: consequences` | Preflight all costs; apply ordered cost bundle before its triggers, then ordered consequence bundle before its triggers. | AC; R |
| R03 | `while condition : contribution` | Live state, not an action and not a repeated counter increment. Older postfix `contribution while condition` remains accepted. | Q; S |
| R04 | `selector have phrase` | Evaluate for each selected unit, rebinding SELF to that unit. No SUBJECT/TARGET bindings inside the attached phrase. | Q; S |
| R05 | `permanent` | Default stored-state lifetime; bound to a concrete recipient ID. | S |
| R06 | `until E` / `removed-after E` | Remove before E applies / after E applies. Cancelled events do not consume either. | S:cleanupStoredContributions |
| R07 | `at next-start/end` | Capture concrete future work and its player; run only at a later matching phase event. Opponent variants select the other player. Work can outlive the source. | T |
| R08 | `E-resolved` | Explicit successful post-resolution stage; delayed attacks do not publish it at declaration. | R; E:1485 |
| R09 | `self`, `subj`, `obj` | Rule owner and singular phrase-local event participants. State effects capture stable recipient IDs; delayed attacks capture coordinates and sometimes victim IDs. | Q; S; E |
| R10 | `o:`, `p:`, `r:`, `c:`, `s:`, `t:` | Owner, property, region, control, side, and unit-type filters. Order is flexible; duplicate fields rejected. | Q |
| R11 | `any S`, `none S`, `all Q P` | Boolean existence, emptiness, or nonempty universal condition. Empty base: ANY/ALL false, NONE true. | Q |
| R12 | `all` action target | Separate from Boolean ALL: freeze matching action targets and perform one singular action per target. | R |
| R13 | `_` | Wildcard for a concrete event operand or numeric parameter. If a numeric vector is supplied, give its full arity, using `_` for unconstrained entries. | Q |
| R14 | `adj R`, `N-from R` | Exact distance 1 / N from one singular reference. Printed action range shorthand uses a radius. | Q; action-selector |
| R15 | `N-away-from/towards/parallel-to R` | Candidate is N from phrase subject and is farther/closer/equidistant to R than subject is. Unnumbered forms omit the N constraint. | Q |
| R16 | `!`, `&`, `\|` | Negation, conjunction, disjunction in conditions; adjacent query terms intersect. Board selector complements include empty tiles. | Q |
| R17 | `up-ACTION` | Numeric deltas for that action's full numeric arity, optionally followed by T/P/F. Does not perform the action. Bash and Bomb-explode are excluded. | Q; V |
| R18 | `is-firing`, etc. | Observable pending relation between actor and chosen target; not a contributable buff. Instant actions also have an ordered pending boundary. | V; R |
| R19 | `atk`, `patk`, `ratk` | Current executable families: atk = Fire/Cannon/Gore-attack/Bash/Bow; patk = Gore-attack/Bash/Bow; ratk = Fire/Cannon. Bomb excluded. Older ambiguity comments are stale for these entries. | V:attackFamilies |
| R20 | Mutation vs observation | Wounded/deployed/active/pending states are observable; effects do not grant them as passive contributions. First-strike/steady/fast/titanium/obsidian can be granted. | V |
| R21 | Life/magic vs events | Continuous contributions are silent. One-time state grants and actions pass through normalized event handling. Do not emit a new event every time effective state is queried. | R; S |
| R22 | Rule order | Runtime sources sort active player's units first, then deck order, then hero preference and identity as tie-breaks; each source retains its rule order. | E:1174 |

## 8. Migration cautions

| Area | Required care |
| --- | --- |
| Delayed victim | Preserve the captured victim-and-tile rule for occupied Fire/Bow targets; fixed-tile-only prose in old docs is insufficient. |
| Geometry | JS uses x-y, Godot x+y. Reflect coordinates consistently before porting regions, direction selectors, or card placements. |
| Counter lifetimes | Permanent and temporary counters are now explicit by user ruling; do not blindly copy deletion of native JS bonus fields onto all counters. |
| Source of truth | Some tests describe older catalogue text (for example River Otter); the catalogue table below records current `cardSources`. This document is an inspection, not a claim that the JS test suite is green. |
| Deferred rules | Listed JS rules are an implementation checklist. Full token flow, movement upgrades, broader trigger scheduling, complete passive/property lifetimes, and catalogue loading require separate ports. |

## 9. Catalogue snapshot

The following table is extracted from every current `cardSources` entry, in source
order. Rules are preserved as authored DSL to avoid changing meaning in a prose
translation. Apply the implicit movement/self-shield/hero-token rules above in
addition to these entries. `enemy` in deployment means a controlled opponent home
region. A dash means no printed passive; it does not mean there are no implicit
rules. This is reference data, not a Godot catalogue import.

Total: **77 cards**. Source line refers to `game/cards.ts`.

| Card | Role | Life | Deployment | Passive | Printed actions and rules | Source line |
| --- | --- | ---: | --- | --- | --- | ---: |
| Queen Bee (`queen-bee`) | hero | 1 | intermediate | — | `move(2)`<br>`bow(3,4)` | 79 |
| Squirrel King (`squirrel-king`) | hero | 4 | starting | — | `fire(1,3)`<br>`self fire _ : up-life(1,0)` | 85 |
| Tiger Queen (`tiger-queen`) | hero | 5 | starting | — | `move(3)` | 92 |
| Wandering Monarch (`wandering-monarch`) | hero | 3 | starting | — | `push(1,2)`<br>`shield(2,1)`<br>`end : move(1)` | 98 |
| Mole Artificer (`mole-artificer`) | hero | 4 | starting | — | `bomb(3,2)`<br>`P.fire(1,2)` | 104 |
| Stag Guardian (`stag-guardian`) | hero | 4 | starting | — | `shield(2,2)`<br>`start : up-life(1,0)` | 111 |
| Raven Prince (`raven-prince`) | hero | 3 | intermediate | — | `fly(3)`<br>`end : stun(1,1)` | 122 |
| Boar Warlord (`boar-warlord`) | hero | 4 | starting | — | `start : move(1)`<br>`self bash _ : self up-mod(1,1)` | 131 |
| Tortoise Emperor (`tortoise-emperor`) | hero | 7 | starting | — | `move(0)`<br>`end : shield(1) all o:you adj self` | 140 |
| Thunder Toad (`thunder-toad`) | troop | 3 | starting | — | `stun(1,1)`<br>`stun _ : up-life(-1,1)` | 149 |
| Bellwing Crane (`bellwing-crane`) | troop | 2 | front | — | `fly(2)`<br>`stun(1,2)`<br>`start : stun(1,1)` | 157 |
| Frosthorn Yak (`frosthorn-yak`) | troop | 4 | starting intermediate | — | `move(0)`<br>`stun(2,1)`<br>`start : pull(2,3)` | 166 |
| Duelist Scorpion (`duelist-scorpion`) | troop | 2 | intermediate | — | `move(2)`<br>`stun(1,1)`<br>`self deploy s:opp : T.shield(3,0) & T.mshield(3,0)` | 171 |
| Needle Peacock (`needle-peacock`) | troop | 1 | intermediate | — | `fly(2)`<br>`P.bow(1,3)`<br>`self wound _ : stun(1) obj` | 180 |
| Iron Bell Golem (`iron-bell-golem`) | troop | 4 | intermediate | titanium | `self deploy _ : self up-mod(0,-3)` | 185 |
| Merino Ram (`merino-ram`) | troop | 3 | starting | — | `move(0)`<br>`gore(3,3)` | 191 |
| Prism Moth (`prism-moth`) | troop | 1 | starting | — | `fly(2)`<br>`F.bow(1,2)`<br>`_ bash self : up-mod(1,1)` | 196 |
| Warding Bat (`warding-bat`) | troop | 1 | front | — | `fly(2)`<br>`start : F.fire(1,1)` | 201 |
| Arcane Viper (`arcane-viper`) | troop | 2 | starting intermediate | — | `fire(2,2)`<br>`fire _ : up-mod(0,1)` | 206 |
| Komodo Dragon (`komodo-dragon`) | troop | 3 | intermediate | — | `shield(3,0)`<br>`mshield(3,0)` | 211 |
| Ironhide Boar Pup (`ironhide-boar-pup`) | troop | 1 | starting | — | `gore(1,3)`<br>`hit _ : up-mod(1,1)` | 216 |
| Needle Mantis (`needle-mantis`) | troop | 2 | intermediate | — | `fly(2)`<br>`P.bow(1,3)` | 221 |
| Deep Ocean Octopus (`deep-ocean-octopus`) | troop | 5 | starting intermediate | — | `move(0)`<br>`pull(3,3)`<br>`_ bash self : up-mod(1,0)` | 226 |
| Thornback Archer (`thornback-archer`) | troop | 3 | front | — | `P.bow(2,2)` | 231 |
| Spellshield Beetle (`spellshield-beetle`) | troop | 2 | starting | obsidian | `bash _ : up-mod(1,0)` | 236 |
| Obsidian Lizard (`obsidian-lizard`) | troop | 2 | front | obsidian | `shield(2,0)` | 242 |
| Battle Magpie (`battle-magpie`) | troop | 1 | front | — | `wound _ : up-mod(1,0)`<br>`fly(2)`<br>`P.bow(1,2)` | 248 |
| Bramble Empress (`bramble-empress`) | troop | 1 | starting intermediate | — | `push(2,1)`<br>`pull(1,3)` | 257 |
| Ember Salamander (`ember-salamander`) | troop | 2 | intermediate | — | `fire(3,2)` | 262 |
| Bombardier Beetle (`bombardier-beetle`) | troop | 2 | intermediate | — | `bomb(2,2)` | 267 |
| Powder Newt (`powder-newt`) | troop | 1 | intermediate | — | `move(2)`<br>`bomb(1,3)` | 272 |
| Firefly Sapper (`firefly-sapper`) | troop | 2 | intermediate | — | `fly(2)`<br>`bomb(1,2)`<br>`fire(1,2)` | 277 |
| Moss Tortoise (`moss-tortoise`) | troop | 1 | intermediate | — | `shield(2,2)` | 282 |
| Steppe Lynx (`steppe-lynx`) | troop | 3 | intermediate | — | `bow(3,1)` | 287 |
| Reed Archer (`reed-archer`) | troop | 1 | intermediate | — | `wound _ : up-bow(1,1)`<br>`bow(1,4)` | 292 |
| Crown Breaker (`crown-breaker`) | troop | 3 | starting intermediate | — | `move(2)`<br>`up-mod(2,0) while bashing o:opp t:hero` | 300 |
| Marching Giant (`marching-giant`) | troop | 5 | starting | — | `move _ : up-life(-1,0)` | 305 |
| Phoenix Moth (`phoenix-moth`) | troop | 2 | intermediate | — | `fly(2)`<br>`self die _ : bow(3,2)` | 310 |
| Pine Processionary (`pine-processionary`) | troop | 1 | starting | — | `move(2)`<br>`self die _ : revive` | 315 |
| Canyon Ibex (`canyon-ibex`) | troop | 1 | intermediate | — | `move(3)`<br>`while bashing : up-mod(2,0)` | 323 |
| Marsh Badger (`marsh-badger`) | troop | 4 | starting intermediate | — | `while shielded : up-mod(-2,0)`<br>`move(2)` | 331 |
| Dune Scorpion (`dune-scorpion`) | troop | 1 | intermediate enemy | — | `bow(1,3)` | 339 |
| Snowy Owl (`snowy-owl`) | troop | 2 | starting | — | `move(2)`<br>`bow(1,3)` | 344 |
| Cave Viper (`cave-viper`) | troop | 2 | front | — | `move(0)`<br>`fire(2,3)` | 349 |
| River Otter (`river-otter`) | troop | 3 | starting | — | `up-mod(1,0) while deployed` | 354 |
| Coastal Heron (`coastal-heron`) | troop | 1 | intermediate | — | `fire(2,3)` | 360 |
| Desert Fox (`desert-fox`) | troop | 2 | intermediate | — | `move(2)`<br>`fire(3,1)` | 365 |
| Iron Armadillo (`iron-armadillo`) | troop | 1 | starting intermediate | — | `shield(3,1)` | 370 |
| Volcanic Gecko (`volcanic-gecko`) | troop | 2 | starting | — | `fire(4,1)` | 375 |
| Highland Hawk (`highland-hawk`) | troop | 2 | starting | — | `bow(1,2)` | 380 |
| Ironscale Rhino (`ironscale-rhino`) | troop | 6 | starting enemy | — | `shield(3,2)` | 385 |
| Sahel Porcupine (`sahel-porcupine`) | troop | 2 | intermediate | — | `bash _ : up-bow(1,1)`<br>`move(2)`<br>`bow(1,1)` | 390 |
| Alps Lone Wolf (`alps-lone-wolf`) | troop | 3 | starting | — | `up-mod(2,0) while wounded`<br>`move(2)` | 399 |
| Canyon Hawk (`canyon-hawk`) | troop | 3 | front | steady | `fly(2)` | 407 |
| Cinder Heron, Rice Farmer (`cinder-heron`) | troop | 2 | starting | — | `fly(3)` | 413 |
| Walnut Crab (`walnut-crab`) | troop | 2 | intermediate | — | `cannon(2,3)`<br>`shield(2,0)` | 419 |
| Coconut Crab (`coconut-crab`) | troop | 1 | starting | — | `cannon(3,3)` | 424 |
| Seaweed Crab (`seaweed-crab`) | troop | 2 | intermediate | — | `cannon(2,4)` | 429 |
| Reed Warden (`reed-warden`) | troop | 2 | intermediate | — | `push(2,1)`<br>`shield(2,0)` | 434 |
| Bramble Scout (`bramble-scout`) | troop | 2 | intermediate | — | `move(2)`<br>`push(1,2)` | 439 |
| Spring Temple (`spring-temple`) | temple | 3 | starting intermediate | — | `move(0)`<br>`mend(1,3)` | 444 |
| Oracle Temple (`oracle-temple`) | temple | 2 | intermediate | — | `upgrade(1,0,1)` | 450 |
| Water Temple (`water-temple`) | temple | 3 | front | — | `upgrade(1,1,2)` | 456 |
| War Temple (`war-temple`) | temple | 3 | intermediate | — | `o:you bashing o:opp have up-mod(1,0)` | 462 |
| Ranged Power Temple (`ranged-power-temple`) | temple | 3 | intermediate enemy | — | `o:you have up-bow(1,0)` | 468 |
| Magic Power Temple (`magic-power-temple`) | temple | 3 | intermediate enemy | — | `o:you have up-fire(1,0)` | 474 |
| Magic Range Temple (`magic-range-temple`) | temple | 3 | intermediate enemy | — | `o:you have up-fire(0,1)` | 480 |
| Ranged Range Temple (`ranged-range-temple`) | temple | 3 | intermediate enemy | — | `o:you have up-bow(0,1)` | 486 |
| Temple of the Last Bell (`temple-last-bell`) | temple | 2 | starting intermediate | — | `self die _ : F.bow(3,3)` | 492 |
| Temple of Marches (`temple-marches`) | temple | 2 | front | — | `o:you have up-move(1)` | 499 |
| Mole Miner (`mole-miner`) | troop | 2 | intermediate | — | `_ bomb-throw adj self : up-mod(0,1)`<br>`move(2)`<br>`bomb(2) p:bomb` | 506 |
| Sentinel Wasp (`sentinel-wasp`) | troop | 1 | intermediate | — | `o:opp atk self : T.bow(1) subj & T.move(1) 1-away-from subj`<br>`move(0)`<br>`P.bow(2,2)` | 516 |
| Jumping Hare (`jumping-hare`) | troop | 2 | starting | — | `move-from c:opp : up-actions(1) you at next-start`<br>`move(3)`<br>`push(1,2)` | 526 |
| White Wolf (`white-wolf`) | troop | 2 | starting | — | `while !active : up-bow(1,1) o:you adj self`<br>`bash _ : up-mod(1,-1)`<br>`A.move o:opp 3-from self` | 536 |
| Pyromaniac Beetle (`pyromaniac-beetle`) | troop | 2 | intermediate front | — | `fire _ : bomb-throw(3) self & bomb-light self`<br>`P.fire(1) p:bomb-off`<br>`while deployed : up-mod(0,2)` | 547 |
| Mountain Goat (`mountain-goat`) | troop | 2 | starting intermediate | — | `move(0)`<br>`T.gore(2) o:opp` | 559 |
| Mole Engineer (`mole-engineer`) | troop | 2 | intermediate | — | `end : T.push(1) p:bomb-off adj self`<br>`start : bomb-defuse self`<br>`T.bomb(3) r:front` | 565 |

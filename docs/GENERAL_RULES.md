# General rules

This is the intended game rulebook and guide for defining effects as objects.
The approved crowned heroes and their exact timing/eligibility are in
[HERO_UNITS.md](HERO_UNITS.md): Grey Squirrel King (5 life), Jerboa King (6), Marmot Queen (6).
Shared concise hover notation and the distinct Mshield icon/animation are specified
in [HOVER_TEXT.md](HOVER_TEXT.md). Friendly targets include every unit type unless
an explicit troop/hero/temple filter says otherwise. Jerboa King: friend is shifted: it has +2/+0 until enemy End. Shifted means a forced position change (currently Push/Pull), excluding Walk/Fly, deployment and Return. The exact friend receives the bonus; expiry follows the king's enemy End.
The approved 2026-10-28 roster and detailed timing/counter rulings are in
[SYNERGY_UNITS.md](SYNERGY_UNITS.md), based on
[MY_28_UNIT_PROPOSALS.md](MY_28_UNIT_PROPOSALS.md).
It describes rules, not the implementation status of every feature. Preserve
explicit differences from the older JS game; open decisions are listed in section 9.

Card examples come from the current [JS catalogue](C:/Users/ciava/Documents/guerra.game/game/cards.ts).
[GUERRA_RULES.md](GUERRA_RULES.md) records the JS behavior and full catalogue.
[SELECTION.md](SELECTION.md) describes the current Godot APIs.

**Effects are authored directly as objects. No text parser is required.**
Card wording explains those objects; it is not executable input.

## 1. The board

| Rule | Description |
| --- | --- |
| 1.1 | The board consists of hexagonal tiles, called **hexes**. |
| 1.2 | Regions are non-overlapping sets of hexes. Every hex belongs to exactly one region. |
| 1.3 | Region labels are **starting**, **intermediate**, and **front**. A label is a region type, not the identity of one particular region. |
| 1.4 | Starting/intermediate regions belong geographically to one player's side. Home side does not change when control changes. |
| 1.5 | A radius of N includes distances 0 through N; “exactly N away” includes only distance N. Distance counts adjacent hex steps. |
| 1.6 | The center gap is not a playable destination. Walking requires a playable path; flying and permitted straight-line attacks may cross the gap. |
| 1.7 | Normally a hex holds one unit. Two opposing units may share it during a pending Bash; they remain separate unit targets. |

## 2. Cards and the army

| Rule | Description |
| --- | --- |
| 2.1 | Cards are **units** or **spells**. Units are permanents; spells are consumed when used. |
| 2.2 | Each player chooses an army of unique cards before the match. The online host selects 8, 12 or 16 cards and an initial pool of 8, 10 or 12 deployments. JS reference formats use 8 or 10 cards. |
| 2.3 | A unit belongs to a player and performs actions through effects. Unit ownership, hex side, and regional control are distinct. |
| 2.4 | Unit labels are **hero**, **troop**, and **temple**. |
| 2.5 | Units have printed life, current maximum life, and actual (current) life. Effects can modify the maximum; actual life cannot exceed that maximum. Reducing maximum life also clamps actual life. Older texts call maximum life “starting life.” |
| 2.6 | Unit states are **undeployed**, **deployed**, **defeated**, and **exiled**. |
| 2.7 | Spell states are **undeployed**, **defeated**, and **exiled**. |
| 2.8 | Every card starts undeployed. |
| 2.9 | The match format specifies a deployment allowance. Each deployment consumes one deployment counter. |
| 2.10 | An army contains exactly one hero. Defeating a player's hero causes that player to lose. Sacrifice is the explicit exception in timing: resolve its causal triggers/consequences first, allowing an explicit rescue; an unrescued hero still loses at settlement. |
| 2.11 | The hero must be its player's first deployed card. |
| 2.12 | A troop has no additional movement restriction beyond its own actions and effects. |
| 2.13 | A temple is immovable: its position cannot change after deployment, including through forced movement. This is stronger than merely lacking Move. |
| 2.14 | Actual life below 1 defeats a unit. Defeat preserves its identity for effects such as Revive. |
| 2.15 | A spell becomes defeated after use. |
| 2.16 | Each card defines deployment targets, usually through region types and additional conditions. Deployment requires a vacant hex in a region the player controls. |
| 2.17 | A card has a collection of action, triggered, continuous, or passive effects. |
| 2.18 | Each deployed unit has an **active** flag. Deployment enters inactive with one Stun counter; deployment spends a player action token, not the unit's activity cost. |
| 2.19 | A defeated card cannot simply deploy again. Revive returns a permitted defeated non-hero card to undeployed; it does not place it on the board. |
| 2.20 | Exiled is distinct from defeated. Return-from-exile and hero-exile outcomes are not yet specified; do not assume Revive applies. |
| 2.21 | During a settled Action window, the active player loses if they have no legal deployment and no legal unit action. Costs, activity, actions and targets must be available. Pending triggers, choices and phase transitions finish before this check. |

## 3. Control, counters, and modifiers

| Rule | Description |
| --- | --- |
| 3.1 | Sum each player's units' actual life within a region, plus printed control contributions and stored control counters. +N control adds N counters to that unit, not a physical modifier. |
| 3.2 | Add 0.5 to that region's home player in starting/intermediate regions. The front has no home bonus. |
| 3.3 | Higher total controls the region; equal totals mean neither player controls it. Deployment requires control. |
| 3.4 | Every unit has a physical and a magical modifier. |
| 3.5 | Every unit implicitly has: “While your player controls this unit's region, this unit has +1 physical.” This is a live contribution, not a counter grant. Implemented through ControlResolver and UnitInfo.modifier. |
| 3.6 | Effects may mutate stored counters or supply continuous contributions. Never double-count one bonus through both mechanisms. |
| 3.7 | Physical modifier = physical + temp_physical counters + live physical contributions. Magical modifier is the equivalent magical sum. |
| 3.8 | Values may be signed. Negative modifiers increase an attack's damage or lethal threshold. |
| 3.9 | Persistent physical/magical counters remain until an effect changes them; attacks do not consume them. |
| 3.10 | Shield/Mshield add temporary physical/magical counters. Contact by the corresponding attack consumes that temporary protection, including zero-damage or piercing contact. |
| 3.11 | Immunity preventing contact preserves temporary protection. Physical attacks do not consume magical protection, or vice versa. |
| 3.12 | Reevaluate control and live bonuses from current board state. Movement, life changes, defeat, and supporting units can change them. |
| 3.13 | Ordinary damage is max(0, attack value − relevant modifier). Fire instead uses the lethal test in 6.13. Read defensive modifiers at resolution. |

| State kind | Meaning | Example |
| --- | --- | --- |
| Persistent counter | Stored number changed once per resolving effect. | +1 physical after each Hit. |
| Temporary counter | Stored number with a defined consumption rule. | Mshield 2 adds 2 to temp_magical. |
| Flag | Stored on/off value. | An explicitly granted Obsidian flag. |
| Continuous contribution | Derived value present only while its condition holds. | +2 physical while wounded. |
| Observable property | A fact that can be tested without changing it. | Active, wounded, deployed, adjacent to a hero. |

Action values have three separate sources: stored counters, timed grants, and
derived continuous contributions. Counters remain until changed; timed grants
expire at a captured cleanup boundary; continuous contributions exist only while
their source and conditions qualify. All add to printed values when an action is
checked or declared.

## 4. Effects

### 4.1 Categories

An effect describes **when it applies, what it requires, and what it does**.
Not every effect has an event or performs an action.

| Category | Parts | Behavior |
| --- | --- | --- |
| Activated | Availability conditions; cost; consequences. | The player chooses to use it in an allowed action window. No triggering event is required. |
| Triggered | Event pattern; optional condition; cost; consequences; optional/mandatory policy. | A matching occurrence creates one execution. Followups run after the triggering event's relevant mutation/resolution boundary. |
| Continuous | Source; condition; recipient selector; contribution. | Applies automatically while its condition holds; no payment or repeated action. |
| Passive property | Property identity; bearer; lifetime or granting condition. | Other rules consult it during relevant operations, such as Steady during Bash. |
| Scheduled consequence | Concrete consequence; captured participants; future player-relative phase. | Registers work now for a later boundary. Execution time and expiration are separate. |

A one-time consequence may perform an action, change life, mutate a counter/flag,
grant a stored contribution, or schedule work. “One-time” means once per execution,
not once per match.

### 4.2 Phrases and references

| Part | Meaning |
| --- | --- |
| Subject | Actor or source of the operation; not necessarily the owner of the effect. |
| Verb | Operation, numeric parameters, supported stickers, accepted subject/target kinds, and legality. |
| Target selector | Rule finding eligible recipients or locations. |
| Target mode | CHOOSE_ONE by default, or ALL when stated. Continuous effects apply to all selected recipients automatically. |
| SELF | Card owning the effect; shared across its cost and consequence executions. |
| SUBJECT / TARGET | Participants chosen for this phrase. They are not global mutable bindings shared by every phrase. |
| EVENT_SUBJECT / EVENT_TARGET | Participants of the triggering event; available throughout this effect execution. |
| Previous result | Named result of an earlier phrase, for dependent consequences. |
| Origin / destination | Captured event coordinates. An origin condition must not accidentally inspect the new location. |

Selectors return typed references. Distance naturally selects hexes; a unit verb
expands those hexes into individual occupants. UnitsOn, HexOf, and PropertyOf
explicitly change domains inside composed selections. A counter/flag is addressed
by its host and key.

### 4.3 Costs and choices

| Rule | Description |
| --- | --- |
| 4.3.1 | A condition reads state; a cost changes it. “Is active” tests eligibility; self-stun pays activity. |
| 4.3.2 | No explicit cost does not necessarily mean free: apply the operation's default unless a sticker removes it. Explicit payment replaces the default. |
| 4.3.3 | Validate the action and complete payment before commitment. Do not partially pay an unaffordable bundle. |
| 4.3.4 | Ask whether to perform an optional effect before paying. Declining does nothing. Paid costs are not automatically refunded after later failure/cancellation. |
| 4.3.5 | CHOOSE_ONE requires a choice, even with one target. A unique subject may be resolved automatically. |
| 4.3.6 | ALL freezes the legal recipient set in deterministic order. New arrivals do not join an already committed occurrence. |
| 4.3.7 | Consequence sequences follow printed order. Each phrase owns its subject/targets and may refer to the original event or named earlier results. |
| 4.3.8 | Recheck legality at application. Do not substitute another target. A sequence is not automatically atomic or simultaneous. |
| 4.3.9 | A pending choice suspends the execution and enclosing phase until answered. |
| 4.3.10 | A triggered action with an activity cost is optional unless mandatory is explicit. Free/Tireless triggered actions are mandatory by default. Mandatory does not bypass legality or make an impossible cost payable. |

Optionality is independent of target count: optional ALL asks once for the set,
not separately for each recipient unless the card explicitly says so.

### 4.4 Events and lifetimes

| Event / timing | Meaning |
| --- | --- |
| Declaration / Target | Commit a legal action to its participants/locations; a delayed attack becomes pending. |
| Attacks | In declaration-trigger wording, the subject starts a Bash or uses Bow, Fire or Cannon. |
| Resolved | Reach the action's resolution boundary. Queueing a delayed attack is not resolution. |
| Hit | Actual attack contact, physical or magical, including zero resulting damage. Cannon and Fire participate; immunity and misses prevent Hit. Bomb blasts remain outside attack families and publish bomb_hit instead. |
| Wound | Positive actual life loss from attack contact, physical or magical. Nonlethal Fire creates Hit without Wound; lethal Fire creates both. Life payments, Reset and ordinary life changes do not invent attack contact. |
| Deploy | Unit enters the board; record it and its destination. |
| Die | A unit dies and becomes defeated; retain its last location and source information. Disable is a distinct hand-to-defeated change and does not emit Die. |
| Start / End | Named player's phase boundary. Your next Start differs from opponent's next Start. |
| Permanent | Remains until explicitly changed/removed. Numeric persistent modifier grants use counters where appropriate. |
| Until event | Contribution expires before that event applies. |
| Removed after event | Contribution participates in the event, then expires before its followups. |
| At a future phase | Capture participants now and execute once at the later matching boundary. |

An event pattern matches an occurrence; it does not execute its verb again.
“After this unit Fires” observes the appropriate Fire boundary without firing
another attack just to test the pattern.

### 4.5 Continuous effects

For the formal interaction rulings on continuous contributions and defeat-trigger
suppression, see [RULINGS.md](RULINGS.md).

The condition is an **observable**: it reads state. The contribution changes
effective state without repeatedly changing stored counters.

| Rule | Description |
| --- | --- |
| 4.5.1 | Printed continuous effects operate while their source is deployed unless another scope is explicit. |
| 4.5.2 | Conditions can test properties, relationships, or any/all/no selector matches, combined through AND, OR, and NOT. |
| 4.5.3 | “While adjacent to a hero, +1 physical” contributes once if any hero is adjacent; not once per hero. |
| 4.5.4 | “Friendly units have +1 physical while bashing” tests the recipient condition separately for every selected friendly unit. |
| 4.5.5 | Different contributions add. Reading the same contribution repeatedly never accumulates another copy. |
| 4.5.6 | Losing the condition, recipient eligibility, or deployed source removes the live contribution. Earlier permanent triggered grants remain. |
| 4.5.7 | Contributions may adjust modifiers, grant passive properties, or change action parameters/stickers. A granted passive is present while at least one valid source supplies it. |
| 4.5.8 | The implicit region-control modifier uses this model and must not also be added separately by combat. |
| 4.5.9 | A timed grant is stored on its concrete recipients and removed at its captured expiry; it is not a counter and is not reselected during reads. |
| 4.5.10 | An end-of-turn grant lasts through End trigger choices and expires before the next player's Start. Source departure does not erase a grant already made. |
| 4.5.11 | Stored action counters, timed action grants, and continuous action contributions add independently to printed parameters. Multiple grants stack and expire independently. |

### 4.6 Card texts expressed through objects

These examples describe the required structures, not parser input. They are
based on the current [card texts](C:/Users/ciava/Documents/guerra.game/game/cards.ts);
some general object interfaces still need implementation.

| Card | Meaning | Required structure |
| --- | --- | --- |
| Alps Lone Wolf | While wounded, +2 physical to itself. | Continuous; Wounded(SELF) condition; SELF recipient; Physical(+2). |
| Crown Breaker | While bashing an enemy hero, +2 physical. | Continuous relationship condition BashingEnemyHero; SELF recipient. |
| War Temple | Friendly units bashing enemies have +1 physical. | Aura with friendly recipients, per-recipient Bash condition, Physical(+1). |
| White Wolf | While inactive, adjacent friendly units gain +1 Bow damage and +1 Bow range. | Source condition NOT Active; friendly adjacency selector; Bow parameter contribution. |
| Pyromaniac Beetle | While deployed, +2 magical to itself. | Continuous Magical(+2); never repeatedly increment a counter. |
| Ironhide Boar Pup | After each Hit by this unit, gain +1 physical and +1 magical. | Hit trigger with actor SELF; persistent counter grants to SELF. |
| Squirrel King | When this unit uses Fire, restore 1 current life to itself, capped at max life. | Fire target-stage declaration trigger with actor SELF; automatic ALL-on-SELF Mend. Heal follows the committed Fire use, without waiting for its attack to resolve (user ruling, 2026-10-19). |
| Marching Giant | After its Move, lose 1 actual life. | Move-resolved trigger; one life-change consequence. |
| Needle Peacock | After Wounding a unit, Stun that wounded unit for 1. | Wound trigger with actor SELF; Stun targets EVENT_TARGET. |
| Tortoise Emperor | At your End, optionally Shield 1 all adjacent friendly units. | Phase trigger; optional costed phrase; friendly adjacency targets; ALL. |
| Prism Moth | After being engaged by an opposing Bash, gain +1 physical/magical. Its Bow is instant. | Bash-occurrence trigger targeting SELF, distinct from Bash-resolved; persistent grants. Separate Bow carries Instant. |
| Sentinel Wasp | After an enemy attack against it, Tireless Bow 1 at that attacker, then Tireless Move 1 away from that attacker. | Attack-family trigger; ordered two-phrase sequence; both preserve EVENT_SUBJECT as target/directional reference. |
| Jumping Hare | Moving from opponent control schedules an extra token at your next Start. | Captured movement-origin condition; scheduled player-resource consequence. |
| Mole Artificer | Piercing Fire 1 within radius 2. | Fire phrase with Pierce; distance selector. |
| Canyon Hawk | Has Steady. | Passive property; no cost, target choice, or repeated action. |

### 4.7 Object model

| Object | Responsibility / current status |
| --- | --- |
| Effect | Reusable cost/event/consequence definition. Exists with single or atomic built-in resource cost bundles and consequence sequences. |
| Phrase / Verb / Selector | Actor, operation, candidates, parameters, target mode. Exist; named verbs own target kinds. |
| EffectExecution | One activation's SELF, event, progress, and prior results. Exists. |
| PhraseExecution | One phrase's chosen actor/targets and pending choices. Exists; shares its parent instead of storing context on selectors. |
| TargetRef | Unit, hex, player, or property identity. Exists. |
| StateModifier | Attached physical/magical contribution with Selector, Condition, or always-on condition. Exists. |
| Condition | Wounded, Boolean combinations, ANY/NONE/nonempty-ALL, property comparisons and explicit event facts exist; broader relationship/recipient conditions remain future work. |
| ContinuousEffect / Contribution | Live modifiers, passive flags, Bow/Fire/Cannon/Move/Fly value grants, and defeat-trigger suppression share typed card-owned contributions. Other action families, lifetimes, and UI provenance remain future work. |
| Sequence / ScheduledConsequence | Ordered consequence phrases exist; captured future-phase work remains future work. |
| ActionStickers | Typed P/F/T/A stickers attach to one action phrase. Timed sticker grants, continuous sticker grants, and scheduled upgrades remain future work. |

Examples using existing APIs:

```gdscript
# Consequence only: the enclosing effect supplies its payment.
var piercing_fire := Effect.ConsequencePhrase.new(
    Selectors.Self.new(),
    Verbs.fire(1, false, true), # amount, instant, pierce
    DistanceSelector.within(2)
)

# Attach only to a unit with this continuous rule.
unit.state_effects.append(StateModifier.adjacent_to_hero())

# One-time persistent magical counter grant.
var magical_grant := Effect.ConsequencePhrase.new(
    Selectors.Self.new(), Verbs.change_counter(1),
    Selectors.PropertyOf.new(Selectors.Self.new(), UnitInfo.MAGICAL_COUNTER)
)
```

### 4.8 Keywords and zone changes

“In hand” means undeployed. Hand and defeated units remain individually selectable
stable identities; an effect's player selector specifies friendly, enemy, explicit
player, or either owner. An unspecified ownership filter does not imply friendly.
Choose one legal unit unless the effect explicitly says all.

| Term | Rule |
| --- | --- |
| **Deploy** | Put a permitted card from hand on a vacant allowed-region hex you control. Spend one deployment and one action; it enters inactive with one Stun. The hero must be your first deployment. |
| **Reset** | Restore the chosen unit's printed life, actions, triggers, statics, passives, deployment regions and control bonus. Remove wounds, counters, upgrades, timed grants and copies. Preserve owner, location, card state and activity. Any unit, including a hero, enemy, self or defeated unit, can be selected unless restricted. |
| **Revive** | Return another friendly defeated non-hero to its owner's hand, inactive at its current full maximum health. Preserve counters, upgrades and abilities. It is not deployment and does not Reset. |
| **Return** | Move a unit to its owner's hand. Revive emits Return, so Return watchers see it. Board Return accepts any deployed unit (including self, heroes or enemies) unless its selector restricts it. Enter hand inactive, preserving owner, health, counters, upgrades and abilities; clear board position and cancel departed Bash encounters. It does not Reset, heal, Deploy, Die or Flee. |
| **Disable** | Choose a unit in hand and change its state to defeated, preserving health, counters and abilities. Clear activity and board position. Ownership is selected by the effect. This emits Disable, not Die or Return; it does not fire death triggers. A disabled hero still loses under the hero-defeat rule. |
| **Copy** | Duplicate one selected action, trigger, static, continuous contribution or passive effect. The donor keeps it; the recipient's future executions bind SELF to the recipient. Do not copy wounds, counters or execution state. Copies remain until Reset; missing required printed resource counters start at zero. |
| **Flee** | A Bash's original defender leaves its hex alive while still deployed, dodging that encounter. Walking or forced movement can cause it. The attacker leaving or the defender dying is not Flee. The attacker is whoever entered the occupied hex, including forced entry. |
| **[A]** | Pay one player action plus written resource costs; no implicit self-Stun. Replaces old C notation. |
| **[S]** | Pay ordinary activity/self-Stun 1 plus written costs; no player action. Requires an active deployed payer and leaves it inactive. |
| **[AS]** | Pay one player action and activity/self-Stun 1, plus written costs. Default for actions with no explicit cost marker; replaces AC notation. |
| **[2S] / [A2S]** | Pay two self-Stun instead of one; A is present only when a player action is also charged. |
| **Sacrifice** | Defeat a chosen deployed friend as payment, emitting ordinary Die and a distinct Sacrifice occurrence. The card selector determines range and SELF eligibility. Heroes qualify: their loss waits for causal triggers/consequences that might explicitly rescue them. A still-defeated or zero-life hero loses at settlement. Paid sacrifices are not refunded after consequence failure. |
| **Ember** | A unit counter: each Ember adds +1 damage to the next declared Fire. Capture the full bonus and consume current Ember before declaration triggers; later Ember belongs to a future Fire. Misses, ignition and immunity do not refund spent Ember. |
| **Projectile** | Stored ammunition spent by the printed action. These cards gain two on their own Deploy, not on Reset; Return preserves existing ammunition. |

Reset does not cause Deploy, Return or Die. Captured triggers and queued attacks
keep their original histories even when their source is Reset or defeated.
A Reset defeated unit stays defeated even though its health is restored. Disable
is a distinct zone change, not lethal damage; no Slash, Wound, Hit or Die is implied.
A Return watcher sees one occurrence per returned unit, not an extra occurrence
for the Revive keyword itself.

### 4.9 Death synergies and player resources

- Wild Rat is a deployed static amplifier. Friendly abilities matching a Die
  occurrence activate one additional time per matching amplifier, with independent
  executions and choices. Capture applies before the casualty leaves play.
  Multiple amplifiers add; they do not create extra Die events. Trigger suppression
  takes precedence. Wild Rat itself has no death ability to repeat.
- Mouse Necromancer's own death grants its owner +2 remaining deployments. It
  does not grant actions, deploy a card, or increase the format's base allowance.
- Rat Dark Mage's own death chooses one unit to Reset. The defeated source can
  still resolve its captured trigger and can be chosen itself.
- Rat Musketeer observes an enemy Die, then chooses another friendly defeated
  non-hero to Revive. Disabling an enemy does not satisfy the death event.
- Rat Thief's Wound chooses one effect from that exact wounded target, including
  a target defeated by the wound. Copy does not remove that target's effect.
- Rat Warrior gains one Soul counter on itself for each friendly Return. Soul
  persists until spent or Reset. Its conversion atomically pays two Soul and normal
  activity, consumes one action, and grants one remaining deployment. An
  unaffordable payment spends nothing; a later consequence failure does not refund.
- Rat Pikeman's physical contribution is X = your remaining deployments minus
  the opponent's. It may be negative; it is derived, never stored as counters and
  never added to regional control strength.
- Rat Swordsman has +1 physical while bashing any enemy. Only its original defender
  fleeing a Bash it initiated grants +1 action at its owner's next Start. The
  bonus survives the Swordsman leaving play, is added to that turn's allowance,
  and is consumed once. Flee is observed from a cancelled encounter; normal
  attack triggers still require successful occurrences.

An action can prevent no-legal-action defeat only if its source, cost and initial
required targets are legal. Include deployment, Tireless and Action-free abilities
under their usual rules. Do not declare defeat during an unpaid preview, pending
choice, trigger acknowledgement, or unfinished turn continuation. Consequence
sequences retain their ordinary ordered execution and later-failure policy.

## 5. Phases

| Phase | Rule |
| --- | --- |
| 5.1 Start | The hero removes one Stun counter from each friendly deployed unit with positive Stun (6.3), then resolve Start effects. This recovery does not activate units. Opponent-relative Start effects belong to the other player's rules. |
| 5.2 Action | Choose and pay for actions; if multiple action tokens are available, stay in the action window while they remain. |
| 5.3 Action-resolve | Resolve an immediate action or declare its delayed attack, then finish followups/choices. This is the detailed step within Action. |
| 5.4 Combat-resolve | Resolve eligible opposing attacks after the response window, then ready Bashes. |
| 5.5 End | Resolve End effects and choices, then automatically activate each inactive deployed unit belonging to the ending player that has no Stun counters. Opposing units are unaffected. Finish the resulting Activate followups; ordinary new Bashes become eligible after an End has passed. |
| 5.6 Next turn | After End and activation followups, clean up expiring turn grants, switch players, and begin Start. Never advance through unresolved choices. |

JS combat ordering is Bow/Gore, Cannon/Bomb, Fire, then ready Bash, preserving
declaration order within each group. Earlier wounds or consumed protection can
change later results.

## 6. Actions

| Rule | Action | Description |
| --- | --- | --- |
| 6.1 | General | Reusable operation with declaration and resolution boundaries, even when immediate. |
| 6.2 | Implicit activity cost | Intended payment: SELF Stun(1) SELF. Paying requires activity, makes the unit inactive, and adds one stun counter. Explicit costs replace defaults; Tireless omits this implicit payment. |
| 6.3 | Stun recovery / activation | At your Start, your hero removes one Stun counter from each friendly deployed unit with positive Stun, including itself; this changes only counters, not activity. At your End, after End effects and choices, automatically activate each of your inactive deployed units with no Stun counters. Emit Activate only for units that actually become active; their followups finish before turn cleanup/switch. This automatic activation does not affect opposing units or remove Stun. |
| 6.4 | Walk / Move(N) | Follow a free adjacent path of at most N steps to a valid destination. Walk and Move name the same operation here. |
| 6.5 | Fly(N) | Reach a valid destination within N, ignoring intermediate occupancy. |
| 6.6 | Movement defaults | Every non-temple has an implicit Walk 1 unless an ordinary Walk/Move or Fly action is explicit. Explicit Move 0 suppresses the default; Fly replaces it. The default is an available action but is hidden from compact hex infos. Triggered movement does not replace an ordinary movement action. No friendly-occupied landing or entry into an existing Bash. Temples cannot move. |
| 6.7 | Damage kinds | Physical: Bash, Bow, Gore attack. Magical: Fire, Cannon, Bomb explosion. Use only the applicable modifier. |
| 6.8 | Delayed attacks | Normally resolve in the following opposing turn's Combat, after its response window. Instant changes timing. Black magic can damage either player. |
| 6.9 | Captured targets | Capture value, origin, destination, controller. JS Bow/Fire also capture an existing victim ID; it must remain at that hex. A replacement is not hit. An initially empty target can catch a later occupant. |
| 6.10 | Bash | Automatic cost-free encounter when entering an enemy hex. If either leaves before resolution, no exchange. Normal damage received is max(0, opponent life + opponent physical − own physical). Equal combat powers defeat both; otherwise stronger survives with the resulting injury. Special properties alter this exchange. |
| 6.11 | Bow(D,R) | Within radius R, deal max(0,D−physical modifier) lasting injury to the valid opposing victim at resolution. |
| 6.12 | Gore(D,R) | Immediately leap along a straight line up to R, ignoring intermediate units; queue D physical damage for opposing units encountered. Enemy landing also creates Bash. Damage precedes range in card parameters. |
| 6.13 | Fire(D,R) | Red magic: within R, defeat the valid opposing victim iff actual life <= D−magical modifier. Otherwise life stays unchanged. |
| 6.14 | Cannon(D,R) | Black magic along a line up to R; each affected occupant of either player takes max(0,D−magical modifier) lasting damage. |
| 6.15 | Bomb-throw(D,R) | Place an inert bomb of value D within R; bombs on the same hex merge damage. Inert bombs do not explode by themselves. |
| 6.16 | Bomb-light / explosion | Fire or an explosion can light a bomb. Fire on a bomb becomes the bomb blast rather than also damaging its occupant with Fire. Blast covers center and adjacent playable hexes, deals black magical damage, and normally waits for the next opposing response. Fresh chain explosions wait for a later window. |
| 6.17 | Bomb-defuse | A pending lit origin returns to unlit, cancelling its whole queued area; preserve its original owner, source, damage and stored Pierce. An already-unlit bomb is removed. Once the blast batch is frozen/resolving it cannot be defused. Triggered Light/Defuse are forced and activity-free in JS, distinct from chosen normal actions. |
| 6.18 | Shield(V,R) / Mshield(V,R) | Add V temporary physical/magical protection to an ally within R. Grants stack; range zero targets the actor. |
| 6.19 | Push(N,R) / Pull(N,R) | Select an aligned target within R and displace it N steps away/toward along the line. Intermediate units/gap do not block; landing must be playable, not its ally or an existing Bash. Enemy landing creates Bash. |
| 6.20 | Bomb displacement | Push/Pull can move bombs. Merging sums damage and preserves piercing if either bomb had it. |
| 6.21 | Stun(N,R) | Makes a hostile recipient inactive and adds N stun counters. The recipient need not be active; that requirement belongs to paying the self-stun cost. Its hero removes one counter at each own Start; once it has no Stun, it activates at its own End after End effects. All other counters, including temporary protection and resource counters, remain intact. Reset is the separate clearing action. |
| 6.22 | Mend(V,R) | Restore up to V actual life to an allied target within R, without exceeding starting life. |
| 6.23 | Upgrade | Adjust a specified action's parameters or supported stickers, not general defensive modifiers. JS temporary Upgrade excludes temples and is consumed on action use/resolution; permanent/continuous updates keep their own lifetimes. |
| 6.24 | Revive | Return a defeated allied non-hero to its current full maximum life in undeployed reserve. Do not deploy it; the death-source rule cannot select itself. |
| 6.25 | Resources | Change a counter, flag, life value, or player's action-token balance. Spending requires sufficient resources; modifier penalties can still be negative. |

## 7. Unit properties

Properties belong to a unit and may be printed, granted, or continuously supplied.
They do not themselves perform actions or pay costs.

| Property | Rule | Interaction |
| --- | --- | --- |
| Steady | In Bash, treat the opponent's entire physical modifier as zero, whether attacking or defending. | Does not zero its bearer's modifier or either life value; never erases persistent counters. Both bearers suppress each other. |
| First Strike | In Bash, attack before retaliation. A defeated opponent cannot retaliate; a survivor uses reduced life and current modifiers. | If both bearers have First Strike, the Bash attacker goes first, matching JS. |
| Fast | Either participant's Fast lets a new Bash enter the creating action's Combat window without waiting through End. | Unit property affecting Bash, distinct from Instant on one action. |
| Titanium | Prevent physical contact/damage against the bearer; it can still deal Bash damage. | Preserve temporary physical protection. JS physical Pierce does not bypass it. Both surviving participants can remain engaged for another window. |
| Obsidian | Prevent ordinary magical contact. | Preserve temporary magical protection; magical Pierce bypasses it. |
| Control contribution | Add the stated amount to regional control strength. | Separate from the +1 physical awarded for standing in a controlled region. |

| Observable property | Meaning |
| --- | --- |
| Active / inactive | Current activity flag. |
| Wounded | Actual life below current starting life. |
| Deployed / undeployed / defeated / exiled | Current card state. |
| Shielded / magically shielded | Corresponding temporary protection; persistent/live modifiers alone are not a shield grant. |
| Bashing / bashed by | Relationship to a pending Bash participant. |
| Firing, bowing, etc. | Pending action interval and its target. |
| Ownership / region / side / control | Match facts used by conditions and selectors. |
| Adjacent / in range | Current spatial relationship unless historical event positions are explicitly requested. |

Observable facts cannot simply be granted as passive buffs: giving a unit
“wounded” means actually changing its life appropriately, not adding a Wounded
sticker.

## 8. Action stickers

A sticker modifies one action definition or granted occurrence, not every action
its unit can perform.

| Sticker | Meaning | What it does not change |
| --- | --- | --- |
| Pierce (P) | Ignore the modifier of that attack's damage kind. Magical Pierce also bypasses Obsidian. | Does not change range, remove payment, cause partial Fire damage, or automatically bypass Titanium. Contact still consumes relevant temporary protection. |
| Instant (F) | Resolve a supported normally delayed attack immediately. | Does not remove costs. Fire keeps its lethal test. |
| Tireless (T) | Omit implicit activity/self-stun payment. | Does not activate the unit, remove existing stun, waive unrelated explicit costs, or remove a player token payment. Other legality still applies. |
| Action-free (A) | Omit ordinary standalone action-token payment. | Does not omit activity/self-stun payment. Can combine with Tireless. |
| Optional / mandatory | Execution policy of a consequence, not a damage modifier. | Independent of CHOOSE_ONE/ALL and Instant. |

Stickers combine where supported. Instant Piercing Fire resolves immediately
against unmodified life but still pays its ordinary cost unless a separate rule
removes/replaces it.

P/F/T/A are typed `ActionSticker` definitions attached to one action phrase.
Action values granted through a counter or continuous rule are parameters, not
stickers. A temporary sticker grant also needs an explicit lifetime; it is not
implied by a numeric action-value grant.

Bash and Bomb explosion are engine consequences, not ordinary upgradable turn
actions. Exceptional Bash behavior comes from Steady, First Strike, and Fast;
do not invent generic P/T/F Bash actions.

## 9. Decisions and implementation gaps

| Topic | Intended rule / outstanding detail |
| --- | --- |
| Activity | Godot uses self-Stun 1 costs and one initial Stun on deployment. Hero recovery removes one friendly Stun at own Start; automatic activation is owner-only at End after effects. This supersedes the previous Start activation rule (user ruling, 2026-10-19). JS uses inactivity timestamps; do not run both recovery systems. |
| Stun side effects | JS clears native protection on Stun. Intended Stun only deactivates and adds Stun; it preserves all other counters, including temporary protection. Use Reset to clear acquired state (user ruling, 2026-10-26). |
| Action tokens | The local format grants its action allowance at each own Start, plus captured one-shot next-turn bonuses. A committed deployment/action spends one token unless Action-free. Allowance size remains format-dependent. |
| Deployments | Preserve the format-dependent allowance; its amount, refills, and exceptions still need specification. |
| Temples | Intended immovability forbids Move, Fly, Gore, and forced displacement. The Godot movement and Push/Pull/Gore validators reject temples. |
| Spells / exile | Not implemented by the current unit-only Godot prototype. Spell payment, exile returns, and hero exile need explicit definitions. |
| Property precedence | Implemented as in JS: Titanium's damage-prevention branch precedes First Strike; if both have First Strike, the Bash attacker goes first. |
| Region control | Implemented: actual life + printed `control_bonus`, with +0.5 for the home player in starting/intermediate regions; ties are neutral. Deployment requires a vacant allowed-region hex under the player's control. The +1 physical contribution is live and derived. |
| Effect objects | Conditions, typed Contributions, Sequences, and P/F/T/A sticker definitions are implemented. General scheduled consequences remain open. No parser. |
| Runtime coverage | Fire, Move/Fly, Mend, hostile Stun, paid/triggered Revive, modifier counters, owner-only StateModifier, and basic phrase execution exist. Other listed mechanics may still require implementation. |

### Current rules and verification

Sections 4.8–4.9 consolidate the 2026-10-23 keyword and rat rulings.
[RAT_SYNERGIES.md](RAT_SYNERGIES.md) lists card stats and execution callers;
[SELECTION.md](SELECTION.md) shows object-authoring examples. The focused
`tests/rat_effects_test.tscn` suite covers these additions. Each newly introduced
or changed effect requires a behavioral regression test; AGENTS.md records the
creation/run policy.

### Life-effect notation
Life-changing phrases use signed current-life delta, heart icon, signed maximum-life delta: for example -1 (heart) +1. Both deltas remain explicit, including zero. These printed effect numbers are neutral, not magenta. This notation is general for life effects; an already-modified maximum in a unit's health display still uses its separate magenta/source-summary convention.

## Woodland additions (2026-10-24)

Life-increase triggers count independently positive, applied current/max changes. Life costs may defeat the payer; paid consequences still resolve. Health gain never implicitly Revives a defeated unit. Zero maximum must be restored before Revive. Upgrade chooses a unit then its numeric activated ability, granting +M/+N to that exact ability until Reset. Flee is one free use of an existing Walk/Fly with normal routes and current range. Wild and species groups are case-insensitive substrings of the unit name, not flags or abilities. Bomb contact includes zero damage but excludes immunity. Wild Mouse pays one action without self-Stun to grant the enemy one next-turn action and gain two Soul; its AC abilities pay self-Stun and one Soul. All bundled resources are preflighted before mutation.

See [WOODLAND_UNITS.md](WOODLAND_UNITS.md) for card wording, interactions, caller maps and focused regression coverage. Tests were added; running them requires a request ending in TEST.

## Wild Return additions (2026-10-26)

An omitted range is unlimited. Adjacent means exactly distance one, including
Marmot and Dormouse Return targets. Porcupine chooses a deployed friendly unit,
one positive stored counter kind and a positive X; flags and derived bonuses do
not qualify. Its AC payments are atomic and its consequences retain paid X.
Flying Squirrel's C replaces ordinary self-Stun 1 with self-Stun 2, costing one
action. Lemming enters with four Stun in total and uses unlimited Instant Fire 1.
Hedgehog's received Hit grants persistent +1 physical/+1 magical, including magical contact under the 2026-10-28 shared Hit/Wound ruling.
Chinchilla's death replacement Returns a friend and deploys its defeated source
there at full current maximum health without ordinary deployment requirements
or resource spending; it emits Deploy and grants +1 deployment again. A source
already recovered cannot perform a second replacement for a doubled death rule.

See [WILD_RETURN_UNITS.md](WILD_RETURN_UNITS.md) for all eight cards, complete
interaction rulings, actual authoring APIs, caller maps and regression coverage.

## Disable additions (2026-10-27)

Wild Mara is a 2-life Intermediate Cannon 2/2 unit. Friendly Disable grants it
permanent +1 Cannon damage; enemy Disable grants it +1 current/+1 maximum life.
Ownership refers to the disabled card, not its actor. Wild Tamia converts one
friendly non-hero hand card into +1 remaining deployment with normal activity
and action costs. Wild Grey Squirrel gives one adjacent friend +1 Bow damage
until End with Action-free, still paying ordinary self-Stun. Permanent Cannon
upgrades use stored counters, while Grey's bonus uses the existing captured
TimedGrant lifetime. See [DISABLE_UNITS.md](DISABLE_UNITS.md) for exact eligibility,
timing, authoring APIs, caller maps and focused regression coverage.

## Adventurer additions (2026-10-29)

The twenty new class/rodent cards are defined in
[ADVENTURER_UNITS.md](ADVENTURER_UNITS.md), including their full rules table.
Porcupine Shaman chooses any two distinct bashing units, even from different
encounters; both are chosen and validated before either returns. Mouse Summoner
may redeploy the same friend it returned on that friend's former hex, preserving
health and paying no extra deployment. Guinea Pig Cleric increases only an
already-present counter type on an adjacent friend, including value zero; it
cannot create a missing type. Merchant's recipient-owned next-Fire Pierce/Instant
is consumed at successful declaration, survives Return/End and clears on Reset.
Jester reacts to a new enemy regional-control transition, not repeated reads.
Scout requires presence on enemy Starting, regardless of who controls it.

Bomb sweep ruling (2026-11-06): the original lit marker stays on its origin during
the response window. At blast resolution, visual copies spread only to neighbours
with contact-capable units or an inert bomb to ignite; empty and non-pierced
Obsidian-only cells receive no copy. Zero-damage contact remains effective.
The ring resolves from the lighting player's geographical side (P1 southwest,
P2 southeast), counterclockwise, with the original center last. The full playable
area remains authoritative, including silent cells. Each finite explosion and its
Slash/Skull/trigger followups settle before the next hex resolves.

## Frontier additions (2026-11-07)

A once-per-turn trigger reserves its occurrence at capture. Later events in
that turn, including ones queued behind it, cannot capture it again. Reset
does not undo that reservation. Positive Ember additions emit one occurrence
per addition regardless of amount. Sacrifice may supply the donor's actual
life at payment to a consequence; later departure effects cannot change X.

Enemy geography and regional control are separate. The Mole Shaman checks
enemy geography for its Revive, while the Mara Merchant may deploy in vacant
enemy-controlled hexes with all other deployment requirements intact.
Compulsory Bash restricts a Walk to legal enemy landings if at least one exists.
It neither forces a command nor changes ordinary path and occupancy rules.
See [Frontier units](FRONTIER_UNITS.md) for the affected cards and timing.

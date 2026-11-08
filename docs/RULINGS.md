# Feral Kingdom rulings

This is the growing rules-reference book for interactions that need a consistent
answer at the table and in the engine. The intended rules are authoritative;
Guerra JS and Forge are implementation/behavior references, not rules authority.
Each entry records the rule, scope, timing, examples, and implementation note.
Open design questions remain in [GENERAL_RULES.md](GENERAL_RULES.md).

## How to use this book

- Read the numbered ruling when a card interaction is unclear.
- Apply its timing and scope to every matching card; do not add card-specific
  engine branches where a shared rule object can express the behavior.
- Update the entry when the user confirms a new ruling. Mark unresolved details
  as open instead of inferring an answer from the legacy JS implementation.
- Use [forge.md](forge.md) for Forge's technical model and source links. MTG
  card text and rulings are analogies only unless separately adopted here.

## FK-1 — Defeat-caused triggers are suppressed by Hushbringer effects

**Status:** Implemented.

**Rule.** While a live Hushbringer-style continuous effect applies to a unit,
that unit's defeat does not cause triggered abilities to fire. This suppresses
the defeated unit's own `die` trigger and other cards' triggers caused by the
same `die` occurrence. It does not undo defeat or suppress unrelated events.

**Timing.** The game publishes the successful `die` event with its unit identity,
last hex, owner, and controller. `RulesRunner.capture_event()` applies the
continuous trigger policy before creating any trigger executions. Previously
captured triggers are not cancelled retroactively. Non-trigger consequences of
defeat remain intact.

**Examples.** A Pine Processionary defeated under the effect does not revive an
ally. Temple of the Last Bell's death reaction to that same defeat is also
suppressed. An unrelated `end` trigger remains eligible.

**Implementation note.** This follows Forge's per-trigger candidate filtering
model for static suppression, while retaining Feral Kingdom's own immutable
event record. The continuous policy is an authored `Contribution` on a
`ContinuousEffect`; it is checked by `RulesRunner` at event capture. See
[Forge notes](forge.md) and [the trigger execution map](M2_EXECUTION.md).

**Boundary.** `Match.defeat()` captures before removing its one defeated unit.
If a future resolver introduces simultaneous multi-unit defeat, it must snapshot
the relevant policy sources for the full batch before the first removal. That
batch behavior is not yet implemented because current defeat resolution is
sequential.

## FK-2 — Continuous “while” and “have” contributions are derived

**Status:** Implemented for modifiers, passive flags, Bow/Fire/Cannon/Move/Fly
parameters, and defeat-trigger policy.

**Rule.** A continuous contribution is present only while its source is live,
its recipient selector includes the queried recipient, and its source/recipient
conditions pass. A “while” condition is evaluated against current state. A
“have” selector exports its contribution to each selected recipient. Repeated
reads do not accumulate state.

**Examples.** “While wounded, +2 physical” can use
`ContinuousEffect.while_self(Condition.Wounded.new(), [...])`. “Your units have
+1/+0 Bow” can use `ContinuousEffect.have(friendly, [Contribution.bow_values(1,
0)])`. “Your units have +1 Fire damage” uses
`Contribution.action_values(&"fire", [1, 0])`. A passive grant uses
`Contribution.passive_flag(&"steady")`.

**Timing.** Modifier, passive, and action-value consumers query current live
state when checking or committing the relevant action. Delayed Bow captures its
effective amount at declaration. Stored counters and permanent upgrades remain
separate from live grants.

**Boundary.** Typed continuous outputs currently include physical/magical
modifiers, passive flags, Bow/Fire/Cannon/Move/Fly value adjustments, and the
FK-1 defeat policy. Continuous action-value adjustments for other families,
contribution provenance in UI, and scheduled future consequences remain future work.

## FK-4 — Action stickers and action-value grant lifetimes

**Status:** Implemented for P/F/T/A action stickers, persistent Bow value counters,
temporary named action-value grants, and live continuous action-value grants.

**Rule.** An action value can come from three distinct sources. A counter is stored
on the recipient and remains until another effect changes it. A timed grant is a
concrete, temporary contribution to its selected recipient and expires at its
captured cleanup boundary. A continuous rule derives a contribution from its live
source, selector, and conditions. All three add to printed action values; none
rewrites the shared action definition.

**Examples.** “+1/+1 Bow counter” adds one to the recipient's persistent Bow damage
and Bow range counters. “+1/+1 Bow until end of turn” stores a timed action-value
grant on each chosen unit. “Your units have +1/+1 Bow” is a live `have` rule; the
bonus vanishes from a recipient as soon as it leaves the selector or the source
stops qualifying.

**Timing.** An end-of-turn grant captures the current active player and turn serial
when its consequence resolves. It remains available through that player's End
trigger choices and is removed after those followups finish, before the opponent's
Start. The concrete recipients are fixed when the grant is made. Source defeat or
leaving an aura does not remove an already-created timed grant. Multiple grants
stack and expire independently. Saving an idle match preserves the grant and its
expiration identity.

**Action stickers.** P (Pierce), F (Instant), T (Tireless), and A (Action-free)
are typed `ActionSticker` definitions attached to one action phrase. P/F affect
the action's resolution; T omits default self-Stun payment; A omits the standalone
player action token. T and A remain independent. Stickers do not become counters
and do not implicitly transfer to other actions. Existing action factories accept
legacy boolean options and record the matching typed definitions.

**Implementation note.** Bow damage/range counters are ordinary unit `Prop`
counters keyed by `bow_damage` and `bow_range`, created when first awarded and
serialized with other properties. `TimedGrant` stores a copied numeric action
contribution and its recipient-specific expiration. `UnitInfo.effective_action_values()`
adds printed values, stored counters, current timed grants, and current continuous
contributions. Continuous reads remain side-effect free. Broader timed grant types
(life, passive flags, and stickers) and UI provenance are still future work.

## FK-3 — Explicit costs, Start recovery, End activation, and temple movement

**Status:** Established project rules.

Preserve the rules in `AGENTS.md` and [GENERAL_RULES.md](GENERAL_RULES.md):
self-Stun activity costs, hero Start Stun recovery, owner End activation, and immovable temples follow the
intended Godot rules even where Guerra JS differs. Consult those documents for
the current full wording; do not infer alternate details from an MTG analogue.

**Activity revision, 2026-10-19.** Normal actions still cost self-Stun 1.
At own Start, the hero removes one counter from each friendly deployed unit
with positive Stun; activity does not change. After own End effects/choices,
automatically activate only that player's inactive deployed units with no Stun.
This never removes Stun or activates opposing units. Emit Activate only on an
inactive-to-active transition; finish captured Activate followups before timed
grant cleanup/player switch. End effects can therefore add Stun and prevent
automatic activation, or remove Stun and make their recipient eligible.

**Example.** A normal action adds one Stun and leaves its actor inactive.
Its current End cannot activate it. The opponent's End does not change it.
Its next own Start removes the counter but leaves it inactive; its next own
End activates it if no intervening effect adds Stun. An already-active unit
stays active and generates no automatic Activate occurrence.

## FK-5 — Implicit default Walk

**Status:** Implemented.

**Rule.** Every non-temple has Walk 1 unless it has an ordinary Walk/Move or Fly
action. An explicit Move 0 suppresses the default. Triggered movement does not
replace the unit's ordinary movement action. Temples remain immovable.

**Timing.** After validating the complete roster, `Match.start_local_match()`
ensures each unit has the default before assigning it a stable army index. Card
definitions with explicit movement retain their authored action, while every
other non-temple receives one default. Invalid rosters are rejected before card
definitions are changed.

**Presentation.** The implicit action is available in the action chooser and is
the default action. Its `Effect.implicit` marker keeps it out of compact hex
action summaries; expanded card details can still show the usable action.

**Implementation note.** `UnitInfo.ensure_implicit_walk()` scans ordinary
phrase/sequence consequences for `move` or `fly`, then appends
`Collection.movement(1)` marked implicit when neither exists. It is safe to call
again and does not inspect trigger definitions.

## FK-6 — Board Return and counter-preserving Stun

**User ruling, 2026-10-26.** Return moves a deployed card to its owner's hand,
inactive, retaining health, counters, upgrades and abilities. The default UNIT
verb allows self, heroes and either owner; selectors restrict individual effects.
Hand and defeated cards are ineligible. Return clears position, cancels departed
Bashes and updates regional control. It emits one `return_to_hand` occurrence,
so Rat Warrior gains one Soul for a friendly Return. It does not emit Die,
Revive, Deploy, Reset or Flee, and returning a hero does not defeat it.

Stun deactivates and adds its requested Stun counters without removing any other
counters, including temporary shields and Soul. This closes the former open
temporary-protection decision. Reset remains the distinct printed-state restore.

## FK-7 — Wild Return cards, variable counter costs and special deployment

**User rulings, 2026-10-26.** Omitted ranges are unlimited. Adjacency is exactly
distance one. Porcupine removes a player-chosen positive X of one positive stored
counter kind from a deployed friendly unit, selected unit → counter kind → X;
flags are not counters. Both harvesting and Soul-to-Stun are AC actions. Full
payment is atomic, and X is the captured paid amount across followups.

Lemming's own Deploy adds three Stun beyond the normal one (four total); its
unlimited Fire 1 is Instant. Flying Squirrel's C replaces normal self-Stun with
two, while retaining the one-action payment. Chinchilla bypasses ordinary
deployment rules after its own death by Returning a friend and deploying itself
on that card's former hex; its own Deploy grants +1 remaining deployment again.

The complete card text, replacement edge cases, eligibility and implemented
caller map are maintained in [WILD_RETURN_UNITS.md](WILD_RETURN_UNITS.md).

## FK-8 — Disable engines and temporary adjacent Bow support

**2026-10-27.** Mara's friendly/enemy Disable triggers classify the disabled
recipient, not the actor causing Disable. Friendly Disable grants permanent
Cannon damage counters; enemy Disable grants actual +1 current/+1 maximum life,
including ordinary life-increase followups. Disable is not Die or Return.
Tamia pays normal activity/action to disable a non-hero friend in hand, then
gain one deployment; temples qualify, heroes do not. Grey Squirrel's adjacent
Bow grant is Action-free but still costs activity. It expires after the captured
current player's End followups and survives source departure until that cleanup.
Full card text, lifetime details, APIs and callers are in
[DISABLE_UNITS.md](DISABLE_UNITS.md).

## FK-9 — Approved synergy roster, costs and shared contact

**2026-10-28.** [MY_28_UNIT_PROPOSALS.md](MY_28_UNIT_PROPOSALS.md) supersedes
the earlier proposal. [A] spends an action, [S] pays self-Stun, [AS] pays both,
and [2S] pays two self-Stun without an action. Unmarked actions default to [AS].
Triggered consequences do not acquire implicit A or S costs.

Hit includes magical as well as physical contact. Wound means positive attack
life loss of either kind. Nonlethal Fire is Hit without Wound; lethal Fire emits
both. Immunity/misses emit neither. Existing Hit/Wound watchers participate in
these shared events; bomb_hit remains a separate occurrence.

Control counters contribute once to region strength. Ember increases the next
declared Fire and is consumed at capture. Projectiles are stored ammunition.
Sentinel suppresses all watchers of an adjacent unit's Deploy, regardless of
either owner's identity; it does not cancel deployment costs or entry Stun.

Sacrifice defeats a selected deployed friend as an atomic cost. Ordinary Die and
distinct Sacrifice followups finish before consequences. Paladin can Revive the
sacrificed identity under normal non-hero/other-than-SELF eligibility. The approved
text adds no once-per-turn cap or implicit non-hero Sacrifice restriction.
The user confirmed heroes may be sacrificed and rescued by other Sacrifice
triggers. Their loss remains provisional until causal work finishes. Explicit
recovery can save them; restoring health while leaving the hero defeated cannot.
Ordinary combat/Disable hero losses and Revive's non-hero restriction are unchanged.

Pikeman supplies a live +1 action allowance while bashing. Spending is tracked
separately so Bash entry/exit cannot refill spent actions. Courier transfers up
to two counters of one selected kind between different deployed units of either
owner within 2, conserving their sum. Transfer changes counters, not activity,
and does not perform hostile Stun. Blue Mage reads pre-action Stun and awards a
raw counter without recursively emitting another Stun action.

Complete card text, interpretation notes, caller map and regression scene are in
[SYNERGY_UNITS.md](SYNERGY_UNITS.md).

## FK-10 — Adventurers, two-participant Return and existing counter grants

Confirmed 2026-10-29: Shaman chooses any two distinct bashing units, including
different encounters. Collect both choices before either Return; revalidate both
before mutation. Summoner may redeploy the friend just returned, retaining the
paid cost's historical hex and preserving health/counters. Cleric increases only
an existing adjacent friendly counter kind, including zero, and cannot create a
missing kind or choose a FLAG. Its effect text states this explicitly.

Warlock's paid [3S] command may Revive the friendly non-hero hand card just
disabled, even if no friend was defeated before payment. Revive recipient
eligibility is the same for paid commands and captured triggers: friendly,
defeated, positive maximum life, non-hero, and a different identity from SELF.
Disable does not emit Die; Revive still emits Return. Availability explores the
chosen cost-created recipient without committing the Disable in its preview.

Merchant P/F grants belong to the recipient's next successful Fire declaration,
combine on that Fire, persist through Return/End, and clear on use/Reset. Failed
declarations preserve them. Alchemist earns one Soul per positive friendly
deployed Ember addition, not per Ember; enemy/zero/removal cases do not trigger.
Jester captures one actual newly enemy-owned transition for its current region;
repeated refresh and unrelated regions do not trigger. Scout's action bonus is
geographical and uses the spent-action ledger. See
[ADVENTURER_UNITS.md](ADVENTURER_UNITS.md) for full definitions and caller maps.

## FK-11 — Crowned hero support and sacrifice range

Grey Squirrel King's Supply creates one Projectile on an adjacent friend of any
unit type without granting an attack. Its +1 physical aura reads current ammunition
and disappears when the final Projectile is spent. Friends include heroes/temples.
Jerboa King's enemy-only Push follows normal displacement legality; its revised
Shifted support grants the exact displaced friend +2/+0 until the king's enemy End. Shifted means a successful forced position change, currently Push/Pull; Walk/Fly, deployment, Return and failed displacement do not trigger it. Repeated shifts refresh the same source/recipient grant. Own-turn awards survive own End and expire after the next enemy End followups; enemy-turn awards expire after that enemy End. Grants survive source departure and persist as typed recipient-bound timed contributions.
Marmot Queen's free sacrifice reward reads the friendly victim's captured departure
hex within two, excludes SELF, and does not trigger on ordinary Die. Shield/Mshield
are consumed temporary counters. Her healing excludes SELF; her wounded-source
aura applies to adjacent friends of every unit type and ends at full life or source
departure. See [HERO_UNITS.md](HERO_UNITS.md) for full card texts and callers.

## FK-12 — Global Guardian thresholds

Grey Squirrel Guardian's Bow +1/+0 and Beaver Guardian's +0/+1 apply to all
deployed friends with physical modifier at least +3, including their own identity
if eligible, without adjacency. Shield remains a separate costed range-one action.
Dropping below threshold or leaving deployment removes support immediately;
enemies remain ineligible. Existing physical-axis evaluation prevents the magical
reward from recursively qualifying itself. See [SYNERGY_UNITS.md](SYNERGY_UNITS.md).

## FK-13 — Banner Bash support and cost notation

Jerboa Banner Bearer now grants +1/+0 to adjacent bashing friends without a
forced-movement or turn-history requirement. The exact friendly participant,
adjacency and unresolved Bash remain required. Other listed adventurer/synergy
abilities retain their rules and payments. Player-visible Tireless/T is replaced
by the existing independent [A]/[S]/[AS] cost notation; engine exemptions remain
unchanged. See [HOVER_TEXT.md](HOVER_TEXT.md) for the shared wording and Blue Mage,
Jester, Disable and Defeat explanations.

## Future entries

Online identity enforcement (2026-11-05): the host applies the existing rules to
both players' commands and choices. A guest may control only its own active
units or its own captured-trigger choices. Trigger acknowledgement is per
relay-authenticated seat and per gate epoch, so delayed input cannot acknowledge
a later trigger by the same unit. Transport receipts do not execute actions.
Paid-cost consequences that fail still produce an accepted replicated engine
transition; the existing no-refund ruling remains unchanged. See
[MULTIPLAYER.md](MULTIPLAYER.md).

Use the FK-N format above for simultaneous combat, copied/redirected events,
replacement effects, control ties, and other interactions as they are decided.

Region membership correction (2026-10-20): the left intermediate triangle is six hexes, not only the three x+y=0 diagonal hexes. After excluding the left starting region, classify all remaining x<0/y>0 hexes together. This restores the intended non-overlapping six-hex regions without changing strength rules or snapshot hex IDs.

**2026-10-26 Beaver correction.** After moving, Wild Beaver automatically leaves
Bomb 2 on the movement event's captured former hex, regardless of region. It no
longer chooses an arbitrary Starting hex. This uses historical origin data,
without changing ordinary Bomb placement/merging or detonation rules.

Marmot Berserker's printed Walk onto an enemy within two costs [S]: deactivate
and add one self-Stun, without spending a player action. Normal movement and
enemy-destination restrictions remain; its separate Shield action still costs [AS].

Bomb presentation/order revision (2026-11-06): lighting retains one lit origin
until the response window. Spread begins when the Cannon/Bomb batch is frozen,
before its first resolution callback. Copies use then-current contact eligibility
or chain-bomb presence; they are presentation only. The lighting owner determines
the ring start (P1 southwest, P2 southeast), not the thrower's owner/source position.
The sweep is counterclockwise, center last, and preserves silent area resolutions.

Lit Defuse ruling (2026-11-06): during the pending response window, Defuse at the
lit origin restores the original unlit bomb and retires every queued area record
without contact, damage, explosion or chain events. It preserves the bomb's stored
damage, Pierce, original owner and source; these differ from the lighting attack's
owner/Pierce. Normal Defuse ownership/range/activity rules still apply. Neighbour
blast hexes and frozen/resolving batches cannot be defused. Defuse of an already
unlit bomb still removes it. If another inert bomb has since been placed at the
origin, restoration merges using ordinary same-hex damage/Pierce rules.

## FK-14 — Frontier trigger, movement and deployment interactions

- Reserve Lemming Wizard's turn at capture. Only a positive Ember award on a
  different friendly deployed unit qualifies.
- Mole Alchemist reads the actual life immediately before the paid Sacrifice.
  Flying Squirrel Thief reads the captured +1/+1 change and grants deployment
  before resolving Revive, even if no card can be revived.
- Rat Hunter checks positive stored Projectiles on the friendly actor when
  they start Bash or declare Bow, Fire or Cannon. Its one-step retreat must
  increase distance from that actor.
- Guinea Pig Berserker earns Soul on its own Bash declaration and retains the
  paid X through the Walk and modifier grant. The latter expires at enemy End.
- Mara Merchant allows enemy control, never neutral control. Red Squirrel
  Paladin pays self-Stun and Shield on the opposing deployed hero before
  shielding its selected friendly Bash participant.
- Jerboa Pirate's Walk requires a reachable Bash destination when one exists.
  The live bonus changes only other friends' Walk range.

See [Frontier units](FRONTIER_UNITS.md) for the caller map and card examples.

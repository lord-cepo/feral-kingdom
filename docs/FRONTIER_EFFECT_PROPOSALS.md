# Nine card proposals for the Frontier sprites

This is the original design brief and balance rationale. The revised live card
texts, deployment values and timing decisions are in the second batch of the
[current Frontier roster](FRONTIER_UNITS.md#second-batch).

**Notation.** S, I and F in the deployment column mean Starting, Intermediate
and Front. Normal control and vacancy rules apply. **[AS]** costs one player
action and self-Stun 1. **[Free]** pays neither. For attacks and protection,
`value/range` lists the value first. Adjacent means exactly one hex. A turn cap
resets on each player switch unless the card specifies **your turn**. Capped
triggers reserve the use at capture, even if the player declines or the
consequence later loses its legal target.

| Troop | Life | Deploy | Role | First-pass power |
| --- | ---: | --- | --- | --- | --- |
| Beaver Bard | 2 | I/F | Launches infantry charges | Medium, formation-dependent |
| Chinchilla Druid | 2 | I/F | Keeps wounded troops contesting regions | Medium, high in a close control fight |
| Dormouse Bard | 1 | I | Keeps a formation intact through Return | Medium, setup-dependent |
| Guinea Pig Jester | 2 | I | Draws a shot and slips away | Medium, matchup-dependent |
| Hedgehog Cleric | 3 | S | Turns physical protection into recovery | Medium, defensive |
| Hedgehog Musketeer | 2 | F | Shoots through its own line to support a later Bash | Medium, costly setup |
| Lemming Monk | 2 | S/I | Helps heavily stunned troops get back into play | Low to medium, matchup-dependent |
| Mara Witch | 2 | I | Converts reserve cards into Fire pressure | Medium, high in a Disable deck |
| Otter Blacksmith | 3 | I | Turns spare armor into ammunition | Medium, strong with repeatable resupply |

## 1. Beaver Bard — lead the charge

- **[AS]** Walk 2.
- **[AS]** Push 1/2.
- **[Free] Rally.** On your turn, the first time another friendly troop starts
  a Bash by Walking or Flying from a hex adjacent to Beaver Bard, that attacker
  gains **+1 physical through the next enemy End**. Check adjacency at the
  move's origin. A Push, Pull, deployment or Gore does not count.

**Timing.** The attacker gets the bonus before combat, even with Fast. In a
normal Bash, it lasts into the opponent's response turn and through the Bash
window before their End. It applies to incoming Bow or Gore in that window as
well. Once granted, it stays with the attacker if the Bard moves or dies.

**Power.** Jerboa Banner Bearer gives adjacent bashing allies a live +1
physical and can support more than one. The Bard can launch a troop that ends
up out of formation, but buffs only one charge and needs the troop to start
beside it. Jerboa Pirate is a natural lead attacker. Jerboa King still gives a
larger +2 physical for displacement, so keep Rally exclusive to Walk and Fly.
If the Bard makes Fast charges too reliable, narrow deployment to Intermediate
before reducing the one-point reward. [Synergy roster](SYNERGY_UNITS.md)
[Crowned heroes](HERO_UNITS.md) [Frontier roster](FRONTIER_UNITS.md)

## 2. Chinchilla Druid — hold contested ground

- **[AS]** Walk 2.
- **[AS]** Mend 1/1 to another wounded friendly troop.
- **Continuous · Deep Roots.** Each other wounded friendly troop in the
  Druid's geographical region contributes **+1 regional strength** while the
  Druid is deployed there. The bonus follows current wounds and position.

**Timing.** This is a live control contribution. At a neutral Front region
with strength tied at 4–4 before Deep Roots, one eligible troop makes it 5–4.
If that troop heals its last missing life, the extra life replaces the lost
contribution one-for-one. The normal +1 physical for owning the region is
derived separately. Crossing a regional boundary can break the effect even
when the troops stay adjacent.

**Power.** Lemming Healer has longer-range Mend and earlier deployment. Mara
Merchant provides +3 printed control from one body and can enter
enemy-controlled regions. The Druid needs allies already on the board and
wounded, but makes it harder to dislodge several of them. This is the best
candidate for a dedicated control army. If contested regions become too hard
to flip, cap Deep Roots at **+2 total strength** per Druid. [Adventurer roster](ADVENTURER_UNITS.md)
[Frontier roster](FRONTIER_UNITS.md)

## 3. Dormouse Bard — cover the retreat

- **[AS]** Walk 2.
- **[AS]** Return another adjacent friendly troop to hand.
- **[Free, optional] Relief Step.** The first time each turn another friendly
  troop Returns from within 2 hexes of Dormouse Bard, choose a different
  deployed friendly troop adjacent to the vacated hex, excluding the Bard.
  That troop may Walk 1 into the vacated hex if it is still empty. Use the
  returned troop's recorded departure hex. Apply normal Walk restrictions.

**Timing.** The step happens after Return and before the suspended action or
phase continues. It is free even for an inactive replacement, and it never
starts a Bash. If a Mouse Summoner fills the hex within the same operation, or
an enemy stays on it after a shared Bash, the step has no legal landing.

**Power.** Wild Marmot already offers the same Walk and adjacent Return on a
2-life Starting body. The 1-life Bard gives up that durability and early
deployment for immediate board coverage. This supports Rat Warrior's Return
engine without granting a second deployment refund. The strongest use is
rescuing a wounded troop while keeping the next attacker out of the gap. If
moving an inactive relief troop proves too efficient, require it to be active
at the time of the step. [Wild Return roster](WILD_RETURN_UNITS.md)
[Rat synergies](RAT_SYNERGIES.md) [Adventurer roster](ADVENTURER_UNITS.md)

## 4. Guinea Pig Jester — bait the shot

- **[AS]** Walk 2.
- **[AS]** Bow 1/2.
- **[Free]** On own Deploy, gain **1 Soul**.
- **[Optional] Slip Away.** On the first eligible enemy **delayed** Bow or Fire
  declaration targeting this exact Jester each turn, spend **1 Soul** from the
  Jester to Walk 1 to a legal vacant hex. No player action or self-Stun. The
  trigger requires a payable Soul and an available exit.

**Timing.** The escape happens at declaration, so the queued attack keeps
the original victim and hex. It misses if the Jester is elsewhere at impact.
If the Jester is forced back before then, it can be hit. Empty-hex declarations,
Instant attacks, Cannon and Bash give no escape trigger. Declining saves the
Soul. Soul supplies from Jerboa Courier can buy another escape on a later turn.

**Power.** Wild Jerboa can Return an incoming Bash attacker. The Jester
answers fewer situations per deployment unless resupplied, and spends a
resource instead of displacing the attacker. Compared with Jerboa Jester's
Instant Bow 2/2 on a control swing, this Jester gives up burst for personal
safety. Keep the dodge self-only and one hex. Opponents can block exits or
attack the formation with Cannon. [Wild Return roster](WILD_RETURN_UNITS.md)
[Adventurer roster](ADVENTURER_UNITS.md) [Synergy roster](SYNERGY_UNITS.md)

## 5. Hedgehog Cleric — mend behind the shield

- **[AS]** Walk 1.
- **[AS]** Shield 2/1 to a friendly deployed unit, including self.
- **[Free] Field Dressing.** The first time each turn another adjacent
  friendly troop survives enemy Bow or Gore contact that consumes positive
  temporary physical protection, Mend 1 to that exact troop. Only capture
  when it is wounded after contact, including a zero-damage Hit on a troop
  that was already wounded.

**Timing.** Apply the heal after the shield is spent and the injury is known.
An ally at 2 of 3 life can take a shielded zero-damage Hit and return to 3.
Lethal contact, Titanium, magical attacks and Bash do not qualify. The heal
never raises maximum life or restores the consumed shield. It can affect a
later attack in the same combat window if the runner finishes this followup
first.

**Power.** Beaver Guardian shields for 3 and supplies a global magical bonus
to high-physical allies. The Cleric offers smaller immediate protection and
gets its extra point only if an enemy contacts the right ally and leaves it
alive. Wild Hedgehog grows permanently on contact. The Cleric instead helps
keep another body in play. If repeat shielding stalls combat, restrict the
trigger to contact that also Wounds. [Synergy roster](SYNERGY_UNITS.md)
[Wild Return roster](WILD_RETURN_UNITS.md)

## 6. Hedgehog Musketeer — fire through the line

- **[AS]** Walk 1.
- **[Free]** On own Deploy, gain **2 Projectiles**.
- **[AS] + 1 Projectile** from this troop to use Cannon 2/3.
- **[Free] Brace for Impact.** The first time each turn this troop's Cannon
  Wounds another friendly troop that survives the contact, give that exact
  troop **Shield 2**. A friendly unit fully protected from the Cannon takes
  no Wound and receives no Shield.

**Timing.** Ammunition is paid at declaration. The reward follows the
resolved friendly Wound, which can occur on the opponent's turn. For example,
a friendly bashing troop with magical +1 loses one life to Cannon 2 and then
gains Shield 2 before the later Bash. In that exchange, the troop loses one
life but adds two points of physical protection. Fire still sees the lower
life total. If multiple friends qualify, only the first in the Cannon's
resolution order earns Shield.

**Power.** Grey Squirrel Musketeer hits harder at Cannon 3/3 and refunds
ammunition on friendly Wounds. Jerboa Cannoneer needs no ammunition and
converts friendly Wounds into Ember. The Hedgehog gives a Bash formation a
reason to risk friendly fire, and the Otter can keep the gun loaded. If it
becomes a generic Cannon pick with incidental upside, restrict the Shield
recipient to a troop already in Bash. [Synergy roster](SYNERGY_UNITS.md)
[Combat and phase rules](GENERAL_RULES.md#5-phases)

## 7. Lemming Monk — clear the last Stun

- **[AS]** Walk 2.
- **[AS]** Remove **1 Stun** from another adjacent inactive friendly troop
  that has positive Stun. The Monk pays the self-Stun. The target's activity
  and other counters stay as they were.
- **[Free] Steady Breath.** At your End, the first time another adjacent
  friendly troop becomes active in the automatic activation pass, give that
  troop **Mshield 2**. No trigger for an already active troop or for merely
  removing Stun.

**Timing.** A troop with 2 Stun before Start drops to 1. The Monk clears the
last counter in Action, letting it activate at this End rather than a later
one. It still misses this Action window. The Mshield arrives too late for
combat that already happened this turn, but persists into later combat
until consumed or cleared. The Monk can grant it while inactive.

**Power.** Grey Squirrel Naturalist's Reset can clear more state at once.
The Monk's narrower intervention preserves ammo, Ember, shields and upgrades.
This is most valuable against hostile Stun or beside a troop like Tamia Knight
that enters with extra Stun. If it only sees play in those matchups, extend
the command's range to 2 while keeping the trigger adjacent. [Synergy roster](SYNERGY_UNITS.md)
[Activity ruling](RULINGS.md#fk-3--explicit-costs-start-recovery-end-activation-and-temple-movement)

## 8. Mara Witch — burn the reserve

- **[AS]** Walk 1.
- **[AS]** Fire 1/3.
- **[AS] Ash Offering.** Disable one friendly troop in hand, then choose
  another deployed friendly troop with a printed Fire action within 2 and
  give it **2 Ember**. Both steps need an eligible target when the command
  starts. The Disable is the first consequence. If the second step later
  loses all legal recipients, the card stays Disabled.

**Timing.** Ember waits for the chosen troop's next Fire declaration and
can therefore help an inactive recipient. Fire 1 becomes Fire 3 before any
other bonuses. Ember does not improve a Fire already queued, and Reset can
clear it before use. Disable triggers Wild Mara's friendly-Disable Cannon
upgrade. The Ember gain can also feed a separate Lemming Wizard.

**Power.** Mole Alchemist can harvest more than two Ember, but pays with a
deployed body and loads itself. Dormouse Witch buys permanent Fire damage
one point at a time. Mara Witch trades an unused reserve card for a faster,
one-shot spike on another Fire user. In a deck with easy Revive and Wild
Mara, test whether the lost reserve card feels like a real cost. If the
package makes both Cannon and Fire scale too cheaply, drop the reward to
**1 Ember**. [Frontier roster](FRONTIER_UNITS.md) [Adventurer roster](ADVENTURER_UNITS.md)
[Disable roster](DISABLE_UNITS.md)

## 9. Otter Blacksmith — reforge the armor

- **[AS]** Walk 1.
- **[AS]** Shield 2/0.
- **[AS] + 1 stored temporary physical protection** from this troop to grant
  **2 Projectiles** to another adjacent deployed friendly troop with a
  printed Bow or Cannon that explicitly spends Projectiles. Pay from the
  temporary physical counter. Permanent physical, auras, regional bonuses
  and Mshield cannot pay. This spending does not count as contact.

**Timing.** The Otter can build its own payment or receive Shield from a
friend, but self-Shield and forging both require the Otter to be active.
It normally cannot do both in the same Action window. Protection can be
consumed by an opponent before it is forged. The ammunition persists until
spent or cleared, so the recipient can be inactive when loaded. The cost
spends only one point and does not discard any remainder.

**Power.** Grey Squirrel King supplies one Projectile without spending armor
and also buffs loaded adjacent allies. The Otter supplies two shots per
successful forge, but pays in position, an action and stored defense. It
leaves Tamia Crossbowman and other Bow users without a printed Projectile
cost outside its recipient pool. Test the Grey Squirrel Crossbowman first.
If two shots of Bow 4/2 make the exchange too favorable with a Guardian
feeding shields, reduce the grant to **1 Projectile**. [Crowned heroes](HERO_UNITS.md)
[Synergy roster](SYNERGY_UNITS.md)

## What to prototype and measure

**Start with the Hedgehog Musketeer, Dormouse Bard and Chinchilla Druid.**
They test three different decisions. Shoot through your own formation, take
a troop off the board without losing the position, or commit wounded troops
to a control fight. Add the Otter after the Musketeer has a baseline, so
ammunition supply and the Cannon payoff can be judged separately. The Lemming
Monk needs a matchup with meaningful Stun pressure before its floor is clear.

- **Compare at the same job.** Swap one proposed card for its closest live
  counterpart in the same army. Track useful triggers per match, paid actions,
  how often the source was ready, and whether the payoff changed combat,
  deployment or a hero threat. Try the card first without its ideal partner,
  then with the best available partner.
- **Check the first legal use.** A damage or range upgrade has to survive to
  declaration. If a recipient paid self-Stun this turn, a grant through this
  End is usually wasted on its ordinary action. Use a stored next-use resource,
  a live aura, or an expiry that reaches the actual use window. A queued attack
  already has its value. A defensive grant instead needs to arrive before the
  relevant contact. [Rules on action grants](RULINGS.md#fk-4--action-stickers-and-action-value-grant-lifetimes)
- **Watch the repeatable pairings.** Try Ash Offering with Wild Mara and a
  Revive source, Forging with Beaver Guardian and Grey Squirrel Crossbowman,
  and Rally with Jerboa Pirate. Also try each against opponents who spread
  out, pressure the support body, deny a retreat hex or withhold the contact
  that would trigger a payoff.
- **Keep the new rules small.** Compose typed selectors, conditions, costs
  and sequences from the existing objects. Deep Roots needs a proposed
  read-only control contribution that never queries current regional ownership.
  Field Dressing needs the consumed shield amount captured on physical contact
  before the counter is cleared. Rally can use the resolved Walk/Fly origin
  and may need an explicit link to the Bash the move started. Slip Away can
  use the captured victim ID, with an Instant flag added to the Bow declaration
  details to match Fire. Relief Step uses the recorded departure hex. Give
  each approved signature a focused result, ownership and non-trigger
  regression when implementing it. [Selection and execution guide](SELECTION.md)

## Borrowing from other turn-based games

Sample patterns from games such as *Magic: The Gathering*. A build-around
should have enough partners to make a deck and a payoff that advances a win.
Panharmonicon is a good reference for building around a familiar event with
many different beneficiaries. Dormouse Bard uses that design idea for Return,
with a single positional payoff. Mara Witch uses the familiar sacrifice-style
trade of giving up one resource to fuel another, adapted to the reserve and
Disable rules. Compare designs with and without their best partners before
adjusting their numbers. [Wizards on build-arounds](https://magic.wizards.com/en/news/making-magic/odds-and-ends-kaladesh-part-1)
[Wizards on playtesting](https://magic.wizards.com/en/news/making-magic/playtesting)

When a borrowed mechanic arrives here, reprice it in actions, self-Stun,
position and deployment access. A Return payoff should care about the hex that
opened. An ammunition payoff should care about the next legal shot. Forge is a
technical reference for separating triggers, activated abilities and continuous
rules. The card definitions here use the existing typed GDScript objects.
[Forge notes](forge.md) [Forge card scripting reference](https://github.com/Card-Forge/forge/wiki/Card-scripting-API)

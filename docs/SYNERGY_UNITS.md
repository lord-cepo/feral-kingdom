# Approved 28-unit synergy roster

The later approved crowned hero support package is documented separately in
[HERO_UNITS.md](HERO_UNITS.md); it adds Grey Squirrel King, Jerboa King and Marmot
Queen to both inventories without changing this 28-card block.

Guardian revision (2026-11-05): Grey Squirrel Guardian and Beaver Guardian now
support every deployed friend with physical modifier at least +3, at any distance,
including SELF when eligible. Their separate Shield actions remain range 1 (2
Shield 1 and 3 Shield 1 respectively). The physical test includes stored,
temporary and live physical bonuses; the Bow/magical rewards never qualify their
own condition. Enemy, off-board and below-threshold units receive neither bonus.
Focused result/eligibility/non-trigger coverage is updated in `test_guardians()`.
Earlier adjacency descriptions of these two auras are superseded by this revision.

Implemented from [MY_28_UNIT_PROPOSALS.md](MY_28_UNIT_PROPOSALS.md), including
the updated Jerboa Soldier, on 2026-10-28. That is the user's authored card
specification. [NEW_28_UNIT_PROPOSALS.md](NEW_28_UNIT_PROPOSALS.md) is the earlier
proposal and does not override it.

All 28 definitions are direct objects in
[`SynergyCatalogue`](../scripts/catalogue/synergy_catalogue.gd), with helpers in
[`SynergyRules`](../scripts/effects/synergy_rules.gd) and
[`SynergyActions`](../scripts/effects/synergy_actions.gd). No parser is used.
Both owners append after the old 70-unit roster prefix: each player now has 63
sprite-backed cards, and the full reference catalogue has 80 definitions.

## Costs and triggers

| Marker | Payment |
| --- | --- |
| [A] | One player action plus written costs; no implicit self-Stun. |
| [S] | Active payer becomes inactive and gains one Stun, plus written costs; no player action. |
| [AS] | Both payments plus written costs; default for unmarked actions. |
| [2S] | Two self-Stun, no player action. |
| [A2S] | Two self-Stun and one player action; the existing Flying Squirrel keeps this cost. |

Old C/AC presentation becomes A/AS. Internal Action-free/Tireless sticker types
remain separate execution controls; A-as-Action-free is no longer displayed.
Resource bundles collect identities before cumulative preflight and mutation.
Paid costs are not refunded after consequence failure. Triggered consequences
in this roster pay neither A nor S and are mandatory unless explicitly optional.

## Card families

- **Grey Squirrels:** Archer's Wound adds two control counters. Naturalist has
  Stun 2/1 for 2S and a separate AS adjacent-friendly Reset. Crossbowman and
  Musketeer gain two projectiles on Deploy and spend one plus AS for their
  printed attacks. Musketeer refunds one for each friendly Wound. Warrior earns
  Soul from friendly Bow Wounds and spends two plus AS to upgrade one chosen
  friendly ability within 2 by +1/+0. Guardian's high-physical friends at any distance
  gain +1 Bow damage. Wizard gains Soul on a friendly Reset and spends one plus
  AS to Return any adjacent unit. Pikeman has Pull 2/2 and a live +1 action while
  bashing.
- **Beavers:** Warrior has +1 magical and separately gives friends on inert bombs
  +1 magical, including SELF when eligible. Guardian's high-physical
  friends gain +1 magical. Architect spends Soul plus AS for Bomb 3/3 and earns
  one Soul after its own successful Defuse within 2.
- **Jerboas:** Banner Bearer supports adjacent bashing friends with +1/+0,
  without any forced-movement prerequisite (2026-11-05 revision).
  Warrior has +3 physical while bashing a stunned enemy.
  Cannoneer grants one Ember to the exact friendly Wound victim. Assassin has
  Steady/First Strike. Pyromancer's Hit-without-Wound chooses one adjacent friend
  for one Ember. Soldier gains Mshield 1 on SELF after friendly Fire Hit. Courier
  transfers counters for S only.
- **Marmots:** Halberdier sacrifices a friend within 2 plus AS for persistent
  +1/+1. Paladin Revives an eligible friend after a friendly Sacrifice, with no
  additional range or per-turn restriction. Sacrifice still triggers Die.
- **Chinchillas:** Soldier's own Deploy must Return another deployed friend at
  any distance if eligible. Sentinel prevents every ability caused by an adjacent
  unit's Deploy, including opposing and external watchers.
- **Tamias:** Knight adds three extra Stun on Deploy and has +4 physical while
  bashing. Warrior sacrifices an adjacent friend plus AS for Instant Bow 3/2.
  Archer's Bow 1/3 costs S only. Crossbowman's Hit adds permanent Bow range.
  Red Mage's Hit-without-Wound gives SELF two Ember. Blue Mage adds one raw Stun
  counter after a friendly hostile Stun action whose target was already stunned.

Life, deployment regions and all printed action values follow the user's table.

## Shared rules and interpretation notes

These make abbreviated wording concrete and identify the shared rules to adjust
if the user supplies a different interpretation.

- **Magical contact:** Cannon/Fire wording requires shared Hit and Wound.
  Bow/Gore/Bash and Cannon/Fire emit one Hit per actual contact, even at zero
  damage; Wound requires positive applied life loss. Nonlethal Fire is Hit without
  Wound; lethal Fire emits both. Immunity, misses, declaration and ignition alone
  do not qualify. Existing generic Hit/Wound cards also see magical contact;
  bombs remain outside the attack families and publish distinct bomb_hit instead.
  Life payments and ordinary health changes emit no
  attack contact. Event history captures the applied loss and `wounded` Boolean.
- **Ember:** one counter adds one damage to the next Fire declaration. Capture
  and consume current Ember before declaration followups; later grants cannot
  rewrite a queued attack. Misses, immunity and bomb ignition do not refund it.
  Reset clears unspent Ember; other attack families do not consume it.
- **Control:** current life + printed control bonus + control counters determine
  regional strength. Physical modifiers, including regional +1 physical, never
  feed back into that calculation.
  Guardian threshold predicates read the physical axis only. Bow/magical-only
  aura outputs are filtered before modifier predicates, so a magical reward
  cannot recursively evaluate its own physical eligibility.
- **Ammunition:** projectiles start at zero. Own Deploy grants two unless
  suppressed. Reset restores zero without emitting Deploy. Return preserves
  counters, so later redeployment can grant two more.
- **Sacrifice:** its established keyword meaning restricts the victim to a
  friendly deployed unit. No unprinted non-hero restriction is added. Halberdier's
  radius includes SELF; Warrior's exact adjacency excludes SELF. Sacrificing a
  hero is provisionally defeated until causal triggers/consequences finish, so an
  explicit Sacrifice rescue can save it. A still-defeated or zero-life hero then
  loses; Reset alone does not save it and ordinary Revive still excludes heroes.
  A self-sacrificing Halberdier receives its paid +1/+1 while
  defeated without reviving. Duplicate victims and later resource spending from
  a sacrificed unit fail full preflight before mutation.
- **Paladin:** the just-sacrificed non-hero is eligible for Revive. Normal Revive
  excludes Paladin itself. Die and Sacrifice watchers capture before departure,
  so a sacrificed Paladin can still Revive another friend. Ordinary Die/Disable cannot substitute for Sacrifice;
  Wild Rat doubles Die abilities, not Sacrifice abilities. No per-turn cap is
  inherited from the earlier proposal.
- **Sentinel:** suppress the entire Deploy occurrence before capturing any
  watcher on either side. This includes good and bad ETB and external watchers.
  Normal deployment costs and entry Stun remain. Exact adjacency excludes the
  source's own entry unless another Sentinel qualifies.
- **Pikeman:** one live player action while any pending Bash involves it;
  multiple sources stack. The separate spending ledger can be negative after
  bonus actions are spent. Leaving/re-entering Bash changes the allowance without
  refilling spending. A committed action still charges once if it removes its own
  bonus. Start resets base resources; snapshots retain the ledger.
- **Courier:** choose a positive counter PROPERTY and X from 1 to min(2, balance),
  then another UNIT. Unqualified "unit" allows either owner. Both hosts must
  remain deployed within 2 at commit. Remove/add the same kind and amount together.
  An invalid/cancelled destination never removes donor counters; already-paid
  activity is not refunded. Flags and derived modifiers are ineligible. Transfer
  changes counters only, preserving activity; moving Stun is not hostile Stun.
- **Blue Mage:** the actor must be another friend, not the mage itself. Test positive Stun before the original hostile action, not the
  counters just added. Activity costs do not qualify. Award a raw counter without
  another Stun occurrence, so multiple Blue Mages add without recursion.
- **Banner:** the revised aura requires a friendly exact-adjacent participant of
  an unresolved Bash. It no longer tests displacement or turn history. Non-bashing,
  enemy and nonadjacent units receive nothing; resolved Bash immediately removes
  support. Auras remain read-only and respect exact shared-hex identities.

## Caller map

| Caller → implementation | Responsibility |
| --- | --- |
| `CardCatalogue.starter_army/all_units` → `SynergyCatalogue.all_units(owner)` | Append 28 definitions per owner without changing older IDs. |
| Catalogue → `SynergyRules.command/observe/counter/transfer/upgrade` | Compose typed costs, events, selectors and ordered consequences. |
| `Verbs.sacrifice` → `CostPayment` / `RulesRunner._cost_choices_available` | Collect choices and preflight activity/resources/duplicate sacrifices without mutation. |
| `CostPayment.commit` → `SynergyActions.sacrifice` → `Match.defeat` | Publish Die/Sacrifice and release cost followups before paid consequences. |
| `PhraseExecution` → `Verb.amount_limit` / `RuleBinding` | Retain bounded amount, donor and key in executions, never on definitions. |
| `SynergyActions.transfer_counter` | Recheck kind, both hosts, range and balance, then conserve counters atomically. |
| `CombatResolver` → `_publish_contact` | Publish actual contact/applied loss before death removal. |
| Fire declaration / `UnitInfo.effective_action_values` | Preview/capture Ember and consume the declared attack's current counters. |
| `CombatResolver.stun` → `AlreadyStunned` | Capture pre-action Stun and avoid recursive bonus actions. |
| `RulesRunner._suppresses_event_triggers` → continuous contribution | Reject the whole suppressed Deploy before watcher capture. |
| `Player.actions_remaining` → `SynergyRules.player_action_bonus` | Derive live availability from a separate spending ledger. |
| `Match.finish_action/start_turn` / `MatchSnapshot` | Charge once; reset/persist spending and displacement history. |
| `Match.defeat/settle_sacrificed_heroes` / runner completion | Retain a hero's provisional Sacrifice loss through causal choices and finalize only after an opportunity for explicit rescue. |
| `ControlResolver.strength` | Include stored control without counting physical modifiers. |
| `EffectText` / `RuleGuide` / catalogue exporter | Show independent cost markers and new resource/condition semantics. |
| `BoardCharacter` → manifest/alignment | Reuse native art and existing finite transition gates for both owners. |

Object-authoring examples using implemented APIs:

```gdscript
# Default AS plus ammunition, collected before mutation.
var shot := SynergyRules.command(
    SynergyRules.phrase(Verbs.bow(4, 2), Selectors.BowTargets.new(2)),
    1, true, SynergyRules.spend(UnitInfo.PROJECTILE_COUNTER, 1))

# Courier preserves the selected counter kind and amount through a completed step.
var donor_key := RuleBinding.new(&"step_0", RuleBinding.Field.PROPERTY_KEY)
var amount := RuleBinding.new(&"step_0", RuleBinding.Field.AMOUNT)
```

## Art and verification

`tools/import_synergy_characters.py` imports existing owned bundles. Each has
eight standing directions, five six-frame walks, a nine-frame sitting clip and a
thirteen-frame action. Rise reverses the sitting clip. Missing west-side walks
use native standing rotations; absent seated facings reuse the existing south
pose. `manifest.json` records these gaps. No new art was generated.
`tools/build_character_alignment.py` bakes native foot positions for all 63 assets.

`tests/synergy_units_test.tscn` has focused result, ownership/eligibility and
non-trigger coverage for the 28 cards and shared contact, resource capture,
cost conservation, suppression, persistence and action ledger rules. Existing
roster and received-Hit expectations are updated. Compilation does not execute
these scenes. Behavioral tests remain unrun because the request did not end TEST.

When explicitly requested with TEST, run this scene and relevant shared
`fire_test`, `selection_test`, `m2_test`, `wild_return_test`,
`woodland_effects_test`, `disable_units_test` and `full_roster_test` scenes.

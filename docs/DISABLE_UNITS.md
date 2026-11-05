# Disable units: Mara, Tamia and Grey Squirrel

Implemented from the 2026-10-27 request and the accepted Tamia/Grey Squirrel
proposal. All three have existing PixelLab characters and are appended for
both owners after the previous 64-unit roster prefix. Each player now has the
35 sprite-backed definitions available; the full reference catalogue has 52
implemented definitions.

## Card text

| Unit | Life | Deployment | Actions | Triggers |
| --- | --- | --- | --- | --- |
| Wild Mara | 2 | Intermediate | Cannon 2, range 2; implicit Walk 1 | Friend is disabled: +1 Cannon +0 to itself. Enemy is disabled: +1 current life/+1 maximum life to itself. |
| Wild Tamia | 2 | Starting | Walk 2; disable a non-hero friend in hand, then +1 deployment | — |
| Wild Grey Squirrel | 1 | Starting/Intermediate | Walk 2; [A] +1 Bow damage/+0 range to an adjacent friend until End | — |

Tamia's conversion pays ordinary self-Stun 1 and one action. Disable is the
first consequence, followed by its owner's deployment grant, not a custom
atomic cost. Only a friendly undeployed non-hero is selectable; troops and
temples qualify, heroes/deployed/defeated/enemy cards do not. Disable preserves
health, properties and abilities, emits Disable once, and does not emit Die or
Return. The resource grant does not refund an action or automatically deploy
anything. No eligible hand card means no legal command.

Mara's two triggers classify the **disabled card's owner**, regardless of who
caused Disable. Their target queries intentionally have no deployed-state
restriction: the occurrence is published after its recipient enters defeated.
Only a deployed Mara captures new occurrences. Friendly Disable awards a
permanent `cannon_damage` counter to Mara; zero range change creates no range
counter. Enemy Disable grants actual current/max health through `Action.up_life`,
so Explorer and other existing life-increase rules can respond. Ordinary Die,
Return and failed/repeated Disable do not qualify. Both rules are free triggers.

Grey Squirrel uses the Action-free sticker, not Tireless: it must pay activity
and self-Stun 1 but retains the player's action token. Its exact-distance-one
UNIT selector excludes SELF, same-hex occupants, enemies and off-board/distant
friends. The recipient owns a concrete Bow TimedGrant; source departure does
not remove it. It survives End triggers/activation and expires in the captured
current player's End cleanup, even if the source is gone. Already captured Bow
attacks retain their attack values after expiry. It grants neither a permanent
Bow counter nor an additional action.

## Permanent Cannon values

`UnitInfo.CANNON_DAMAGE_COUNTER` and `CANNON_RANGE_COUNTER` are stable counter
keys created only when awarded. They follow the existing Bow-counter approach:
preview, line/range validation and attack capture read
`effective_action_values("cannon", [damage, range])`; permanent counters are not
consumed by firing. They survive Return and snapshots, disappear on Reset, and
are eligible for Porcupine's positive stored-counter harvesting. They do not
change printed Verb definitions, regional strength or already queued attacks.

## Authoring and callers

```gdscript
# Classify the disabled target, not the actor, after its zone transition.
var friend := QuerySelector.new()
friend.relative_owner = Enum.YOU
var disabled := Effect.EventPhrase.observe(&"disable", QuerySelector.new(), friend)
var consequence := Effect.ConsequencePhrase.new(Selectors.Self.new(),
    Verbs.upgrade_cannon(1, 0), Selectors.Self.new(), Effect.Phrase.TargetMode.ALL)

# Real type exclusion includes troops AND temples, unlike a troop-only query.
var hand := QuerySelector.new()
hand.relative_owner = Enum.YOU
hand.state = Enum.t_state.UNDEPLOYED
hand.excluded_type = Enum.type.HERO

# Timed, Action-free support still pays ordinary self-Stun through shared policy.
var adjacent := Selectors.UnitsOn.new(DistanceSelector.new(1)).where(WoodlandRules.friends())
var support := Collection.grant_action_values(&"bow", [1, 0], adjacent, false, true)
```

| Caller → implementation | Responsibility |
| --- | --- |
| `CardCatalogue.starter_army()` / `all_units()` → three new factories | Append both-owner playable cards without reordering saved IDs; keep full catalogue discovery current. |
| Mara → `WildRules.grow_on_disable(friendly)` | Observe the disabled target's relative owner and compose separate SELF consequences. |
| `Verbs.upgrade_cannon()` → `Action.upgrade_cannon()` → `UnitInfo.add_cannon_counters()` | Award recipient-bound permanent Cannon properties; the shared effective-value query feeds preview and combat. |
| Tamia → `WildRules.disable_for_deployment()` | Build normal activity cost and ordered Disable/resource consequences using existing verbs. |
| Grey → `WildRules.prepare_bow()` → `Collection.grant_action_values()` | Build exact adjacency and the A sticker; existing Action/TimedGrant/End cleanup owns lifetime. |
| `QuerySelector.excluded_type` → `matches()` | Enforce the non-hero restriction without guessing troop-only eligibility. |
| `EffectText` / local action menu / hex labels | Show Cannon growth and A support with neutral printed grants and magenta applied M/N values. |
| Board → `BoardCharacter` / playground manifest | Reuse native directional art, walk/rise/action lengths and existing finite animation timing. |

## Art and regression coverage

PixelLab sources are recorded in the playground manifest. All three include
eight standing and seated directions, six-frame walks in eight directions and
nine-frame rises. Tamia and Grey have nine-frame action clips. Mara has no
action clip in its existing PixelLab state: its action uses one native standing
frame as a documented fallback. No art generation or new animation was charged.

`tests/disable_units_test.tscn` covers each effect's result, target/source
ownership and non-trigger cases; normal/A payments; troops versus temples and
heroes; Disable versus Die/Return; life-growth followups; permanent Cannon
capture/Return/snapshot/Reset; timed Bow capture, source departure and expiry;
and both-owner sprite/roster registration. `tests/full_roster_test.tscn` now
expects 35 cards per owner. Shared combat, selection, timed-grant and woodland
suites remain relevant. Tests were authored but must not run unless the user
request ends with `TEST`.

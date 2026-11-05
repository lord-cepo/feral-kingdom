# Crowned heroes

Approved in the hero-design conversation, implemented as direct objects on 2026-11-05. These three alternatives append after the existing roster, preserving older unit IDs. Both players can choose them as their first hero deployment under the existing one-hero rule. All deploy in controlled vacant Starting hexes. Crowns identify heroes only.

Every printed action costs **[AS]**: one player action and self-Stun 1. Triggered rewards cost neither.

| Hero | Life | Actions | Continuous / triggered effects |
| --- | ---: | --- | --- |
| Grey Squirrel King | 5 | Move 1; [AS]: +1 Projectile to adjacent friend; 2 Shield 2. | Adjacent friends with one or more projectiles have +1/+0. |
| Jerboa King | 6 | Move 2; 1 Push 2; 1 Stun 1. | Moved friends have +2/+0 until End. |
| Marmot Queen | 6 | Move 1; 2 Mend 2. | Friend is sacrificed within 2: 1 Shield and 1 Mshield to this unit; while this unit is wounded: +0/+1 to adjacent friends. |

## Eligibility and timing

- Supply creates missing Projectile counters without granting an attack ability. Friends include every friendly unit type, including heroes and temples. Exact adjacency excludes distance zero. Spending the final Projectile immediately removes the live physical bonus; it never writes physical counters.
- Fortify accepts any deployed friend within radius, including SELF; Shield uses consumed temporary physical counters.
- Khan's Push follows ordinary alignment, landing, immovable-temple and shared-Bash rules. It cannot Push friends. Push and Stun remain independent actions. The revised support replaces its old Bash aura: each resolved normal Move by any deployed friend, including SELF at any distance, grants that exact mover +2/+0 through the current player's End followups. Forced Push/Pull and Fly are separate actions and do not trigger this Move rule. Repeated Move refreshes the same source/recipient grant rather than accumulating +2 per occurrence; different sources stack. Already-made grants survive source departure, follow their recipient through Return, clear on Reset and expire at captured End cleanup. They are typed timed contributions, not consumable Shield or permanent counters. Snapshot roundtrips retain their kind and expiration.
- Queen's Mend excludes SELF and full-life units, clamps current life and never increases maximum life.
- Queen's sacrifice trigger reads the exact friendly victim and recorded departure hex within radius 2; the actor is unrestricted by this watcher. The source must be deployed at capture. Another sacrificed unit on her hex qualifies; self-sacrifice does not. Ordinary Die, Disable, Return and life payment are not Sacrifice. Both temporary protections stack and are consumed normally. There is no once-per-turn limit.
- Queen's wounded aura includes friendly heroes and temples. Exact adjacency excludes SELF and same-hex occupants. Healing her to full life, source departure or recipient movement outside adjacency removes the contribution without changing stored counters.

Examples: a Crossbowman next to the king receives one Projectile and immediately gains +1 physical; spending its last shot removes that bonus. A distant friendly unit that Moves gains Khan's +2/+0 for the remainder of this turn; another Move keeps it at +2/+0. A nearby Halberdier's sacrifice protects the queen while Paladin handles Revive independently.

## Caller map

| Caller → implementation | Responsibility |
| --- | --- |
| `CardCatalogue.starter_army/all_units` → `HeroCatalogue.all_units` | Append three alternatives per owner after older IDs: 86 cards per owner. |
| `HeroCatalogue` → `SynergyRules.command/phrase`, `Collection`, `Verbs` | Compose ordinary costs and exact UNIT choices through the existing runner. |
| `ContinuousEffect` → `OtherFriends/Loaded/Wounded` | Derive friendly eligibility and live modifiers without counter writes. |
| Move → `RulesRunner` → `Verbs.grant_modifiers` → typed `TimedGrant` | Attach the exact mover's +2/+0 through captured End; repeated same-source grants refresh. |
| `UnitInfo.state_modifiers/modifier_breakdown`, `Match.expire_timed_grants`, `MatchSnapshot` | Read, explain, expire and persist modifier grants separately from action-value grants. |
| Sacrifice → `RulesRunner.capture_event` → `NearbySacrifice` | Inspect the recorded victim hex before removal; retain a free two-step protection execution. |
| `BoardCharacter` → mapped keys and atlases | Display cached crowned standing, walks, seated, rise and action frames. |
| `EffectText` → hover/export text | Shared amount/icon/range, explicit written-effect costs, recipient-first auras and compact event conditions; no unit-name overrides. |
| `tools/import_hero_characters.py` → alignment/sheet builders | Copy reviewed native art and rebuild runtime caches. |
| `tests/hero_units_test.tscn` → shared synergy fixture helpers | Focused outcomes, ownership/range/type exclusions, costs and registration. |

## Animation and verification

Each hero has eight native six-frame directional walks, a nine-frame south sit/rise and thirteen-frame south action. Actions finish on exact standing pixels; rise reverses sit-down. Other seated directions reuse south, matching the existing roster convention. Source art/continuity evidence remain in `exports/hero-sprites/pixellab`.

Godot editor import/compilation is separate from behavioral tests. Focused tests and roster expectations were added/updated but remain unrun: execute scenes only on a request ending `TEST`. Relevant scenes: `hero_units_test`, `synergy_units_test`, `full_roster_test`, `adventurer_units_test`, `disable_units_test`, `character_cache_test`, `fire_test`, `selection_test`, `m2_test`.

# Shared hover wording and Mshield

Further shared clauses: Courier's two retained choices describe one transfer of
up to two same-kind counters between distinct units within 2 of SELF; its [S]
payment remains. Sacrifice costs read `sacrifice within 2`, relying on Sacrifice's
friendly-victim rule. Enemy counter removal followed by awarding that same kind
to SELF reads `transfer one counter from adjacent enemy to this unit`. Counter
payments name their host (`-1 counter on adjacent friend`); Reset radius reads
`reset 2`. Shaman's two choices read `return two bashing units`, with [A] and -1
deployment retained. Summoner's paid Return reads `return friend: deploy friend
on target`; target is the returned friend's captured hex and the returned card
itself may be redeployed. Cleric adds `+1 existing counter on adjacent friend`,
including an existing zero balance, never creating a new counter type. Bard's
`adjacent units have +1 [Bow] +0` includes both owners. Sentinel suppresses every
ability caused by an adjacent unit's Deploy occurrence.

Tireless/T is removed from visible qualifiers, glossary stickers and catalogue
legend. [A] expresses action payment without activity; [S]/[AS] retain independent
costs. Existing internal activity-exemption flags continue enforcing the same
rules; removing the display sticker does not change free triggered effects.

Blue Mage: another friend's hostile Stun applied to an already-stunned enemy adds one
raw Stun counter after the original action. Initial Stun, self-Stun costs and
unrelated counter transfers do not trigger it. The raw extra counter does not
emit another Stun action, preventing recursion.
The mage's own printed Stun does not trigger its reward. Its concise text is
`another friend Stuns any stunned unit: +1 Stun to target`; "any" adds no new
target-ownership restriction beyond the original Stun action's legality.

Jester: a new transition to enemy control of the region occupied by the deployed
Jester captures one Instant Bow 2/2 trigger. Continued enemy control, unrelated
regions and repeated control refreshes do not trigger. The player still chooses
a legal Bow target; no action/activity payment is added to the trigger.
Its concise text is `enemy gains control of this unit's region: 2F [Bow] 2`.

Disable takes a unit from hand to defeated, preserving life/counters/abilities,
and emits Disable without Die. Defeat of a deployed unit sets life to zero,
removes it from the board and emits Die. Both end in the defeated state; ordinary
Revive may recover eligible non-heroes, but death watchers only see Defeat's Die.

Caller additions: `_steps` summarizes Courier/Shaman choice sequences;
`describe_effect` folds Rogue's matching counter payment/award into transfer
wording; `_payment_text` names counter hosts and Sacrifice radius;
`_aura_targets` supplies plural set wording without changing action pickers.
Regression additions are `test_compound_wording()` and the revised `test_banner()`.

Additional shared conventions (2026-11-05): unrestricted Hit/Wound victims are
omitted (`wild friend hits: ...`, `this unit wounds: ...`); constrained victims
remain explicit. Enemy-only Fire projected from units to hexes reads `1F [Fire]
to enemy` without projection terminology. An exact-ability Upgrade prints its
damage/range pair before the keyword and recipient radius after it: `1/0 upgrade
2`. Its [AS]/Soul payment remains explicit. Upgrade parchment rows use the same
formatter. Physical-threshold auras read `friends with +3 or more physical have
...`; inert-bomb support reads `friends over bombs have +0/+1`. The bomb wording
still requires an inert bomb. Wild Marmot's Return is confirmed [AS], not free.
Attack-family guards fold into the contact clause: `friend wounds with [Bow]:
+1 Soul to itself`, retaining the Bow requirement without a separate technical
`if the contact was caused by Bow` sentence.

Grey Squirrel Warrior earns one Soul for each friendly Bow Wound (positive life
loss, not mere Hit), then spends two Soul plus [AS] to upgrade one selected
numeric ability on a friend within 2 by +1/+0. Its chosen-ability grant persists
until Reset; it is not consumed by using the ability. Example: Bow 1/4 becomes
Bow 2/4. The other printed effect is its Soul-income trigger.

The user's 2026-11-05 spot corrections define shared presentation rules, not unit-name overrides. Card definitions remain authoritative objects; descriptions never execute them.

- A SELF action trigger with an unrestricted destination reads `this unit [action icon]: ...`, omitting redundant `to any hex`. Historical stages and genuinely constrained participants remain explicit.
- Simple actions use amount/icon/range. Each family's normal ownership filter is implicit: Shield/Mshield/Mend choose friends; Stun/Push/Pull use the authored hostile shorthand. Other target restrictions remain in structural descriptions.
- Default [AS] is implicit for compact actions. Written consequences show `[AS]: ...`; independent [S]/[A]/[2S] and resource costs retain their actual markers. A Disable-to-deployment conversion reads `[AS] disable friend: +1 deploy`, without changing its sequential paid behavior. Disable's normal in-hand non-hero restriction remains authoritative in its verb and glossary.
- Modifier auras read `adjacent friends with one or more projectiles have +1/+0`. Source conditions read `while this unit is wounded: +0/+1 to adjacent friends`. Friends means every friendly unit type; an explicit troop filter is a separate condition. Adjacency excludes distance zero.
- A movement-to-modifier grant reads `moved friends have +2/+0 until End`. A nearby Sacrifice condition is folded into the event once: `friend is sacrificed within 2: ...`. Two automatic same-recipient Shield/Mshield grants share `and ... to this unit` while remaining ordered rule actions.

## Caller map and examples

| Caller → formatter | Responsibility |
| --- | --- |
| Hover/Bash/tray/export → `EffectText.unit_lines/describe_effect` | Share costs, events and consequence wording. |
| `compact_action/_compact_radius` | Read numeric arity and each action family's standard spatial owner filter. |
| `_query/_event/_condition/_continuous/_steps` | Describe selectors, events, predicates, auras and safe same-recipient display grouping. |
| `GameIcons.action_path/bb` → `RuleGuide.decorate` | Use distinct steel Shield and purple Mshield images with separate glossary links. |
| Resolved Mshield → `GuerraBoard._on_action_presentation` → `board_trigger.setup` | Play the nine-frame purple barrier on the exact recipient for 1.5 seconds with existing fade timing. |
| `tools/import_mshield.py` | Import owned PixelLab object `0bcb86ee-0927-4fbe-9a23-fa9e6c575464`, animation group `405db63a-76d8-4448-987a-f59ad3fb4447`. |

The importer preserves all nine original 32px animation frames. Only the UI glyph is alpha-cropped and nearest-resized to the existing 48px source height; `GameIcons.bb` sizes it to the requested text height. The finite effect remains independent of authoritative rules and persistent ambience.

Examples are the Red Squirrel King's Fire trigger, Grey Squirrel King's Supply/Shield/loaded aura, Jerboa King's Move grant, Marmot Queen's Mend/Sacrifice/wounded aura, and Wild Tamia's Disable conversion. Focused coverage is in `tests/hero_units_test.tscn`; it includes ownership/type exclusions, captured modifier lifetime/snapshot persistence and distinct Mshield frame loading. Tests remain unrun unless requested with `TEST`.

# Opt-in regression routines

The character-cache regression uses shipped atlases for its required checks and
compares original PNGs when available. It can run on a checkout without the
editable frames. See [CHARACTER_SHEETS.md](CHARACTER_SHEETS.md) for the caller map.

Hand state and rule-query regression, **2026-11-08**. The 19 gameplay and
presentation suites passed with Godot 4.7.2 in
`.tools/test-runs/20261108T221312356376Z/results.json`. The separate
`character_cache_test` failed to load in that run due to a removed runtime
constant. The repaired fixture owns the optional source path.

Previous completed run: **2026-10-29 — 15/15 suites passed, zero failures** using
the bundled headless engine. Full evidence is retained at
`.tools/test-runs/20261029T133619439329Z/results.json` with a separate complete
output log for each scene. This includes all 83 appearances/166 owner-specific
roster identities, the 20 new cards, and nine managed cross-roster scenarios.

Run only after a user request ending `TEST` (AGENTS.md). These routines never
run during editor import or ordinary gameplay.

```powershell
python tools/run_tests.py
python tools/run_tests.py character_cache_test
python tools/run_tests.py adventurer_units_test adventurer_synergies_test
python tools/run_tests.py --godot "C:/path/to/Godot_console.exe"
```

The default engine is the bundled Godot 4.5.1 console build under `.tools/godot`.
With no scene names, the runner discovers all `tests/*_test.tscn` scenes.
Each is a separate headless process with isolated APPDATA/LOCALAPPDATA, so it
cannot load/overwrite the player's real save. The timeout is 180 seconds per
scene (`--timeout` changes it); sprite-cache verification can take two minutes.

Full logs and incremental `results.json` are retained in
`.tools/test-runs/<UTC-run-id>/`. Results include elapsed time, exit code, timeout,
reported assertion counts when available, and log paths. Nonzero exit, timeout,
logged script/engine/fatal errors, or reported nonzero failures fail the suite.
A script exception cannot be hidden by a scene that eventually exits zero.

## Coverage and caller map

| Scene | Coverage |
| --- | --- |
| `full_roster_test` | All 106 sprite-backed units for both owners, including stable IDs, rule contracts, movement defaults, hero choice and snapshots. |
| `frontier_units_test` | Both Frontier batches, including Ember/Sacrifice capture, the two movement occurrences, pre-impact Flee, Shield counters, wounded control, the Stun threshold and written resource payments. |
| `adventurer_units_test` | All 20 new cards: printed effects, ownership/range exclusions, atomic payments, modifiers, Return/Revive, counters and next-Fire stickers. |
| `adventurer_synergies_test` | Nine managed multi-card chains listed below. |
| `synergy_units_test` | Earlier 28-card block: ammunition, contact rewards, control/thresholds, transfer, sacrifice, trigger suppression, Bash allowances and activity exclusions. |
| `rat_effects_test` | Rat effects, clean Return/Revive and legacy hand snapshots, fresh redeployment, Wild Rat predicate counts, Copy categories, Disable, life provenance and no-command loss. |
| `woodland_effects_test` | Growth, Bomb/contact payoffs, Flee, upgrades and life/resource payments. |
| `wild_return_test` | Wild Return cards, variable counter costs and effect redeployment. |
| `disable_units_test` | Wild Mara/Tamia/Grey Squirrel engines, ownership and timed Bow grants. |
| `fire_test` | Fire/Bow/Cannon/Bomb/Gore, Push/Pull/Bash, immunity, delayed identity and modifiers. |
| `selection_test` | Reference domains, shared-hex identities, projections, CHOOSE_ONE/ALL, stale choices and exactly-once execution. |
| `m2_test` | Costs, captured trigger choices, continuations and board/execution handoff. |
| `trigger_state_test` | Event matching, continuous state and trigger ordering. |
| `local_match_test` | Deployment, required hero redeployment, loss when no deployment counter remains, actions, and turn lifecycle. |
| `simulation_snapshot_test` | In-memory match restoration, counter and queued Fire isolation, deterministic ID allocation, and alternate branches of an opponent-owned pending trigger. |
| `tactical_heuristic_test` | Safety before weighted value, lethal Bash reach, readiness, a friendly answer to a ranged attacker, Fire versus Cannon injury, legal dodges against a queued Bow, and scoring bundled sacrifice costs. |
| `mcts_search_test` | Heuristic-first expansion, admission of every legal option, simulation evidence overriding the initial ranking, and separate backup of truncated-rollout estimates. |
| `menu_flows_test` | Saved-deck selection fills the centre column and the match result appears after terminal hero feedback. |
| `presentation_test` | Actual game scene: cosmetic replay, HUD/save/reset, and the Bash order from split Slash and life reveal through Skull, departure and recentering. |
| `character_cache_test` | Shipped atlas regions, cached texture identity, portraits, measured alpha bounds and feet, legacy fallback exclusion, and pixel comparison for originals available on disk. |

The new cross-roster scene checks:

1. Summoner Return → Cleric Reset in hand → same-card deployment at the retained
   hex, with exactly-once events and one command payment.
2. Shaman chooses across two Bashes → both Return → two Cleric Reset choices.
3. Warlock Disable → Mara Cannon reward → same-card Revive; no Merchant death
   income, Blue Mage self-cost amplification or player action payment.
4. Druid maximum-life gain → Explorer magical gain + Wild Red Squirrel Instant
   Bow, without fabricated current-life growth or recursion.
5. Bard + Guardian auras → Ranger captures Pierce Bow; source departure changes
   future values without changing the queued attack.
6. Ember addition → Alchemist Soul → Witch conversion; a friendly death funds two
   Merchants whose P/F grants combine on Witch's upgraded Fire.
7. Scout geography + Pikeman Bash allowances preserve spent actions through
   departure/reentry and never grant the opposing player actions.
8. Cleric counter grant → Hunter pays Cleric Stun → enemy Reset; removal/Reset
   never activates early, and owner End excludes the opposing army.
9. Cleric increases an existing zero counter → player two's Rogue steals that
   exact kind; only the acting player pays, and friendly donors remain excluded.

`adventurer_synergies_test.gd` reuses fixture helpers but overrides `_ready`, so
inherited suites do not run implicitly. `submit` checks actual availability and
uses `RulesRunner.submit`; `take` checks the retained phrase before choosing an
exact identity; `count_event` counts resolved occurrences. The full-roster entry
calls `check_all_rule_contracts` after Match supplies stable IDs, default movement
and printed baselines.

These are focused regressions and representative interaction chains, not an
exhaustive enumeration of every board configuration/card combination.

## Fixes found on 2026-10-29

- CostBundle validation now accepts Return, Disable and deployment payments that
  already have atomic ledger/commit support.
- Revive permits Warlock's paid ordinary command as well as captured triggers,
  retaining friendly/non-hero/defeated/other-unit eligibility.
- Availability retains private preview payment bindings through consequence
  checks. Rogue can bind the exact donor counter kind, reject a conflicting
  recipient FLAG and try another kind without any mutation or events.
- Warlock recognizes a Revive candidate created by its selected Disable cost.
- Old roster counts now expect 83 per owner. Blue Mage's opponent test now acts
  on the opponent's turn and separately asserts out-of-turn rejection.

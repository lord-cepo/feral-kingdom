# Headless matches

From the project root, use the same Godot executable as for the game. The first command plays a seeded random-vs-random match and writes its decisions. The second submits those recorded decisions to a fresh match.

```powershell
godot --headless --path . res://tools/headless_match.tscn -- 42 match-42.json
godot --headless --path . res://tools/headless_match.tscn -- --replay match-42.json
```

The command uses the normal map, the full starter catalogue, and the game scene's starting allowances of one action per turn and eight deployments per player. Both policies sample uniformly among the options currently offered. The seed drives those choices. A replay reads the selected options directly and checks the decision owner, phase, turn, ordered legal option digest, and final captured match state. Replay traces are intended for the same rules and catalogue revision.

The driver exits with status 0 for a rules victory, 1 for invalid input, a rejected option, file or replay failure, and 2 for a stall or the 4,000-decision cap. A cap or stall is recorded separately from the winner field. The trace includes the setup, each chosen option, and any rules runner diagnostics.

## Caller map

- [The headless scene](../tools/headless_match.tscn) loads [the driver](../tools/headless_match.gd). The driver supplies the roster and budgets and owns the random policy, trace, and process exit.
- [HeadlessMatch](../scripts/runtime/headless_match.gd) starts the normal map and Match, enumerates deployments and commands, and exposes pending choices from EffectExecution and PhraseExecution. Choice ownership follows the source owner, which may differ from the active player. The driver disables presentation acknowledgements in this isolated process.
- [Match](../scripts/runtime/match.gd) handles deployment, phase transitions, action spending, and the settled no-action loss. [RulesRunner](../scripts/runtime/rules_runner.gd) checks command availability, owns queued followups, and spends the action after a committed command. The driver invokes the existing loss check synchronously if no decision remains.
- [NetworkSession](../scripts/network/network_session.gd) supplies the base target reference encoding. The harness records ability targets by category, origin unit, and definition index, then resolves them against live candidates during replay. Godot's process-local object IDs can differ between a recording and its replay.

For another policy, supply a fresh army to `HeadlessMatch.start(units, actions, deployments)`, read `decision()`, and pass its player and chosen option to `submit(player, option)` before requesting the next decision. The harness uses one Match autoload per process. Run separate processes for concurrent matches.

## Search snapshots

At a settled Action decision, `HeadlessMatch.checkpoint()` captures the authoritative match state in memory. This includes the map and occupants, both armies and their active and reserve cards, all stored counters and flags on units, players, hexes and the match, action and deployment allowances, whose turn it is, and ordered pending Fire, Bow, Gore, Cannon, bomb and Bash records. The snapshot also retains timed grants, copied abilities, upgrades, trigger-use history, and the rules ID allocators. Mutable values and records are copied on capture and on restore. Shared authored definitions are reused.

If a decision is waiting inside an execution, retain the latest settled checkpoint and the choices made after it. `HeadlessMatch.restore_snapshot(checkpoint, suffix)` restores that checkpoint and submits those choices through the rules. This recreates the pending execution, including its owner, cost selections, captured events, and queued continuations. The suffix contains entries of the form `{"player": decision.player, "option": selected_option}`. Use an empty suffix to branch directly from a settled Action position.

[SimulationSnapshot](../scripts/runtime/simulation_snapshot.gd) captures and restores the records. [The MCTS driver](../tools/mcts_self_play.gd) updates its checkpoint on the committed path and uses it for every simulation and before playing the chosen move. It keeps the policy's random stream outside the snapshot so simulations can sample different moves from the same state. Checkpoints are local to a headless Godot process. The JSON replay and graphical save formats retain their existing entry points.

## MCTS self-play pilot

```powershell
New-Item -ItemType Directory -Force .godot/mcts-pilot
godot --headless --path . res://tools/mcts_self_play.tscn -- 1000 8 4 .godot/mcts-pilot/shard-0.jsonl 12
python tools/train_mcts_value.py .godot/mcts-pilot .godot/mcts-pilot/value.npz
```

The Godot arguments are the first seed, number of games, simulations per searched decision, output file, and optional search interval in decisions. The interval defaults to 1. Using a larger interval saves simulation time while still generating some search targets. A budget of zero generates random bootstrap games. Give each worker a distinct seed range and shard. Each game is flushed as it finishes. The initial experiment uses the original three-card army per player, the normal map, one action per turn, and eight deployment tokens. One-option decisions skip search. A game with no authoritative winner contributes throughput data and no training rows.

[MCTS](../scripts/runtime/mcts.gd) expands legal decisions using UCT, follows uniform continuations, and backs up the result from each decision owner's perspective. It chooses the most-visited action. A decision with more legal choices than simulations receives only partial coverage. Small budgets are useful for generating initial data and measuring cost.

The optional sampled rollout uses `HeadlessMatch.sample_option(rng)` after the first
expanded picker. Each deployed unit contributes one proposal per action slot.
Eligible reserves contribute one proposal per board cell. The sampler draws
uniformly across those groups and checks only the drawn action against live
rules. After eight failed draws it samples the full legal list. Pending
confirmations and targets also use the full picker. Every legal option has
the same probability as full-list sampling, though the same seed can now
produce a different game. Tree nodes and committed moves still use
`decision()` for full ordered choices. The default remains enumerated while
end-to-end rollout throughput is being compared.

The Python trainer fits a small win-probability model from completed games, splitting whole games between training and validation. Its input features are specific to the pilot roster. The JSONL also retains legal choices and visit counts for later policy learning. The checkpoint is an offline experiment. Current MCTS uses terminal outcomes, and the model is not loaded by Godot.

Game simulation is CPU work. Use parallel Godot processes to generate data. Fit this small model on CPU with NumPy, or pass `--device cuda` in a Python environment with NumPy and CUDA-enabled CuPy. Compare end-to-end throughput before using a GPU model during search. Batched inference across independent simulations is the next GPU experiment once a model improves held-out play.

### Paired benchmark and diverse training

```powershell
New-Item -ItemType Directory -Force .godot/mcts-benchmark, .godot/mcts-diverse
godot --headless --path . res://tools/mcts_self_play.tscn -- 2400 24 2 .godot/mcts-benchmark/shard-0.jsonl 1 benchmark
godot --headless --path . res://tools/mcts_self_play.tscn -- 3000 250 2 .godot/mcts-diverse/shard-0.jsonl 32 diverse
python tools/train_mcts_value.py .godot/mcts-diverse .godot/mcts-diverse/value-250.npz --holdout-pairings 0-3 1-2
```

The commands above show single-worker runs. Split the same seed ranges into distinct shards to run in parallel. The self-play driver rotates through the six pairings of four three-card armies. In benchmark mode each aligned block of four seeds runs both UCT seats with each of the two army orders. The paired agents share the starting random seed. UCT makes the decisions owned by its assigned seat, and the other seat samples legal choices uniformly. Benchmark shards retain the outcome and search work, with no training rows.

To measure the sampler, run the same seeds and search budget with a final CLI
argument of `sampled` or `enumerated` after the mode. Output records search
microseconds, simulated steps, attempted simulations, and simulations with a
winner. Compare simulated steps per second as well as completed rollouts per
second, since the random continuations can differ in length.

Use `full-benchmark` for the complete playable catalogue on both sides. The
driver uses the normal map, one action per turn, eight deployments per player,
and the existing first-hero rule. An even seed and its odd successor assign
MCTS to opposite seats and share the same starting random seed. Each result
reports the army sizes, first search coverage, and total deployment candidates
considered versus explored. This mode emits benchmark outcomes without
three-card training features. The interval counts multi-option decisions owned
by the search seat. An interval of 1 searches all of them, while a larger
interval searches the first and then every Nth such decision.

```powershell
New-Item -ItemType Directory -Force .godot/mcts-full-benchmark
godot --headless --path . res://tools/mcts_self_play.tscn -- 6000 2 2 .godot/mcts-full-benchmark/pair-6000.jsonl 1 full-benchmark sampled
```

### Tactical root guidance

```powershell
godot --headless --path . res://tools/mcts_self_play.tscn -- 6000 2 4 .godot/mcts-full-benchmark/guided-6000.jsonl 16 full-benchmark sampled guided
```

Append `guided` to enable [the tactical heuristic](../scripts/runtime/tactical_heuristic.gd). Use `plain` for UCT without tactical ranking. The driver passes a complete order of legal options to MCTS at the root and ranks tree decisions when they first branch. Each ranked node begins with its first option and admits another after 1, 4, 9, and then successive square numbers of selection attempts. UCT allocates revisits and the most-visited action wins, with mean outcome breaking tied visit counts. Unsupported pickers use ordinary UCT. Guided sampled rollouts use the heuristic for the first target picker when one is already open, then use the cheap sampler. Simulated decisions do not update the committed landing history. `widened_searches` and `widened_choices` count searches that tried or chose an option outside the former fixed shortlist.

Between searches, the driver uses the first ranked choice and counts it in `heuristic_choices`. For example, it ranks both Walk and the subsequent destination picker. Unsupported choices use the regular fallback. With a hostile attack queued, the ranker compares legal choices with the damage projected if units stay where they are. It checks captured targets, current protections and damage dealt back in the same Bash. Hero survival and forecast exposure take precedence over net pending damage, which takes precedence over weighted position scores. A choice that reduces the pending threat also counts in `dodge_overrides`. Trigger chains and attacks held in a reaction continuation can change the forecast.

Secondary scores reward direct damage, likely defeats and approaching the opposing hero with a unit that can attack. Commands pay a score penalty for sacrifice and life costs. The cost picker itself prefers preserving the hero and paying with less valuable units. The driver creates a new ranker per game so the last six observed landings of each unit discourage backtracking within that game. Pass `0` simulations with `full-benchmark sampled guided` to measure this policy alone against random, alternating seats by seed.

### Fitting and using a value model

```powershell
New-Item -ItemType Directory -Force .godot/hybrid-training
godot --headless --path . res://tools/mcts_self_play.tscn -- 9000 16 5 .godot/hybrid-training/shard-9000.jsonl 24 full-training sampled guided
python tools/train_mcts_value.py .godot/hybrid-training .godot/hybrid-training/value.npz --export-json .godot/hybrid-training/value.json
godot --headless --path . res://tools/mcts_self_play.tscn -- 9600 16 8 .godot/hybrid-training/duel.jsonl 16 full-duel sampled guided .godot/hybrid-training/value.json
```

`full-training` plays the hybrid against the heuristic, alternating the search seat. Before turn 16, non-search choices occasionally sample other top options within the safest tier to diversify openings. It records compact owner-relative features on both seats' multi-choice decisions and labels games only after a confirmed winner. The trainer keeps paired seeds in the same split and exports the same fitted network to NumPy and Godot formats. `full-duel` disables opening exploration and training rows. Use `full-benchmark` for a random opponent. Keep evaluation seeds separate from training seeds. Use `--additional-shards` to combine compatible training rounds.

`full-duel-varied` starts both seats with the same seeded exploratory policy for the first eight turns, before enabling search for the assigned seat. Use paired even and odd seeds to compare a candidate in both seats from the same opening. The trainer deduplicates exact full-catalogue trajectories before splitting the games and fits with both player perspectives on each training position.

`full-training-random` records the same features with a random opponent. Use it to add positions from a wider range of replies and keep these training seeds separate from random-opponent evaluation.

With a model, the driver calls [MctsValue](../scripts/runtime/mcts_value.gd) for both seat perspectives when a simulated game is still open after 48 rollout decisions. Pass a number from 0 to 512 after the model path to change this horizon. Zero evaluates immediately after expansion. MCTS backs up this estimate with limited magnitude and uses the actual result when a simulation ends in a win. Logs count terminal simulations and model estimates separately. The standalone heuristic is unchanged by fitting a checkpoint.

An optional minimum advantage after the horizon controls when the committed choice can differ from the top heuristic move. With a positive threshold, a challenger needs at least two backed-up visits and a higher mean by that threshold. The threshold doubles for a move outside the safest tier. Search still explores the same branches. Zero leaves the final MCTS choice unrestricted.

Exposure is ordered from safe through answerable injury, unanswered injury, answerable loss, unanswered loss, and hero loss. The forecast checks whether a deployed opponent can reach the acting unit after deployment or movement, which defense applies, and whether a surviving unit or another ready ally can damage the attacker. For a lethal Bash, a defeated attacker already counts as an exchange. A unit that just paid self-Stun cannot supply an ordinary costed response. A Tireless attack can still qualify. A direct Stun, Return or forecasted lethal instant attack can suppress threats from its selected enemy. Delayed attacks leave those threats in the forecast.

The secondary `weights` dictionary adjusts physical and magical attack value, health, each modifier, regional control, upgrades, Reset, Stun, Return and deployment. Ranged attack estimates use the opponents' health and matching defenses. Visible enemy Reset access discounts upgrade value. The current defaults are initial estimates and can be tuned against paired wins. Changing them cannot move a choice ahead of a safer tier.

The forecast covers direct Walk/Fly Bash, Bow, Gore, Fire, and Cannon with common self-Stun or no-cost definitions. It estimates reach and damage from the current board, including the projected landing. The opponent can still dodge delayed attacks, gain an aura, use an indirect effect, or trigger a different sequence. These interactions and unsupported pickers are handled by ordinary search and the authoritative rules when simulated. The current forecast does not establish that an attack or counterattack is forced.

In diverse mode, every aligned two-seed block swaps the two armies. Each observation adds the identities of both rosters to the pilot features. Keep these shards in a separate directory from the pilot shards because the feature widths differ. The trainer's holdout flag excludes whole pairings from fitting and reports the always-predict-Player-1 position accuracy on the same held-out data.
# Watching training games

Choose **Watch Games** in the main menu. The viewer opens full-catalogue
training shards from `.godot/mcts-replays` in the project or
`user://training-replays`. **Open replay file** can load a shard from another
folder. The arrows step through recorded decisions on a static map.

The self-play driver's `_play` records committed choices in `replay_steps`.
The viewer's `_step` submits new choices through HeadlessMatch and caches the
visible positions for backward navigation. Older shards without recorded choices
cannot be opened directly. Re-running a seed records a new replay.


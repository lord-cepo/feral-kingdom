# Feral Kingdom self-play performance

There are three useful measurements: time to play a game given a sequence of decisions, time for MCTS to choose a move, and completed training games per hour. Also track wins at equal think time. A faster search that consistently overlooks the reply to an upgrade is a regression in playing strength.

## Evidence from existing runs

| Saved run | Games | Median elapsed per game | Completed MCTS rollouts |
| --- | ---: | ---: | ---: |
| Random-only pilot, seeds 1200–1215 | 16 | 0.353 s | 0 |
| Diverse self-play with replay from game start, two simulations every 32nd decision | 250 | 3.671 s | 1,874 |
| Diverse self-play with snapshots, four simulations every 32nd decision | 250 | 4.004 s | 4,067 |
| Earlier UCT versus random, two simulations at each eligible UCT decision | 24 | 39.119 s | 2,969 |

These are observations from different seeds, policies and worker loads. The random-only pilot also used a single fixed army pairing. They establish the size of the difference between generating random games and adding search. They cannot isolate the speedup from snapshots or identify which function dominates.

## Measure before choosing a redesign

Use the same seeds, army orders, CPU worker counts, simulator revision and decision/simulation budgets when comparing implementations. Include the six existing pairings, the full catalogue, and saved positions with many deployed cards, chained effects, combat, and pending choices. Compare equal-budget runs for engine throughput and equal-time runs for playing strength. Warm the worker, repeat, and report medians and tail latency. Use monotonic timers around these blocks, then profile functions inside the expensive blocks. [Godot's profiling guide](https://docs.godotengine.org/en/latest/engine_details/development/profiling/)

| Measure | Breakdown |
| --- | --- |
| Rules-only time | Legal option generation, deployment, payment preflight, target resolution, action commit, combat, triggers, regional control and win checks. |
| Snapshot time | Capture, restore, replay of pending choices, legal-option regeneration, and memory copied. Track the suffix length distribution. |
| Search time | Simulations attempted and completed, engine decisions per simulation, terminal and capped rollouts, tree maintenance, and distinct root options visited. Report p50/p95 decision time. |
| Training overhead | Feature extraction, action encoding, serialization, writes, worker startup and CPU scheduling. Measure total games per wall-clock hour, including failed and capped games. |
| Playing strength | Paired UCT versus random and previous agents, both seats, withheld army pairings, and the upgrade/refutation fixtures. |

Establish a trace comparison for exact optimizations. Given the same starting position and submitted choices, compare the next decision owner, ordered legal identities, counters, combat queues, event order, and final winner. Exercise sibling branches in both orders. Derived caches must stay correct during nested effects, which can change the board between two parts of one command.

## Speed up the rules without changing play

These are candidates from inspecting the code. Their order within each group should follow profiler results.

| Area | Candidate changes |
| --- | --- |
| Deployment | In the current enumerator, each reserve card can walk the whole map and call `can_deploy()` per tile. Check seat, action/deployment allowance, zone, and first-hero eligibility once before considering cells. Reuse vacant cells and regional owners for that read-only query. Keep authority revalidation when the deployment commits. [HeadlessMatch](../scripts/runtime/headless_match.gd), [Match](../scripts/runtime/match.gd) |
| Occupancy and roster scans | `Match.occupants()` walks the army per lookup. Index deployed units by hex and owner, and keep reserve and deployed lists. Start with indexes local to a read-only query, then consider incremental maintenance if useful. Preserve both participant IDs in a Bash hex and deterministic ordering. A bomb-by-hex lookup can avoid scanning inert bombs repeatedly. [Match](../scripts/runtime/match.gd) |
| Geometry | Precompute axial distances, ring/radius candidates, neighbours, straight-line paths and region membership for the fixed map. Index spatial candidates by centre and distance. Apply current occupancy, direction and legality afterward. Benchmark selectors on small rosters and crowded boards. [DistanceSelector](../scripts/effects/distance_selector.gd) |
| Regional control | `refresh_control()` already deduplicates the region calculation within a refresh. Other queries, including deployment and physical modifier reads, can still recalculate live strength. Memoize within a read-only decision first. Incremental totals need to handle life, control counters, movement, defeat and continuous grants before affected rules read them. Preserve control-change event timing. [ControlResolver](../scripts/runtime/control_resolver.gd), [Match](../scripts/runtime/match.gd) |
| Command preflight | Reuse native selector results and bound verb values within a decision when inputs match. Short-circuit existence queries once a legal actor/target pair is found. Avoid building an array when a caller only needs a boolean. A verified fast path for one ordinary self-Stun cost can save shadow-ledger allocations. Keep the full preflight for bundles, variable payments, sacrificed/returned units and consequences that depend on captured cost results. [RulesRunner](../scripts/runtime/rules_runner.gd), [TargetResolver](../scripts/effects/target_resolver.gd) |
| Uniform rollout choice | The current rollout builds and encodes all legal choices before sampling one. Where there is a known, duplicate-free candidate universe and cheap per-candidate legality, try drawing candidates uniformly until a legal one is found. Use a bounded attempt count followed by uniform sampling over all legal choices. This preserves the uniform policy under those assumptions. Benchmark it when legal options are sparse, where failed checks may erase the savings. Tree expansion and data export still need full lists where their consumers require them. |
| Identity and allocation | Keep compact typed actions, references and option IDs inside the simulator. Encode dictionaries and JSON at replay/export boundaries. The ability picker currently serializes records in its sort comparator. Precompute its stable comparison keys, and keep the same ordering. Avoid recomputing captions when selecting rules-only ability identities. After profiling, reuse scratch arrays, prefer static typing on hot paths, and replace string-based deduplication where compact keys preserve exact identity. [Godot static typing](https://docs.godotengine.org/en/stable/tutorials/scripting/gdscript/static_typing.html), [HeadlessMatch](../scripts/runtime/headless_match.gd) |
| Notifications | Audit deferred no-action checks and state/UI notifications during simulation. Headless decisions already perform a synchronous no-action check when there are no options. Where equivalent, avoid scheduling redundant checks and cosmetic work on every speculative mutation. Keep gameplay event dispatch, Start/End timing, trigger ordering, and terminal settlement. |
| Setup | Keep warm workers and reuse immutable authored card data and map geometry across games. Reinitialize every mutable card, grant, counter and runner record for a fresh game. Avoid loading art or generating display captions from rules-only code. |

## Make restoration cheaper

The current snapshot replaces replay from turn one with a settled checkpoint plus a short suffix for pending choices. It reflectively copies script records and retains the dispatched occurrence ledger. The self-play driver also captures at each settled boundary when search is enabled, even on sparse-search games. [SimulationSnapshot](../scripts/runtime/simulation_snapshot.gd), [Self-play driver](../tools/mcts_self_play.gd)

1. **Take fewer checkpoints where possible.** Capture on demand for searched settled positions. For searches inside a command, retain an anchor before the command or keep a checkpoint and the decisions needed to recreate the picker. If an optimization uses occasional earlier anchors, measure the tradeoff between capture frequency and suffix replay length. Keep pending trigger ownership and already-paid costs reproducible.
2. **Copy fewer bytes per checkpoint.** Share immutable map geometry, definitions and printed baselines. Keep mutable props, combat records, grants, and provenance isolated. Consider caching each record type's field metadata or using explicit typed copies for the most common records. Keep both rules ID allocators and verify whether old occurrence history can be represented compactly while preserving deduplication.
3. **Use compact state arrays where measured.** Group hot values by unit, hex, or combat-record family. Capture and restore contiguous mutable arrays, retaining alias relationships where the rules rely on them. Test the same rules across branches before replacing object-based state.
4. **Compare undo and copy-on-write.** An undo journal can rewind just the mutations made by one simulated branch. Every relevant write needs to be journaled, including events, owner/phase changes and future combat records. Copy-on-write instead shares unchanged regions of state across branches. Benchmark them against compact copies. Both cost more to maintain when new effects change the mutation paths.
5. **Consider explicit pending continuations only if suffix replay dominates.** Serializable continuation records would allow direct restoration in the middle of a command. Today the runner can hold bound callables, so replaying a short suffix safely reconstructs their original order and captured participants.

## Get more useful search from the same compute

These changes can alter which move is chosen. Measure them with paired games and tactical positions at equal elapsed time.

- **Reduce work on forced choices.** Traverse a chain of single legal choices without storing a separate search node for each one. Still execute each choice through the engine and preserve the owner at the next branching decision.
- **Retain useful search.** Reuse the matching child subtree after a committed move if the restored state and options agree. Cache legal decisions or evaluations by exact state identity only after defining keys that include pending effects, turn, counters, and future-relevant history. Consider graph search once repeated positions are measured. Keep distinct edge statistics and handle cycles explicitly. [KataGo graph-search design](https://github.com/lightvector/katago/blob/master/docs/GraphSearch.md)
- **Spend simulations where they discriminate.** Widen a large root gradually, prioritize tactical replies or learned move priors, and compare sequential halving for small budgets. The two-simulation benchmark had little room to revisit a move. Use the upgrade and refutation suite to check whether additional compute reaches the relevant opponent replies. [MCTS literature guide](MCTS_RESEARCH.md)
- **Reduce rollout length carefully.** Compare guided rollout policies, exact tactical proofs and verified terminal shortcuts. A learned value estimate can replace a long rollout if it improves actual play. The current 500-game checkpoint is weak on withheld pairings. An arbitrary cutoff can discard long winning lines, so report capped simulations separately and benchmark their impact.
- **Separate training objectives.** Generate inexpensive full games for outcome labels and search more deeply on a smaller set of positions for useful policy targets. Choose the frequency, positions and budgets by measuring useful examples per hour and eventual match strength. KataGo's playout cap randomization is one published example of balancing these workloads. [Wu, Accelerating Self-Play Learning in Go](https://arxiv.org/abs/1902.10565)
- **Measure search bookkeeping after simulator costs fall.** Reuse path storage, store edges in indexed arrays, and compare cheaper selection loops for large menus. Preserve reproducibility, tree semantics, and terminal backup by the actual decision owner.

## Increase games per hour

- **Find the worker count empirically.** This machine reports 24 logical processors. Compare 1, 4, 8, 12, 16 and 24 warm Godot processes with the same aggregate workload. Watch wall time, memory, disk pressure, CPU clocks and thermal throttling. Report games/hour as well as single-worker time. Prefer small batches and redistribute remaining seeds when one pairing consistently takes longer.
- **Keep one independent Match per process with the current architecture.** Threading several simulations through the same Match autoload would share mutable state. If a single-process pool later becomes worthwhile, separate the rules state by match and audit the thread-safety of every shared resource and engine call. [Godot thread-safe APIs](https://docs.godotengine.org/en/stable/tutorials/performance/thread_safe_apis.html)
- **Reduce the cost of producing data.** Measure feature extraction, repeated option records, JSON conversion, flushes and file size. Keep detailed traces for debugging and benchmark games. For bulk training, store compact typed features, the searched decisions' legal options and visits, and game metadata. Buffer a bounded number of games per write if I/O warrants it, and preserve restartable shards with unique seeds.
- **Use the GPU for dense batches.** The RTX A3000 can train or evaluate larger policy/value models in batches. Measure accelerator transfer and queueing time together with inference. CPU threads still resolve the authoritative, object-heavy rules. A GPU-native rules simulator would require a separate, batch-oriented state representation and a parity effort, so compare it only after simpler CPU and inference changes.
- **Move measured kernels to native code if necessary.** Candidate boundaries include geometry, compact occupancy and state copies, or eventually a data-oriented simulator. Compare a GDExtension prototype to optimized GDScript at equal work. A second implementation of the complete rules has the largest correctness and maintenance cost. [Godot GDExtension overview](https://docs.godotengine.org/en/stable/engine_details/engine_api/gdextension/what_is_gdextension.html)

## First implementation pass

1. Instrument decision generation, rule application, checkpoint capture/restore, and rollout length on the same saved workload. Record the worker scaling curve.
2. Implement the highest-cost exact improvement. From the code, the first candidates are repeated deployment/occupancy/control work, full option encoding inside random rollouts, and capturing checkpoints that sparse search never uses.
3. Repeat the same traces to establish rules parity, then rerun the same paired benchmark with the saved time spent on more simulations. Compare solve rate on upgrade/refutation positions at the same think time.
4. Revisit compact state, undo and GPU batching if the new breakdown identifies restoration or inference as the dominant cost.

# Monte Carlo tree search for Feral Kingdom

Literature and implementation guide, November 2026.

Build **UCT with outcome-only rollouts** as the reference implementation, then compare **tactical MCTS** and **policy/value-guided PUCT** at equal think time. Treat **Gumbel planning** as a candidate for choosing among many root actions with a small search budget. No published result establishes which combination is strongest for Feral Kingdom. The decisive tests are whether the bot finds multi-action plans, finds the opponent's best interruption, and wins held-out games under the live budget.

## 1. What the simulator must provide

The [headless harness](HEADLESS_MATCH.md) already enumerates live legal decisions and replays them through Godot. It operates on one Match autoload per process. A reusable search simulator needs to restore a decision point and explore multiple independent continuations from it.

- Represent a node at a **decision boundary**, after automatic resolution has advanced as far as it can. Record its actual decision owner. A cost picker, target picker, and subsequent free action may belong to the same player. An opponent's optional trigger can interrupt that sequence. Turn parity cannot identify the decision owner.
- Start with a warm headless process that rebuilds the match and replays a prefix. Measure prefix cost and simulated decisions per second by phase. If needed, add snapshots at settled boundaries, then handle pending decisions with replay from a nearby checkpoint or explicit continuation state. Avoid process startup inside each simulation.
- Verify restoration by comparing legal decisions, then the results of identical suffixes. Test sibling branches in both orders. Include queued combat, optional triggers owned by either side, stable ability identities, paid-cost failures, shared Bash hexes, and hero sacrifice with a possible rescue.
- Verify which state is observable and whether gameplay has chance outcomes. Use exact engine outcomes at chance nodes and sample their probabilities. A future mode with hidden information would need an observation-aware algorithm. For example, ISMCTS searches information sets rather than giving the policy access to the sampled hidden state as if it were public. [Cowling, Powley and Whitehouse, ISMCTS](https://eprints.whiterose.ac.uk/id/eprint/75048/1/CowlingPowleyWhitehouse2012.pdf)

## 2. Build a reference search

**Flat Monte Carlo.** Give several candidate actions a comparable number of continuations and rank them by mean outcome. Keep this as an experimental control. It tests whether explicitly building a reply tree improves play at the same cost.

**UCT.** For each action edge store visits N and accumulated outcomes W, with Q = W/N. Store outcomes from the perspective of the player who owns the decision at the parent. For an explored edge, select the maximum of:

```text
Q(s,a) + C × sqrt(log(N(s)) / N(s,a))
```

Here N(s) is parent visits. Explore an unvisited action first in the reference implementation. Start with a fixed simulation budget and deterministic seeded tie-breaking. At a new leaf, roll out to the authoritative result. Back up +1 for a win, 0 for a rules draw where supported, and −1 for a loss, relative to **each edge's parent owner**. For example, if player 1 takes three consecutive decisions before player 2 responds, the first three edges receive the same sign. A stalled or capped simulation is an incomplete sample. Track it separately, then revisit horizon policy if the incomplete rate matters. Pick a proven win when proof is available. Otherwise start with highest root visit count and compare alternative root selection rules on tactical fixtures. [Kocsis and Szepesvári, Bandit Based Monte-Carlo Planning](https://aima.eecs.berkeley.edu/~russell/classes/cs294/s11/readings/Kocsis%2BSzepesvari%3A2006.pdf), [Coulom, Efficient Selectivity and Backup Operators](https://www.remi-coulom.fr/CG2006/), [OpenSpiel reference MCTS](https://github.com/google-deepmind/open_spiel/blob/master/open_spiel/python/algorithms/mcts.py)

## 3. Make finite-budget search find combinations

| Technique | What to try and what to measure |
| --- | --- |
| Guided rollouts | Begin with uniform play, then compare rollouts that favor immediate hero threats and legal defenses while retaining exploration. Use the same win/loss result for both. Measure tactical accuracy and outcomes per second. A policy that always chases threats may miss an upgrade sequence or overstate it by failing to defend. |
| Progressive widening | Start with a subset of ranked legal actions and add more as the node earns visits. An experimental schedule is min(legal count, max(1, floor(k × visits^α))) with 0 < α < 1. Tune k and α. Preserve eventual coverage and surface forcing threats and defenses early. This is relevant when the catalogue produces a large deployment menu. Measure root coverage and missed best moves. [Chaslot et al., Progressive Strategies for MCTS](https://project.dke.maastrichtuniversity.nl/games/files/articles/pMCTS.pdf) |
| Progressive bias | Add an action preference that decays with edge visits so empirical outcomes take over. Compare it to widening and PUCT separately. Prefer action-local information such as an available upgrade or legal defensive reply. [Chaslot et al., Progressive Strategies for MCTS](https://project.dke.maastrichtuniversity.nl/games/files/articles/pMCTS.pdf) |
| MCTS-Solver | Keep a proven result separate from Q. A node is a proven win for its owner if one child proves that player's win. Proving loss requires every legal continuation to prove defeat. With widened actions, unopened legal moves prevent a loss proof. Test this first on small fixtures where exhaustive search establishes the result. [Winands, Björnsson and Saito, MCTS-Solver](https://staff.ru.is/yngvi/pdf/WinandsBS08.pdf) |
| Tactical minimax | Search a short window exhaustively around threatened heroes, critical upgrades, and forced continuations. MCTS averages evidence from many samples, so a single devastating reply can be underexplored. Trigger a probe selectively and compare both accuracy and total simulation cost. Selective probes can find a winning reply, but proving safety requires coverage of every relevant opponent reply. [Ramanujan et al., On Adversarial Search Spaces](https://ojs.aaai.org/index.php/ICAPS/article/view/13437), [Baier and Winands, MCTS–Minimax Hybrids](https://dke.maastrichtuniversity.nl/m.winands/documents/mcts-minimax_hybrids_final.pdf) |
| Sequential halving at the root | Allocate initial trials across a candidate set, eliminate weaker moves in rounds, and spend the remaining budget on survivors. Compare against UCT at the root when the budget is fixed and the priority is selecting one move. An anytime variant is relevant when a live clock interrupts the search. [Fabiano and Cazenave, SHUSS](https://www.lamsade.dauphine.fr/~cazenave/papers/SequentialHalvingUsingScores.pdf), [Anytime Sequential Halving in MCTS](https://arxiv.org/abs/2411.07171) |
| RAVE and AMAF | Share evidence about actions seen later in rollouts to reduce cold-start noise. Prioritize experiments where repeated action identities have comparable meanings. An upgrade before an attack differs from an upgrade after it, and actor/target legality changes rapidly in this game. Measure the harm from such order-dependent examples. [Gelly and Silver, Rapid Action Value Estimation](https://www.lamsade.dauphine.fr/~cazenave/mcts-gelly-silver.pdf) |
| Factored action proposals | For broad menus, propose candidates by action family, actor, then target, while exposing the final legal option and preserving true rules decision boundaries. Keep legal target dependencies, payment, and intervening triggers in the simulator. RTS work on combinatorial bandits offers sampling ideas for large action sets. [Ontañón, Combinatorial Multi-armed Bandits for RTS Games](https://arxiv.org/abs/1710.04805), [Hubert et al., Learning and Planning in Complex Action Spaces](https://arxiv.org/abs/2104.06303) |

### Upgrade benchmark

Create paired replay prefixes with the same weak unit, available upgrade, and superficially attractive immediate attack. In one fixture the upgrade path survives the strongest available opponent reply. In the other, change one legal dependency so the opponent can interrupt, for example by Stun, displacement, or a forced hero defense. Include cases where the interruption comes from an optional trigger. Check the expected choices by exhaustive search on a small enough position, or record the verified tactical line and label longer positions as empirical.

At each budget, report whether the AI chooses the setup where it works, chooses a better alternative where it fails, finds the refutation when playing the defender, and reaches the position after the upgrade. A bot can appear to understand the combo merely because its rollout opponent rarely interrupts it. Run the defender test independently.

## 4. Learn what to explore and what a position is worth

**PUCT.** Replace the uniform exploration bonus with a policy prior P(s,a) over the legal actions. A common form is:

```text
Q(s,a) + C_puct × P(s,a) × sqrt(N(s)) / (1 + N(s,a))
```

Keep perspective and terminal handling identical to UCT. Specify what Q means before an edge has any visits, and compare neutral initialization with a parent-value-based first-play estimate. Ensure legal actions that need exploration can receive it. A bad prior can bury a unique winning defense. [Rosin, Multi-armed Bandits with Episode Context](https://chrisrosin.com/isaim2010final.pdf), [Silver et al., AlphaZero](https://arxiv.org/abs/1712.01815), [Grill et al., MCTS as Regularized Policy Optimization](https://proceedings.mlr.press/v119/grill20a.html)

**Model inputs.** Encode both armies and their positions and reserves, relative ownership, terrain/control, activity and Stun, action and deployment budgets, queued combat, and current execution state. Encode legal options as structured records with action kind, ability, actor, recipient, and amount as applicable. Score the current legal list and mask unavailable choices before normalization. This allows a single model to score action and trigger menus of varying sizes. Validate symmetries against the actual map, region ownership, and rules before augmenting data.

**Training loop.** Generate games with the exact simulator. Store each observation, legal list, search target distribution, decision owner, final outcome, setup, seed and rules/model version. Train a policy on the search distribution and a value model on the final outcome from the stated player's perspective. During search, use the value model at newly expanded leaves to reduce long rollouts. Test a policy-only model first to isolate whether better ordering helps, then test the learned value. Keep training games diverse across army compositions, starting seats, tactical positions and older checkpoints. Reserve entire games and army pairings for validation. Keep any exploration noise and temperature schedule explicit and evaluate without training-only noise. [AlphaZero](https://arxiv.org/abs/1712.01815), [ELF OpenGo](https://arxiv.org/abs/1902.04522)

**KataGo techniques.** Once training is a bottleneck, study variable search budgets during self-play, pruning exploration-driven visits from policy targets, and auxiliary targets. The practical question is whether a change buys more strength per training hour on this game. Start with verifiable rule-derived auxiliaries such as whether a terminal hero loss occurs within the next response window in the sampled line. Treat them as training targets while keeping victory as the match objective. [Wu, Accelerating Self-Play Learning in Go](https://arxiv.org/abs/1902.10565)

**Gumbel planning.** With a useful prior and few simulations per choice, compare Gumbel sampling without replacement and sequential halving against standard PUCT. The full method also changes policy improvement and non-root selection, so report whether the experiment is root-only or implements the full algorithm. Compare policy improvement and tactical outcomes at equal inference calls and equal wall time. [Danihelka et al., Policy Improvement by Planning with Gumbel](https://openreview.net/forum?id=bERaNdoegnO)

## 5. Make search fast without changing outcomes

- **Measure first.** Break wall time into restoring state, enumerating decisions, applying rules, rollout length, tree maintenance and model inference. Report completed simulations and engine decisions per second. Time restoration at several depths and through pending triggers.
- **Reuse the matching subtree after an actual decision.** Retain it only if the new authoritative decision state agrees, including the player and pending choices. Reset on invalidation. Measure memory and strength gain.
- **Cache model evaluations before sharing tree statistics.** For transpositions, key all state that can affect future legal play. That includes queued attack ordering, captured references, pending costs, selected identities, timed grants and historical counters consulted by rules. Two identical visible boards can have different futures. Verify full equality on cache hits in a debug build. Graph search needs explicit edge statistics and cycle handling. [Czech et al., Monte-Carlo Graph Search for AlphaZero](https://arxiv.org/abs/2012.11045), [KataGo graph search design](https://github.com/lightvector/katago/blob/master/docs/GraphSearch.md)
- **Parallelize independent matches first.** For a single decision, compare independent root searches with merged visits against serial search. Shared-tree workers can reduce duplicated exploration using in-flight visit accounting or virtual loss, but require isolated simulator state and synchronized updates. Compare strength at equal wall time and watch for duplicated leaves. Batch inference only after measuring batch latency and throughput on the actual deployment hardware. [Chaslot et al., Parallel MCTS](https://dke.maastrichtuniversity.nl/m.winands/documents/multithreadedMCTS2.pdf), [Liu et al., On Effective Parallelization of MCTS](https://arxiv.org/abs/2006.08785)

## 6. Research to track after the main baselines

| Work | When to investigate |
| --- | --- |
| [Monte Carlo Permutation Search, 2025 preprint](https://arxiv.org/abs/2510.06381) | If the classical rollout bot is competitive and sharing evidence between related actions helps. Check whether permutation assumptions transfer to costly, order-dependent effects. |
| [Optimized Posterior Policies, 2026 preprint](https://arxiv.org/abs/2601.01301) | If neural leaf inference dominates search cost. Compare batch-oriented recursive search against standard batched PUCT, including low-latency play. |
| [Uncertainty Propagation via Optimal Transport, ICML 2025](https://proceedings.mlr.press/v267/dam25c.html) | If a future rules mode introduces substantial stochasticity or partial observability. |
| [MuZero](https://arxiv.org/abs/1911.08265) | If exact transitions remain too expensive after profiling and a learned model is worth testing. Feral Kingdom already has authoritative rules, so start with exact transitions and learn the policy and value. |

## 7. Implementation and promotion sequence

1. **Prove the simulator.** Add focused replay fixtures for optional triggers and branch isolation. Establish a fixed-seed and fixed-budget measurement harness. Keep simulator validity and trace reproduction as requirements for every candidate.
2. **Build flat rollouts and UCT.** Compare both with random play. Use several starting army pairings and swap seats per setup. Record capped simulations separately. Confirm the implementation against exhaustive small games and Feral Kingdom tactical fixtures before tuning.
3. **Improve tactical search.** Add one change per experiment. Compare guided rollouts, widening, and tactical probes or solver backups. Retain only changes that improve the upgrade/refutation suite or held-out wins within budget.
4. **Train priors and values.** Compare UCT, PUCT with a prior, and policy/value PUCT with fixed compute and fixed elapsed time. Try Gumbel root allocation if many legal moves remain underexplored. Keep frozen opponents, previous checkpoints, and an independently tuned non-neural bot in the pool.
5. **Validate for release.** For every candidate, report wins/draws/losses by seat and army pair, paired confidence intervals, tactical solve rate by budget, invalid actions, incomplete simulations, p50/p95 think time, root coverage, and depth reached in opposing response windows. Tune on separate games from those used for promotion. Use the average-player playtest target in the [AI roadmap](AI_ROADMAP.md) for the human-facing claim.

The immediate work is the optional-trigger fixture, fast reproducible restoration, and a reference UCT search. Those three deliverables make the rest of the literature testable on the actual game.

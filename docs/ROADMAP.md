# Roadmap: readable Godot feature parity

Updated: 2026-09-26. This is an implementation plan and status reference; each
area distinguishes working slices from remaining work.

## Goal and source of truth

Reach Guerra JS's player-facing capabilities with substantially less handwritten
code, while keeping the game understandable and editable by its owner.
Optimize for fewer concepts and fewer places to edit before optimizing line count.
An explicit ten-line function is better than a cryptic three-line expression.

- [GENERAL_RULES.md](GENERAL_RULES.md) defines intended gameplay.
- [GUERRA_RULES.md](GUERRA_RULES.md) inventories JS mechanics, source symbols,
  and all 77 card definitions in the reference snapshot.
- [SELECTION.md](SELECTION.md) documents working Godot APIs.
- [AGENTS.md](../AGENTS.md) records implementation constraints.
- JS [architecture](../../guerra.game/docs/architecture.md) and
  [current state](../../guerra.game/docs/current-state.md) identify product features
  beyond the rules engine. Verify behavior in code/tests when these summaries disagree.

Parity means equivalent capabilities and explicitly recorded rule differences,
not copying the parser, browser rendering machinery, legacy formats, or module
layout. Self-stun, hero Start recovery, owner End activation, immovable temples, persistent modifier
counters, and regional control follow our intended rules. Do not silently replace
them with older JS behavior.

## 1. Starting point

| Area | Present now | Work still needed |
| --- | --- | --- |
| Board/model | Hexes, flat army, player/property references, live control, control-gated deployment, Move/Fly resolution | Full catalogue/deck formats and movement upgrades |
| Selection | Stateless selectors, typed TargetRef, HEX-to-UNIT adaptation, explicit projections | Additional card-driven predicates and geometry |
| Effects | Shared executions, optional pre-payment acceptance, sequences, ALL, captured triggers, resumable choices, atomic resource cost bundles, conditions | Additional card-driven predicates; M3 lifetimes/schedules |
| Costs | Atomic self-Stun/deactivate/decrement bundles, command-owned token payment, shared sticker/default-cost policy | Additional atomic cost types; M3 sticker/upgrade grants |
| Combat | Queued/instant Fire and Bow, line Cannon, Bomb throw/merge/defuse/ignition/blasts/chains, Move/Fly, Gore, Push/Pull unit and Bomb displacement, Bash with Fast/Titanium/First Strike/Steady, temporary shield consumption | Movement upgrades and additional card interactions |
| Modifiers | Counters, StateModifier, typed read-only modifier/passive/Bow auras, defeat-trigger policy, live region-control +1 physical | Other action families, scheduled lifetimes, contribution provenance in UI |
| Turns | Runner-owned commands, pausable Start/End/combat, tracked allowances, hero Start Stun recovery and owner-only End activation after effects | M3 future-phase scheduling; final format decisions |
| Product | Responsive local two-player test match with one action per turn, parchment styling, card art, two JS heroes, and Move/Fire/Bow/Cannon/Gore/Push/Pull/Bomb samples | Full catalogue/deckbuilder, Fly sample, saves, previews, online service |

M0's documented selection/Fire path remains intact. M1 now blocks Pass, another
action, deployment and token completion while a managed choice is pending. M2's
runner captures matching rules before consequences, retains triggered subject and
target choices, defers bundle followups, and resumes phase/combat continuations.
Atomic cost bundles support the built-in self-Stun, deactivate and decrement
operations; custom cost types need an explicit preflight/commit implementation.

Named Actionttickers and a shared factory policy distinguish Instant, Pierce,
Tireless and Action-free. Conditions support Boolean combinations, selector
quantifiers, numeric property comparisons and explicit historical facts. State
queries use a read-only RuleContext rather than constructing fake executions.

See [M2_EXECUTION.md](M2_EXECUTION.md) for implemented APIs, examples, caller map
and intentional limits, and [TRIGGER_ROADMAP.md](TRIGGER_ROADMAP.md) for the
event-handler/matcher foundation and staged trigger-parity plan. M3 scheduled
lifetimes and broader M4 actions,
full catalogue/deck editing, saves and online play remain future work. The local
test preset uses one action and three deployments per player, with the turn
advancing automatically after a completed action or deployment. These values
remain configurable; this test setup does not settle open format rules.

For card-owned continuous/passive implementation status and remaining work, see
[CONTINUOUS_ROADMAP.md](CONTINUOUS_ROADMAP.md) and the numbered
[RULINGS.md](RULINGS.md). Typed continuous rules, P/F/T/A action stickers, Bow
value counters, and timed action-value grants through End cleanup are implemented.
Remaining M3 work includes broader timed grant types, provenance, and scheduled
consequences.

## 2. How to reduce code without making it harder to read

| Choice | Practical rule |
| --- | --- |
| No parser | Build cards from typed objects and small named factories. Do not port grammar, AST translation, aliases, or text-to-code compatibility. |
| One source of game truth | Match owns runtime state. UI displays it and submits choices; it does not calculate its own combat or legal actions. |
| One action path | Ordinary actions and triggered phrases use the same legality, choice, payment, and mutation operations. |
| Shared selection | Keep selectors independent of verbs. TargetResolver handles domain adaptation once; verbs declare their target kind. |
| Shared mechanics, explicit differences | Reuse contact/immunity/modifier helpers where rules match. Keep Fire's lethal test distinct from physical wounds and Bash. |
| Small vocabulary | Add an abstraction when real cards need it. Avoid a universal interpreter, arbitrary expression language, or class per card. |
| Typed records | Prefer named fields/enums over growing dictionaries of magic keys. Use stable IDs for saved references. |
| Derived state | Calculate modifiers from counters and contributions. Never synchronize a second mutable total. Start with clear scans; cache only after measuring a problem. |
| Godot facilities | Use scenes, signals, controls, and animation tools instead of recreating browser infrastructure. Rendering never determines rule timing. |
| Remove obsolete paths | Migrate callers before deleting compatibility helpers and placeholders. Do not retain two recovery systems or duplicate action APIs. |
| Useful comments | Explain contracts and unusual rules; do not remove documentation/tests to meet a line target. |

Keep a small source-size table as milestones finish: engine, authored cards,
presentation, networking/persistence, and tests counted separately. Establish
JS and Godot baselines with identical inclusion rules, excluding generated files,
dependencies, imported assets, and vendored code. Compare completed capabilities,
not today's prototype against the full JS product. Set a reduction target after
the first playable slice; no defensible fixed percentage exists yet.

## 3. Ownership and boundaries

These are responsibilities, not an instruction to create all these files now.
Keep related short functions together. Split a module when it owns unrelated
rules or becomes difficult to navigate, not simply to hit an arbitrary line limit.

| Owner | Responsibility | Must not own |
| --- | --- | --- |
| Match / runtime records | Units, players, tiles, pending work, authoritative transitions | Rendering and mouse input |
| Selectors + TargetResolver | Candidate queries and typed adaptation | Payment, mutation, UI confirmation |
| EffectExecution + PhraseExecution | Bind SELF once, choose, pay, resume, record outcomes | Card-specific exceptions |
| Verbs + Action | Named action definitions, legality, mutation entry points | A second selection engine |
| CombatResolver | Attack capture, ordering, contact and outcome rules | Choosing targets for the user |
| Condition / Contribution | Read-only conditions; modifier, passive, Bow, and trigger-policy outputs | General provenance records and other action families |
| RulesRunner | Ordered events, schedules, suspension at choices | Recursive phase advancement from every callback |
| Catalogue | Card data and composed effects | Custom UI behavior for individual cards |
| Board / menus | Explain state, display legal choices, submit input | Reimplementing game rules |
| Save/network adapter (later) | Serialize and validate commands/snapshots | Independent combat implementations |

Retain Match as the current access point. Before previews/saves, introduce a
cloneable match-state record behind it incrementally if needed. Do not rewrite
every selector or add dependency injection everywhere in advance.

## 4. Implementation sequence

Each milestone must leave a working demonstration. Port representative cards
alongside mechanics rather than postponing every card until the engine is finished.
Names of new objects below are proposals; only the APIs in SELECTION.md exist today.

### M0 — Fix the contract and make the current slice easy to follow

- Inventory capabilities against GENERAL_RULES and the JS source/test map.
  Track each as missing, partial, complete, or intentional difference.
- Document current public functions using section 5, starting with the call paths
  below. Explain cancellation, costs, and delayed Fire before adding more layers.
- Preserve the selection and Fire regression scenes as the initial safety net.
- Record unresolved allowances, stun side effects, property precedence, and
  spell/exile behavior. Implement independent work while those decisions remain open.

**Complete when:** a reader can follow a selected Fire from card definition to
damage resolution and can identify every deliberately missing rule.

### M1 — A small playable local match

- Load a minimal object-authored catalogue with heroes and combat units; create
  armies from decks and implement setup, deployment, death, and victory.
- Implement intended self-stun payment, hero Start Stun recovery, and owner-only
  End activation after End effects/choices (revised 2026-10-19). Do not retain
  the superseded Start activation path alongside this recovery flow.
- Give one owner responsibility for action tokens, turn advancement, and waiting
  for pending choices. The local controller now tracks sample allowances in one place;
  final format values remain open.
- Calculate regional control from current unit life, printed control bonuses, and
  the home half-point; require control for deployment and derive the implicit +1
  physical bonus live from the unit's current region.
- Wire board action selection, confirm/skip/cancel, and turn display to that owner.
- Support a two-player local match before investing in the full menu system.

**Complete when:** two people can start and finish a small Fire match without
editing runtime state. Reject an unaffordable action without mutation; do not
advance while a choice is unresolved. Fire retains its original target rules.

### M2 — Effects that can drive the real catalogue

- Add conditions needed by actual cards: any/none/nonempty-all, Boolean composition,
  comparisons, event bindings, and historical facts where specified.
- Add ordered sequences and explicit cost bundles. Consequence sequences preserve progress across choices and stop on failure.
  Built-in resource cost bundles now preflight cumulative spending and commit atomically.
  Consequence sequences remain sequential, not atomic.
- Centralize implicit costs and P/F/T/A sticker handling. Named sticker options and shared combat factories now distinguish all four;
  continuous grants and upgrades remain M3 work. Explicit costs replace defaults. Optional/mandatory policy remains
  independent of one/all targeting.
- Build one deterministic pending-work queue. Capture matching triggers at the
  correct occurrence boundary, apply mutation/cleanup, then execute consequences
  in the reference order. Preserve last-known death information.
- Make phase progression wait for this queue. Preserve source/event bindings across
  pauses; revalidate choices against current state. Avoid uncontrolled signal recursion.

**Implemented acceptance coverage:** representative on-deploy, on-death, optional, ALL, and bundled
effects work through the same choice UI. Failed bundle payment changes nothing;
paid costs cannot be paid twice after resuming.

### M3 — Persistent, conditional, and scheduled effects

- Extend StateModifier only as needed into contributions for life/max life,
  properties, and action values/stickers. Retain source identity for explanations.
- Support aura and attached effects with the correct recipient binding;
  separate live derived grants from stored one-time grants.
- Add permanent, until, and removed-after lifetimes; schedules capture concrete
  work for next Start/End or opponent phases and survive source death where required.
- Distinguish stored action counters, timed action-value grants, and live continuous
  contributions. Bow counters and end-of-turn action-value grants now use separate
  storage/evaluation paths; other timed grant kinds remain future work.
- Extend typed counter/flag storage to supported hosts. Queries remain side-effect free.
- Plan a serializable representation for contributions and suspended work now;
  saving live Callables, signal connections, or WeakRefs is not a persistence design.
  The first aura slice supports physical/magical modifiers and implements War
  Temple's +1 physical while a friendly unit is in an unresolved opposing Bash;
  other contribution types remain open.

**Complete when:** a unit can enter/leave an aura without accumulating bonuses,
temporary grants expire in the right order, and scheduled work runs exactly once.
The modifier display can explain counters and each contributing source.

### M4 — Movement and the rest of combat

Implement in small groups with a playable card for each:

| Order | Group | Required edge cases |
| --- | --- | --- |
| 1 | Move, Fly, Push/Pull | Paths versus landing checks, board gap, occupied landing, temple immovability, location events |
| 2 | Bow and physical contact | Permanent wounds, shields, Pierce, Titanium, hit versus wound, captured target identity |
| 3 | Bash and Gore | Shared tiles, delayed/Fast windows, dodge, Steady, First Strike, Titanium precedence, source-death cancellation |
| 4 | Cannon | Line geometry, both owners, magic wounds rather than Fire's lethal test |
| 5 | Bomb throw/light/defuse/explode and displacement | Merge damage, ignition by Fire, seven-hex area, chains, ownership and delayed resolution |
| 6 | Mend, hostile Stun, Revive, upgrades | Healing caps, intended stun policy, hero restrictions, upgrade consumption timing |

Implemented so far in this milestone: ordinary Move/Fly path, range and landing
rules with immediate Bash-dodge cleanup; Bow's captured-victim physical damage and
contact events; Cannon's straight-line magical damage; Bomb throw/merge, defuse,
Fire ignition, area damage, and delayed chain blasts; Gore leaps and hits; Push/
Pull of units and bombs; delayed Bash with the listed combat passives; Mend's
allied healing with a max-life cap; additive hostile Stun with Start recovery; and
death-triggered Revive to full-life reserve. Stun preserves all other counters, including temporary protection (2026-10-26 ruling). Board Return moves a deployed card to its owner's hand without resetting it.
Movement upgrades and the remaining listed actions remain open. Combat now waits for
triggered choices, and Bow/Gore/Bash share physical Hit/Wound publication.

Continue broadening the combat window to the full reference ordering and triggered
phase continuations: Bow/Gore, Cannon/Bomb, Fire, then eligible Bash. Resolve
interaction cases when adding trigger scheduling, movement upgrades, hostile
Stun, and the remaining upgrade actions.

**Complete when:** a mixed-combat turn resolves deterministically with the correct
shield consumption, deaths, events, and interrupted choices. Test damage formulas
with examples, not just successful method calls.

### M5 — Regional control (pulled forward into M1)

Control totals, home tie-breaks, neutral ties, control-gated deployment, and the
derived +1 physical contribution are implemented for the current prototype.
Control does not include that physical bonus. Later movement and damage work must
call the same calculation after each relevant state change.

**Complete when:** satisfied for current deployment and combat rules; card-specific
deployment filters remain future work.

### M6 — Catalogue completeness and editing workflow

- Port all 77 snapshot cards in mechanic groups using reusable object factories.
  Keep printed values, properties, and effect composition together.
- Maintain a card checklist linking each card to its required mechanics and status.
  Unsupported effects must be visible, never silently ignored.
- Keep readable authored card text initially. If descriptions drift, add simple
  formatting methods to the same objects; a natural-language parser is unnecessary.
- Add deck validation and builder UI for supported formats, unique cards, one hero,
  card details, and saved deck choices.
- Add spells/exile only after their intended rules are defined; distinguish those
  additions from JS parity work.

**Complete when:** every reference card is accounted for, including documented
intentional changes, and the owner can add a card using existing mechanics without
changing the execution engine. New mechanics should require a small localized change.

### M7 — Saves, playground, previews, and usable presentation

- Save versioned runtime data, decks, counters, grants, pending attacks, schedules,
  and choice continuations. Rebuild definition references from stable catalogue IDs.
- Add load validation and a documented version policy; do not copy JS legacy
  migrations unless importing those saves becomes a requirement.
- Build a local playground for setting up positions, inspecting effective values,
  saving scenarios, and replaying failures.
- Compute semantic previews by running the same transition against isolated state.
  Preview must not mutate the live match, send events to its UI, or persist changes.
- Complete tray/actions, card inspection, range/path/area highlights, control and
  modifier explanations, animations, and reduced-motion support.

**Complete when:** saving mid-choice and loading produces the same continuation;
preview matches confirmation from unchanged state. Animations can be disabled
without changing timing or results.

### M8 — Online product parity

Relay infrastructure slice (2026-11-05): `relay/` now supplies a standalone
Cloudflare Worker/Durable Object lobby and authenticated two-seat message relay,
with 8/12/16 army size, 8/10/12 initial deployment pools, exact compatibility,
Ready/start and reconnect reservations. The host Godot client remains the rules
authority under the user's confirmed direction; the server forwards opaque
messages and never duplicates the game rules. This supersedes dedicated rules
hosting for the current multiplayer plan. The Godot client now connects Host/Find,
saved-deck Ready/start, host-validated commands/choices, authenticated trigger
acknowledgements and checkpoint-plus-command-tail reconnect. Compile-only
verification passed; behavioral tests and two-client gameplay/resume acceptance
remain unrun M8 work. See `relay/README.md` and `docs/MULTIPLAYER.md`.

- Add a transport adapter around the existing authoritative rules path. The host
  validates both players' commands and choices; the relay authenticates seats and
  forwards messages. The guest cannot author confirmed outcomes.
- Cover nickname/session entry, saved decks, matchmaking, match entry/resume,
  reconnect snapshots, and persistence equivalent to the JS product.
- Version commands/snapshots and reject stale choices/previews using a revision.
- Decide transport/hosting from actual deployment needs. Do not port HTTP/browser
  support code line by line or maintain separate Godot and JS rule implementations.

**Complete when:** two clients complete a match, reconnect mid-choice, and receive
identical state; stale/invalid commands cannot spend costs or advance phases.
Full product parity requires this milestone, not only the local rules engine.

## 5. Function documentation: required for every new or changed function

Document functions as they are implemented, not at the end of the project.
Use GDScript `##` comments so the contract is visible in the editor.
For small helpers one or two meaningful lines suffice; for public/stateful
functions include the following details:

| Explain | What the reader needs |
| --- | --- |
| Purpose | The game operation in plain language |
| Inputs | Meaning of IDs, references, units, optional/default values, and valid domains |
| Result | What the return value means, including failure/empty results |
| Side effects | State changed, events emitted, work queued; explicitly say when read-only |
| Timing | Immediate versus delayed behavior and whether a choice can suspend it |
| Used by | Concrete caller or signal connection and why that caller uses it |
| Rule edge | Any surprising behavior and the relevant rulebook section |

Example contract for an existing function (illustrative documentation, not a new API):

```gdscript
## Declares Fire from a deployed unit against a hex; amount must be nonnegative.
## Returns false if illegal. On success captures the attack and announces it.
## Queues delayed Fire, or resolves it now when instant is true.
## Used by Action.fire(), called through the verb created by Verbs.fire().
## Resolution uses a lethal check: surviving units lose no life.
static func declare_fire(source: TargetRef, target: TargetRef, amount: int,
        instant: bool, pierce: bool) -> bool:
    # Implementation lives in scripts/combat/combat_resolver.gd.
    pass
```

Do not paste the example stub over working code. Add the comment to the real
function when documenting it. Do not repeat obvious parameter types in prose.
For an engine callback say “Godot calls this when …”; for a signal handler name
the signal and where it is connected. Label an unused public helper as such,
rather than inventing a caller.

Maintain a short “entry points and callers” table in the relevant subsystem
document when adding/changing public functions. Update caller notes when moving
code. Private helper call sites are easily found by editor “Find References” or
project search; avoid maintaining a second exhaustive index of every private call.

## 6. Current call paths to use as documentation examples

These paths describe current code. Managed commands now enter through
RulesRunner.submit; see M2_EXECUTION.md for trigger/phase continuations.

| Entry / function | Used by / next step |
| --- | --- |
| Collection.fire_DR / bow_DR / cannon_DR / bomb_DR / defuse_bomb / gore_DR in collection.gd | Factories composing activity costs, combat verbs, target selectors, and stickers |
| RulesRunner.submit / Board.observe_execution | Runner owns the command; Board attaches to execution and phrase signals |
| UnitInfo.eval(ieff) in scripts/model/unit_info.gd | Direct entry for a unit's indexed effect; caller still owns action-token accounting |
| EffectExecution.start / _begin in scripts/effects/effect_execution.gd | Validates the effect and starts cost/consequence; emits phrase_started for the board to attach |
| PhraseExecution.begin / choose in scripts/effects/phrase_execution.gd | Started by the effect runner; board choices resume it; resolves and revalidates candidates |
| TargetResolver.resolve in scripts/effects/target_resolver.gd | Phrase candidate queries and event matching; calls the selector and adapts its output to the required kind |
| Effect.Verb.execute_many in effect.gd | PhraseExecution._commit invokes it; calls the verb's action callable for each legal target |
| Verbs.fire / bow / cannon / bomb_throw / defuse_bomb / gore / push / pull in scripts/effects/verbs.gd | Define fixed target kinds and bind action legality/mutation; Collection factories use them |
| Action.fire / bow / cannon / bomb_throw / defuse_bomb / gore / displace in actions.gd | Called by each bound verb; delegate declaration and legality to CombatResolver |
| CombatResolver.resolve_window in scripts/combat/combat_resolver.gd | Runs Bow/Gore, Cannon/Bomb, Fire, then ready Bash; Match.complete_action calls it at the response-window boundary |
| Match.finish_action in scripts/runtime/match.gd | Runner calls after command/deployment followups; spends one token then schedules phase work |
| Match.defeat in scripts/runtime/match.gd | Called by lethal Fire resolution; removes the live position, marks defeat, announces death |
| ControlResolver.region_owner in scripts/runtime/control_resolver.gd | Deployment legality, Querytelector refresh, and UnitInfo's live physical bonus use current strengths |

Reading order: card factory → verb definition → phrase execution → action →
combat resolver. Read selectors separately when changing “which targets”.
Board attachment and highlighting are presentation concerns, not an extra
rules stage. See [SELECTION.md](SELECTION.md) for complete runnable usage and test commands.

## 7. Where the owner should edit common rules

| Desired change | First place to look | Verification |
| --- | --- | --- |
| Printed Fire damage/range | Card definition / Collection factory | New value and valid target range |
| Which entities an action accepts | Verb target kind; selector/projection in its phrase | Correct kind and invalid targets rejected |
| Fire lethal behavior | CombatResolver.resolve_fire | Survivor, lethal, Pierce, immunity, temporary protection |
| Counter/state/control modifier behavior | UnitInfo, StateModifier, and ControlResolver | Values recompute without accumulating or entering control totals |
| Cost or turn policy | Collection.action_cost, Match.finish_action, and LocalMatchController allowance exports | Cannot overspend; no double payment or premature phase change |
| Highlight/choice display | scripts/board/board.gd | Same legal candidates, including off-board choices |
| New triggered card | Catalogue composition after M2 | Event binding, optional choice, and one real interaction |
| New mechanic | Named action + verb; resolver only if combat requires it | One representative card and rule-level regression |

Prefer readable names in new APIs; retain existing names until their callers are
migrated deliberately. Show a short complete card example whenever a new authoring
object is introduced. Clearly label planned examples until they actually run.

## 8. Completion and maintenance discipline

For each implementation slice:

1. State the rule, intentional JS differences, and observable expected result.
2. Add the smallest reusable implementation and one real card/scenario using it.
3. Document every function written/changed and where its entry points are used.
4. Test meaningful rule boundaries: illegal input leaves state unchanged; one/all
   choices, source/target changes, costs, and event order where relevant.
5. Run the affected headless regression scenes. Broaden checks only when shared
   behavior changed; documentation-only edits need link/content checks, not game tests.
6. Update the parity/card checklist, source-size categories, and affected usage docs.
7. Remove superseded code after callers migrate; leave no hidden fallback rules.

A feature is not finished merely because its method exists. The owner should be
able to locate its rule, follow its callers, explain its effects, change a value
or compose a card, and verify the result without assistant supervision.

Disable-card slice (2026-10-27): Mara adds persistent Cannon damage/range counter
support alongside Bow; Tamia composes existing Disable and deployment grants;
Grey Squirrel uses the existing Action-free/timed action-value grant path.
All 35 existing PixelLab characters now have playable definitions for both
owners. Other action-counter families and broader scheduling remain future
work. See DISABLE_UNITS.md for exact implemented rules and focused coverage.

### Approved 28-unit expansion (2026-10-28)

The user-requested [MY_28_UNIT_PROPOSALS.md](MY_28_UNIT_PROPOSALS.md) roster is
implemented through SynergyCatalogue/SynergyRules/SynergyActions, appended after
all previous IDs. Both owners now have 63 sprite-backed cards; the full catalogue
has 80 definitions. Shared additions are independent A/S costs, stored control,
projectiles and next-Fire Ember, Cannon/Fire Hit/Wound, bounded counter transfers,
atomic Sacrifice with a causal hero-rescue window, adjacent Deploy suppression,
and read-only Bash action allowances with retained spending. Physical-axis reads
keep Guardian threshold dependencies from recursing through magical/Bow rewards.
Snapshot support retains spending and displacement history. Native art imports,
usage/ruling documents and focused per-effect regressions accompany the roster.
General future-phase scheduling and unrelated roadmap stages remain deferred.
See [SYNERGY_UNITS.md](SYNERGY_UNITS.md) for current interfaces and caller maps.

### Frontier roster slice (2026-11-07)

The eleven approved [frontier cards](FRONTIER_UNITS.md) append after the
previous catalogue IDs. This slice adds a persisted once-per-turn trigger
ledger, captured Sacrifice life, enemy-control deployment permission and
compulsory Bash destination selection for Walk. It reuses typed timed
modifiers and the existing two-player trigger, payment and selection paths.

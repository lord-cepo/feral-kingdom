extends Node

const Harness = preload("res://scripts/runtime/headless_match.gd")
const Search = preload("res://scripts/runtime/mcts.gd")
const Snapshot = preload("res://scripts/runtime/simulation_snapshot.gd")
const Heuristic = preload("res://scripts/runtime/tactical_heuristic.gd")
const ValueModel = preload("res://scripts/runtime/mcts_value.gd")
const MAX_DECISIONS := 512
const VALUE_FEATURE_COUNT := 26
const VALUE_ROLLOUT_LIMIT := 48

var harness := Harness.new()
var search := Search.new()
var heuristic := Heuristic.new()
var opponent_heuristic := Heuristic.new()
var tree_heuristic := Heuristic.new()
var value_model: ValueModel
var value_horizon := VALUE_ROLLOUT_LIMIT
var minimum_advantage := 0.0
var checkpoint: Snapshot
var suffix: Array[Dictionary] = []
var rejected := false
var roster_ids := [0, 1]
var pairings := [[0, 1], [0, 2], [0, 3], [1, 2], [1, 3], [2, 3]]

## Starts the data-generation job once the Match autoload is ready.
func _ready() -> void:
	_generate.call_deferred()


## Builds one of the four three-card armies used by the benchmark and diverse self-play modes.
func _roster(identifier: int, owner: int) -> Array[UnitInfo]:
	match identifier:
		0: return [CardCatalogue.squirrel_king(owner), CardCatalogue.reed_archer(owner), CardCatalogue.walnut_crab(owner)]
		1: return [CardCatalogue.mole_artificer(owner), CardCatalogue.thunder_toad(owner), CardCatalogue.pine_processionary(owner)]
		2: return [CardCatalogue.queen_bee(owner), CardCatalogue.rat_musketeer(owner), CardCatalogue.rat_thief(owner)]
		_: return [CardCatalogue.squirrel_king(owner), CardCatalogue.mole_miner(owner), CardCatalogue.wild_beaver(owner)]


## Starts one self-play or benchmark game with the preset armies or the full playable catalogue.
## _play calls this once; simulation restores reuse this game's catalogue and map.
func _start_game(full_army: bool) -> Dictionary:
	var army: Array[UnitInfo]
	if full_army:
		army = CardCatalogue.starter_army()
	else:
		army = _roster(roster_ids[0], 1)
		army.append_array(_roster(roster_ids[1], 2))
	if not harness.start(army, 1, 8):
		rejected = true
		return {}
	return harness.decision()


## Restores the search root from its latest settled checkpoint and the choices
## that led into the current picker. MCTS calls this before each simulation.
func _restore() -> Dictionary:
	if not harness.restore_snapshot(checkpoint, suffix):
		rejected = true
		return {}
	return harness.decision()


## Search consumes only an option emitted by decision() for the current state.
## The authority still rechecks deployment, effect execution and target legality.
func _advance(option: Dictionary) -> Dictionary:
	if not harness._apply(option):
		rejected = true
		return {}
	return harness.decision()


## Plays a continuation after MCTS expands a node. Guided search ranks the
## first target picker so a promising command can lead to a plausible target.
## Subsequent picks use the cheap sampler until the game or horizon ends.
func _sample_rollout(current: Dictionary, rng: RandomNumberGenerator, limit: int, guided: bool = false) -> int:
	if current.is_empty() or limit <= 0 or rejected: return 0
	var index := rng.randi_range(0, current.options.size() - 1)
	if guided and current.options.size() > 1 and current.options[0].kind == "choose":
		var preferred := tree_heuristic.rank(current, false, false)
		if not preferred.is_empty(): index = preferred[0]
	var option: Dictionary = current.options[index]
	for step in limit:
		if option.is_empty(): return step
		if not harness._apply(option):
			rejected = true
			return step
		if Match.winner != 0: return step + 1
		if step + 1 < limit: option = harness.sample_option(rng)
	# The enumerated rollout also checks for a no-action loss after its final move.
	harness.decision()
	return limit


## Returns the authority's winner to the search. Zero means no terminal outcome was observed.
func _winner() -> int:
	return Match.winner if not rejected else 0


## Supplies the tree with a complete heuristic order without recording
## simulated landings in either live player's history.
func _rank_tree(decision: Dictionary) -> Array[int]:
	return tree_heuristic.rank(decision, true, false)


## Encodes fixed-size full-catalogue positions for both recorded examples and
## model inference. Features are relative to the requested player's seat.
func _value_features(owner: int) -> Array:
	var features: Array = [owner, int(Match.active_player == owner), mini(Match.turn_number, 100) / 100.0]
	for seat in [owner, 3 - owner]:
		var player: Player = Match.players[seat]
		var field := 0
		var ready := 0
		var life := 0
		var hero_life := 0
		var power := 0
		var stun := 0
		var upgrades := 0
		for unit in Match.army:
			if unit.player != seat or unit.t_state != Enum.t_state.DEPLOYED: continue
			field += 1
			ready += int(unit.active)
			life += unit.actual_life
			if unit.type == Enum.type.HERO: hero_life += unit.actual_life
			power += unit._counter_value(UnitInfo.PHYSICAL_COUNTER) + unit._counter_value(UnitInfo.MAGICAL_COUNTER)
			stun += unit._counter_value(UnitInfo.STUN_COUNTER)
			upgrades += unit.ability_upgrades.size()
		features.append_array([player.actions_remaining, player.deployments_remaining, field, ready,
			life, hero_life, power, stun, upgrades])
	features.append_array([Match.pending_attacks.size(), Match.pending_bow_attacks.size(),
		Match.pending_cannon_attacks.size(), Match.pending_gore_attacks.size(), Match.bashes.size()])
	return features


## Gives MCTS a player-one estimate after a truncated rollout. Averaging both
## perspectives makes the predicted values for the seats zero-sum.
func _evaluate_value() -> float:
	return (value_model.value(_value_features(1)) - value_model.value(_value_features(2))) * 0.5


## Encodes board state and current budget for offline value fitting, from the decision owner's perspective.
func _features(owner: int, diverse: bool) -> Array:
	var features: Array = [owner, Match.active_player == owner, Match.phase, mini(Match.turn_number, 100) / 100.0]
	for player in [owner, 3 - owner]:
		var participant: Player = Match.players[player]
		features.append_array([participant.actions_remaining, participant.deployments_remaining / 8.0])
	for unit in Match.army:
		var tile := Match.get_hex(unit.ihx)
		var stun := Match.get_property(TargetRef.property(TargetRef.unit(unit.iun), UnitInfo.STUN_COUNTER))
		features.append_array([
			unit.player == owner, unit.t_state, unit.active, unit.actual_life / 10.0,
			stun.value / 5.0 if stun != null else 0.0,
			tile.coordinate.x / 4.0 if tile != null else 0.0,
			tile.coordinate.y / 3.0 if tile != null else 0.0,
			unit.physical_modifier / 5.0, unit.magical_modifier / 5.0,
		])
	features.append_array([
		Match.pending_attacks.size(), Match.pending_bow_attacks.size(), Match.pending_gore_attacks.size(),
		Match.pending_cannon_attacks.size(), Match.bombs.size(), Match.bashes.size(),
	])
	if diverse:
		for roster in roster_ids:
			for identifier in 4: features.append(int(roster == identifier))
	return features


## Plays one game for _generate(). Refreshes checkpoints on the committed path
## and labels observations only when an authoritative winner is known. Full
## benchmark games report deployment coverage and use no training rows. Their
## interval counts eligible decisions owned by the search seat, including its first.
## Guided games rank exposure before UCT expands a root and use the first
## ranked choice between searches, including at target and supported cost pickers.
func _play(seed_value: int, budget: int, search_interval: int, mode: String, sampled: bool, guided: bool) -> Dictionary:
	checkpoint = null
	suffix.clear()
	rejected = false
	heuristic = Heuristic.new()
	opponent_heuristic = Heuristic.new()
	var full_training := mode in ["full-training", "full-training-random"]
	var varied_duel := mode == "full-duel-varied"
	var full_army := mode in ["full-benchmark", "full-training", "full-training-random", "full-duel", "full-duel-varied"]
	var guided_opponent := mode in ["full-training", "full-duel", "full-duel-varied"]
	var benchmark := mode == "benchmark" or full_army
	var diverse := mode == "diverse"
	var search_seat := 0
	var pairing := ""
	var play_seed := seed_value
	if full_army:
		pairing = "full-catalogue"
		search_seat = 1 + seed_value % 2
		play_seed = seed_value - seed_value % 2
	elif benchmark or diverse:
		var stride := 4 if benchmark else 2
		var pairing_index := (seed_value / stride) % pairings.size()
		var pair: Array = pairings[pairing_index]
		pairing = "%d-%d" % [pair[0], pair[1]]
		var swapped := seed_value % stride >= stride / 2
		roster_ids = [pair[1], pair[0]] if swapped else pair.duplicate()
		if benchmark:
			search_seat = 1 + seed_value % 2
			play_seed = seed_value - seed_value % 2
	var policy_rng := RandomNumberGenerator.new()
	policy_rng.seed = play_seed
	search.rng.seed = play_seed
	var current := _start_game(full_army)
	var replay_steps: Array[Dictionary] = []
	var army_sizes: Array[int] = [0, 0]
	if not rejected:
		for unit: UnitInfo in Match.army: army_sizes[unit.player - 1] += 1
	var first_search := {}
	var deploy_candidates := 0
	var deploy_explored := 0
	var search_calls := 0
	var search_opportunities := 0
	var rows: Array[Dictionary] = []
	var simulations := 0
	var attempts := 0
	var simulated_steps := 0
	var search_us := 0
	var guided_searches := 0
	var dodge_overrides := 0
	var heuristic_choices := 0
	var widened_choices := 0
	var widened_searches := 0
	var estimated_simulations := 0
	var opening_exploration := 0
	var evidence_fallbacks := 0
	var rollout := _sample_rollout.bind(guided) if sampled else Callable()
	var decision_count := 0
	for step in MAX_DECISIONS:
		if current.is_empty() or rejected: break
		if budget > 0 and not Match.rules_runner.busy():
			var settled := harness.checkpoint()
			if settled != null:
				checkpoint = settled
				suffix.clear()
		var options: Array = current.options
		var selected: Dictionary = options[0]
		if options.size() > 1:
			var features := _value_features(current.player) if full_training else []
			if not benchmark: features = _features(current.player, diverse)
			var result := {"index": policy_rng.randi_range(0, options.size() - 1), "visits": [], "completed": 0}
			var owns_search: bool = search_seat == 0 or current.player == search_seat
			var neutral_opening := varied_duel and Match.turn_number < 8
			var interval_step := search_opportunities if full_army else step
			if owns_search and not neutral_opening: search_opportunities += 1
			var scheduled: bool = budget > 0 and interval_step % search_interval == 0 and owns_search and not neutral_opening
			var started := Time.get_ticks_usec()
			var preferred: Array[int] = []
			var order: Array[int] = []
			if guided and owns_search:
				if scheduled:
					order = heuristic.rank(current, true)
					preferred.assign(order.slice(0, heuristic.safest_count))
				else:
					preferred = heuristic.rank(current)
			elif guided_opponent:
				preferred = opponent_heuristic.rank(current)
			if scheduled:
				if not order.is_empty(): guided_searches += 1
				result = search.search(current, budget, _restore, _advance, _winner, rollout,
					order, _rank_tree if guided else Callable(), _evaluate_value if value_model != null else Callable(),
					value_horizon if value_model != null else Search.ROLLOUT_LIMIT)
				search_us += Time.get_ticks_usec() - started
				if rejected or result.is_empty() or _restore() != current:
					rejected = true
					break
				attempts += budget
				simulated_steps += int(result.steps)
				search_calls += 1
				estimated_simulations += int(result.estimated)
				if minimum_advantage > 0.0 and not preferred.is_empty() and result.index != preferred[0]:
					var required := minimum_advantage if result.index in preferred else 2.0 * minimum_advantage
					if result.visits[result.index] < 2 or float(result.advantage) < required:
						result.index = preferred[0]
						evidence_fallbacks += 1
				var cutoff: Array = preferred.slice(0, maxi(1, budget / 2))
				if not cutoff.is_empty():
					if result.explored.any(func(index: int) -> bool: return index not in cutoff):
						widened_searches += 1
					if result.index not in cutoff: widened_choices += 1
				if full_army:
					var deploy_count := 0
					var explored_deployments := 0
					for option: Dictionary in options:
						if option.kind == "deploy": deploy_count += 1
					for index: int in result.explored:
						if options[index].kind == "deploy": explored_deployments += 1
					deploy_candidates += deploy_count
					deploy_explored += explored_deployments
					if first_search.is_empty():
						first_search = {"options": options.size(), "explored": result.explored.size(),
							"deployments": deploy_count, "deployments_explored": explored_deployments,
							"safest_options": preferred.size()}
						print("seed %d full-catalogue first search: %d of %d choices explored" % [
							seed_value, first_search.explored, first_search.options])
			elif not preferred.is_empty():
				result.index = preferred[0]
				if (neutral_opening or (full_training and Match.turn_number < 16)) and preferred.size() > 1 \
						and policy_rng.randf() < 0.25:
					result.index = preferred[policy_rng.randi_range(1, mini(3, preferred.size() - 1))]
					opening_exploration += 1
				heuristic_choices += 1
				if owns_search and heuristic.can_avoid_pending: dodge_overrides += 1
			selected = options[result.index]
			simulations += int(result.completed)
			if full_training:
				rows.append({"owner": current.player, "features": features})
			elif not benchmark:
				rows.append({"owner": current.player, "features": features, "options": options, "visits": result.visits})
		if budget > 0: suffix.append({"player": current.player, "option": selected})
		if full_army: replay_steps.append({"player": current.player, "option": selected})
		current = _advance(selected)
		decision_count += 1
	var victor := _winner()
	return {"seed": seed_value, "budget": budget, "search_interval": search_interval,
		"pairing": pairing, "rosters": [] if full_army else roster_ids.duplicate(), "search_seat": search_seat,
		"army_sizes": army_sizes, "deployment_allowance": 8, "action_allowance": 1,
		"winner": victor, "decisions": decision_count,
		"simulations": simulations, "simulation_attempts": attempts, "simulated_steps": simulated_steps,
		"search_us": search_us, "search_calls": search_calls, "first_search": first_search,
		"deployment_candidates": deploy_candidates, "deployments_explored": deploy_explored,
		"rollout_policy": "sampled" if sampled else "enumerated",
		"search_policy": "guided" if guided else "plain", "guided_searches": guided_searches,
		"dodge_overrides": dodge_overrides,
		"heuristic_choices": heuristic_choices,
		"widened_searches": widened_searches, "widened_choices": widened_choices,
		"estimated_simulations": estimated_simulations,
		"value_horizon": value_horizon if value_model != null else 0,
		"evidence_fallbacks": evidence_fallbacks, "minimum_advantage": minimum_advantage,
		"opening_exploration": opening_exploration,
		"mode": mode,
		"replay_steps": replay_steps,
		"rejected": rejected, "rows": rows if victor != 0 else []}


## Runs a finite self-play shard in a warm Godot process and flushes each game as JSONL.
## Optional policy arguments select sampled rollouts and tactical root guidance.
func _generate() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 4 or args.size() > 11 or not args[0].is_valid_int() or not args[1].is_valid_int() or not args[2].is_valid_int() \
			or args[0].to_int() < 0 or args[1].to_int() < 1 or args[2].to_int() < 0 \
			or (args.size() >= 5 and (not args[4].is_valid_int() or args[4].to_int() < 1)) \
			or (args.size() >= 6 and args[5] not in ["diverse", "benchmark", "full-benchmark", "full-training", "full-training-random", "full-duel", "full-duel-varied"]) \
			or (args.size() >= 7 and args[6] not in ["sampled", "enumerated"]) \
			or (args.size() >= 8 and args[7] not in ["guided", "plain"]) \
			or (args.size() >= 9 and args[5] not in ["full-training", "full-training-random", "full-benchmark", "full-duel", "full-duel-varied"]) \
			or (args.size() >= 10 and (not args[9].is_valid_int() or args[9].to_int() < 0 \
				or args[9].to_int() > Search.ROLLOUT_LIMIT)) \
			or (args.size() == 11 and (not args[10].is_valid_float() or args[10].to_float() < 0.0 \
				or args[10].to_float() > 1.0)):
		printerr("Usage: -- FIRST_SEED GAMES SIMULATIONS OUTPUT.jsonl [SEARCH_INTERVAL [MODE [sampled|enumerated [guided|plain [MODEL.json [ROLLOUT_LIMIT [MIN_ADVANTAGE]]]]]]]")
		get_tree().quit(1)
		return
	if args.size() >= 9:
		value_model = ValueModel.new()
		if not value_model.load_checkpoint(args[8], VALUE_FEATURE_COUNT):
			printerr("Could not load a compatible full-catalogue value model.")
			get_tree().quit(1)
			return
		if args.size() >= 10: value_horizon = args[9].to_int()
		if args.size() == 11: minimum_advantage = args[10].to_float()
	var output := FileAccess.open(args[3], FileAccess.WRITE)
	if output == null:
		printerr("Could not open the self-play shard.")
		get_tree().quit(1)
		return
	for index in args[1].to_int():
		var started := Time.get_ticks_msec()
		var interval := args[4].to_int() if args.size() >= 5 else 1
		var mode := args[5] if args.size() >= 6 else "pilot"
		var sampled := args.size() >= 7 and args[6] == "sampled"
		var guided := args.size() >= 8 and args[7] == "guided"
		var game := _play(args[0].to_int() + index, args[2].to_int(), interval, mode, sampled, guided)
		game["elapsed_ms"] = Time.get_ticks_msec() - started
		output.store_line(JSON.stringify(game))
		output.flush()
		print("seed %d winner %d decisions %d terminal simulations %d elapsed %d ms" % [
			game.seed, game.winner, game.decisions, game.simulations, game.elapsed_ms])
		if game.rejected:
			get_tree().quit(2)
			return
		await get_tree().process_frame
	get_tree().quit()

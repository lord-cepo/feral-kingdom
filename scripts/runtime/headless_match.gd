class_name HeadlessMatch
extends RefCounted

const SimulationSnapshot = preload("res://scripts/runtime/simulation_snapshot.gd")
const SAMPLE_ATTEMPTS := 8

## Starts a fresh offline match for the headless driver using the normal map and army setup.
## Each driver owns the Match autoload for one game at a time. Pass fresh units for each setup.
func start(units: Array[UnitInfo], actions: int, deployments: int) -> bool:
	if NetworkSession.online: return false
	var regions := RegionMap.new()
	regions._generate_hex_grid()
	regions.free()
	Match.rules_runner.trigger_acknowledgements_enabled = false
	Match.rules_runner.presentation_busy_query = Callable()
	return Match.start_local_match(units, actions, deployments)


## Captures a settled Action boundary for a headless policy. A null result
## means the policy should retain its previous checkpoint and subsequent choices.
func checkpoint() -> SimulationSnapshot:
	var snapshot := SimulationSnapshot.new()
	return snapshot if snapshot.capture() else null


## Restores a checkpoint and replays the choices needed to rebuild a suspended
## rules continuation. The caller then uses decision() to get the live picker.
func restore_snapshot(snapshot: SimulationSnapshot, suffix: Array[Dictionary]) -> bool:
	if snapshot == null or not snapshot.restore(): return false
	for entry in suffix:
		if not submit(entry.player, entry.option): return false
	return true


## Returns the next decision to the headless policy or replay driver after synchronous rules settle.
## A busy runner can offer a choice owned by either seat. An empty result means terminal or stalled.
func decision() -> Dictionary:
	if Match.winner != 0 or Match.rules_runner.halted: return {}
	var run := Match.rules_runner.active
	if run != null:
		return _effect_decision(run)
	if Match.rules_runner.busy() or Match.phase != Match.Phase.ACTION: return {}
	var options: Array[Dictionary] = []
	for unit in Match.army:
		if unit.player != Match.active_player: continue
		if unit.t_state == Enum.t_state.UNDEPLOYED:
			for tile in Match.map:
				if Match.can_deploy(unit.iun, tile.hex_id):
					options.append({"kind": "deploy", "unit": unit.iun, "hex": tile.hex_id})
		elif unit.t_state == Enum.t_state.DEPLOYED:
			for slot in unit.effects.size():
				var effect: Effect = unit.effects[slot]
				if Match.rules_runner.command_available(effect, TargetRef.unit(unit.iun)):
					options.append({"kind": "effect", "unit": unit.iun, "slot": slot})
	if options.is_empty():
		Match._check_no_legal_actions()
		return {}
	return {"player": Match.active_player, "options": options}


## Draws one uniform legal option for an MCTS rollout. Each live unit contributes
## one candidate per action slot or board cell, so larger groups get proportionate weight.
## Every proposal uses the current rules. The full picker handles sparse menus,
## pending choices, required hero deployments and the settled no-action loss.
func sample_option(rng: RandomNumberGenerator) -> Dictionary:
	if Match.winner != 0 or Match.rules_runner.halted: return {}
	if Match.rules_runner.busy() or Match.phase != Match.Phase.ACTION:
		return _sample_decision(rng)
	if Match.hero_deployment_required(): return _sample_decision(rng)
	var units: Array[UnitInfo] = []
	var ends: Array[int] = []
	var count := 0
	var player: Player = Match.players[Match.active_player]
	var can_deploy := player.deployments_remaining > 0 and player.actions_remaining > 0
	for unit: UnitInfo in Match.army:
		if unit == null or unit.player != player.id: continue
		var size := 0
		if unit.t_state == Enum.t_state.DEPLOYED:
			size = unit.effects.size()
		elif can_deploy and unit.t_state == Enum.t_state.UNDEPLOYED:
			if unit.type == Enum.type.HERO and player.selected_hero_id >= 0 and player.selected_hero_id != unit.iun: continue
			size = Match.map.size()
		if size == 0: continue
		count += size
		units.append(unit)
		ends.append(count)
	if count > 0:
		for attempt in SAMPLE_ATTEMPTS:
			var index := rng.randi_range(0, count - 1)
			var group := 0
			while index >= ends[group]: group += 1
			var slot := index if group == 0 else index - ends[group - 1]
			var unit := units[group]
			if unit.t_state == Enum.t_state.DEPLOYED:
				if Match.rules_runner.command_available(unit.effects[slot], TargetRef.unit(unit.iun)):
					return {"kind": "effect", "unit": unit.iun, "slot": slot}
			else:
				var tile := Match.map[slot]
				if tile != null and Match.can_deploy(unit.iun, tile.hex_id):
					return {"kind": "deploy", "unit": unit.iun, "hex": tile.hex_id}
	return _sample_decision(rng)


## Samples the full legal picker for sample_option(), including a trigger owned by either seat.
## Calling decision() also settles the authoritative loss when no legal option exists.
func _sample_decision(rng: RandomNumberGenerator) -> Dictionary:
	var current := decision()
	if current.is_empty(): return {}
	return current.options[rng.randi_range(0, current.options.size() - 1)]


## Builds the exact pending picker for decision(), using the same source-owner convention as network authorization.
func _effect_decision(run: EffectExecution) -> Dictionary:
	var owner := Match.owner_of(run.source)
	if owner not in [1, 2]: return {}
	var options: Array[Dictionary] = []
	var phrase := run.current
	if run.status == EffectExecution.Status.CONFIRMING:
		options.assign([{"kind": "confirm_effect", "accepted": false}, {"kind": "confirm_effect", "accepted": true}])
	elif phrase != null:
		match phrase.status:
			PhraseExecution.Status.CONFIRMING:
				options.assign([{"kind": "confirm_phrase", "accepted": false}, {"kind": "confirm_phrase", "accepted": true}])
			PhraseExecution.Status.SUBJECT, PhraseExecution.Status.TARGET:
				var has_ability := false
				for candidate in phrase.candidates:
					var ref := _trace_ref(candidate)
					has_ability = has_ability or str(ref.get("key", "")).begins_with("ability:")
					options.append({"kind": "choose", "ref": ref})
				if has_ability:
					options.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
						return JSON.stringify(left) < JSON.stringify(right))
			PhraseExecution.Status.AMOUNT:
				for amount in range(1, phrase.amount_max + 1):
					options.append({"kind": "amount", "amount": amount})
	return {"player": owner, "options": options} if not options.is_empty() else {}


## Encodes a candidate for the policy and replay log. Ability pickers use the authored origin
## because the live synthetic property key contains a process-local object ID.
func _trace_ref(candidate: TargetRef) -> Dictionary:
	var encoded := NetworkSession.encode_ref(candidate)
	if candidate.kind == TargetRef.Kind.PROPERTY and String(candidate.property_key).begins_with("effect:"):
		var option := Match.get_property(candidate) as EffectOption
		if option != null:
			encoded.key = "ability:%s:%d:%d" % [option.category, option.origin_unit, option.origin_index]
	return encoded


## Applies an option from the caller's current decision, checking its owner and identity against live choices.
## A consumed picker can lead to a failed consequence. The runner still settles that choice and any paid cost.
func submit(player: int, option: Dictionary) -> bool:
	var current := decision()
	if current.is_empty() or player != current.player: return false
	for legal: Dictionary in current.options:
		if legal == option: return _apply(legal)
	var decoded: Variant = JSON.parse_string(JSON.stringify(option))
	for legal: Dictionary in current.options:
		if JSON.parse_string(JSON.stringify(legal)) == decoded: return _apply(legal)
	return false


## Dispatches a validated option from submit() through the normal authority entry points.
func _apply(option: Dictionary) -> bool:
	var run := Match.rules_runner.active
	match option.kind:
		"deploy": return Match.deploy(option.unit, option.hex)
		"effect":
			var unit := Match.get_unit(option.unit)
			return Match.rules_runner.submit(unit.effects[option.slot], TargetRef.unit(unit.iun), true)
		"confirm_effect": run.confirm(option.accepted)
		"confirm_phrase": run.current.confirm(option.accepted)
		"choose":
			for candidate in run.current.candidates:
				if _trace_ref(candidate) == option.ref:
					run.current.choose(candidate)
					return true
			return false
		"amount": run.current.choose_amount(option.amount)
		_: return false
	return true

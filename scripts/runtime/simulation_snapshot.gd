extends RefCounted

const MATCH_FIELDS := [
	"phase", "active_player", "turn_number", "winner", "_next_timed_grant_id",
	"props", "pending_attacks", "pending_bow_attacks", "pending_gore_attacks",
	"pending_cannon_attacks", "bombs", "bashes", "sacrificed_heroes", "_transitioning",
]
const UNIT_FIELDS := [
	"uuid", "name", "type", "player", "iun", "ihx", "t_state", "active",
	"actual_life", "max_life", "max_life_changes", "control_bonus", "deploy_regions",
	"deployment_enemy_side", "props", "printed_state", "effects", "trigger_effects",
	"state_effects", "continuous_effects", "timed_grants", "next_fire_stickers",
	"ability_upgrades", "copied_effects", "trigger_turns", "last_displaced_turn",
]
const HEX_FIELDS := ["hex_id", "coordinate", "region", "side", "region_count", "props", "control", "iun", "owner"]
const PLAYER_FIELDS := [
	"id", "name", "props", "action_allowance", "base_actions_remaining",
	"deployment_allowance", "deployments_remaining", "has_deployed",
	"selected_hero_id", "next_turn_actions",
]
const RUNNER_FIELDS := ["dispatched_occurrences", "diagnostics", "operations", "command_owner"]

var _army: Array[UnitInfo]
var _map: Array[HexInfo]
var _players: Dictionary[int, Player]
var _match_state: Dictionary
var _unit_states: Array[Dictionary] = []
var _hex_states: Array[Dictionary] = []
var _player_states: Dictionary = {}
var _runner_state: Dictionary
var _next_occurrence: int


## Captures an in-memory rules checkpoint for HeadlessMatch at a settled action boundary.
## Pending choices are represented by the checkpoint plus subsequent decisions, because the
## runner's queued Callables bind to the original execution and cannot be copied independently.
func capture() -> bool:
	var runner := Match.rules_runner
	if Match.phase != Match.Phase.ACTION or Match._transitioning or runner.busy() or runner.draining \
			or runner.continuation_waiting or not runner.boundary_work.is_empty() \
			or not Match.sacrificed_heroes.is_empty() or CombatResolver._resolving_bash != null:
		return false
	var copies := {}
	_army = Match.army.duplicate()
	_map = Match.map.duplicate()
	_players = Match.players.duplicate()
	_match_state = _read_fields(Match, MATCH_FIELDS, copies)
	_unit_states.clear()
	for unit in _army: _unit_states.append(_read_fields(unit, UNIT_FIELDS, copies))
	_hex_states.clear()
	for tile in _map: _hex_states.append(_read_fields(tile, HEX_FIELDS, copies))
	_player_states.clear()
	for seat in _players: _player_states[seat] = _read_fields(_players[seat], PLAYER_FIELDS, copies)
	_runner_state = _read_fields(runner, RUNNER_FIELDS, copies)
	_next_occurrence = EffectEvent._next_occurrence_id
	return true


## Restores the captured boundary without publishing events or resolving a turn.
## HeadlessMatch calls this before replaying the short suffix or trying another branch.
func restore() -> bool:
	if _match_state.is_empty(): return false
	var copies := {}
	Match.rules_runner.reset()
	CombatResolver._resolving_bash = null
	Match.army = _army.duplicate()
	Match.map = _map.duplicate()
	Match.players = _players.duplicate()
	_write_fields(Match, _match_state, copies)
	for index in _army.size(): _write_fields(_army[index], _unit_states[index], copies)
	for index in _map.size(): _write_fields(_map[index], _hex_states[index], copies)
	for seat in _players: _write_fields(_players[seat], _player_states[seat], copies)
	_write_fields(Match.rules_runner, _runner_state, copies)
	EffectEvent._next_occurrence_id = _next_occurrence
	return true


## Reads the declared gameplay fields for capture(). Derived values stay on their ordinary getters.
func _read_fields(object: Object, fields: Array, copies: Dictionary) -> Dictionary:
	var state := {}
	for field in fields: state[field] = _copy_value(object.get(field), copies)
	return state


## Assigns fresh values during restore(), so a branch cannot mutate the checkpoint.
func _write_fields(object: Object, state: Dictionary, copies: Dictionary) -> void:
	for field in state: object.set(field, _copy_value(state[field], copies))


## Copies mutable rules records in both directions, retaining aliases such as a copied
## passive's entry in props and its provenance record. Authored definitions are shared.
func _copy_value(value: Variant, copies: Dictionary) -> Variant:
	if value is Array:
		var result: Array = value.duplicate()
		for index in result.size(): result[index] = _copy_value(result[index], copies)
		return result
	if value is Dictionary:
		var result: Dictionary = value.duplicate()
		for key in result: result[key] = _copy_value(result[key], copies)
		return result
	if value is Prop or value is TimedGrant or value is TargetRef or value is FireAttack \
			or value is BowAttack or value is GoreAttack or value is CannonAttack or value is BombInfo or value is BashInfo:
		if copies.has(value): return copies[value]
		var result: Object = value.get_script().new()
		copies[value] = result
		for property in value.get_property_list():
			if int(property.usage) & PROPERTY_USAGE_SCRIPT_VARIABLE:
				result.set(property.name, _copy_value(value.get(property.name), copies))
		return result
	return value

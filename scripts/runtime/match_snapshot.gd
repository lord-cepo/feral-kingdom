extends RefCounted

const SNAPSHOT_PATH := "user://local_match_snapshot.json"
const FORMAT_VERSION := 3

## Reports whether a previous local match snapshot is available at startup.
## LocalMatchController.start_match() checks this before loading the new match state.
static func exists() -> bool:
	return FileAccess.file_exists(SNAPSHOT_PATH)

## Allows saving only at an idle Action boundary with no continuation awaiting a choice.
## LocalMatchController disables Save while rules or a provisional sacrificed-hero loss remain unresolved.
static func can_save() -> bool:
	return Match.phase == Match.Phase.ACTION and not Match.rules_runner.busy() and Match.sacrificed_heroes.is_empty()

## Writes an idle Action-phase match as JSON for the next Godot launch.
## The Save Snapshot HUD button calls this; unresolved runner work is rejected.
static func save_snapshot() -> bool:
	if not can_save(): return false
	var file := FileAccess.open(SNAPSHOT_PATH, FileAccess.WRITE)
	if file == null: return false
	file.store_string(JSON.stringify(_capture_state(), "\t"))
	var write_succeeded := file.get_error() == OK
	file.close()
	return write_succeeded

## Restores a saved local match over the catalogue-created starter records.
## LocalMatchController.start_match() calls this after Match.start_local_match().
static func load_snapshot() -> bool:
	if not exists(): return false
	var file := FileAccess.open(SNAPSHOT_PATH, FileAccess.READ)
	if file == null: return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not parsed is Dictionary or not _is_compatible_snapshot(parsed): return false
	_apply_state(parsed)
	return true

## Removes the persisted snapshot so Reset cannot restore the old match next launch.
## LocalMatchController._reset_match() calls this before reloading the main scene.
static func delete_snapshot() -> void:
	if not exists(): return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SNAPSHOT_PATH))

## Captures stable gameplay fields, stored properties, timed grants, and unresolved combat records as JSON-compatible values.
## save_snapshot() calls this only while no command or phase continuation is active.
## Captures action spending, displacement history and pending recipient-owned next-Fire stickers alongside ordinary properties/provenance.
static func _capture_state() -> Dictionary:
	var units: Array[Dictionary] = []
	for unit: UnitInfo in Match.army:
		units.append({
			"uuid": unit.uuid,
			"life": unit.actual_life,
			"max_life": unit.max_life,
			"max_life_changes": unit.max_life_changes.duplicate(true),
			"ability_upgrades": _capture_ability_upgrades(unit),
			"active": unit.active,
			"last_displaced_turn": unit.last_displaced_turn,
			"hex": unit.ihx,
			"state": int(unit.t_state),
			"bow_damage_bonus": unit.bow_damage_bonus,
			"bow_range_bonus": unit.bow_range_bonus,
			"props": _capture_props(unit.props.filter(func(prop: Prop) -> bool:
				return not unit.copied_effects.any(func(copy: Dictionary) -> bool: return copy.category == &"props" and copy.definition == prop))),
			"copied_effects": _capture_effect_copies(unit),
			"timed_grants": _capture_timed_grants(unit.timed_grants),
			"next_fire_stickers": unit.next_fire_stickers.duplicate(),
		})
	var players: Dictionary = {}
	for player_id in [1, 2]:
		var player: Player = Match.players[player_id]
		players[str(player_id)] = {
			"name": player.name,
			"action_allowance": player.action_allowance,
			"actions_remaining": player.actions_remaining,
			"base_actions_remaining": player.base_actions_remaining,
			"deployment_allowance": player.deployment_allowance,
			"deployments_remaining": player.deployments_remaining,
			"has_deployed": player.has_deployed,
			"selected_hero_id": player.selected_hero_id,
			"next_turn_actions": player.next_turn_actions,
			"props": _capture_props(player.props),
		}
	var hexes: Array[Dictionary] = []
	for tile: HexInfo in Match.map:
		hexes.append({"hex_id": tile.hex_id, "props": _capture_props(tile.props)})
	return {
		"version": FORMAT_VERSION,
		"phase": int(Match.phase),
		"active_player": Match.active_player,
		"turn_number": Match.turn_number,
		"winner": Match.winner,
		"units": units,
		"players": players,
		"hexes": hexes,
		"props": _capture_props(Match.props),
		"bombs": _capture_bombs(),
		"pending_fire": _capture_fire_attacks(),
		"pending_bow": _capture_bow_attacks(),
		"pending_gore": _capture_gore_attacks(),
		"pending_cannon": _capture_cannon_attacks(),
		"bashes": _capture_bashes(),
	}

## Checks snapshot version, roster identity, map IDs, counters, Bow bonuses, pending next-Fire sticker names and phase before mutation.
## load_snapshot() uses this guard so a stale file cannot partially overwrite a new match.
## A shorter unchanged roster prefix is compatible when catalogue additions only append units; new units remain in their initial hand state.
static func _is_compatible_snapshot(state: Dictionary) -> bool:
	if int(state.get("version", -1)) not in [1, 2, FORMAT_VERSION]: return false
	if int(state.get("phase", -1)) != Match.Phase.ACTION: return false
	for key in ["units", "hexes", "props", "bombs", "pending_fire", "pending_bow",
			"pending_gore", "pending_cannon", "bashes"]:
		if not _contains_only_dictionaries(state.get(key)): return false
	if state.units.is_empty() or state.units.size() > Match.army.size(): return false
	if state.hexes.size() != Match.map.size(): return false
	if not state.get("players") is Dictionary: return false
	for index in state.units.size():
		var saved: Variant = state.units[index]
		if not saved is Dictionary or str(saved.get("uuid", "")) != Match.army[index].uuid: return false
		if not _contains_only_dictionaries(saved.get("props")): return false
		if not _contains_only_dictionaries(saved.get("max_life_changes", [])): return false
		if saved.has("timed_grants") and not _valid_timed_grants(saved.timed_grants): return false
		if not saved.get("next_fire_stickers", []) is Array: return false
		for sticker in saved.get("next_fire_stickers", []):
			if sticker not in ["pierce", "instant"]: return false
		if not _valid_effect_copies(saved.get("copied_effects", []), int(state.version)): return false
		var upgrades: Variant = saved.get("ability_upgrades", [])
		if not _contains_only_dictionaries(upgrades): return false
		var ability_count := Match.army[index].effects.size()
		for copy: Dictionary in saved.get("copied_effects", []):
			if copy.get("category") == "effects": ability_count += 1
		for upgrade: Dictionary in upgrades:
			if int(upgrade.get("index", -1)) < 0 or int(upgrade.index) >= ability_count or int(upgrade.get("damage", -1)) < 0 or int(upgrade.get("range", -1)) < 0: return false
		var saved_max_life := int(saved.get("max_life", Match.army[index].max_life))
		if saved_max_life < 0 or (saved_max_life == 0 and int(saved.state) != Enum.t_state.DEFEATED) or int(saved.get("life", 0)) < 0 or int(saved.get("life", 0)) > saved_max_life: return false
	for index in Match.map.size():
		var saved_hex: Variant = state.hexes[index]
		if not saved_hex is Dictionary or int(saved_hex.get("hex_id", -1)) != Match.map[index].hex_id: return false
		if not _contains_only_dictionaries(saved_hex.get("props")): return false
	for player_id in [1, 2]:
		var saved_player: Variant = state.players.get(str(player_id))
		if not saved_player is Dictionary or not _contains_only_dictionaries(saved_player.get("props")): return false
		if int(saved_player.get("next_turn_actions", 0)) < 0: return false
		var hero_id := int(saved_player.get("selected_hero_id", -1))
		if hero_id >= 0 and (hero_id >= state.units.size() or Match.get_unit(hero_id).player != player_id or Match.get_unit(hero_id).type != Enum.type.HERO): return false
	return int(state.get("active_player", 0)) in [1, 2]

## Restores the chosen hero without exposing newly appended alternatives; legacy snapshots had one hero per owner in their saved prefix.
## _apply_state calls this after units are restored; returning a hero to hand never unlocks another candidate.
static func _restored_hero_choice(state: Dictionary, player_id: int) -> int:
	var player: Dictionary = state.players[str(player_id)]
	if player.has("selected_hero_id"): return int(player.selected_hero_id)
	if not bool(player.has_deployed): return -1
	var first := -1
	for index in state.units.size():
		var unit := Match.get_unit(index)
		if unit.player != player_id or unit.type != Enum.type.HERO: continue
		if first < 0: first = index
		if int(state.units[index].state) != Enum.t_state.UNDEPLOYED: return index
	return first

## Confirms a JSON value is an array of property or combat dictionaries.
## _is_compatible_snapshot() uses this before any saved record is reconstructed.
static func _contains_only_dictionaries(value: Variant) -> bool:
	if not value is Array: return false
	for item: Variant in value:
		if not item is Dictionary: return false
	return true

## Save captures stable printed origin/category/index triples; copies of copies retain their original printed source.
static func _capture_effect_copies(unit: UnitInfo) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for copy in unit.copied_effects:
		result.append({"unit": copy.unit, "category": String(copy.category), "index": copy.index})
	return result

## Old snapshots stored Wild as the first appended flag after the five built-in counters; discard those copies without changing card names.
## Validation and reconstruction share this narrow versioned migration, preserving other real passive copies and older roster identities.
static func _legacy_name_copy(copy: Dictionary, version: int) -> bool:
	var source := Match.get_unit(int(copy.get("unit", -1)))
	return version < 3 and copy.get("category", "") == "props" and int(copy.get("index", -1)) == 5 \
		and source != null and source.name.to_lower().contains("wild")

## Rejects missing printed definitions before mutation, except the obsolete Wild flag copy explicitly removed by the version-three migration.
static func _valid_effect_copies(value: Variant, version: int = FORMAT_VERSION) -> bool:
	if not _contains_only_dictionaries(value): return false
	for copy: Dictionary in value:
		if _legacy_name_copy(copy, version): continue
		var source := Match.get_unit(int(copy.get("unit", -1)))
		var category := StringName(copy.get("category", ""))
		if source == null or category not in [&"effects", &"trigger_effects", &"state_effects", &"continuous_effects", &"props"]: return false
		var definitions: Array = source.printed_state.get(category, [])
		var index := int(copy.get("index", -1))
		if index < 0 or index >= definitions.size(): return false
		if category == &"props" and definitions[index].increment != Enum.p_increment.FLAG: return false
	return true

## Applies saved properties/grants, migrates version-one Bow bonuses, rebuilds combat records, and recomputes control.
## Restores printed arrays and real passive copies, discarding legacy Wild flags/copies; Reset baselines remain separate from runtime state.
## Only saved roster-prefix entries are overwritten, preserving appended catalogue units in hand while retaining old unit IDs and combat history.
## Restores next-Fire stickers and action ledgers after Bash records; legacy saves default missing sticker records to empty.
static func _apply_state(state: Dictionary) -> void:
	Match.rules_runner.reset()
	Match.sacrificed_heroes.clear()
	Match._transitioning = false
	Match.active_player = int(state.active_player)
	Match.phase = int(state.phase)
	Match.turn_number = int(state.turn_number)
	Match.winner = int(state.winner)
	for index in state.units.size():
		var unit: UnitInfo = Match.army[index]
		var saved: Dictionary = state.units[index]
		unit.reset_printed_state()
		unit.max_life = int(saved.get("max_life", unit.max_life))
		unit.max_life_changes.assign(saved.get("max_life_changes", []))
		unit.actual_life = int(saved.life)
		unit.active = bool(saved.active)
		unit.last_displaced_turn = int(saved.get("last_displaced_turn", -1))
		unit.ihx = int(saved.hex)
		unit.t_state = int(saved.state)
		unit.props = _restore_props(saved.props)
		unit.timed_grants = _restore_timed_grants(saved.get("timed_grants", []))
		unit.next_fire_stickers.clear()
		for sticker in saved.get("next_fire_stickers", []): unit.next_fire_stickers.append(StringName(sticker))
		if unit.bow_damage_bonus == 0 and int(saved.get("bow_damage_bonus", 0)) != 0:
			unit.add_bow_counters(int(saved.bow_damage_bonus), 0)
		if unit.bow_range_bonus == 0 and int(saved.get("bow_range_bonus", 0)) != 0:
			unit.add_bow_counters(0, int(saved.bow_range_bonus))
	for index in state.units.size():
		for copy: Dictionary in state.units[index].get("copied_effects", []):
			if _legacy_name_copy(copy, int(state.version)): continue
			var source := Match.get_unit(int(copy.unit))
			var option := EffectOption.new()
			option.category = StringName(copy.category)
			option.origin_unit = int(copy.unit)
			option.origin_index = int(copy.index)
			option.definition = source.printed_state[option.category][option.origin_index]
			Match.army[index].add_effect_copy(option)
	for index in state.units.size():
		var unit := Match.get_unit(index)
		for upgrade: Dictionary in state.units[index].get("ability_upgrades", []):
			unit.ability_upgrades.append({"effect": unit.effects[int(upgrade.index)], "damage": int(upgrade.damage), "range": int(upgrade.range), "source": str(upgrade.get("source", "Effect"))})
	for player_id in [1, 2]:
		var player: Player = Match.players[player_id]
		var saved_player: Dictionary = state.players[str(player_id)]
		player.name = str(saved_player.get("name", player.name))
		player.action_allowance = int(saved_player.action_allowance)
		player.deployment_allowance = int(saved_player.deployment_allowance)
		player.deployments_remaining = int(saved_player.deployments_remaining)
		player.has_deployed = bool(saved_player.has_deployed)
		player.selected_hero_id = _restored_hero_choice(state, player_id)
		player.next_turn_actions = int(saved_player.get("next_turn_actions", 0))
		player.props = _restore_props(saved_player.props)
	for index in Match.map.size():
		Match.map[index].props = _restore_props(state.hexes[index].props)
	Match.props = _restore_props(state.props)
	_restore_combat_records(state)
	for player_id in [1, 2]:
		var saved_player: Dictionary = state.players[str(player_id)]
		if saved_player.has("base_actions_remaining"):
			Match.players[player_id].base_actions_remaining = int(saved_player.base_actions_remaining)
		else: Match.players[player_id].actions_remaining = int(saved_player.actions_remaining)
	Match.refresh_control(false)
	Match.phase_changed.emit(Match.phase, Match.active_player)
	Match.state_changed.emit()

## Encodes typed counters and flags with their identity and enum kinds.
## _capture_state() uses this for unit, player, hex, and match property lists.
static func _capture_props(properties: Array[Prop]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for prop: Prop in properties:
		result.append({"name": prop.name, "value": prop.value,
			"increment": int(prop.increment), "target": int(prop.target)})
	return result

## Encodes concrete temporary action grants so an idle snapshot preserves their cleanup boundary.
## _capture_state() calls this for each unit; definitions and callbacks are reconstructed from values.
## Kind distinguishes modifier pairs from action parameters while retaining existing action-grant save compatibility.
static func _capture_timed_grants(grants: Array[TimedGrant]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for grant in grants:
		if grant == null: continue
		result.append({"id": grant.id, "source": grant.source.id if grant.source != null else -1,
			"family": String(grant.action_family), "kind": int(grant.kind), "parameters": grant.parameters.duplicate(),
			"expires_player": grant.expires_player, "expires_turn": grant.expires_turn})
	return result

## Rejects malformed or ambiguous timed-grant records before any snapshot mutation.
## _is_compatible_snapshot() calls it for new snapshots; version-one saves may omit the field.
## Old records default to action values; modifier records require exactly two parameters and a known kind.
static func _valid_timed_grants(value: Variant) -> bool:
	if not value is Array: return false
	for grant: Variant in value:
		if not grant is Dictionary or not grant.get("parameters") is Array: return false
		if int(grant.get("id", 0)) <= 0 or int(grant.get("source", -1)) < 0 \
				or int(grant.get("source", -1)) >= Match.army.size(): return false
		if str(grant.get("family", "")).is_empty() or grant.parameters.is_empty(): return false
		if int(grant.get("kind", 0)) not in [TimedGrant.Kind.ACTION_VALUES, TimedGrant.Kind.MODIFIERS]: return false
		if int(grant.get("kind", 0)) == TimedGrant.Kind.MODIFIERS and grant.parameters.size() != 2: return false
		if int(grant.get("expires_player", 0)) not in [1, 2] or int(grant.get("expires_turn", -1)) < 0: return false
	return true

## Rebuilds typed temporary grants from validated stable IDs and captured expiration values.
## _apply_state() calls this after restoring each recipient's ordinary properties.
## Restores the typed modifier/action distinction; source identity and captured End remain recipient-bound.
static func _restore_timed_grants(value: Array) -> Array[TimedGrant]:
	var result: Array[TimedGrant] = []
	for saved: Dictionary in value:
		var values: Array[int] = []
		for parameter: Variant in saved.parameters: values.append(int(parameter))
		result.append(TimedGrant.action_values(int(saved.id), TargetRef.unit(int(saved.source)),
			StringName(saved.family), values, int(saved.expires_player), int(saved.expires_turn)))
		result[-1].kind = int(saved.get("kind", TimedGrant.Kind.ACTION_VALUES))
		Match._next_timed_grant_id = maxi(Match._next_timed_grant_id, int(saved.id) + 1)
	return result

## Captures permanent chosen-ability grants by recipient effect slot; copied definitions are restored before these slots are rebound on load.
static func _capture_ability_upgrades(unit: UnitInfo) -> Array[Dictionary]:
	var records: Array[Dictionary] = []
	for grant in unit.ability_upgrades:
		var index := unit.effects.find(grant.effect)
		if index >= 0: records.append({"index": index, "damage": grant.damage, "range": grant.range, "source": grant.source})
	return records

## Rebuilds a typed property list from the JSON records emitted by _capture_props().
## _apply_state() restores saved properties while dropping the former Wild flag; group membership is derived from each unit's name.
static func _restore_props(records: Array) -> Array[Prop]:
	var result: Array[Prop] = []
	for record: Dictionary in records:
		if String(record.name).to_lower() == "wild" and int(record.increment) == Enum.p_increment.FLAG: continue
		var prop := Prop.new()
		prop.name = str(record.name)
		prop.value = int(record.value)
		prop.increment = int(record.increment)
		prop.target = int(record.target)
		result.append(prop)
	return result

## Captures bombs that remain on the board between player turns.
## _capture_state() includes this list so saved combat setup is preserved.
static func _capture_bombs() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for bomb: BombInfo in Match.bombs:
		result.append({"owner": bomb.owner, "source": bomb.source_id, "hex": bomb.hex_id,
			"damage": bomb.damage, "pierce": bomb.pierce})
	return result

## Captures declared Fire attacks awaiting a combat window.
## _capture_state() stores captured values so they do not drift on resume.
static func _capture_fire_attacks() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for attack: FireAttack in Match.pending_attacks:
		result.append({"source": attack.source_id, "owner": attack.owner,
			"origin": attack.origin_hex, "target": attack.target_hex,
			"target_unit": attack.target_unit_id, "amount": attack.amount,
			"pierce": attack.pierce, "instant": attack.instant,
			"turn": attack.declared_turn, "resolved": attack.resolved})
	return result

## Captures declared Bow attacks awaiting a combat window.
## _capture_state() stores original victims and captured attack values.
static func _capture_bow_attacks() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for attack: BowAttack in Match.pending_bow_attacks:
		result.append({"source": attack.source_id, "owner": attack.owner,
			"origin": attack.origin_hex, "target": attack.target_hex,
			"target_unit": attack.target_unit_id, "amount": attack.amount,
			"pierce": attack.pierce, "instant": attack.instant, "resolved": attack.resolved})
	return result

## Captures declared Gore leaps awaiting a combat window.
## _capture_state() stores the original leap path and target identity.
static func _capture_gore_attacks() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for attack: GoreAttack in Match.pending_gore_attacks:
		result.append({"source": attack.source_id, "owner": attack.owner,
			"origin": attack.origin_hex, "destination": attack.destination_hex,
			"target": attack.target_hex, "target_unit": attack.target_unit_id,
			"amount": attack.amount, "resolved": attack.resolved})
	return result

## Captures declared Cannon shots and queued Bomb blasts awaiting a combat window.
## _capture_state() preserves projectile values, mode, chain attribution, and lit Bomb centers.
static func _capture_cannon_attacks() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for attack: CannonAttack in Match.pending_cannon_attacks:
		result.append({"source": attack.source_id, "owner": attack.owner,
			"target": attack.target_hex, "amount": attack.amount, "pierce": attack.pierce,
			"instant": attack.instant, "explosion": attack.explosion,
			"bomb_hex": attack.bomb_hex,
			"chain_owner": attack.chain_owner, "resolved": attack.resolved})
	return result

## Captures unresolved Bash encounters retained across action windows.
## _capture_state() preserves both participants and the responding player.
static func _capture_bashes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for bash: BashInfo in Match.bashes:
		result.append({"attacker": bash.attacker_id, "defender": bash.defender_id,
			"target": bash.target_hex, "responding_player": bash.responding_player,
			"resolved": bash.resolved})
	return result

## Recreates bombs, captured attacks, and Bash records without emitting new events.
## _apply_state() calls this after restoring unit and player state; older snapshots
## without Bomb center metadata retain -1 rather than inventing a lit marker location.
static func _restore_combat_records(state: Dictionary) -> void:
	Match.bombs.clear()
	for saved: Dictionary in state.get("bombs", []):
		var bomb := BombInfo.new()
		bomb.owner = int(saved.owner)
		bomb.source_id = int(saved.source)
		bomb.hex_id = int(saved.hex)
		bomb.damage = int(saved.damage)
		bomb.pierce = bool(saved.pierce)
		Match.bombs.append(bomb)
	Match.pending_attacks.clear()
	for saved: Dictionary in state.get("pending_fire", []):
		var attack := FireAttack.new()
		attack.source_id = int(saved.source)
		attack.owner = int(saved.owner)
		attack.origin_hex = int(saved.origin)
		attack.target_hex = int(saved.target)
		attack.target_unit_id = int(saved.target_unit)
		attack.amount = int(saved.amount)
		attack.pierce = bool(saved.pierce)
		attack.instant = bool(saved.instant)
		attack.declared_turn = int(saved.turn)
		attack.resolved = bool(saved.resolved)
		Match.pending_attacks.append(attack)
	Match.pending_bow_attacks.clear()
	for saved: Dictionary in state.get("pending_bow", []):
		var attack := BowAttack.new()
		attack.source_id = int(saved.source)
		attack.owner = int(saved.owner)
		attack.origin_hex = int(saved.origin)
		attack.target_hex = int(saved.target)
		attack.target_unit_id = int(saved.target_unit)
		attack.amount = int(saved.amount)
		attack.pierce = bool(saved.pierce)
		attack.instant = bool(saved.instant)
		attack.resolved = bool(saved.resolved)
		Match.pending_bow_attacks.append(attack)
	Match.pending_gore_attacks.clear()
	for saved: Dictionary in state.get("pending_gore", []):
		var attack := GoreAttack.new()
		attack.source_id = int(saved.source)
		attack.owner = int(saved.owner)
		attack.origin_hex = int(saved.origin)
		attack.destination_hex = int(saved.destination)
		attack.target_hex = int(saved.target)
		attack.target_unit_id = int(saved.target_unit)
		attack.amount = int(saved.amount)
		attack.resolved = bool(saved.resolved)
		Match.pending_gore_attacks.append(attack)
	Match.pending_cannon_attacks.clear()
	for saved: Dictionary in state.get("pending_cannon", []):
		var attack := CannonAttack.new()
		attack.source_id = int(saved.source)
		attack.owner = int(saved.owner)
		attack.target_hex = int(saved.target)
		attack.amount = int(saved.amount)
		attack.pierce = bool(saved.pierce)
		attack.instant = bool(saved.instant)
		attack.explosion = bool(saved.explosion)
		attack.bomb_hex = int(saved.get("bomb_hex", -1))
		attack.chain_owner = int(saved.chain_owner)
		attack.resolved = bool(saved.resolved)
		Match.pending_cannon_attacks.append(attack)
	Match.bashes.clear()
	for saved: Dictionary in state.get("bashes", []):
		var bash := BashInfo.new()
		bash.attacker_id = int(saved.attacker)
		bash.defender_id = int(saved.defender)
		bash.target_hex = int(saved.target)
		bash.responding_player = int(saved.responding_player)
		bash.resolved = bool(saved.resolved)
		Match.bashes.append(bash)

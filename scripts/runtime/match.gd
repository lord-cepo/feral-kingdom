extends Node

signal deactivate(subject: TargetRef, target: TargetRef)
signal fire(subject: TargetRef, target: TargetRef, damage: int)
signal action_event(event: EffectEvent)
signal fire_resolved(attack: FireAttack)
signal phase_changed(phase: int, player: int)
signal state_changed

enum Phase { START, ACTION, ACTION_RESOLVE, COMBAT_RESOLVE, END }
var phase := Phase.ACTION
var active_player := 1
var turn_number := 0
var _next_timed_grant_id := 1
var winner := 0
## Sacrificed heroes are checked only after their causal triggers/consequences, allowing an explicit rescue before the loss becomes final.
var sacrificed_heroes: Array[int] = []
var pending_attacks: Array[FireAttack] = []
var pending_bow_attacks: Array[BowAttack] = []
var pending_gore_attacks: Array[GoreAttack] = []
var pending_cannon_attacks: Array[CannonAttack] = []
var bombs: Array[BombInfo] = []
var bashes: Array[BashInfo] = []
var _transitioning := false
var rules_runner := RulesRunner.new()

var map: Array[HexInfo] = []
var army: Array[UnitInfo] = []
var players: Dictionary[int, Player] = {1: Player.new(), 2: Player.new()}
var props: Array[Prop] = []

## Connects the Match event boundary to its single rules runner.
## Godot calls this once for the autoload, before board/controller listeners are attached.
## Idle and deferred state notifications check the no-legal-command loss only after queued choices/phase work settle.
func _ready() -> void:
	for identifier in players: players[identifier].id = identifier
	if not action_event.is_connected(rules_runner.capture_event):
		action_event.connect(rules_runner.capture_event)
	rules_runner.idle.connect(_check_no_legal_actions, CONNECT_DEFERRED)
	state_changed.connect(_check_no_legal_actions, CONNECT_DEFERRED)

## Settled Action windows lose immediately when neither deployment nor a payable, legally targeted unit command exists.
## Runner idle/state notifications call this after Start/action followups; zero-action transitions and pending choices never cause a premature loss.
func _check_no_legal_actions() -> void:
	if winner != 0 or army.is_empty() or phase != Phase.ACTION or _transitioning or rules_runner.busy(): return
	if active_player not in [1, 2]: return
	if has_legal_action(): return
	winner = 3 - active_player
	state_changed.emit()

## Queries the active player's deployments and all deployed effects against live authoritative legality without paying or selecting anything.
## The loss check and future authority adapters use this; action-free and Tireless effects retain their ordinary eligibility.
func has_legal_action() -> bool:
	for unit: UnitInfo in army:
		if unit == null or unit.player != active_player: continue
		if unit.t_state == Enum.t_state.UNDEPLOYED:
			for tile: HexInfo in map:
				if can_deploy(unit.iun, tile.hex_id): return true
		elif unit.t_state == Enum.t_state.DEPLOYED:
			for effect in unit.effects:
				if rules_runner.command_available(effect, TargetRef.unit(unit.iun)): return true
	return false

## Initializes a fresh local object-authored match and clears dynamic match properties.
## The composition root calls this after the board map exists; it assigns stable
## army indices, supplies implicit Walk 1 where needed, and begins player 1's first turn.
## Accepts at least one hero candidate per owner; first deployment chooses exactly one for that match. Invalid input changes nothing.
## Captures printed baselines and clears previous-match displacement history and next-Fire grants; setup rebuilds control without triggers.
func start_local_match(units: Array[UnitInfo], action_allowance: int, deployment_allowance: int) -> bool:
	if units.is_empty() or map.is_empty() or action_allowance < 1 or deployment_allowance < 1: return false
	var heroes := {1: 0, 2: 0}
	var card_ids := {}
	for unit in units:
		if unit == null or unit.player not in [1, 2]: return false
		if unit.uuid.is_empty() or unit.max_life < 1 or unit.actual_life < 1 or unit.actual_life > unit.max_life: return false
		if unit.type not in [Enum.type.HERO, Enum.type.TROOP, Enum.type.TEMPLE]: return false
		var card_key := "%d:%s" % [unit.player, unit.uuid]
		if card_ids.has(card_key): return false
		card_ids[card_key] = true
		if unit.type == Enum.type.HERO: heroes[unit.player] += 1
	if heroes[1] < 1 or heroes[2] < 1: return false
	for unit in units: unit.ensure_implicit_walk()
	army.clear()
	rules_runner.reset()
	pending_attacks.clear()
	pending_bow_attacks.clear()
	pending_gore_attacks.clear()
	pending_cannon_attacks.clear()
	bombs.clear()
	bashes.clear()
	_transitioning = false
	winner = 0
	sacrificed_heroes.clear()
	turn_number = 0
	_next_timed_grant_id = 1
	for player_id in [1, 2]:
		var participant: Player = players[player_id]
		participant.name = ""
		participant.props.clear()
		participant.action_allowance = action_allowance
		participant.actions_remaining = action_allowance
		participant.deployment_allowance = deployment_allowance
		participant.deployments_remaining = deployment_allowance
		participant.has_deployed = false
		participant.selected_hero_id = -1
		participant.next_turn_actions = 0
	for tile: HexInfo in map: tile.props.clear()
	props.clear()
	for unit in units:
		unit.iun = army.size()
		unit.ihx = -1
		unit.last_displaced_turn = -1
		unit.capture_printed_state()
		unit.t_state = Enum.t_state.UNDEPLOYED
		unit.active = false
		unit.timed_grants.clear()
		unit.next_fire_stickers.clear()
		army.append(unit)
	refresh_control(false)
	start_turn(1)
	return true

## Begins a player's turn, resets their action allowance, and applies the hero's one-Stun recovery to friendly deployed units.
## Setup and _next_turn() call this; recovery changes only positive Stun counters, never activity or Activate events.
## The Start occurrence and its choices finish before Action; zero-Stun inactive units wait for their owner's End.
## One-shot next-turn action grants are added once and cleared here; they never replace the format's recurring allowance.
func start_turn(player_id: int) -> void:
	if player_id not in [1, 2] or winner != 0: return
	rules_runner.begin_boundary()
	active_player = player_id
	_set_phase(Phase.START)
	var participant: Player = players[player_id]
	participant.base_actions_remaining = participant.action_allowance + participant.next_turn_actions
	participant.next_turn_actions = 0
	for index in army.size():
		var unit: UnitInfo = army[index]
		if unit == null or unit.player != player_id or unit.t_state != Enum.t_state.DEPLOYED: continue
		var stun := get_property(TargetRef.property(TargetRef.unit(index), UnitInfo.STUN_COUNTER))
		if stun != null and stun.value > 0:
			stun.value -= 1
	rules_runner.schedule([_start_boundary.bind(player_id), _enter_action])
	rules_runner.end_boundary()

## Announces Start after the hero's Stun recovery; captured Start followups finish before Action.
## start_turn() schedules this once; automatic activation belongs to the owner's End continuation.
func _start_boundary(player_id: int) -> void:
	if winner != 0: return
	action_event.emit(EffectEvent.new(&"start", TargetRef.player(player_id), TargetRef.player(player_id)))

## Returns to player commands only after pending Start/action followups complete.
## The phase runner calls this; it never advances while a phrase is waiting.
func _enter_action() -> void:
	if winner != 0: return
	_set_phase(Phase.ACTION)
	state_changed.emit()
	_transitioning = false

## Checks card state, first-deployment hero choice, region control, vacancy and allowances; nonchosen hero alternatives cannot enter later.
## The local controller calls this both to highlight destinations and before placement.
func can_deploy(unit_id: int, hex_id: int) -> bool:
	if _transitioning or rules_runner.busy() or phase != Phase.ACTION or winner != 0 or active_player not in [1, 2]: return false
	var participant: Player = players[active_player]
	if participant.actions_remaining <= 0 or participant.deployments_remaining <= 0: return false
	var unit := get_unit(unit_id)
	var tile := get_hex(hex_id)
	if unit == null or tile == null or unit.player != active_player or unit.t_state != Enum.t_state.UNDEPLOYED: return false
	if tile.region not in unit.deploy_regions: return false
	if unit.deployment_enemy_side and int(tile.side) != 3 - unit.player: return false
	if not participant.has_deployed and unit.type != Enum.type.HERO: return false
	if unit.type == Enum.type.HERO and participant.selected_hero_id >= 0 and participant.selected_hero_id != unit_id: return false
	if occupants(hex_id).size() > 0 or ControlResolver.region_owner(tile) != active_player: return false
	return true

## Places a legal unit inactive with one Stun, pays resources and records the first hero choice; returning that hero never unlocks alternatives.
## Called after the player chooses a highlighted tile; returns false without mutation if illegal.
## Online callers submit an intent first; host-authorized/replayed calls enter these same resource and eligibility checks.
func deploy(unit_id: int, hex_id: int) -> bool:
	# Online UI submits an identity-only intent; only host acceptance enters the existing deployment rules.
	if NetworkSession.routes_input(): return NetworkSession.request_intent({"kind": "deploy", "unit": unit_id, "hex": hex_id})
	if not can_deploy(unit_id, hex_id): return false
	var unit := get_unit(unit_id)
	var participant: Player = players[active_player]
	unit.ihx = hex_id
	unit.t_state = Enum.t_state.DEPLOYED
	unit.active = false
	var deployment_stun := get_property(TargetRef.property(TargetRef.unit(unit_id), UnitInfo.STUN_COUNTER))
	if deployment_stun != null: deployment_stun.value += 1
	participant.has_deployed = true
	if unit.type == Enum.type.HERO: participant.selected_hero_id = unit_id
	participant.deployments_remaining -= 1
	refresh_control()
	rules_runner.begin_boundary()
	action_event.emit(EffectEvent.new(&"deploy", TargetRef.unit(unit_id), TargetRef.hex(hex_id)))
	rules_runner.schedule([finish_action.bind(active_player)])
	rules_runner.end_boundary()
	return true

## Chinchilla's death consequence deploys its defeated card without player-token, deployment, region, side, or control requirements.
## Preserves stored state, restores full current maximum health, adds one deployment Stun and emits Deploy for ordinary followups.
## An opposing occupant starts the normal Bash; another friendly occupant remains illegal to preserve one participant per owner.
## WildActions calls this inside its Return boundary, so both zone changes complete before captured triggers and phase continuations.
func deploy_from_effect(unit_id: int, hex_id: int) -> bool:
	var unit := get_unit(unit_id)
	if unit == null or unit.t_state != Enum.t_state.DEFEATED or unit.max_life <= 0 or get_hex(hex_id) == null: return false
	var occupants_before := occupants(hex_id)
	if occupants_before.any(func(ref: TargetRef) -> bool: return owner_of(ref) == unit.player): return false
	rules_runner.begin_boundary()
	unit.actual_life = unit.max_life
	unit.ihx = hex_id
	unit.t_state = Enum.t_state.DEPLOYED
	unit.active = false
	get_property(TargetRef.property(TargetRef.unit(unit_id), UnitInfo.STUN_COUNTER)).value += 1
	players[unit.player].has_deployed = true
	refresh_control()
	action_event.emit(EffectEvent.new(&"deploy", TargetRef.unit(unit_id), TargetRef.hex(hex_id), {"effect_deployment": true}))
	if not occupants_before.is_empty(): CombatResolver._create_bash(unit_id, occupants_before[0].id, hex_id)
	state_changed.emit()
	rules_runner.end_boundary()
	return true

## Recomputes regional display control and captures one occurrence per actual region gaining a player owner.
## Mutations/Board refresh publish by default; setup/snapshot restoration pass false to rebuild caches without fictional gameplay occurrences.
## Caches update before triggers, so repeated/reentrant reads cannot recapture a transition.
func refresh_control(publish_events: bool = true) -> void:
	var changed_regions: Array[Dictionary] = []
	var seen: Dictionary = {}
	for tile in map:
		var key := Vector3i(int(tile.region), int(tile.side), tile.region_count)
		if seen.has(key): continue
		seen[key] = true
		var owner := ControlResolver.region_owner(tile)
		if owner in [1, 2] and tile.control != ControlResolver.control_enum(owner):
			changed_regions.append({"hex": tile.hex_id, "owner": owner, "previous": tile.control})
	ControlResolver.refresh()
	if not publish_events: return
	rules_runner.begin_boundary()
	for region in changed_regions:
		action_event.emit(EffectEvent.new(&"gain_region", TargetRef.player(region.owner), TargetRef.hex(region.hex), {"previous": region.previous}))
	rules_runner.end_boundary()

## Spends one action from the retained ledger; a committed command can lose its live bonus before its final token is charged.
## RulesRunner command/deployment continuations call once after all followups finish.
func finish_action(player_id: int, committed: bool = false) -> bool:
	if _transitioning: return false
	if rules_runner.active != null or rules_runner.command_open or rules_runner.halted: return false
	if player_id != active_player or phase != Phase.ACTION or winner != 0: return false
	var participant: Player = players[player_id]
	if participant.actions_remaining <= 0 and not committed: return false
	participant.base_actions_remaining -= 1
	return complete_action(player_id, participant.actions_remaining)

## Completes the current action window using the remaining action count.
## finish_action() supplies the tracked count; the HUD can pass zero to end early.
## At zero this resolves Bow/Gore, Cannon/Bomb, Fire, and ready Bash before progressing the turn.
## Each phase waits for triggered choices. Invalid/reentrant transitions return false.
## At turn end, owner-only zero-Stun activation follows End choices and finishes its own followups before cleanup/switch.
func complete_action(player: int, actions_remaining: int = 0) -> bool:
	if _transitioning or winner != 0 or player != active_player or actions_remaining < 0: return false
	if rules_runner.active != null or rules_runner.command_open or rules_runner.halted: return false
	if phase not in [Phase.ACTION, Phase.ACTION_RESOLVE]: return false
	players[player].actions_remaining = actions_remaining
	_transitioning = true
	_set_phase(Phase.ACTION_RESOLVE)
	if actions_remaining > 0: rules_runner.schedule([_enter_action])
	else: rules_runner.schedule([_combat_phase.bind(player), _end_phase.bind(player),
		_activate_unstunned_units.bind(player), _next_turn.bind(player)])
	return true

## Freezes the combat window and schedules attacks before the End continuation.
## complete_action queues this; each attack may release triggers that wait for choices.
func _combat_phase(player: int) -> void:
	if winner != 0: return
	_set_phase(Phase.COMBAT_RESOLVE)
	CombatResolver.resolve_window(player)

## Announces the named player's End; all captured End effects finish before automatic owner activation.
## The turn continuation calls this after all eligible combat and followups.
func _end_phase(player: int) -> void:
	if winner != 0: return
	_set_phase(Phase.END)
	action_event.emit(EffectEvent.new(&"end", TargetRef.player(player), TargetRef.player(player)))

## Activates only the ending player's inactive deployed units with no positive Stun, in stable army order.
## complete_action() schedules this after End effects/choices; it neither removes Stun nor touches the opposing army.
## Each newly active unit emits one Activate occurrence; the runner releases followups after the pass, before _next_turn().
func _activate_unstunned_units(player_id: int) -> void:
	if winner != 0: return
	rules_runner.begin_boundary()
	for index in army.size():
		var unit: UnitInfo = army[index]
		if unit == null or unit.player != player_id or unit.t_state != Enum.t_state.DEPLOYED or unit.active: continue
		var ref := TargetRef.unit(index)
		var stun := get_property(TargetRef.property(ref, UnitInfo.STUN_COUNTER))
		if stun != null and stun.value > 0: continue
		unit.active = true
		action_event.emit(EffectEvent.new(&"activate", ref, TargetRef.hex(unit.ihx)))
	rules_runner.end_boundary()

## Expires current-turn grants after End and activation followups, then switches players and begins Start recovery.
## complete_action() schedules this after _activate_unstunned_units(); terminal matches never start another turn.
func _next_turn(player: int) -> void:
	if winner != 0:
		_transitioning = false
		return
	expire_timed_grants(player, turn_number)
	turn_number += 1
	start_turn(3 - player)

## Removes timed grants whose captured player turn just completed, after End followups finish.
## The phase runner calls this from _next_turn before incrementing the turn serial or starting the opponent.
func expire_timed_grants(player_id: int, completed_turn: int) -> void:
	for unit: UnitInfo in army:
		if unit == null or unit.timed_grants.is_empty(): continue
		for index in range(unit.timed_grants.size() - 1, -1, -1):
			var grant := unit.timed_grants[index]
			if grant != null and grant.expires_after(player_id, completed_turn):
				unit.timed_grants.remove_at(index)

## Allocates the stable match-local identity stored on a concrete temporary grant.
## Action.grant_action_values() requests one immediately before attaching a grant to its recipient.
func allocate_timed_grant_id() -> int:
	var result := _next_timed_grant_id
	_next_timed_grant_id += 1
	return result

## Emits presentation phase state; game phase occurrences are explicitly published above.
func _set_phase(next: Phase) -> void:
	phase = next
	phase_changed.emit(phase, active_player)

## Clears pending combat and captured trigger work for focused scenarios.
## Integration scenes call this before rebuilding their own map and army.
func reset_combat() -> void:
	rules_runner.reset()
	pending_attacks.clear()
	pending_bow_attacks.clear()
	pending_gore_attacks.clear()
	pending_cannon_attacks.clear()
	bombs.clear()
	bashes.clear()
	phase = Phase.ACTION
	active_player = 1
	turn_number = 0
	winner = 0
	sacrificed_heroes.clear()
	_transitioning = false
	for participant: Player in players.values():
		participant.selected_hero_id = -1
		participant.actions_remaining = participant.action_allowance
		participant.deployments_remaining = participant.deployment_allowance

## Marks a unit defeated, removes its live board position, emits death, and cancels any Bash it leaves.
## Combat passes the causing controller; sacrifice additionally supplies a departure occurrence captured after Die but before removal, so the victim can observe itself.
func defeat(ref: TargetRef, event_controller: int = 0, departure_events: Array[EffectEvent] = []) -> void:
	if ref == null or ref.kind != TargetRef.Kind.UNIT: return
	var unit := get_unit(ref.id)
	if unit == null or unit.t_state == Enum.t_state.DEFEATED: return
	var last_hex := unit.ihx
	rules_runner.begin_boundary()
	var death := EffectEvent.new(&"die", ref, TargetRef.hex(last_hex),
		{"last_hex": last_hex, "owner": unit.player}, &"resolved", event_controller)
	rules_runner.capture_event(death)
	for event in departure_events: rules_runner.capture_event(event)
	unit.actual_life = 0
	unit.active = false
	unit.t_state = Enum.t_state.DEFEATED
	unit.ihx = -1
	if unit.type == Enum.type.HERO:
		if departure_events.any(func(event: EffectEvent) -> bool: return event.action == &"sacrifice"):
			if ref.id not in sacrificed_heroes: sacrificed_heroes.append(ref.id)
		else: winner = 3 - unit.player
	action_event.emit(death)
	for event in departure_events: action_event.emit(event)
	CombatResolver.cancel_dodged_bashes(ref.id)
	refresh_control()
	state_changed.emit()
	rules_runner.end_boundary()

## Runner command completion/idle calls after causal sacrifice work settles; health restoration alone cannot save a still-defeated hero.
## Ordinary combat and Disable hero losses keep their existing immediate policy; only the explicitly sacrificed identities are deferred.
func settle_sacrificed_heroes() -> void:
	if sacrificed_heroes.is_empty(): return
	var pending := sacrificed_heroes.duplicate()
	sacrificed_heroes.clear()
	if winner != 0: return
	for identifier in pending:
		var unit := get_unit(identifier)
		if unit != null and (unit.t_state == Enum.t_state.DEFEATED or unit.actual_life < 1):
			winner = 3 - unit.player
			state_changed.emit()
			return

## Looks up a stable army index; returns null when it is outside the current army.
## Used by selectors, actions, resolvers, and TargetRef validation.
func get_unit(identifier: int) -> UnitInfo:
	return army[identifier] if identifier >= 0 and identifier < army.size() else null

## Looks up a stable board index; returns null when the index is outside the map.
## Selectors, deployment, and spatial actions use this live tile record.
func get_hex(identifier: int) -> HexInfo:
	return map[identifier] if identifier >= 0 and identifier < map.size() else null

## Checks whether a reference still identifies a match entity or unambiguous property.
## TargetRef.valid() delegates here at selection and action boundaries.
func exists(ref: TargetRef) -> bool:
	if ref == null: return false
	match ref.kind:
		TargetRef.Kind.UNIT: return get_unit(ref.id) != null
		TargetRef.Kind.HEX: return get_hex(ref.id) != null
		TargetRef.Kind.PLAYER: return players.has(ref.id)
		TargetRef.Kind.MATCH: return ref.id == 0
		TargetRef.Kind.PROPERTY: return get_property(ref) != null
	return false

## Returns the current hex ID for a deployed unit/hex, or -1 when it has no position.
## Selectors and combat legality use this live value; historical positions belong on events.
func position_of(ref: TargetRef) -> int:
	if ref == null: return -1
	if ref.kind == TargetRef.Kind.HEX: return ref.id if get_hex(ref.id) != null else -1
	if ref.kind == TargetRef.Kind.UNIT:
		var info := get_unit(ref.id)
		if info != null and info.t_state == Enum.t_state.DEPLOYED and get_hex(info.ihx) != null:
			return info.ihx
	if ref.kind == TargetRef.Kind.PROPERTY and ref.host != null and ref.host.kind != TargetRef.Kind.PROPERTY:
		return position_of(ref.host)
	return -1

## Resolves current ownership through units, hexes, players, and property hosts.
## Legality and target filters use it; it does not cache ownership on TargetRef.
func owner_of(ref: TargetRef) -> int:
	if not exists(ref): return Enum.owner.NONE
	match ref.kind:
		TargetRef.Kind.UNIT: return get_unit(ref.id).player
		TargetRef.Kind.HEX: return get_hex(ref.id).owner
		TargetRef.Kind.PLAYER: return ref.id
		TargetRef.Kind.PROPERTY: return owner_of(ref.host)
	return Enum.owner.NONE

## Returns live units at a hex in stable army order; selectors and combat use this query.
func occupants(hex_index: int) -> Array[TargetRef]:
	var result: Array[TargetRef] = []
	if get_hex(hex_index) == null: return result
	for index in army.size():
		var ref := TargetRef.unit(index)
		if position_of(ref) == hex_index: result.append(ref)
	return result

## Returns the inert bomb at a tile, if present.
## CombatResolver uses this for throwing, Fire lighting, defusing, and chain blasts.
func bomb_at(hex_id: int) -> BombInfo:
	for bomb in bombs:
		if bomb != null and bomb.hex_id == hex_id: return bomb
	return null

## Enumerates stable references in one supported native domain.
## QuerySelector calls this before applying owner/state/location filters.
func all(kind: int) -> Array[TargetRef]:
	var result: Array[TargetRef] = []
	match kind:
		TargetRef.Kind.UNIT:
			for index in army.size():
				if army[index] != null: result.append(TargetRef.unit(index))
		TargetRef.Kind.HEX:
			for index in map.size():
				if map[index] != null: result.append(TargetRef.hex(index))
		TargetRef.Kind.PLAYER:
			for index in players: result.append(TargetRef.player(index))
	return result

## Resolves a property reference only when its host/key is unambiguous.
## Property selectors and counter/flag actions call this at use time.
## Unit effect properties are read-only choices for Copy, resolved by stable category/definition keys independently of numeric properties.
func get_property(ref: TargetRef) -> Prop:
	if ref == null or ref.kind != TargetRef.Kind.PROPERTY or ref.host == null: return null
	if ref.host.kind == TargetRef.Kind.PROPERTY or not exists(ref.host): return null
	if ref.host.kind == TargetRef.Kind.UNIT and String(ref.property_key).begins_with("effect:"):
		for option in get_unit(ref.host.id).effect_options():
			if option.name == ref.property_key: return option
		return null
	var properties: Array[Prop] = []
	match ref.host.kind:
		TargetRef.Kind.UNIT: properties = get_unit(ref.host.id).props
		TargetRef.Kind.HEX: properties = get_hex(ref.host.id).props
		TargetRef.Kind.PLAYER: properties = players[ref.host.id].props
		TargetRef.Kind.MATCH: properties = props
	var found: Prop
	for item in properties:
		if item != null and item.name == ref.property_key:
			if found != null: return null
			found = item
	return found

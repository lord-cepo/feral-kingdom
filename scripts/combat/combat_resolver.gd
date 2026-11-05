class_name CombatResolver
extends RefCounted

static var _resolving_bash: BashInfo

## Checks Bow's physical range including permanent unit upgrades against a HEX candidate.
## Action.can_bow() calls this before selection and again when the chosen target commits.
static func can_bow(source: TargetRef, target: TargetRef, amount: int, range: int,
		action_free: bool = false) -> bool:
	if not _can_start_attack(source, target, amount, range, action_free): return false
	var source_hex := Match.get_hex(source.hex_id())
	var attacker := Match.get_unit(source.id)
	var effective_range := range + attacker.effective_bow_bonus().y if attacker != null else range
	if source_hex == null or DistanceSelector.hex_distance(source_hex.coordinate, Match.get_hex(target.id).coordinate) > effective_range: return false
	var enemy := enemy_on(target.id, Match.owner_of(source))
	return Match.occupants(target.id).is_empty() or enemy != null

## Captures a Bow target and queues it for the next opposing Combat window, or resolves it now.
## Action.bow() calls this after the target passes can_bow(); occupied targets retain unit identity.
static func declare_bow(source: TargetRef, target: TargetRef, amount: int, range: int,
		instant: bool, pierce: bool, action_free: bool = false) -> bool:
	Match.rules_runner.begin_boundary()
	var result := _apply_declare_bow(source, target, amount, range, instant, pierce, action_free)
	Match.rules_runner.end_boundary()
	return result

## Implements declare_bow inside its public wrapper's mutation boundary, capturing upgraded damage.
## Captured followups run only after this operation finishes its cleanup.
static func _apply_declare_bow(source: TargetRef, target: TargetRef, amount: int, range: int,
		instant: bool, pierce: bool, action_free: bool = false) -> bool:
	if not can_bow(source, target, amount, range, action_free): return false
	var attack := BowAttack.new()
	attack.owner = Match.owner_of(source)
	attack.source_id = source.id
	attack.origin_hex = source.hex_id()
	attack.target_hex = target.id
	var attacker := Match.get_unit(source.id)
	attack.amount = amount + (attacker.effective_bow_bonus().x if attacker != null else 0)
	attack.instant = instant
	attack.pierce = pierce
	var victim := enemy_on(target.id, attack.owner)
	if victim != null: attack.target_unit_id = victim.id
	if not instant: Match.pending_bow_attacks.append(attack)
	Match.action_event.emit(EffectEvent.new(&"bow", source, target, _bow_details(attack), &"target"))
	if instant: resolve_bow(attack)
	return true

## Resolves one captured Bow, requiring its original victim to remain on its hex.
## resolve_window() runs queued Bow before Gore, Cannon/Bomb, and Fire; Instant calls it directly.
static func resolve_bow(attack: BowAttack) -> void:
	Match.rules_runner.begin_boundary()
	_apply_resolve_bow(attack)
	Match.rules_runner.end_boundary()

## Implements resolve_bow inside its public wrapper's mutation boundary.
## Captured followups run only after this operation finishes its cleanup.
static func _apply_resolve_bow(attack: BowAttack) -> void:
	if attack == null or attack.resolved: return
	attack.resolved = true
	var victim := TargetRef.unit(attack.target_unit_id) if attack.target_unit_id >= 0 else enemy_on(attack.target_hex, attack.owner)
	attack.outcome = {"status": "missed", "damage": 0}
	if victim != null and victim.valid() and victim.has_hex() and victim.hex_id() == attack.target_hex \
			and Match.owner_of(victim) != attack.owner:
		var unit := Match.get_unit(victim.id)
		if unit.has_effective_flag(&"titanium"):
			attack.outcome = {"status": "blocked", "target": victim, "damage": 0}
		else:
			var damage := maxi(0, attack.amount - (0 if attack.pierce else unit.physical_modifier))
			attack.outcome = {"status": "hit", "target": victim, "damage": damage}
			_physical_contact(TargetRef.unit(attack.source_id), victim, damage, &"bow", _bow_details(attack))
			if unit.actual_life < 1: Match.defeat(victim, attack.owner)
			else: Match.state_changed.emit()
			Match.refresh_control()
	var result_target := TargetRef.hex(attack.target_hex)
	var details := _bow_details(attack)
	details["outcome"] = attack.outcome.duplicate(true)
	Match.action_event.emit(EffectEvent.new(&"bow", TargetRef.unit(attack.source_id), result_target,
		details, &"resolved"))

## Validates Gore's axial leap, including destination vacancy rules and activity allowance.
## Action.can_gore() uses this before the destination is offered and at commit.
static func can_gore(source: TargetRef, target: TargetRef, amount: int, range: int,
		action_free: bool = false) -> bool:
	if not _can_start_attack(source, target, amount, range, action_free): return false
	if Match.get_unit(source.id).type == Enum.type.TEMPLE: return false
	var path := _straight_line_hexes(source.hex_id(), target.id, range)
	if path.is_empty() or Match.bashes.any(func(bash: BashInfo) -> bool: return bash.target_hex == target.id): return false
	var owner := Match.owner_of(source)
	for occupant in Match.occupants(target.id):
		if Match.owner_of(occupant) == owner: return false
	return true

## Moves the Gore source immediately and queues one physical hit per enemy captured on its path.
## Action.gore() calls this after the player selects an aligned destination hex.
static func declare_gore(source: TargetRef, target: TargetRef, amount: int, range: int,
		action_free: bool = false) -> bool:
	Match.rules_runner.begin_boundary()
	var result := _apply_declare_gore(source, target, amount, range, action_free)
	Match.rules_runner.end_boundary()
	return result

## Checks a Move/Fly destination against printed plus live range, occupancy, temples, Bash reservations, and path rules.
## Action.can_move()/can_fly() call this for previews and PhraseExecution repeats it at commit.
static func can_move(source: TargetRef, target: TargetRef, range: int, flying: bool,
		action_free: bool = false) -> bool:
	var action_name: StringName = &"fly" if flying else &"move"
	var mover := Match.get_unit(source.id) if source != null and source.kind == TargetRef.Kind.UNIT else null
	if mover != null: range = mover.effective_action_values(action_name, [range])[0]
	if not _can_start_attack(source, target, 0, range, action_free): return false
	var unit := Match.get_unit(source.id)
	if unit == null or unit.type == Enum.type.TEMPLE or source.hex_id() == target.id: return false
	if DistanceSelector.hex_distance(Match.get_hex(source.hex_id()).coordinate,
			Match.get_hex(target.id).coordinate) > range or _bash_at(target.id): return false
	for occupant in Match.occupants(target.id):
		if Match.owner_of(occupant) == Match.owner_of(source): return false
	return flying or _has_free_move_path(source.hex_id(), target.id, range)

## Checks whether SELF can immediately heal an injured ally in range.
## Action.can_mend() uses this for selection and commit; full-health units are not candidates.
static func can_mend(source: TargetRef, target: TargetRef, amount: int, range: int,
		action_free: bool = false) -> bool:
	if source == null or target == null or source.kind != TargetRef.Kind.UNIT \
			or target.kind != TargetRef.Kind.UNIT or amount < 1 or range < 0: return false
	if not source.has_hex() or not target.has_hex() or Match.owner_of(source) != Match.owner_of(target): return false
	var source_unit := Match.get_unit(source.id)
	var target_unit := Match.get_unit(target.id)
	if source_unit == null or target_unit == null or target_unit.actual_life <= 0 \
			or target_unit.actual_life >= target_unit.max_life: return false
	var owner := Match.owner_of(source)
	if Match.winner != 0 or not Match.players.has(owner): return false
	if not Match.rules_runner.is_triggered() and (owner != Match.active_player or Match.phase != Match.Phase.ACTION \
			or (Match.players[owner].actions_remaining <= 0 and not action_free)): return false
	var source_hex := Match.get_hex(source.hex_id())
	var target_hex := Match.get_hex(target.hex_id())
	return source_hex != null and target_hex != null \
		and DistanceSelector.hex_distance(source_hex.coordinate, target_hex.coordinate) <= range

## Checks a hostile deployed unit in range for the intended additive Stun action.
## Action.can_stun() uses this for previews and commit; inactive enemies remain eligible and -1 denotes omitted/unlimited range.
static func can_stun(source: TargetRef, target: TargetRef, amount: int, range: int,
		action_free: bool = false) -> bool:
	if source == null or target == null or source.kind != TargetRef.Kind.UNIT \
			or target.kind != TargetRef.Kind.UNIT or source.id == target.id: return false
	if amount < 1 or range < -1 or not source.has_hex() or not target.has_hex(): return false
	var source_unit := Match.get_unit(source.id)
	var target_unit := Match.get_unit(target.id)
	if source_unit == null or target_unit == null or target_unit.t_state != Enum.t_state.DEPLOYED \
			or source_unit.player == target_unit.player: return false
	var owner := source_unit.player
	if Match.winner != 0 or not Match.players.has(owner): return false
	if not Match.rules_runner.is_triggered() and (owner != Match.active_player or Match.phase != Match.Phase.ACTION \
			or (Match.players[owner].actions_remaining <= 0 and not action_free)): return false
	var source_hex := Match.get_hex(source.hex_id())
	var target_hex := Match.get_hex(target.hex_id())
	var stun := Match.get_property(TargetRef.property(target, UnitInfo.STUN_COUNTER))
	return source_hex != null and target_hex != null and stun != null \
		and stun.increment == Enum.p_increment.COUNTER \
		and (range == -1 or DistanceSelector.hex_distance(source_hex.coordinate, target_hex.coordinate) <= range)

## Adds the requested Stun counters and deactivates the hostile recipient in one boundary.
## Retains pre-action Stun for Blue Mage; all other counters remain intact and additive bonus counters do not create a second Stun occurrence.
static func stun(source: TargetRef, target: TargetRef, amount: int, range: int,
		action_free: bool = false) -> bool:
	if not can_stun(source, target, amount, range, action_free): return false
	Match.rules_runner.begin_boundary()
	var unit := Match.get_unit(target.id)
	var counter := Match.get_property(TargetRef.property(target, UnitInfo.STUN_COUNTER))
	var previous_stun := counter.value
	unit.active = false
	counter.value += amount
	Match.action_event.emit(EffectEvent.new(&"stun", source, target,
		{"amount": amount, "hostile": true, "previous_stun": previous_stun}, &"resolved"))
	Match.state_changed.emit()
	Match.rules_runner.end_boundary()
	return true

## Applies immediate healing inside a mutation boundary and republishes derived control.
## Action.mend() calls this; the resolved event records actual life restored for triggers.
static func mend(source: TargetRef, target: TargetRef, amount: int, range: int,
		action_free: bool = false) -> bool:
	if not can_mend(source, target, amount, range, action_free): return false
	Match.rules_runner.begin_boundary()
	var unit := Match.get_unit(target.id)
	var before := unit.actual_life
	unit.actual_life = mini(unit.max_life, unit.actual_life + amount)
	var restored := unit.actual_life - before
	LifeChanges.publish(unit, Vector2i(before, unit.max_life), source)
	Match.action_event.emit(EffectEvent.new(&"mend", source, target,
		{"amount": restored, "requested": amount}, &"resolved"))
	Match.refresh_control()
	Match.state_changed.emit()
	Match.rules_runner.end_boundary()
	return restored > 0

## Moves or flies a unit immediately and captures historical location/control for triggers.
## Action.move()/fly() call this after selection; movement completes before followups can run.
static func move_unit(source: TargetRef, target: TargetRef, range: int, flying: bool,
		action_free: bool = false) -> bool:
	Match.rules_runner.begin_boundary()
	var result := _apply_move_unit(source, target, range, flying, action_free)
	Match.rules_runner.end_boundary()
	return result

## Performs movement inside its public wrapper's trigger boundary.
## Captures origin and a legal Walk path before mutation, then publishes one resolved movement occurrence.
## Board animates the captured hex IDs without re-querying occupancy after the move.
## Bash-exit presentation is derived by HexCell from its previous layout, independently of this movement action.
static func _apply_move_unit(source: TargetRef, target: TargetRef, range: int, flying: bool,
		action_free: bool = false) -> bool:
	if not can_move(source, target, range, flying, action_free): return false
	var unit := Match.get_unit(source.id)
	var origin_hex := unit.ihx
	var origin_control := ControlResolver.region_owner(Match.get_hex(origin_hex))
	var effective_range := unit.effective_action_values(&"fly" if flying else &"move", [range])[0]
	var path: Array[int] = [origin_hex, target.id]
	if not flying: path = walk_path(origin_hex, target.id, effective_range)
	unit.ihx = target.id
	cancel_dodged_bashes(source.id)
	var enemies := Match.occupants(target.id).filter(func(ref: TargetRef) -> bool:
		return ref.id != source.id and Match.owner_of(ref) != unit.player)
	if not enemies.is_empty(): _create_bash(source.id, enemies[0].id, target.id)
	var details := {"origin_hex": origin_hex, "destination_hex": target.id,
		"origin_control": origin_control, "destination_control": ControlResolver.region_owner(Match.get_hex(target.id)),
		"movement_kind": &"fly" if flying else &"move", "path": path}
	Match.action_event.emit(EffectEvent.new(&"move", source, target, details))
	Match.refresh_control()
	Match.state_changed.emit()
	return true

## Implements declare_gore inside its public wrapper's mutation boundary.
## Captured followups run only after this operation finishes its cleanup.
static func _apply_declare_gore(source: TargetRef, target: TargetRef, amount: int, range: int,
		action_free: bool = false) -> bool:
	if not can_gore(source, target, amount, range, action_free): return false
	var path := _straight_line_hexes(source.hex_id(), target.id, range)
	var attack_owner := Match.owner_of(source)
	var original_hex := source.hex_id()
	var occurrence := EffectEvent.new(&"gore", source, target,
		{"amount": amount, "origin_hex": original_hex, "destination_hex": target.id,
		"origin_control": ControlResolver.region_owner(Match.get_hex(original_hex)), "path": path.duplicate()}, &"target")
	Match.rules_runner.capture_event(occurrence)
	for hex_id in path:
		for occupant in Match.occupants(hex_id):
			if Match.owner_of(occupant) == attack_owner:
				continue
			var attack := GoreAttack.new()
			attack.owner = attack_owner
			attack.source_id = source.id
			attack.origin_hex = original_hex
			attack.destination_hex = target.id
			attack.target_hex = hex_id
			attack.target_unit_id = occupant.id
			attack.amount = amount
			Match.pending_gore_attacks.append(attack)
	Match.get_unit(source.id).ihx = target.id
	cancel_dodged_bashes(source.id)
	var landing := Match.occupants(target.id).filter(func(unit: TargetRef) -> bool: return unit.id != source.id)
	if not landing.is_empty(): _create_bash(source.id, landing[0].id, target.id)
	Match.action_event.emit(occurrence)
	Match.refresh_control()
	Match.state_changed.emit()
	return true

## Checks that a chosen UNIT can be displaced along an aligned line to a legal landing hex.
## Action.can_displace() uses it for both Push and Pull previews and commits.
static func can_displace(source: TargetRef, target: TargetRef, distance: int, range: int,
		pull: bool, action_free: bool = false) -> bool:
	if not _can_start_unit_action(source, target, distance, range, action_free): return false
	if target.id == source.id or not target.has_hex(): return false
	if Match.get_unit(source.id).type == Enum.type.TEMPLE or Match.get_unit(target.id).type == Enum.type.TEMPLE: return false
	var source_tile := Match.get_hex(source.hex_id())
	var target_tile := Match.get_hex(target.hex_id())
	if source_tile == null or target_tile == null or DistanceSelector.hex_distance(source_tile.coordinate, target_tile.coordinate) > range: return false
	var destination := _displacement_hex(source.hex_id(), target.hex_id(), distance, pull)
	if destination < 0 or _bash_at(destination): return false
	for occupant in Match.occupants(destination):
		if occupant.id != target.id and Match.owner_of(occupant) == Match.owner_of(target): return false
	return true

## Displaces a selected unit; an opposing occupant at the landing tile starts Bash.
## Verbs.push()/pull() call this after UNIT target selection.
static func displace(source: TargetRef, target: TargetRef, distance: int, range: int,
		pull: bool, action_free: bool = false) -> bool:
	Match.rules_runner.begin_boundary()
	var result := _apply_displace(source, target, distance, range, pull, action_free)
	Match.rules_runner.end_boundary()
	return result

## Implements displacement and records its turn before creating a landing Bash; Banner Bearer reads this history without counters.
## The resolved event retains the actor hex as well as the recipient's old/new hexes for directional cosmetic playback.
## Captured followups run only after this operation finishes its cleanup.
static func _apply_displace(source: TargetRef, target: TargetRef, distance: int, range: int,
		pull: bool, action_free: bool = false) -> bool:
	if not can_displace(source, target, distance, range, pull, action_free): return false
	var destination := _displacement_hex(source.hex_id(), target.hex_id(), distance, pull)
	var occupant := Match.occupants(destination).filter(func(unit: TargetRef) -> bool: return unit.id != target.id)
	var old_hex := target.hex_id()
	var origin_control := ControlResolver.region_owner(Match.get_hex(old_hex))
	Match.get_unit(target.id).ihx = destination
	Match.get_unit(target.id).last_displaced_turn = Match.turn_number
	cancel_dodged_bashes(target.id)
	if not occupant.is_empty(): _create_bash(target.id, occupant[0].id, destination)
	Match.action_event.emit(EffectEvent.new(&"pull" if pull else &"push", source, target,
		{"source_hex": source.hex_id(), "origin_hex": old_hex, "destination_hex": destination, "origin_control": origin_control}, &"resolved"))
	Match.refresh_control()
	Match.state_changed.emit()
	return true

## Validates Bomb displacement with the same aligned geometry but a HEX target.
## The explicit push_bomb/pull_bomb verbs call this for board highlighting and commit.
static func can_displace_bomb(source: TargetRef, target: TargetRef, distance: int, range: int,
		pull: bool, action_free: bool = false) -> bool:
	if not _can_start_attack(source, target, distance, range, action_free) or Match.bomb_at(target.id) == null: return false
	var source_tile := Match.get_hex(source.hex_id())
	var target_tile := Match.get_hex(target.id)
	if source_tile == null or target_tile == null or DistanceSelector.hex_distance(source_tile.coordinate, target_tile.coordinate) > range: return false
	return _displacement_hex(source.hex_id(), target.id, distance, pull) >= 0

## Moves an inert Bomb or merges it with the Bomb at the landing hex.
## Action.displace_bomb() calls this after HEX selection.
static func displace_bomb(source: TargetRef, target: TargetRef, distance: int, range: int,
		pull: bool, action_free: bool = false) -> bool:
	Match.rules_runner.begin_boundary()
	var result := _apply_displace_bomb(source, target, distance, range, pull, action_free)
	Match.rules_runner.end_boundary()
	return result

## Implements displace_bomb inside its public wrapper's mutation boundary.
## Captured followups run only after this operation finishes its cleanup.
static func _apply_displace_bomb(source: TargetRef, target: TargetRef, distance: int, range: int,
		pull: bool, action_free: bool = false) -> bool:
	if not can_displace_bomb(source, target, distance, range, pull, action_free): return false
	var bomb := Match.bomb_at(target.id)
	var origin := bomb.hex_id
	var destination := _displacement_hex(source.hex_id(), target.id, distance, pull)
	var other := Match.bomb_at(destination)
	if other != null and other != bomb:
		other.damage += bomb.damage
		other.pierce = other.pierce or bomb.pierce
		Match.bombs.erase(bomb)
	else:
		bomb.hex_id = destination
	Match.action_event.emit(EffectEvent.new(&"pull_bomb" if pull else &"push_bomb", source,
		TargetRef.hex(destination), {"origin_hex": origin}, &"resolved"))
	Match.state_changed.emit()
	return true

## Checks Cannon's nonzero straight line, effective damage/range, and current action-token availability.
## Action.can_cannon() uses it to filter the distance selector's endpoint candidates.
static func can_cannon(source: TargetRef, target: TargetRef, amount: int, range: int,
		action_free: bool = false) -> bool:
	var attacker := Match.get_unit(source.id) if source != null and source.kind == TargetRef.Kind.UNIT else null
	if attacker != null:
		var values := attacker.effective_action_values(&"cannon", [amount, range])
		amount = values[0]
		range = values[1]
	if not _can_start_attack(source, target, amount, range, action_free): return false
	return not _cannon_hexes(source.hex_id(), target.id, range).is_empty()

## Captures one Cannon record per playable hex along the chosen line.
## Action.cannon() invokes it after endpoint selection; empty hexes can catch later arrivals.
static func declare_cannon(source: TargetRef, target: TargetRef, amount: int, range: int,
		instant: bool, pierce: bool, action_free: bool = false) -> bool:
	Match.rules_runner.begin_boundary()
	var result := _apply_declare_cannon(source, target, amount, range, instant, pierce, action_free)
	Match.rules_runner.end_boundary()
	return result

## Implements declare_cannon inside its public wrapper's mutation boundary.
## Captured followups run only after this operation finishes its cleanup.
static func _apply_declare_cannon(source: TargetRef, target: TargetRef, amount: int, range: int,
		instant: bool, pierce: bool, action_free: bool = false) -> bool:
	if not can_cannon(source, target, amount, range, action_free): return false
	var effective_values := Match.get_unit(source.id).effective_action_values(&"cannon", [amount, range])
	amount = effective_values[0]
	range = effective_values[1]
	var owner := Match.owner_of(source)
	var line := _cannon_hexes(source.hex_id(), target.id, range)
	Match.action_event.emit(EffectEvent.new(&"cannon", source, target,
		{"amount": amount, "pierce": pierce, "line": line.duplicate()}, &"target"))
	for hex_id in line:
		var attack := CannonAttack.new()
		attack.owner = owner
		attack.source_id = source.id
		attack.target_hex = hex_id
		attack.amount = amount
		attack.instant = instant
		attack.pierce = pierce
		if instant: resolve_cannon(attack)
		else: Match.pending_cannon_attacks.append(attack)
	return true

## Applies Cannon/Bomb damage; Cannon publishes shared Hit/Wound, while explosions retain the distinct bomb_hit event outside attack families.
## resolve_window() invokes this after Bow/Gore and before Fire; Pierce bypasses Obsidian and modifiers.
static func resolve_cannon(attack: CannonAttack) -> void:
	Match.rules_runner.begin_boundary()
	_apply_resolve_cannon(attack)
	Match.rules_runner.end_boundary()

## Implements resolve_cannon inside its public wrapper's mutation boundary.
## Captured followups run only after this operation finishes its cleanup.
static func _apply_resolve_cannon(attack: CannonAttack) -> void:
	if attack == null or attack.resolved: return
	attack.resolved = true
	var targets := Match.occupants(attack.target_hex)
	var outcomes: Array[Dictionary] = []
	for ref in targets:
		var unit := Match.get_unit(ref.id)
		if not attack.pierce and unit.has_effective_flag(&"obsidian"):
			outcomes.append({"target": ref, "status": "immune", "damage": 0})
			continue
		var damage := attack.amount if attack.pierce else maxi(0, attack.amount - unit.magical_modifier)
		var loss := mini(maxi(0, unit.actual_life), damage)
		unit.consume_temporary_magic()
		unit.actual_life -= damage
		outcomes.append({"target": ref, "status": "hit", "damage": damage})
		if attack.explosion:
			Match.action_event.emit(EffectEvent.new(&"bomb_hit", TargetRef.unit(attack.source_id), ref, {"damage": damage, "kind": &"bomb"}, &"resolved", attack.owner))
		else:
			_publish_contact(TargetRef.unit(attack.source_id), ref, loss, &"cannon", {}, attack.owner)
		if unit.actual_life < 1: Match.defeat(ref, attack.owner)
		else: Match.state_changed.emit()
		Match.refresh_control()
	if attack.explosion:
		var chained_bomb := Match.bomb_at(attack.target_hex)
		if chained_bomb != null:
			ignite_bomb(chained_bomb, attack.chain_owner, attack.pierce, false)
	attack.outcome = {"targets": outcomes}
	var event_name := &"bomb_explosion" if attack.explosion else &"cannon"
	Match.action_event.emit(EffectEvent.new(event_name, TargetRef.unit(attack.source_id),
		TargetRef.hex(attack.target_hex), {"outcome": attack.outcome.duplicate(true)}, &"resolved", attack.owner))

## Resolves a captured Gore hit if its original victim remains on the crossed hex.
## resolve_window() runs these after Bow and before Cannon; dead sources cancel their hits.
static func resolve_gore(attack: GoreAttack) -> void:
	Match.rules_runner.begin_boundary()
	_apply_resolve_gore(attack)
	Match.rules_runner.end_boundary()

## Implements resolve_gore inside its public wrapper's mutation boundary.
## Captured followups run only after this operation finishes its cleanup.
static func _apply_resolve_gore(attack: GoreAttack) -> void:
	if attack == null or attack.resolved: return
	attack.resolved = true
	var source := Match.get_unit(attack.source_id)
	var victim := Match.get_unit(attack.target_unit_id)
	var outcome := {"status": "missed", "damage": 0}
	if source != null and source.t_state == Enum.t_state.DEPLOYED and victim != null \
			and victim.t_state == Enum.t_state.DEPLOYED and victim.ihx == attack.target_hex \
			and victim.player != attack.owner:
		if victim.has_effective_flag(&"titanium"):
			outcome.status = "blocked"
		else:
			var damage := maxi(0, attack.amount - victim.physical_modifier)
			outcome = {"status": "hit", "damage": damage, "target": TargetRef.unit(victim.iun)}
			_physical_contact(TargetRef.unit(attack.source_id), TargetRef.unit(victim.iun), damage, &"gore", {"amount": attack.amount})
			if victim.actual_life < 1: Match.defeat(TargetRef.unit(victim.iun), Match.owner_of(TargetRef.unit(attack.source_id)))
			else: Match.state_changed.emit()
			Match.refresh_control()
		attack.outcome = outcome
	Match.action_event.emit(EffectEvent.new(&"gore", TargetRef.unit(attack.source_id),
		TargetRef.hex(attack.target_hex), {"outcome": outcome.duplicate(true),
			"origin_hex": attack.origin_hex, "destination_hex": attack.destination_hex}, &"resolved"))

## Resolves a pending Bash after its assigned opponent has completed a response turn.
## resolve_window() calls this after Bow/Gore, Cannon/Bomb, and Fire have resolved.
static func resolve_bash(bash: BashInfo, defender: int) -> void:
	Match.rules_runner.begin_boundary()
	_apply_resolve_bash(bash, defender)
	Match.rules_runner.end_boundary()

## Implements resolve_bash inside its public wrapper's mutation boundary.
## Captured followups run only after this operation finishes its cleanup.
static func _apply_resolve_bash(bash: BashInfo, defender: int) -> void:
	if bash == null or bash.resolved or bash.responding_player != defender: return
	var attacker_ref := TargetRef.unit(bash.attacker_id)
	var defender_ref := TargetRef.unit(bash.defender_id)
	var attacker := Match.get_unit(bash.attacker_id)
	var opponent := Match.get_unit(bash.defender_id)
	if attacker == null or opponent == null or attacker.t_state != Enum.t_state.DEPLOYED \
			or opponent.t_state != Enum.t_state.DEPLOYED or attacker.ihx != bash.target_hex \
			or opponent.ihx != bash.target_hex:
		bash.resolved = true
		Match.bashes.erase(bash)
		Match.action_event.emit(EffectEvent.new(&"bash", attacker_ref, defender_ref,
			{"cancelled": true, "hex": bash.target_hex}, &"resolved"))
		return
	_resolving_bash = bash
	var attacker_titanium := attacker.has_effective_flag(&"titanium")
	var defender_titanium := opponent.has_effective_flag(&"titanium")
	var attacker_modifier := attacker.physical_modifier
	var defender_modifier := opponent.physical_modifier
	if opponent.has_effective_flag(&"steady"): attacker_modifier = 0
	if attacker.has_effective_flag(&"steady"): defender_modifier = 0
	var attacker_power := attacker.actual_life + attacker_modifier
	var defender_power := opponent.actual_life + defender_modifier
	var first := attacker if attacker.has_effective_flag(&"first-strike") else opponent if opponent.has_effective_flag(&"first-strike") else null
	if attacker_titanium or defender_titanium:
		if not attacker_titanium: _physical_contact(defender_ref, attacker_ref, maxi(0, defender_power - attacker_modifier), &"bash")
		if not defender_titanium: _physical_contact(attacker_ref, defender_ref, maxi(0, attacker_power - defender_modifier), &"bash")
	elif first != null:
		var target := opponent if first == attacker else attacker
		var first_modifier := attacker_modifier if first == attacker else defender_modifier
		var target_modifier := defender_modifier if first == attacker else attacker_modifier
		_physical_contact(TargetRef.unit(first.iun), TargetRef.unit(target.iun), maxi(0, first.actual_life + first_modifier - target_modifier), &"bash")
		if target.actual_life >= 1:
			_physical_contact(TargetRef.unit(target.iun), TargetRef.unit(first.iun), maxi(0, target.actual_life + target_modifier - first_modifier), &"bash")
	else:
		# Capture both powers before applying either half of the simultaneous exchange.
		_physical_contact(attacker_ref, defender_ref, maxi(0, attacker_power - defender_modifier), &"bash")
		_physical_contact(defender_ref, attacker_ref, maxi(0, defender_power - attacker_modifier), &"bash")
	if attacker.actual_life < 1: Match.defeat(attacker_ref, Match.owner_of(defender_ref))
	if opponent.actual_life < 1: Match.defeat(defender_ref, Match.owner_of(attacker_ref))
	var both_survive := attacker.t_state == Enum.t_state.DEPLOYED and opponent.t_state == Enum.t_state.DEPLOYED
	Match.action_event.emit(EffectEvent.new(&"bash", attacker_ref, defender_ref,
		{"hex": bash.target_hex, "first_strike": first != null}, &"resolved"))
	if both_survive:
		bash.responding_player = 3 - defender
	else:
		bash.resolved = true
		Match.bashes.erase(bash)
	_resolving_bash = null
	Match.refresh_control()
	Match.state_changed.emit()

## Checks a Bomb throw's range and ordinary action-token requirement.
## Action.can_bomb_throw() calls this during preview and commit.
static func can_bomb_throw(source: TargetRef, target: TargetRef, amount: int, range: int,
		action_free: bool = false) -> bool:
	if not _can_start_attack(source, target, amount, range, action_free): return false
	var origin := Match.get_hex(source.hex_id())
	var destination := Match.get_hex(target.id)
	return origin != null and destination != null \
		and DistanceSelector.hex_distance(origin.coordinate, destination.coordinate) <= range

## Places an inert bomb or merges damage/piercing into the bomb already at the chosen tile.
## Action.bomb_throw() calls this after target choice; Match.state_changed refreshes the board display.
static func throw_bomb(source: TargetRef, target: TargetRef, amount: int, range: int,
		pierce: bool, action_free: bool = false) -> bool:
	Match.rules_runner.begin_boundary()
	var result := _apply_throw_bomb(source, target, amount, range, pierce, action_free)
	Match.rules_runner.end_boundary()
	return result

## Implements throw_bomb inside its public wrapper's mutation boundary.
## Captured followups run only after this operation finishes its cleanup.
static func _apply_throw_bomb(source: TargetRef, target: TargetRef, amount: int, range: int,
		pierce: bool, action_free: bool = false) -> bool:
	if not can_bomb_throw(source, target, amount, range, action_free): return false
	var bomb := Match.bomb_at(target.id)
	if bomb == null:
		bomb = BombInfo.new()
		bomb.owner = Match.owner_of(source)
		bomb.source_id = source.id
		bomb.hex_id = target.id
		bomb.damage = amount
		bomb.pierce = pierce
		Match.bombs.append(bomb)
	else:
		bomb.damage += amount
		bomb.pierce = bomb.pierce or pierce
	Match.action_event.emit(EffectEvent.new(&"bomb_throw", source, target,
		{"damage": bomb.damage, "pierce": bomb.pierce}, &"resolved"))
	Match.state_changed.emit()
	return true

## Checks that an inert Bomb is within the acting unit's range and can be removed.
## Action.can_defuse_bomb() uses the same range rule before target selection.
static func can_defuse_bomb(source: TargetRef, target: TargetRef, range: int,
		action_free: bool = false) -> bool:
	if not _can_start_attack(source, target, 0, range, action_free): return false
	var origin := Match.get_hex(source.hex_id())
	var destination := Match.get_hex(target.id)
	return origin != null and destination != null and Match.bomb_at(target.id) != null \
		and DistanceSelector.hex_distance(origin.coordinate, destination.coordinate) <= range

## Removes an inert bomb without triggering its blast.
## Action.defuse_bomb() calls this after the target remains legal at commit.
static func defuse_bomb(source: TargetRef, target: TargetRef, range: int,
		action_free: bool = false) -> bool:
	Match.rules_runner.begin_boundary()
	var result := _apply_defuse_bomb(source, target, range, action_free)
	Match.rules_runner.end_boundary()
	return result

## Implements defuse_bomb inside its public wrapper's mutation boundary.
## Captured followups run only after this operation finishes its cleanup.
static func _apply_defuse_bomb(source: TargetRef, target: TargetRef, range: int,
		action_free: bool = false) -> bool:
	if not can_defuse_bomb(source, target, range, action_free): return false
	var bomb := Match.bomb_at(target.id)
	Match.bombs.erase(bomb)
	Match.action_event.emit(EffectEvent.new(&"bomb_defuse", source, target, {"damage": bomb.damage}, &"resolved"))
	Match.state_changed.emit()
	return true

## Removes a bomb and schedules a center-plus-adjacent magical area.
## Fire declaration calls it; fresh chain blasts are queued for a later response window.
static func ignite_bomb(bomb: BombInfo, owner: int, pierce: bool, instant: bool) -> void:
	Match.rules_runner.begin_boundary()
	_apply_ignite_bomb(bomb, owner, pierce, instant)
	Match.rules_runner.end_boundary()

## Implements ignite_bomb inside its public wrapper's mutation boundary.
## Captures the Bomb center on each blast record for HexCell's pending lit marker.
## Captured followups run only after this operation finishes its cleanup.
static func _apply_ignite_bomb(bomb: BombInfo, owner: int, pierce: bool, instant: bool) -> void:
	if bomb == null or not Match.bombs.has(bomb): return
	Match.bombs.erase(bomb)
	var center := Match.get_hex(bomb.hex_id)
	if center == null: return
	var adjacent := [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
		Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]
	var area := [center.coordinate]
	for direction in adjacent: area.append(center.coordinate + direction)
	var source_id := bomb.source_id
	for coordinate in area:
		var target_hex := _hex_at_coordinate(coordinate)
		if target_hex < 0: continue
		var attack := CannonAttack.new()
		attack.owner = owner
		attack.source_id = source_id
		attack.target_hex = target_hex
		attack.amount = bomb.damage
		attack.pierce = pierce
		attack.instant = instant
		attack.explosion = true
		attack.bomb_hex = bomb.hex_id
		attack.chain_owner = 3 - owner
		if instant: resolve_cannon(attack)
		else: Match.pending_cannon_attacks.append(attack)
	Match.action_event.emit(EffectEvent.new(&"bomb_light", TargetRef.unit(source_id),
		TargetRef.hex(bomb.hex_id), {"damage": bomb.damage, "pierce": pierce}, &"resolved", owner))
	Match.state_changed.emit()

## Returns true for a deployed, current-player source with a valid target and available token.
## Bow and Cannon legality checks share this invariant before adding action-specific geometry.
static func _can_start_attack(source: TargetRef, target: TargetRef, amount: int, range: int,
		action_free: bool) -> bool:
	if source == null or target == null or source.kind != TargetRef.Kind.UNIT or target.kind != TargetRef.Kind.HEX:
		return false
	if amount < 0 or range < 0 or not source.has_hex() or not target.valid(): return false
	var owner := Match.owner_of(source)
	return Match.winner == 0 and Match.players.has(owner) and (Match.rules_runner.is_triggered() or (owner == Match.active_player \
		and Match.phase == Match.Phase.ACTION \
		and (Match.players[owner].actions_remaining > 0 or action_free)))

## Produces playable hexes along one of six axial directions, excluding the source.
## Cannon legality and declaration both call it, so preview and committed line geometry match.
static func _cannon_hexes(source_hex: int, target_hex: int, max_range: int) -> Array[int]:
	var result: Array[int] = []
	var source := Match.get_hex(source_hex)
	var target := Match.get_hex(target_hex)
	if source == null or target == null: return result
	var delta := target.coordinate - source.coordinate
	var distance := DistanceSelector.hex_distance(source.coordinate, target.coordinate)
	if distance == 0 or distance > max_range or not (delta.x == 0 or delta.y == 0 or delta.x + delta.y == 0): return result
	var step := Vector2i(signi(delta.x), signi(delta.y))
	for distance_step in range(1, distance + 1):
		var coordinate := source.coordinate + step * distance_step
		var hex_id := _hex_at_coordinate(coordinate)
		if hex_id >= 0: result.append(hex_id)
	return result

## Looks up a playable hex by axial coordinate.
## _cannon_hexes() uses it to skip the unplayable board gap without ending the line.
static func _hex_at_coordinate(coordinate: Vector2i) -> int:
	for tile in Match.map:
		if tile != null and tile.coordinate == coordinate: return tile.hex_id
	return -1

## Builds a stable Bow declaration payload for hit, wound, and resolution events.
## resolve_bow() uses this read-only helper; current position is descriptive, not attack identity.
static func _bow_details(attack: BowAttack) -> Dictionary:
	return {"amount": attack.amount, "pierce": attack.pierce,
		"origin_hex": attack.origin_hex, "target_hex": attack.target_hex,
		"target_unit_id": attack.target_unit_id}

## Checks Fire source timing, effective damage, target domain, and enemy-or-empty occupancy.
## Action.can_fire() calls this before selection and commit; Action-free only exempts the token.
static func can_fire(source: TargetRef, target: TargetRef, amount: int, action_free: bool = false) -> bool:
	var attacker := Match.get_unit(source.id) if source != null and source.kind == TargetRef.Kind.UNIT else null
	if attacker != null: amount = attacker.effective_action_values(&"fire", [amount, 0])[0]
	if Match.winner != 0 or source == null or target == null or amount < 0:
		return false
	if source.kind != TargetRef.Kind.UNIT or target.kind != TargetRef.Kind.HEX:
		return false
	if not source.has_hex() or not target.valid():
		return false
	var owner := Match.owner_of(source)
	if not Match.players.has(owner) or (not Match.rules_runner.is_triggered() and (owner != Match.active_player or Match.phase != Match.Phase.ACTION)):
		return false
	if not Match.rules_runner.is_triggered() and Match.players[owner].actions_remaining <= 0 and not action_free: return false
	var occupants := Match.occupants(target.id)
	# Empty hexes are valid; a shared hex targets the opposing participant.
	return occupants.is_empty() or enemy_on(target.id, owner) != null or Match.bomb_at(target.id) != null

static func enemy_on(hex_id: int, owner: int) -> TargetRef:
	for ref in Match.occupants(hex_id):
		if Match.owner_of(ref) != owner: return ref
	return null

## Captures and announces Fire with its current continuous damage grant; action_free exempts only the player token.
## Action.fire() calls this after Verb legality. Delayed attacks queue for the
## opposing combat window; instant attacks resolve immediately.
static func declare_fire(source: TargetRef, target: TargetRef, amount: int, instant: bool,
		pierce: bool, action_free: bool = false) -> bool:
	Match.rules_runner.begin_boundary()
	var result := _apply_declare_fire(source, target, amount, instant, pierce, action_free)
	Match.rules_runner.end_boundary()
	return result

## Implements declare_fire inside its public wrapper's mutation boundary.
## Captured followups run after cleanup; Ember/next-Fire stickers are captured and consumed before declaration triggers, then state refreshes once declared.
static func _apply_declare_fire(source: TargetRef, target: TargetRef, amount: int, instant: bool,
		pierce: bool, action_free: bool = false) -> bool:
	if not can_fire(source, target, amount, action_free): return false
	var attacker := Match.get_unit(source.id)
	instant = instant or &"instant" in attacker.next_fire_stickers
	pierce = pierce or &"pierce" in attacker.next_fire_stickers
	attacker.next_fire_stickers.clear()
	amount = Match.get_unit(source.id).effective_action_values(&"fire", [amount, 0])[0]
	var embers := Match.get_property(TargetRef.property(source, UnitInfo.EMBER_COUNTER))
	if embers != null: embers.value = 0
	var attack := FireAttack.new()
	attack.source_id = source.id
	attack.owner = Match.owner_of(source)
	attack.origin_hex = source.hex_id()
	attack.target_hex = target.id
	attack.amount = amount
	attack.instant = instant
	attack.pierce = pierce
	attack.declared_turn = Match.turn_number
	var enemy := enemy_on(target.id, attack.owner)
	if enemy != null: attack.target_unit_id = enemy.id
	var bomb := Match.bomb_at(target.id)
	if bomb == null and not instant: Match.pending_attacks.append(attack)
	Match.fire.emit(source, target, amount)
	Match.action_event.emit(EffectEvent.new(&"fire", source, target, attack.details(), &"target"))
	if bomb != null: ignite_bomb(bomb, attack.owner, pierce, instant)
	elif instant: resolve_fire(attack)
	Match.state_changed.emit()
	return true

## Resolves one captured Fire once, validating its original victim and applying the lethal test.
## Called directly for instant Fire or by resolve_window(); survivors lose no life.
## Contact consumes temporary magical protection, while immunity preserves it.
static func resolve_fire(attack: FireAttack) -> void:
	Match.rules_runner.begin_boundary()
	_apply_resolve_fire(attack)
	Match.rules_runner.end_boundary()

## Implements resolve_fire inside its public wrapper's mutation boundary.
## Publishes resolved Fire on misses and Hit/Wound on actual magical contact; lethal contact records positive life loss before death capture.
static func _apply_resolve_fire(attack: FireAttack) -> void:
	if attack.resolved: return
	# Set before signals to prevent reentrant or repeated resolution.
	attack.resolved = true
	var target := TargetRef.unit(attack.target_unit_id) if attack.target_unit_id >= 0 else enemy_on(attack.target_hex, attack.owner)
	attack.outcome = {"status": "missed", "defeated": false, "life_lost": 0}
	if target == null or not target.valid() or target.hex_id() != attack.target_hex or Match.owner_of(target) == attack.owner:
		var missed_details := attack.details()
		missed_details["outcome"] = attack.outcome.duplicate()
		Match.action_event.emit(EffectEvent.new(&"fire", TargetRef.unit(attack.source_id),
			TargetRef.hex(attack.target_hex), missed_details, &"resolved"))
		Match.fire_resolved.emit(attack)
		return
	var unit := Match.get_unit(target.id)
	if not attack.pierce and unit.has_effective_flag(&"obsidian"):
		attack.outcome.status = "immune"
	else:
		var modifier := unit.magical_modifier
		var threshold := attack.amount - (0 if attack.pierce else modifier)
		var lethal := unit.actual_life <= threshold
		attack.outcome = {
			"status": "defeated" if lethal else "survived", "target": target,
			"magical_modifier": modifier, "threshold": threshold,
			"defeated": lethal, "life_lost": unit.actual_life if lethal else 0}
		unit.consume_temporary_magic()
		if lethal: unit.actual_life = 0
		_publish_contact(TargetRef.unit(attack.source_id), target, int(attack.outcome.life_lost), &"fire", attack.details(), attack.owner)
		if lethal: Match.defeat(target, attack.owner)
	var details := attack.details()
	details["outcome"] = attack.outcome.duplicate()
	Match.action_event.emit(EffectEvent.new(&"fire", TargetRef.unit(attack.source_id), TargetRef.hex(attack.target_hex), details, &"resolved"))
	Match.fire_resolved.emit(attack)

## Resolves opposing Bow/Gore, Cannon/Bomb, Fire, then Bash in their declared order.
## Match.complete_action() calls this at Combat-resolve; callback-created attacks wait.
static func resolve_window(defender: int) -> void:
	var steps: Array = []
	# Freeze all groups before resolving the first attack; callbacks cannot join later groups.
	for attack in Match.pending_bow_attacks.duplicate():
		if attack.owner != defender and not attack.resolved:
			Match.pending_bow_attacks.erase(attack)
			steps.append(resolve_bow.bind(attack))
	for attack in Match.pending_gore_attacks.duplicate():
		if attack.owner != defender and not attack.resolved:
			Match.pending_gore_attacks.erase(attack)
			steps.append(resolve_gore.bind(attack))
	for attack in Match.pending_cannon_attacks.duplicate():
		if attack.owner != defender and not attack.resolved:
			Match.pending_cannon_attacks.erase(attack)
			steps.append(resolve_cannon.bind(attack))
	for attack in Match.pending_attacks.duplicate():
		if attack.owner != defender and not attack.resolved:
			Match.pending_attacks.erase(attack)
			steps.append(resolve_fire.bind(attack))
	for bash in Match.bashes.duplicate():
		if bash.responding_player == defender and not bash.resolved:
			steps.append(resolve_bash.bind(bash, defender))
	Match.rules_runner.schedule(steps)

## Checks that a deployed current-player UNIT can pay for the selected target action.
## Gore, Push/Pull, and Bomb displacement share phase, activity-token, and distance validation.
static func _can_start_unit_action(source: TargetRef, target: TargetRef, distance: int,
		range: int, action_free: bool) -> bool:
	if source == null or target == null or source.kind != TargetRef.Kind.UNIT \
			or target.kind != TargetRef.Kind.UNIT or source.id == target.id: return false
	if distance < 1 or range < 0 or not source.has_hex() or not target.has_hex(): return false
	var owner := Match.owner_of(source)
	return Match.winner == 0 and Match.players.has(owner) and (Match.rules_runner.is_triggered() or (owner == Match.active_player \
		and Match.phase == Match.Phase.ACTION \
		and (Match.players[owner].actions_remaining > 0 or action_free)))

## Builds the playable portion of an axial straight path, excluding its origin.
## Gore uses it to capture hit hexes; the final hex must be the selected destination.
static func _straight_line_hexes(source_hex: int, target_hex: int, max_range: int) -> Array[int]:
	var result: Array[int] = []
	var source := Match.get_hex(source_hex)
	var target := Match.get_hex(target_hex)
	if source == null or target == null: return result
	var delta := target.coordinate - source.coordinate
	var distance := DistanceSelector.hex_distance(source.coordinate, target.coordinate)
	if distance == 0 or distance > max_range \
			or not (delta.x == 0 or delta.y == 0 or delta.x + delta.y == 0): return result
	var step := Vector2i(signi(delta.x), signi(delta.y))
	for index in range(1, distance + 1):
		var hex_id := _hex_at_coordinate(source.coordinate + step * index)
		if hex_id >= 0: result.append(hex_id)
	return result if result.back() == target_hex else []

## Returns the final playable hex for Push/Pull, allowing the path itself to cross the board gap.
## Unit and Bomb displacement validators use the same endpoint calculation.
static func _displacement_hex(source_hex: int, target_hex: int, distance: int, pull: bool) -> int:
	var source := Match.get_hex(source_hex)
	var target := Match.get_hex(target_hex)
	if source == null or target == null or distance < 1: return -1
	var delta := target.coordinate - source.coordinate
	if not (delta.x == 0 or delta.y == 0 or delta.x + delta.y == 0): return -1
	var step := Vector2i(signi(delta.x), signi(delta.y)) * (-1 if pull else 1)
	return _hex_at_coordinate(target.coordinate + step * distance)

## Finds whether a hex is already reserved by an unresolved Bash.
## Gore and displacement reject landings that would overlap another encounter.
static func _bash_at(hex_id: int) -> bool:
	for bash in Match.bashes:
		if not bash.resolved and bash.target_hex == hex_id: return true
	return false

## Removes unresolved Bash records as soon as a participant leaves their shared tile.
## Move, Fly, Gore, Push, and Pull call this after changing position; no damage is applied.
## The captured defender_fled flag distinguishes the opponent leaving an attacker-initiated encounter, including forced movement.
static func cancel_dodged_bashes(unit_id: int) -> void:
	var unit_ref := TargetRef.unit(unit_id)
	var current_hex := Match.position_of(unit_ref)
	for bash in Match.bashes.duplicate():
		if bash == null or bash.resolved or bash == _resolving_bash or bash.target_hex == current_hex: continue
		if bash.attacker_id != unit_id and bash.defender_id != unit_id: continue
		bash.resolved = true
		Match.bashes.erase(bash)
		Match.action_event.emit(EffectEvent.new(&"bash", TargetRef.unit(bash.attacker_id),
			TargetRef.unit(bash.defender_id), {"cancelled": true, "dodged": true, "defender_fled": unit_id == bash.defender_id and unit_ref.has_hex(), "hex": bash.target_hex}, &"resolved"))

## Finds a path of at most range steps through playable, unoccupied intermediate hexes.
## Move validation calls this; the occupied destination is allowed only as the final step.
static func _has_free_move_path(origin_hex: int, destination_hex: int, range: int) -> bool:
	return not walk_path(origin_hex, destination_hex, range).is_empty()

## Returns one deterministic shortest Walk path including origin/destination, or empty if blocked.
## Move legality and _apply_move_unit share this BFS; only the final tile may be occupied.
static func walk_path(origin_hex: int, destination_hex: int, range: int) -> Array[int]:
	var empty: Array[int] = []
	var origin := Match.get_hex(origin_hex)
	var destination := Match.get_hex(destination_hex)
	if origin == null or destination == null or range < 1 or origin_hex == destination_hex: return empty
	var queue: Array[Vector2i] = [origin.coordinate]
	var distances: Dictionary = {}
	var previous: Dictionary = {}
	distances[origin.coordinate] = 0
	var neighbors: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1),
		Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 1)]
	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		var steps: int = distances[current]
		if steps >= range: continue
		for direction: Vector2i in neighbors:
			var next := current + direction
			if distances.has(next): continue
			var next_hex := _hex_at_coordinate(next)
			if next_hex < 0: continue
			previous[next_hex] = _hex_at_coordinate(current)
			if next_hex == destination_hex:
				var path: Array[int] = [destination_hex]
				while path[0] != origin_hex: path.push_front(previous[path[0]])
				return path
			if not Match.occupants(next_hex).is_empty(): continue
			distances[next] = steps + 1
			queue.append(next)
	return empty

## Records a Bash that will resolve after the opponent has had a response turn.
## Movement, Gore, Push/Pull and Match.deploy_from_effect call this when their destination contains an enemy.
static func _create_bash(attacker_id: int, defender_id: int, hex_id: int) -> void:
	if _bash_at(hex_id): return
	var bash := BashInfo.new()
	bash.attacker_id = attacker_id
	bash.defender_id = defender_id
	bash.target_hex = hex_id
	var attacker := Match.get_unit(attacker_id)
	var defender := Match.get_unit(defender_id)
	var fast := (attacker != null and attacker.has_effective_flag(&"fast")) \
		or (defender != null and defender.has_effective_flag(&"fast"))
	bash.responding_player = Match.active_player if fast else 3 - Match.active_player
	Match.bashes.append(bash)
	Match.action_event.emit(EffectEvent.new(&"bash", TargetRef.unit(attacker_id),
		TargetRef.unit(defender_id), {"hex": hex_id}, &"target"))

## Applies a physical contact and captures Hit/Wound before death removes participants.
## Bow/Gore/Bash call inside mutation boundaries; the shared publisher also handles magical contact without consuming physical shields.
static func _physical_contact(source: TargetRef, target: TargetRef, damage: int, kind: StringName, details: Dictionary = {}) -> void:
	var unit := Match.get_unit(target.id)
	unit.consume_temporary_physical()
	var loss := mini(maxi(0, unit.actual_life), damage)
	unit.actual_life -= damage
	var history := details.duplicate(true)
	history["damage"] = loss
	history["kind"] = kind
	_publish_contact(source, target, loss, kind, history)

## Physical attacks, Cannon and Fire publish one Hit per contact and Wound only for positive applied life loss, before death removal.
## The captured wounded fact lets Fire/zero-damage payoffs avoid querying a target whose life later changes during followups.
static func _publish_contact(source: TargetRef, target: TargetRef, loss: int, kind: StringName,
		details: Dictionary = {}, controller: int = 0) -> void:
	var history := details.duplicate(true)
	history["kind"] = kind
	history["damage"] = loss
	history["wounded"] = loss > 0
	Match.action_event.emit(EffectEvent.new(&"hit", source, target, history, &"resolved", controller))
	if loss > 0: Match.action_event.emit(EffectEvent.new(&"wound", source, target, history, &"resolved", controller))

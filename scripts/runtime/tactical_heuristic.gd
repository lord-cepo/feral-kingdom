## Read-only root guidance for headless MCTS. Tactical exposure is ordered
## before weighted preferences. The match remains the authority for outcomes.
extends RefCounted

enum Exposure { SAFE, ANSWERED_HIT, UNANSWERED_HIT, ANSWERED_LOSS, UNANSWERED_LOSS, HERO_LOSS }

const ATTACKS := [&"move", &"fly", &"bow", &"gore", &"fire", &"cannon"]
const UPGRADES := [&"upgrade_ability", &"upgrade_bow", &"upgrade_cannon", &"grant_action_values", &"up_life"]
const RETURNS := [&"return_to_hand", &"return_and_deploy", &"deploy_returned_hex"]

var weights := {
	"physical_attack": 1.0,
	"magical_attack": 1.0,
	"health": 0.7,
	"physical_modifier": 0.35,
	"magical_modifier": 0.35,
	"control": 0.8,
	"upgrade": 0.7,
	"reset": 0.55,
	"stun": 0.65,
	"return": 0.5,
	"deployment": 0.4,
}

class Attack:
	var definition: Effect.Verb
	var family: StringName
	var amount := 0
	var radius := 0
	var pierce := false
	var instant := false
	var ready := false
	var activity_cost := false

class Profile:
	var unit: UnitInfo
	var physical := 0
	var magical := 0
	var titanium := false
	var obsidian := false
	var steady := false
	var first_strike := false
	var attacks: Array[Attack] = []
	var resets: Array[Effect.Phrase] = []
	var death_reset := false
	var support := 0.0
	var upgrade := 0.0

var _profiles: Dictionary[int, Profile] = {}
var _field: Array[Profile] = []
var _occupancy: Dictionary[int, Array] = {}
var _regions: Dictionary[Vector3i, Vector2] = {}
var _paths: Dictionary[Vector3i, Dictionary] = {}
var _exposure: Dictionary[Vector4i, int] = {}
var _pending: Dictionary[Vector3i, Vector2i] = {}
var _has_pending := false
var _recent_hexes: Dictionary[int, Array] = {}
## The driver reads this after rank() to decide whether to act between searches.
var can_avoid_pending := false
## The driver reads the length of the safest prefix after a complete rank.
var safest_count := 0


## Cheap guard for the self-play driver before asking for a dodge on an
## unscheduled decision. The actual forecast checks captured targets and damage.
func has_pending_attack(owner: int) -> bool:
	for queue in [Match.pending_bow_attacks, Match.pending_gore_attacks, Match.pending_cannon_attacks, Match.pending_attacks]:
		for attack in queue:
			if not attack.resolved and attack.owner != owner: return true
	for bash in Match.bashes:
		if not bash.resolved and bash.responding_player == owner: return true
	return false


## Ranks eligible root options by exposure, net pending damage, then weighted
## value. The self-play driver uses the best ranked option between searches.
## include_all supplies progressive widening with the complete order. Search
## sets observe_history to false so simulations cannot alter committed history.
## An empty order leaves unsupported pickers to the caller's fallback.
func rank(decision: Dictionary, include_all: bool = false, observe_history: bool = true) -> Array[int]:
	_profiles.clear()
	_field.clear()
	_occupancy.clear()
	_regions.clear()
	_paths.clear()
	_exposure.clear()
	_pending.clear()
	can_avoid_pending = false
	safest_count = 0
	var owner: int = decision.player
	_has_pending = has_pending_attack(owner)
	for unit: UnitInfo in Match.army:
		if unit == null or unit.t_state != Enum.t_state.DEPLOYED or Match.get_hex(unit.ihx) == null: continue
		if not _occupancy.has(unit.ihx): _occupancy[unit.ihx] = []
		_occupancy[unit.ihx].append(unit)
		_field.append(_profile(unit))
		if observe_history and unit.player == owner: _observe_hex(unit)
	var candidates: Array[Dictionary] = []
	var options: Array = decision.options
	for index in options.size():
		var rating := _rate(options[index], owner)
		if rating.is_empty(): return []
		rating.index = index
		candidates.append(rating)
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a.index < b.index if a.risk == b.risk and a.pending.y == b.pending.y and a.score == b.score \
			else _better_rating(a, b))
	var order: Array[int] = []
	for candidate in candidates:
		if candidate.risk == candidates[0].risk and candidate.pending.y == candidates[0].pending.y:
			safest_count += 1
		elif not include_all:
			break
		order.append(candidate.index)
	if _has_pending and not candidates.is_empty():
		var baseline := _pending_priority(owner, null, -1, -1, -1)
		var projected: Vector2i = candidates[0].pending
		can_avoid_pending = projected.x < baseline.x or (projected.x == baseline.x and projected.y < baseline.y)
	return order


## Resolves the affected actor and projected landing for rank(). An action
## that opens a direct movement or suppression picker is scored using its
## safest currently legal target.
func _rate(option: Dictionary, owner: int) -> Dictionary:
	if option.kind == "deploy":
		return _rate_position(_profile(Match.get_unit(option.unit)), option.hex, true, &"deploy", null)
	if option.kind == "effect":
		var unit := Match.get_unit(option.unit)
		var effect: Effect = unit.effects[option.slot]
		var phrase := _first_phrase(effect.consequence)
		var profile := _profile(unit)
		var spent := _pays_activity(effect)
		if phrase == null or phrase.verb == null: return _rate_position(profile, unit.ihx, spent, &"", null)
		var family := phrase.verb.name
		var moving := family in [&"move", &"fly", &"gore", &"flee"] and phrase.subject is Selectors.Self
		var payment := _material_cost(effect)
		if phrase.target_mode == Effect.Phrase.TargetMode.CHOOSE_ONE \
				and (moving or family in [&"stun", &"return_to_hand", &"bow", &"fire", &"cannon"]):
			var ctx := RuleContext.new(TargetRef.unit(unit.iun))
			ctx.subject = ctx.source
			ctx.query_verb = phrase.verb
			var targets := TargetResolver.resolve(phrase.target, phrase.verb.target_kind, ctx)
			var best := {}
			for target in phrase.verb.bound_to(ctx).filter_targets(ctx.source, targets.candidates):
				var landing := target.id if moving and target.kind == TargetRef.Kind.HEX else unit.ihx
				var rating := _rate_position(profile, landing, spent, family, target, phrase.verb)
				if _better_rating(rating, best):
					best = rating
			if not best.is_empty():
				best.score -= payment
				return best
		var rating := _rate_position(profile, unit.ihx, spent, family, null)
		rating.score -= payment
		return rating
	var execution := Match.rules_runner.active
	if option.kind != "choose" or execution == null or execution.current == null:
		return {}
	var phrase_run := execution.current
	if phrase_run.status != PhraseExecution.Status.TARGET or phrase_run.subject == null \
			or phrase_run.subject.kind != TargetRef.Kind.UNIT:
		return {}
	var actor := Match.get_unit(phrase_run.subject.id)
	if actor == null or actor.player != owner or actor.t_state != Enum.t_state.DEPLOYED: return {}
	var target := NetworkSession.decode_ref(option.ref)
	var family := phrase_run.phrase.verb.name
	if execution.status == EffectExecution.Status.COST and family in [&"sacrifice", &"pay_life"] \
			and target != null and target.kind == TargetRef.Kind.UNIT:
		var payer := Match.get_unit(target.id)
		if payer != null and payer.player == owner:
			var loss := 4.0 + payer.actual_life + _profile(payer).support
			var lethal := family == &"sacrifice"
			if family == &"pay_life":
				var params := phrase_run.phrase.verb.user_params
				lethal = payer.actual_life <= int(params[0]) or payer.max_life <= int(params[1])
				if not lethal: loss = maxi(int(params[0]), int(params[1]))
			var risk := Exposure.HERO_LOSS if lethal and payer.type == Enum.type.HERO else Exposure.SAFE
			return {"risk": risk, "pending": Vector2i.ZERO, "score": -loss}
	if execution.status != EffectExecution.Status.CONSEQUENCE: return {}
	var landing := actor.ihx
	if target != null and target.kind == TargetRef.Kind.HEX and family in [&"move", &"fly", &"gore", &"relocate", &"flee"]:
		landing = target.id
	var stun := Match.get_property(TargetRef.property(TargetRef.unit(actor.iun), UnitInfo.STUN_COUNTER))
	return _rate_position(_profile(actor), landing, not actor.active or (stun != null and stun.value > 0),
		family, target, phrase_run.phrase.verb)


## Supplies the projected exposure and weighted preferences for one root choice.
## A specific ranged target adds its prospective damage as a secondary preference.
func _rate_position(profile: Profile, hex: int, spent: bool, family: StringName, target: TargetRef,
		verb: Effect.Verb = null) -> Dictionary:
	var unit := profile.unit
	var attack_score := 0.0
	for strike in profile.attacks:
		var magic := strike.family in [&"fire", &"cannon"]
		var weight: float = weights.magical_attack if magic else weights.physical_attack
		var best_hit := 0.0
		for enemy in _field:
			if enemy.unit.player == unit.player: continue
			var enemy_hex := enemy.unit.ihx
			var melee := strike.family in [&"move", &"fly"]
			var damage := _bash_damage(profile, enemy, enemy_hex, true).x if melee else _ranged_damage(strike, enemy, enemy_hex)
			var fraction := float(mini(damage, enemy.unit.actual_life)) / maxi(1, enemy.unit.actual_life)
			var in_range := _distance(hex, enemy_hex) <= strike.radius if melee else _ranged_reaches(strike, hex, enemy_hex)
			var reach := 1.0 if in_range else 0.2
			var selected := target != null and target.kind == TargetRef.Kind.HEX and target.id == enemy_hex and strike.family == family
			best_hit = maxf(best_hit, fraction * reach)
			if selected and strike.definition == verb:
				attack_score += 2.0 * mini(damage, enemy.unit.actual_life)
				if damage >= enemy.unit.actual_life:
					attack_score += 12.0 if enemy.unit.type == Enum.type.HERO else 4.0
		attack_score = maxf(attack_score, weight * (best_hit + 0.08 * maxf(0, strike.amount) + 0.04 * strike.radius))
	var score: float = weights.health * unit.actual_life + weights.physical_modifier * _physical_at(profile, hex) \
		+ weights.magical_modifier * profile.magical + attack_score + profile.support
	var upgrade_value := profile.upgrade * (0.4 if profile.upgrade > 0.0 and _reset_threat(profile, hex) else 1.0)
	score += weights.upgrade * upgrade_value + weights.control * _control_gain(unit, hex)
	score += _utility(family)
	if hex != unit.ihx and not _occupancy.has(hex):
		var recent: Array = _recent_hexes.get(unit.iun, [])
		score -= 1.5 * recent.count(hex)
	for enemy in _field:
		if enemy.unit.player == unit.player or enemy.unit.type != Enum.type.HERO: continue
		var distance := _distance(hex, enemy.unit.ihx)
		if distance >= 0 and not profile.attacks.is_empty():
			score += 4.0 / (1.0 + distance)
	if target != null:
		var host := target.host if target.kind == TargetRef.Kind.PROPERTY else target
		if host != null and host.kind == TargetRef.Kind.UNIT:
			var recipient := Match.get_unit(host.id)
			if recipient != null:
				if family in UPGRADES and _reset_threat(_profile(recipient), recipient.ihx):
					score -= weights.upgrade * 0.6
				elif family == &"reset":
					var printed_life := int(recipient.printed_state.get("life", recipient.max_life))
					var upgrade_count := recipient.ability_upgrades.size() + recipient.timed_grants.size() \
						+ maxi(0, recipient.bow_damage_bonus) + maxi(0, recipient.action_counter(UnitInfo.CANNON_DAMAGE_COUNTER))
					var impact := float(printed_life - recipient.actual_life - upgrade_count)
					score += weights.reset * impact * (1.0 if recipient.player == unit.player else -1.0)
				elif family == &"stun" and recipient.player != unit.player and recipient.active:
					score += weights.stun
	var suppression := _suppression(profile, hex, family, target, verb)
	var removed := -suppression - 1 if suppression < 0 else -1
	var evacuated := -1
	if family == &"return_to_hand" and target != null and target.kind == TargetRef.Kind.UNIT:
		var returned := Match.get_unit(target.id)
		if returned != null and returned.player == unit.player: evacuated = returned.iun
	var pending := _pending_priority(unit.player, profile, hex, removed, evacuated)
	var risk := _worst_exposure(profile, hex, spent, suppression) if evacuated != unit.iun else Exposure.SAFE
	return {"risk": maxi(risk, pending.x), "pending": pending, "score": score}


## Tracks committed landings across the driver's root decisions. Recent
## revisits reduce positional value without weakening the safety ordering.
func _observe_hex(unit: UnitInfo) -> void:
	if not _recent_hexes.has(unit.iun): _recent_hexes[unit.iun] = []
	var recent: Array = _recent_hexes[unit.iun]
	if not recent.is_empty() and recent.back() == unit.ihx: return
	recent.append(unit.ihx)
	if recent.size() > 6: recent.pop_front()


## Orders targets within one prospective command by the same priorities as rank().
func _better_rating(candidate: Dictionary, best: Dictionary) -> bool:
	if best.is_empty() or candidate.risk != best.risk:
		return best.is_empty() or candidate.risk < best.risk
	if candidate.pending.y != best.pending.y: return candidate.pending.y < best.pending.y
	return candidate.score > best.score


## Aggregates imminent attack losses across the whole side. An unrelated
## safe action does not erase an attack aimed at a different friendly unit.
func _pending_priority(owner: int, mover: Profile, hex: int, removed: int, evacuated: int) -> Vector2i:
	var result := Vector2i.ZERO
	if not _has_pending: return result
	for ally in _field:
		if ally.unit.player != owner or ally.unit.iun == evacuated: continue
		var landing := hex if ally == mover else ally.unit.ihx
		var threat := _pending_for(ally, landing, removed)
		result.x = maxi(result.x, threat.x)
		result.y += threat.y
	if mover != null and mover.unit.t_state == Enum.t_state.UNDEPLOYED:
		var threat := _pending_for(mover, hex, removed)
		result.x = maxi(result.x, threat.x)
		result.y += threat.y
	return result


## Forecasts already queued enemy attacks at a projected hex in combat order.
## Damage is capped at remaining life. Bow/Fire preserve captured victim
## identity, Gore also needs its deployed source, and Cannon hits the cell.
func _pending_for(victim: Profile, hex: int, removed: int) -> Vector2i:
	var key := Vector3i(victim.unit.iun, hex, removed)
	if _pending.has(key): return _pending[key]
	var unit := victim.unit
	var remaining := unit.actual_life
	var physical := _physical_at(victim, hex)
	var magical := victim.magical
	var physical_shield := unit._counter_value(UnitInfo.TEMP_PHYSICAL_COUNTER)
	var magic_shield := unit._counter_value(UnitInfo.TEMP_MAGICAL_COUNTER)
	var returned := 0
	for queue in [Match.pending_bow_attacks, Match.pending_gore_attacks, Match.pending_cannon_attacks, Match.pending_attacks]:
		for attack in queue:
			if remaining <= 0 or attack.resolved or attack.owner == unit.player or attack.target_hex != hex: continue
			if not attack is CannonAttack and attack.target_unit_id >= 0 and attack.target_unit_id != unit.iun: continue
			if attack is GoreAttack:
				var source := Match.get_unit(attack.source_id)
				if attack.target_unit_id != unit.iun or attack.source_id == removed or source == null \
						or source.t_state != Enum.t_state.DEPLOYED: continue
			var pierce: bool = not attack is GoreAttack and attack.pierce
			if attack is BowAttack or attack is GoreAttack:
				if victim.titanium: continue
				remaining -= maxi(0, attack.amount - (0 if pierce else physical))
				physical -= physical_shield
				physical_shield = 0
			else:
				if victim.obsidian and not pierce: continue
				var damage := maxi(0, int(attack.amount) - (0 if pierce else magical))
				if not attack is FireAttack or damage >= remaining: remaining -= damage
				magical -= magic_shield
				magic_shield = 0
	if remaining > 0 and unit.ihx == hex:
		for bash in Match.bashes:
			if bash.resolved or bash.target_hex != hex or bash.responding_player != unit.player: continue
			if unit.iun not in [bash.attacker_id, bash.defender_id]: continue
			var enemy_id := bash.attacker_id if bash.defender_id == unit.iun else bash.defender_id
			var enemy := Match.get_unit(enemy_id)
			if enemy == null or enemy_id == removed or enemy.t_state != Enum.t_state.DEPLOYED or enemy.ihx != hex: continue
			var exchange := _bash_damage(_profile(enemy), victim, hex, bash.attacker_id == enemy_id,
				unit.actual_life - remaining, unit._counter_value(UnitInfo.TEMP_PHYSICAL_COUNTER) - physical_shield)
			remaining -= exchange.x
			returned += mini(exchange.y, enemy.actual_life)
			break
	var debt := maxi(0, unit.actual_life - maxi(0, remaining) - returned)
	var risk := Exposure.SAFE
	if remaining <= 0 and unit.type == Enum.type.HERO: risk = Exposure.HERO_LOSS
	elif debt > 0: risk = Exposure.UNANSWERED_LOSS if remaining <= 0 else Exposure.UNANSWERED_HIT
	var result := Vector2i(risk, debt)
	_pending[key] = result
	return result


## Encodes a forecasted enemy removal as -(ID + 1), or Stun as ID + 1.
## A delayed attack does not suppress a reply. An instant hit is credited only
## for a direct lethal forecast, and a Stun still permits Tireless attacks.
func _suppression(profile: Profile, hex: int, family: StringName, target: TargetRef, verb: Effect.Verb) -> int:
	if target == null: return 0
	if target.kind == TargetRef.Kind.UNIT and family in [&"stun", &"return_to_hand"]:
		var unit := Match.get_unit(target.id)
		if unit != null and unit.player != profile.unit.player:
			return target.id + 1 if family == &"stun" else -(target.id + 1)
	if target.kind == TargetRef.Kind.HEX:
		for strike in profile.attacks:
			if strike.definition != verb or not strike.instant or not _ranged_reaches(strike, hex, target.id): continue
			for victim: UnitInfo in _occupancy.get(target.id, []):
				if victim.player != profile.unit.player and _ranged_damage(strike, _profile(victim), target.id) >= victim.actual_life:
					return -(victim.iun + 1)
	return 0


## Takes the worst direct punishment available to a deployed opponent in this
## forecast. Safety uses discrete tiers so secondary weights cannot buy it off.
func _worst_exposure(victim: Profile, hex: int, spent: bool, suppression: int = 0) -> int:
	var key := Vector4i(victim.unit.iun, hex, int(spent), suppression)
	if _exposure.has(key): return _exposure[key]
	var worst: int = Exposure.SAFE
	for enemy in _field:
		if enemy.unit.player == victim.unit.player or suppression == -(enemy.unit.iun + 1): continue
		var enemy_hex := enemy.unit.ihx
		if enemy_hex == hex and _shares_bash(victim.unit, enemy.unit, hex):
			var exchange := _bash_damage(enemy, victim, hex, _enemy_attacks_first(victim.unit, enemy.unit, hex))
			if mini(exchange.x, victim.unit.actual_life) > mini(exchange.y, enemy.unit.actual_life) \
					or (victim.unit.type == Enum.type.HERO and exchange.x >= victim.unit.actual_life):
				worst = maxi(worst, _threat_tier(victim, hex, spent, enemy, hex, exchange))
		for strike in enemy.attacks:
			if not strike.ready or (suppression == enemy.unit.iun + 1 and strike.activity_cost): continue
			if strike.family in [&"move", &"fly"]:
				if not _can_bash(enemy, strike, victim, hex): continue
				worst = maxi(worst, _threat_tier(victim, hex, spent, enemy, hex, _bash_damage(enemy, victim, hex, true)))
			elif _ranged_reaches(strike, enemy_hex, hex):
				var hit := _ranged_damage(strike, victim, hex)
				var reply_hex := hex if strike.family == &"gore" else enemy_hex
				worst = maxi(worst, _threat_tier(victim, hex, spent, enemy, reply_hex, Vector2i(hit, 0)))
	_exposure[key] = worst
	return worst


## Classifies a threat after checking whether the attacker dies in the exchange
## or can be damaged by a friendly unit in the response window.
func _threat_tier(victim: Profile, hex: int, spent: bool, enemy: Profile, enemy_hex: int, exchange: Vector2i) -> int:
	if exchange.x <= 0: return Exposure.SAFE
	var lethal := exchange.x >= victim.unit.actual_life
	if lethal and victim.unit.type == Enum.type.HERO: return Exposure.HERO_LOSS
	var answered := exchange.y >= enemy.unit.actual_life
	if not answered:
		answered = _has_response(victim, hex, spent, lethal, enemy, enemy_hex, exchange.y)
	if lethal: return Exposure.ANSWERED_LOSS if answered else Exposure.UNANSWERED_LOSS
	return Exposure.ANSWERED_HIT if answered else Exposure.UNANSWERED_HIT


## Forecasts damage to the enemy who just attacked. A lost ally cannot answer.
## A spent survivor may use a Tireless attack and other ready allies can respond.
func _has_response(victim: Profile, hex: int, spent: bool, lethal: bool, enemy: Profile, enemy_hex: int,
		enemy_loss: int) -> bool:
	for ally in _field:
		if ally.unit.player != victim.unit.player: continue
		var is_victim := ally == victim
		if is_victim and lethal: continue
		var origin := hex if is_victim else ally.unit.ihx
		for strike in ally.attacks:
			if not strike.ready or (is_victim and spent and strike.activity_cost): continue
			if strike.family in [&"move", &"fly"]:
				# A surviving Bash pair occupies the landing together.
				if origin != ally.unit.ihx or (not lethal and enemy_hex == hex): continue
				if _can_bash(ally, strike, enemy, enemy_hex, victim.unit.iun) \
						and _bash_damage(ally, enemy, enemy_hex, true, enemy_loss).x > 0: return true
			elif _ranged_reaches(strike, origin, enemy_hex) \
					and _ranged_damage(strike, enemy, enemy_hex, enemy_loss) > 0:
				return true
	return false


## Forecasts direct Walk/Fly Bash reach with the current reservations and
## blockers, removing a projected mover from its previous position.
func _can_bash(attacker: Profile, strike: Attack, victim: Profile, hex: int, removed: int = -1) -> bool:
	var origin := attacker.unit.ihx
	if attacker.unit.type == Enum.type.TEMPLE or hex == origin or CombatResolver._bash_at(hex): return false
	var distance := _distance(origin, hex)
	if distance < 1 or distance > strike.radius: return false
	for unit: UnitInfo in _occupancy.get(hex, []):
		if unit.iun != removed and unit != victim.unit and unit.player == attacker.unit.player: return false
	if strike.family == &"fly" or distance == 1: return true
	var vacated := victim.unit.iun if victim.unit.t_state == Enum.t_state.DEPLOYED else -1
	if removed >= 0: vacated = removed
	var key := Vector3i(origin, strike.radius, vacated)
	if not _paths.has(key):
		var occupied: Dictionary[int, int] = {}
		for tile in _occupancy:
			for unit: UnitInfo in _occupancy[tile]:
				if unit.iun != vacated:
					occupied[tile] = 1
					break
		_paths[key] = CombatResolver._walk_predecessors(origin, strike.radius, -1, occupied)
	return _paths[key].has(hex)


## Forecasts physical life loss on both sides of one Bash exchange. The
## projected landing supplies regional physical strength for both participants.
func _bash_damage(attacker: Profile, victim: Profile, hex: int, attacker_initiated: bool,
		victim_loss: int = 0, consumed_shield: int = 0) -> Vector2i:
	var margin := _region_margin(hex, victim.unit.player) + _regional_entry(victim.unit, hex) - _regional_entry(attacker.unit, hex)
	var am := 0 if victim.steady else attacker.physical + int(margin < 0.0)
	var vm := 0 if attacker.steady else victim.physical + int(margin > 0.0) - consumed_shield
	var hit := 0 if victim.titanium else maxi(0, attacker.unit.actual_life + am - vm)
	var victim_life := victim.unit.actual_life - victim_loss
	var reply := 0 if attacker.titanium else maxi(0, victim_life + vm - am)
	if attacker.titanium or victim.titanium: return Vector2i(hit, reply)
	if attacker.first_strike and (not victim.first_strike or attacker_initiated):
		reply = 0 if hit >= victim_life else maxi(0, reply - hit)
	elif victim.first_strike:
		hit = 0 if reply >= attacker.unit.actual_life else maxi(0, hit - reply)
	return Vector2i(hit, reply)


## Identifies a projected enemy landing or a currently unresolved shared Bash.
func _shares_bash(victim: UnitInfo, enemy: UnitInfo, hex: int) -> bool:
	if victim.ihx != hex: return true
	for bash in Match.bashes:
		if not bash.resolved and bash.target_hex == hex and victim.iun in [bash.attacker_id, bash.defender_id] \
				and enemy.iun in [bash.attacker_id, bash.defender_id]: return true
	return false


## Preserves the initiating participant's First Strike tie-break for a live Bash.
## For a proposed landing, the unit being rated is the initiator.
func _enemy_attacks_first(victim: UnitInfo, enemy: UnitInfo, hex: int) -> bool:
	if victim.ihx != hex: return false
	for bash in Match.bashes:
		if not bash.resolved and bash.target_hex == hex and bash.attacker_id == enemy.iun: return true
	return false


## Checks direct attack reach. Gore and Cannon require axial alignment;
## a bomb-occupied Fire target is handled by the actual blast simulation.
func _ranged_reaches(strike: Attack, origin: int, target: int) -> bool:
	var distance := _distance(origin, target)
	if strike.amount < 0 or distance < 0 or distance > strike.radius: return false
	if strike.family == &"fire": return Match.bomb_at(target) == null
	if strike.family == &"bow": return true
	var delta := Match.get_hex(target).coordinate - Match.get_hex(origin).coordinate
	return distance > 0 and (delta.x == 0 or delta.y == 0 or delta.x + delta.y == 0)


## Uses the defender's applicable modifier and immunity. Fire is lethal or
## zero damage; physical Pierce still respects Titanium.
func _ranged_damage(strike: Attack, victim: Profile, hex: int, victim_loss: int = 0) -> int:
	if strike.family in [&"bow", &"gore"]:
		if victim.titanium: return 0
		return maxi(0, strike.amount - (0 if strike.pierce else _physical_at(victim, hex)))
	if victim.obsidian and not strike.pierce: return 0
	var damage := maxi(0, strike.amount - (0 if strike.pierce else victim.magical))
	return 0 if strike.family == &"fire" and damage < victim.unit.actual_life - victim_loss else damage


## Checks currently visible opposing Reset access for upgrade discounts.
## A deployed death-Reset source also makes the upgrade less durable.
func _reset_threat(victim: Profile, hex: int) -> bool:
	for enemy in _field:
		if enemy.unit.player == victim.unit.player: continue
		if enemy.death_reset: return true
		for phrase in enemy.resets:
			var ctx := RuleContext.new(TargetRef.unit(enemy.unit.iun))
			ctx.subject = ctx.source
			ctx.query_verb = phrase.verb
			if phrase.target.output_kind(ctx) == TargetRef.Kind.HEX:
				if not TargetResolver.resolve(phrase.target, TargetRef.Kind.HEX, ctx, TargetRef.hex(hex)).candidates.is_empty():
					return true
			elif not TargetResolver.resolve(phrase.target, TargetRef.Kind.UNIT, ctx,
					TargetRef.unit(victim.unit.iun)).candidates.is_empty():
				return true
	return false


## Captures a card's visible combat and support capabilities once per root.
## Reserve values use printed counters; deployed values use live modifiers.
func _profile(unit: UnitInfo) -> Profile:
	if _profiles.has(unit.iun): return _profiles[unit.iun]
	var profile := Profile.new()
	profile.unit = unit
	var deployed := unit.t_state == Enum.t_state.DEPLOYED
	var modifier := unit.modifier if deployed else unit.counter_modifiers()
	profile.physical = modifier.x - (1 if deployed and _region_margin(unit.ihx, unit.player) > 0 else 0)
	profile.magical = modifier.y
	profile.titanium = unit.has_effective_flag(&"titanium") if deployed else unit.has_flag(&"titanium")
	profile.obsidian = unit.has_effective_flag(&"obsidian") if deployed else unit.has_flag(&"obsidian")
	profile.steady = unit.has_effective_flag(&"steady") if deployed else unit.has_flag(&"steady")
	profile.first_strike = unit.has_effective_flag(&"first-strike") if deployed else unit.has_flag(&"first-strike")
	for effect: Effect in unit.effects:
		var phrase := _first_phrase(effect.consequence)
		if phrase == null or phrase.verb == null: continue
		profile.support += _utility(phrase.verb.name) * 0.35
		if phrase.verb.name in UPGRADES: profile.upgrade += 0.5
		var ready := _ready_attack(unit, effect)
		if phrase.verb.name == &"reset" and ready: profile.resets.append(phrase)
		if phrase.verb.name in ATTACKS:
			var strike := _attack(unit, phrase, ready, _pays_activity(effect))
			if strike != null: profile.attacks.append(strike)
	for effect: Effect in unit.trigger_effects:
		var phrase := _first_phrase(effect.consequence)
		if phrase == null or phrase.verb == null: continue
		if phrase.verb.name in UPGRADES: profile.upgrade += 0.5
		if phrase.verb.name == &"reset" and effect.event != null and effect.event.observed_action == &"die":
			profile.death_reset = true
	profile.upgrade += unit.ability_upgrades.size() + maxi(0, unit.bow_damage_bonus) * 0.5 \
		+ maxi(0, unit.action_counter(UnitInfo.CANNON_DAMAGE_COUNTER)) * 0.5
	_profiles[unit.iun] = profile
	return profile


## Builds one direct attack forecast with the same live counter/upgrade
## inputs as its named verb. Composite attacks remain for MCTS to resolve.
func _attack(unit: UnitInfo, phrase: Effect.Phrase, ready: bool, activity_cost: bool) -> Attack:
	if not phrase.subject is Selectors.Self: return null
	if phrase.verb.name == &"bow":
		if not phrase.target is Selectors.BowTargets: return null
	else:
		var spatial := phrase.target as DistanceSelector
		if spatial == null or spatial.direction != Enum.direction.FROM or not spatial.include_inside \
				or spatial.center not in [Selectors.Anchor.SELF, Selectors.Anchor.SUBJECT]: return null
	var ctx := RuleContext.new(TargetRef.unit(unit.iun))
	ctx.subject = ctx.source
	ctx.query_verb = phrase.verb
	var bound := phrase.verb.bound_to(ctx)
	var parameters := bound.user_params
	if parameters.is_empty() or not parameters[0] is int: return null
	var strike := Attack.new()
	strike.definition = phrase.verb
	strike.family = bound.name
	strike.ready = ready
	strike.activity_cost = activity_cost
	if strike.family in [&"move", &"fly"]:
		strike.radius = unit.effective_action_values(strike.family, [parameters[0]])[0]
		return strike
	if strike.family == &"fire":
		if parameters.size() < 3: return null
		var distance := (phrase.target as DistanceSelector).distance + unit.ability_bonus(phrase.verb).y
		var values := unit.effective_action_values(&"fire", [parameters[0], distance])
		strike.amount = values[0]
		strike.radius = values[1]
		strike.pierce = bool(parameters[2]) or &"pierce" in unit.next_fire_stickers
		strike.instant = bool(parameters[1]) or &"instant" in unit.next_fire_stickers
		return strike
	if parameters.size() < 2 or not parameters[1] is int: return null
	var values: Array[int] = [parameters[0], parameters[1]]
	if strike.family in [&"bow", &"cannon"]:
		if parameters.size() < 4 or (strike.family == &"bow" and (values[0] < 0 or values[1] < 0)): return null
		values = unit.effective_action_values(strike.family, values)
		strike.pierce = bool(parameters[3])
		strike.instant = bool(parameters[2])
	strike.amount = values[0]
	strike.radius = values[1]
	return strike


## Estimates readiness for the next response using the unit's live activity
## and direct cost. Start Stun recovery alone does not activate an inactive unit.
func _ready_attack(unit: UnitInfo, effect: Effect) -> bool:
	if unit.t_state != Enum.t_state.DEPLOYED: return false
	if effect.cost != null:
		if not effect.cost is Effect.CostPhrase or not _pays_activity(effect) or not unit.active: return false
		var stun := Match.get_property(TargetRef.property(TargetRef.unit(unit.iun), UnitInfo.STUN_COUNTER))
		if stun == null or stun.increment != Enum.p_increment.COUNTER: return false
	return effect.condition == null or effect.condition.test(RuleContext.new(TargetRef.unit(unit.iun)))


## Identifies the ordinary self-Stun payment for the exposure and response forecasts.
func _pays_activity(effect: Effect) -> bool:
	if effect.cost is Effect.CostPhrase:
		return effect.cost.verb != null and effect.cost.verb.name == &"self_stun"
	if effect.cost is Effect.CostBundle:
		for cost in effect.cost.phrases:
			if cost.verb != null and cost.verb.name == &"self_stun": return true
	return false


## Estimates material committed before the consequence resolves. The root
## ranker charges it once per command, before the cost picker names its payer.
func _material_cost(effect: Effect) -> float:
	var costs: Array = []
	if effect.cost is Effect.CostPhrase: costs = [effect.cost]
	elif effect.cost is Effect.CostBundle: costs.assign(effect.cost.phrases)
	var value := 0.0
	for cost in costs:
		if cost.verb == null: continue
		if cost.verb.name == &"sacrifice": value += 14.0
		elif cost.verb.name == &"pay_life":
			value += 2.0 * maxi(int(cost.verb.user_params[0]), int(cost.verb.user_params[1]))
	return value


## Finds the first mandatory consequence used by root guidance.
func _first_phrase(consequence: RefCounted) -> Effect.Phrase:
	if consequence is Effect.Phrase: return consequence
	if consequence is Effect.ConsequenceSequence:
		for phrase in consequence.phrases:
			if not phrase.optional: return phrase
	return null


## Maps visible support actions to adjustable secondary preferences.
func _utility(family: StringName) -> float:
	if family == &"reset": return weights.reset
	if family == &"stun": return weights.stun
	if family in RETURNS: return weights["return"]
	if family in [&"deploy", &"grant_deployments"]: return weights.deployment
	if family in UPGRADES: return weights.upgrade
	return 0.0


## Returns a projected physical value with the destination's current regional bonus.
func _physical_at(profile: Profile, hex: int) -> int:
	var margin := _region_margin(hex, profile.unit.player) + _regional_entry(profile.unit, hex)
	return profile.physical + int(margin > 0.0)


## Reads current control strength once per region for the current root.
func _region_margin(hex: int, owner: int) -> float:
	var tile := Match.get_hex(hex)
	if tile == null: return 0.0
	var key := Vector3i(tile.region, tile.side, tile.region_count)
	if not _regions.has(key):
		_regions[key] = Vector2(ControlResolver.strength(tile, 1), ControlResolver.strength(tile, 2))
	var strengths := _regions[key]
	return strengths.x - strengths.y if owner == 1 else strengths.y - strengths.x


## Rewards entering a region where this unit's life and control can contest
## ownership. A stationary card receives no additional deployment contribution.
func _control_gain(unit: UnitInfo, hex: int) -> float:
	var margin := _region_margin(hex, unit.player)
	return clampf(margin + _regional_entry(unit, hex), -4.0, 4.0) - clampf(margin, -4.0, 4.0)


## Supplies a moved or deployed unit's contribution to a different region.
## Current control already includes a stationary participant's contribution.
func _regional_entry(unit: UnitInfo, hex: int) -> float:
	var target := Match.get_hex(hex)
	if target == null: return 0.0
	if unit.t_state == Enum.t_state.DEPLOYED and ControlResolver.same_region(Match.get_hex(unit.ihx), target):
		return 0.0
	return float(unit.actual_life + unit.control_bonus + unit._counter_value(UnitInfo.CONTROL_COUNTER))


## Returns axial distance for an on-board forecast, or -1 for a missing anchor.
func _distance(origin: int, target: int) -> int:
	var first := Match.get_hex(origin)
	var second := Match.get_hex(target)
	return -1 if first == null or second == null else DistanceSelector.hex_distance(first.coordinate, second.coordinate)

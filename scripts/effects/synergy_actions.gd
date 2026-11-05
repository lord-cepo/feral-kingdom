## Shared counter operations for the approved 28-unit roster; choices stay in PhraseExecution.
class_name SynergyActions
extends RefCounted

## Sacrifice's atomic verb accepts a living deployed friend; card selectors define range, SELF and any additional type restrictions.
static func can_sacrifice(subject: TargetRef, target: TargetRef) -> bool:
	if subject == null or target == null or subject.kind != TargetRef.Kind.UNIT or target.kind != TargetRef.Kind.UNIT: return false
	var unit := Match.get_unit(target.id)
	return Match.get_unit(subject.id) != null and unit != null and Match.owner_of(subject) == unit.player \
		and unit.t_state == Enum.t_state.DEPLOYED and unit.actual_life > 0

## Supplies a captured Sacrifice departure event to defeat: both Die and Sacrifice watchers are retained before removal, including the victim's own rules.
static func sacrifice(subject: TargetRef, target: TargetRef) -> bool:
	if not can_sacrifice(subject, target): return false
	Match.rules_runner.begin_boundary()
	var unit := Match.get_unit(target.id)
	var last_hex := unit.ihx
	var owner := unit.player
	var event := EffectEvent.new(&"sacrifice", subject, target, {"last_hex": last_hex, "owner": owner})
	Match.defeat(target, Match.owner_of(subject), [event])
	Match.rules_runner.end_boundary()
	return true

## Courier's counter choice requires one existing positive counter and a payable bounded amount without changing either host.
static func can_choose_counter(subject: TargetRef, target: TargetRef, amount: int) -> bool:
	return Action.can_decrement(subject, target, amount) and amount <= 2

## Records a PROPERTY/amount choice in the completed phrase; the later transfer performs both resource changes together.
static func choose_counter(subject: TargetRef, target: TargetRef, amount: int) -> bool:
	return can_choose_counter(subject, target, amount)

## Catalogue resource grants accept a real UNIT and an unambiguous counter key, including captured defeated recipients.
static func can_add_counter(subject: TargetRef, target: TargetRef, key: StringName, amount: int) -> bool:
	if subject == null or subject.kind != TargetRef.Kind.UNIT or target == null or target.kind != TargetRef.Kind.UNIT or key.is_empty() or amount <= 0: return false
	var unit := Match.get_unit(target.id)
	if unit == null: return false
	var matches := 0
	for prop in unit.props:
		if prop.name != key: continue
		matches += 1
		if prop.increment != Enum.p_increment.COUNTER or matches > 1: return false
	return Match.get_unit(subject.id) != null

## Awards stored counters by stable key, creating only missing counters; Control refreshes through the common Match boundary.
static func add_counter(subject: TargetRef, target: TargetRef, key: StringName, amount: int) -> bool:
	if not can_add_counter(subject, target, key, amount): return false
	Match.rules_runner.begin_boundary()
	Match.get_unit(target.id)._change_action_counter(key, amount)
	Match.action_event.emit(EffectEvent.new(&"add_counter", subject, target, {"key": key, "amount": amount}))
	Match.refresh_control()
	Match.state_changed.emit()
	Match.rules_runner.end_boundary()
	return true

## Counter-transfer destination selection requires a different deployed host and a real positive selected counter on the donor.
static func can_transfer_counter(subject: TargetRef, target: TargetRef, donor_id: int, key: StringName, amount: int) -> bool:
	if not can_add_counter(subject, target, key, amount) or target.id == donor_id: return false
	var donor := Match.get_unit(donor_id)
	var recipient := Match.get_unit(target.id)
	if donor == null or donor.t_state != Enum.t_state.DEPLOYED or recipient.t_state != Enum.t_state.DEPLOYED \
			or not subject.has_hex() or donor._counter_value(key) < amount or amount > 2: return false
	var origin := Match.get_hex(subject.hex_id())
	return DistanceSelector.hex_distance(origin.coordinate, Match.get_hex(donor.ihx).coordinate) <= 2 \
		and DistanceSelector.hex_distance(origin.coordinate, Match.get_hex(recipient.ihx).coordinate) <= 2

## Courier commits both counter deltas together after its source/property/amount/destination choices; no counter kind is converted.
static func transfer_counter(subject: TargetRef, target: TargetRef, donor_id: int, key: StringName, amount: int) -> bool:
	if not can_transfer_counter(subject, target, donor_id, key, amount): return false
	Match.rules_runner.begin_boundary()
	Match.get_unit(donor_id)._change_action_counter(key, -amount)
	Match.get_unit(target.id)._change_action_counter(key, amount)
	Match.action_event.emit(EffectEvent.new(&"transfer_counter", subject, target,
		{"donor": donor_id, "key": key, "amount": amount}))
	Match.refresh_control()
	Match.state_changed.emit()
	Match.rules_runner.end_boundary()
	return true

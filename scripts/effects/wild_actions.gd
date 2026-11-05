## Shared mutations supporting Wild rodent cards; definitions, references and numeric choices stay in executions.
class_name WildActions
extends RefCounted

## Porcupine's first choice accepts an existing UNIT with at least one positive stored counter; selectors own zone/ownership policy.
static func can_choose_counter_unit(subject: TargetRef, target: TargetRef) -> bool:
	if subject == null or target == null or subject.kind != TargetRef.Kind.UNIT or target.kind != TargetRef.Kind.UNIT: return false
	var unit := Match.get_unit(target.id)
	return Match.get_unit(subject.id) != null and unit != null and unit.props.any(func(prop: Prop) -> bool:
		return prop.increment == Enum.p_increment.COUNTER and prop.value > 0)

## Atomic cost bundles retain this identity without changing state or emitting an event; the dependent counter cost does the spending.
static func choose_counter_unit(subject: TargetRef, target: TargetRef) -> bool:
	return can_choose_counter_unit(subject, target)

## Chinchilla's captured death may replace one deployed friendly card only while the source remains defeated and has a positive maximum.
## The effect's selector supplies ownership; a duplicate Wild Rat activation cannot Return another card after the first recovery.
static func can_return_and_deploy(subject: TargetRef, target: TargetRef) -> bool:
	if not Action.can_return_to_hand(subject, target): return false
	var source := Match.get_unit(subject.id)
	return source.t_state == Enum.t_state.DEFEATED and source.max_life > 0 and source.player == Match.owner_of(target)

## Returns the exact chosen friend, then deploys the defeated actor on its former hex inside one boundary, before releasing followups.
## Effect deployment restores current maximum health, preserves counters/abilities, adds normal deployment Stun and emits Deploy again.
static func return_and_deploy(subject: TargetRef, target: TargetRef) -> bool:
	if not can_return_and_deploy(subject, target): return false
	Match.rules_runner.begin_boundary()
	var destination := target.hex_id()
	Action.return_to_hand(subject, target)
	var deployed := Match.deploy_from_effect(subject.id, destination)
	Match.rules_runner.end_boundary()
	return deployed

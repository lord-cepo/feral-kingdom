## Concrete verbs needed by woodland cards; shared runner/selector boundaries retain all activation choices.
class_name WoodlandActions
extends RefCounted

## Life payments address only the living deployed payer; equality is payable and may defeat it, but resources cannot be overspent.
static func can_pay_life(subject: TargetRef, target: TargetRef, actual: int, maximum: int) -> bool:
	if subject == null or target == null or not subject.same(target) or target.kind != TargetRef.Kind.UNIT: return false
	var unit := Match.get_unit(target.id)
	return unit != null and unit.t_state == Enum.t_state.DEPLOYED and unit.actual_life > 0 and actual >= 0 and maximum >= 0 \
		and actual + maximum > 0 and unit.actual_life >= actual and unit.max_life >= maximum

## A committed life cost may kill its payer; the enclosing execution still owns its paid consequences and captured followups.
static func pay_life(subject: TargetRef, target: TargetRef, actual: int, maximum: int) -> bool:
	if not can_pay_life(subject, target, actual, maximum): return false
	Match.rules_runner.begin_boundary()
	var unit := Match.get_unit(target.id)
	var old := Vector2i(unit.actual_life, unit.max_life)
	unit.max_life -= maximum
	unit.actual_life = mini(unit.actual_life - actual, unit.max_life)
	unit.record_max_life_change(subject, -maximum)
	Match.action_event.emit(EffectEvent.new(&"up_life", subject, target, {"actual": unit.actual_life - old.x, "max": -maximum, "life_cost": true}))
	if unit.actual_life <= 0: Match.defeat(target, unit.player)
	Match.refresh_control()
	Match.state_changed.emit()
	Match.rules_runner.end_boundary()
	return true

## Upgrade eligibility is structural: numeric standalone actions, excluding implicit engine consequences and unrelated triggered/static rules.
static func is_upgradable(option: Variant) -> bool:
	if not option is EffectOption or option.category != &"effects" or not option.definition is Effect: return false
	var effect: Effect = option.definition
	if not effect.consequence is Effect.ConsequencePhrase: return false
	return effect.consequence.verb.name in [&"move", &"fly", &"bow", &"fire", &"cannon", &"gore", &"bomb_throw", &"push", &"pull", &"stun", &"mend", &"shield", &"mshield", &"up_life"]

## The first Upgrade phrase chooses an eligible deployed unit; its result anchors the subsequent effect-property choice.
static func can_choose_upgrade_unit(subject: TargetRef, target: TargetRef) -> bool:
	if subject == null or target == null or target.kind != TargetRef.Kind.UNIT: return false
	var unit := Match.get_unit(target.id)
	return unit != null and unit.t_state == Enum.t_state.DEPLOYED and unit.effect_options().any(is_upgradable)

## Selection-only no-op stores an exact completed UNIT identity; it emits no fictional gameplay occurrence.
static func choose_upgrade_unit(subject: TargetRef, target: TargetRef) -> bool:
	return can_choose_upgrade_unit(subject, target)

## Second-stage Upgrade choices remain PROPERTY identities belonging to deployed recipients; ownership/range were authored in the unit selector.
static func can_upgrade_ability(subject: TargetRef, target: TargetRef, damage: int, range: int) -> bool:
	if subject == null or target == null or target.kind != TargetRef.Kind.PROPERTY or target.host.kind != TargetRef.Kind.UNIT: return false
	var unit := Match.get_unit(target.host.id)
	return unit != null and unit.t_state == Enum.t_state.DEPLOYED and damage >= 0 and range >= 0 and is_upgradable(Match.get_property(target))

## Stores a permanent recipient-bound bonus on exactly the chosen ability; donor definitions are never edited and Reset removes the record.
static func upgrade_ability(subject: TargetRef, target: TargetRef, damage: int, range: int) -> bool:
	if not can_upgrade_ability(subject, target, damage, range): return false
	var option: EffectOption = Match.get_property(target)
	Match.get_unit(target.host.id).add_ability_upgrade(option.definition, damage, range, subject)
	Match.action_event.emit(EffectEvent.new(&"upgrade_ability", subject, target, {"damage": damage, "range": range}))
	Match.state_changed.emit()
	return true

## Flee grants one free use of a current Move/Fly ability, including that exact ability's upgrades and ordinary route legality.
static func flee_movement(subject: TargetRef, target: TargetRef) -> Effect.Verb:
	if subject == null or subject.kind != TargetRef.Kind.UNIT or not subject.has_hex(): return null
	var unit := Match.get_unit(subject.id)
	for effect in unit.effects:
		if not effect.consequence is Effect.ConsequencePhrase: continue
		var verb: Effect.Verb = effect.consequence.verb
		if verb.name not in [&"move", &"fly"]: continue
		var range := int(verb.user_params[0]) + unit.ability_bonus(verb).x
		var movement := Verbs.movement(range, verb.name == &"fly", true)
		if movement.can_apply(subject, target): return movement
	return null

## Shared Flee selector asks which destination can be reached by one complete movement; no activity/action payment is charged.
static func can_flee(subject: TargetRef, target: TargetRef) -> bool:
	return flee_movement(subject, target) != null

## Executes the selected ordinary movement once, retaining Move/Fly events and Bash cancellation/transitions for replay and other triggers.
static func flee(subject: TargetRef, target: TargetRef) -> bool:
	var movement := flee_movement(subject, target)
	return movement != null and bool(movement.function.callv([subject, target] + movement.user_params))
